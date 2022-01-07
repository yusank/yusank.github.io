---
title: "haproxy 开发 lua 插件过程遇到的坑"
date: 2021-11-03T13:20:00+08:00
categories: ["网关"]
tags: ["lua", "haproxy"]
draft: true
---

> 总结在开发和调试以及压测 lua 插件 功能过程中遇到的坑
> 该插件实现在 haproxy 中简单的蓝绿标记请求并转发到对应的服务。 **pfb 即为 pre feartue brach 特性分支。**

## 遇到的第一个问题

由于对 haproxy 提供的 lua api 不熟悉，导致前期开发的过程中错误使用 `core.Map` 能力，导致新能比较差而且还遇到在运行时不能调用 `Map.new()` 方法的问题，最后通过初始化过程缓存 Map 对象的方式解决这个问题。

修改前代码：

```lua
-- ha 启动时 会将 frontend 配置文件进行解析 并以 host 为 key 进行去重后写入文件里
-- 在判断流量时 根据请求的 host 去找文件并在运行时打开文件进行查找
function _M.lookupBEWithType(host, path, mapType)
    local mapFile = "/opt/" .. host
    local beMap = nil

    if mapType == Map._reg then
        mapFile = mapFile .. ".path_reg"
        beMap = Map.new(mapFile, Map._reg)
    else
        mapFile = mapFile .. ".path_beg"
        beMap = Map.new(mapFile, Map._beg)
    end

    if beMap == nil then
        core.Warning("beMap is nil")
        return nil
    end

    return Map.lookup(beMap, path)
end
```

修改后：

```lua
local _M = {
    hostMap = {}
}

function _M.parseFrontendConfigs()
    -- 初始化内存
end


-- 初始化时直接将host 作为 key  ha 的 map 作为value 存到内存中，直接使用
function _M.lookupBEWithType(host, path, mapType)
    -- local mapFile = "/opt/" .. host
    local beMap = nil
    local hm = _M.hostMap[host]
    if hm == nil then
        _M.warning("host map is nil host: " .. host)
        return nil
    end

    if mapType == Map._reg then
        beMap = hm.reg
    else
        beMap = hm.beg
    end

    if beMap == nil then
        _M.warning("beMap is nil, host: " .. host)
        return nil
    end

    return Map.lookup(beMap, path)
end

local function parse(txn)
    _M.parseFrontendConfigs()
end

-- 注册初始化方法
core.register_init(parse)
```

## 遇到的第二个问题

需要支持长链接和 ws。

最开始的开发中使用的 ha 提供的 http 库来直接调用蓝绿服务的节点，但是这个库过于简单，长链接，连接池，websocket都不支持更不用说 rpc 了，想要支持只能自行开发，但是很费时间和精力，经过思考讨论决定使用 ha 的原生能力去转发，而不是自己发出请求。

修改前的配置文件：

```shell
# 蓝绿服务节点缓存管理接口，由 controller 调用
http-request use-service lua.svcManage if { path_beg /svc-cache/api/v1/endpoints }

# 调用 lua 代码区分流量类型，并将类型写入到变量 req.flowType
# var 是 ha 提供的变量能力，可以有 txn, req, res 等前缀，分别作用在整个请求、request 阶段和 response 阶段
http-request set-var(req.flowType) lua.flowType()
# pfb 流量在 lua 代码内调用 pfb 节点
http-request use-service lua.pfbDispatch if { var(req.flowType) -m str 'pfb' }
# 其他服务走原有的配置
```

修改前 pfb 的选择节点和发起请求的代码块：

```lua
function _pfb.dispatch(applet)
    -- 在 flowType() 方法中确定 pfb 服务后 将 pfb key写入上下文并在这里读取使用
    local cacheKey = applet:get_priv()
    if cacheKey == nil or cacheKey == "" then
        _pfb.warning("ep is nil")
        util.errorResponse(applet, "internal error")
        return
    end
    _pfb.info("pfb cache key:" .. cacheKey)

    -- 获取节点列表并进行负载
    local endpoint = pfbCache.loadEndpoint(cacheKey)
    if endpoint == nil then
        _pfb.warning("load endpoint fail, key: " .. cacheKey)
        util.errorResponse(applet, "internal error")
        return
    end

    local body = applet:receive(applet.length)
    local uri = "http://" .. endpoint .. applet.path .. "?" .. applet.qs

    -- 发起请求
    local resp, err = util.httpAny(uri, applet.method, applet.headers, body)
    if err ~= nil then
        _pfb.warning("http any err: " .. err)
        util.errorResponse(applet, err)
    end

    applet:set_status(resp.status_code)
    for key, value in pairs(resp.headers) do
        applet:add_header(key, value)
    end

    -- 写响应
    applet:start_response()
    applet:send(resp.content)
end

---根据 key 读取 service 数据，并根据index 和 endpoints length 做 balance
--- 返回 ip:port or nil
---@param key string 缓存的 key
---@return string endpoint balance 后得到的节点 ip:port
function _cache.loadEndpoint(key)
    local svc = _cache[key]
    if svc == nil then
        return ""
    end

    if svc.endpoints == nil or #svc.endpoints == 0 then
        return ""
    end

    -- if svc.index > #svc.endpoints then 1 else svc.index
    local endpoint = svc.endpoints[svc.index > #svc.endpoints and 1 or svc.index]
    _cache.info("load index: " .. tostring(svc.index) .. " load endpoint: " .. endpoint)
    -- if svc.index + 1 > #svc.endpoints then 1 else svc.index + 1
    svc.index = svc.index + 1 > #svc.endpoints and 1 or svc.index + 1

    return endpoint
end
```



修改后配置：

```diff
     http-request set-var(req.flowType) lua.flowType()
    
-    http-request use-service lua.pfbDispatch if { var(req.flowType) -m str 'pfb' }

+   # pfb
+    http-request set-dst lua.getDstIP if { var(req.flowType) -m str 'pfb' }
+    http-request set-dst-port lua.getDstPort if { var(req.flowType) -m str 'pfb' }
+    use_backend %[lua.pfbDynamicBackend] if { var(req.flowType) -m str 'pfb' }
```

直接删除 `pfbDispatch` 方法，在判断 pfb 流量后将进行负载均衡操作，并把选到的 `ip:port` 写入上下文。此时之后流量发到 pfb 节点的流程发生了比较大的变化：

-   由 controller 生成一份 pfb 服务的 backend 配置文件 所有的 backend 名字以 pfb 开通的特定规则的 backend
-   使用 ha 的 `set-dst` 规则重写 destination ip 和端口，但是协议和能力还是走 ha 的原生能力，即解决了长链接问题
-   通过执行三段 lua 代码通过上下文即可指定 ip 端口以及使用的 backend

注：如果需要直接指定 ip 则 backend 必需是以下格式：

```shell
backend xxx
    server server 0.0.0.0:0
```


## 遇到的第三个问题

压测性能问题。

在压测过程中正常流量与 pfb 流量耗时和消耗的资源差距比较大，尤其是占用 cpu 会高出一倍多。

优化点有四个：

1. **不要使用全局变量。**

最开始负载均衡模块抽离出来做了全局的 LB 的类，但是压测遇到性能瓶颈后，改为 local后性能有 10%左右的提升

2.   **调用链长的问题**

使用过程中会有比较长的跨包引用，这块简化后也得到了明显的性能提升

3.   **字符串拼接**

lua 代码中我们用了大量的字符串拼接，这块对 lua 的性能影响也很大

4.   **日志问题**

直接调用的 ha 的 core 库提供的日志，但是我们最开始日志打的比较多，导致压测时西能下降很严重，这块去了大部分日志后，性能提升最高

### lua 的面向对象

由于 go 出身，开发 lua 插件的时候总是想往面向对象思想靠拢 但是对 lua 不是很熟悉，开发一段时间后才总结了一些小经验，以以下代码为例，讲解如何定义对象和其方法以及如何使用。

```lua
-- 实现简单的轮顺算法
local round_robin = {}

---new round robin class
---@param endpoints table
---@return table
function round_robin.new(self, endpoints)
    local o = {
        endpoints = endpoints,
        index = 1
    }

    setmetatable(o, self)
    self.__index = self

    return o
end

---balance endpints
---@return string endpoint ip:port
function round_robin.Balance(self)
    local ln = #self.endpoints
    if ln == 0 then
        return nil
    end

    -- if self.index > #self.endpoints then 1 else self.index
    local endpoint = self.endpoints[self.index > ln and 1 or self.index]
    -- if self.index + 1 > #self.endpoints then 1 else self.index + 1
    self.index = self.index + 1 > ln and 1 or self.index + 1

    return endpoint
end

---check is there has any valid endpoints
---@return table
function round_robin.Get(self)
    return {
        endpoints = self.endpoints,
        index = self.index
    }
end

return round_robin

-- 其他包内引入使用

local rr = round_robin:new(endpoints)
local endpoint = rr:Balance()
```


## 遇到的第四个问题

连接数比较高的情况下 ha 发生 crash 重启。

这个问题比较奇怪，前后花的时间也比较长，总体来说可以分几个阶段。

### 发现问题

crash 日志：

```shell
Thread 13 is about to kill the process.
...
*>Thread 13: id=0x7f4822ffd700 act=1 glob=1 wq=1 rq=1 tl=1 tlsz=18 rqsz=159
             stuck=1 prof=1 harmless=0 wantrdv=0
             cpu_ns: poll=9971328211 now=18093189004 diff=8121860793
             curr_task=0x7f47d87eb370 (task) calls=1 last=6726431149 ns ago
               fct=0x5645b8182850(process_stream) ctx=(nil)

             call trace(15):
             | 0x5645b825a587 [48 83 c4 10 5b 5d 41 5c]: wdt_handler+0x107/0x114
             | 0x7f4830fc5730 [48 c7 c0 0f 00 00 00 0f]: libpthread:+0x12730
             | 0x5645b81011c2 [e9 c1 fd ff ff 66 0f 1f]: hlua_ctx_destroy+0x312/0x367
             | 0x5645b8186316 [49 83 bf f0 00 00 00 00]: process_stream+0x3ac6/0x50ff
```

初步判断是跟 lua 相关，但是无法定位到具体方法上。

经过翻阅官方 repo 的 [issue](https://github.com/haproxy/haproxy/issues/1284#issuecomment-863294819) 后，发现 ha 可以通过global 参数 `set dumpable` 来开启 core dump 的，然后打开该开关，然后复现问题拿到 dump 文件进行分析。

Coredump 文件分析后最后结束在hlua_ctx_init 方法，此时依然不能精准问题所在处，然后看到了官方列出的已知 [bug](http://git.haproxy.org/?p=haproxy-2.2.git;a=commitdiff;h=36cdbee)。

### 定位问题

```markdown
**BUG/MEDIUM: lua: Always init the lua stack before referencing the context**

author	Christopher Faulet <cfaulet@haproxy.com>	
Wed, 24 Mar 2021 22:03:01 +0800 (15:03 +0100)
committer	Christopher Faulet <cfaulet@haproxy.com>	
Thu, 25 Mar 2021 00:15:21 +0800 (17:15 +0100)
----
When a lua context is allocated, its stack must be initialized to NULL
before attaching it to its owner (task, stream or applet).  Otherwise, if
the watchdog is fired before the stack is really created, that may lead to a
segfault because we try to dump the traceback of an uninitialized lua stack.

It is easy to trigger this bug if a lua script do a blocking call while
another thread try to initialize a new lua context. Because of the global
lua lock, the init is blocked before the stack creation. Of course, it only
happens if the script is executed in the shared global context.

This patch must be backported as far as 2.0.

(cherry picked from commit 1e8433f594de4b860e5205fdd6cb40d91ff58f17)
Signed-off-by: Christopher Faulet <cfaulet@haproxy.com>
```

大致意思是执行的 lua 脚本有阻塞行为时，如果别的线程尝试创建新的 context 的话，会崩溃的情况。而且在 issue 里有人尝试在 lua 代码 sleep 5s 也能触发。即每调用一次 lua 必然伴随自执行 `hlua_ctx_init` 和 `hlua_ctx_destroy` 方法。

我们遇到的场景时，请求量达到一定数值后，每个请求处理的时间会边长，从而会出现一些延迟高的请求，从而导致上述的 bug。

### 解决问题

1.   **升级版本**

官方给出这个 bug 在 2.3 之前的版本会有，我们首先想到就是升到 2.3 以上（目前是 2.2.2），然后尝试升级了版本（2.3.14）后，跑一次压力测试。这次没有崩溃但是连接数达到 8w 后 ha 开始处理不过来更多的请求，这个离 ha 的极限性能还差一段距离的，所以问题其实并没有真正解决，而且线上环境上升级版本的难度很大。

2.   **从 lua 下手**

可以重新看一下 pfb 相关的配置

```shell
http-request set-var(req.flowType) lua.flowType()
# pfb
http-request set-dst lua.getDstIP if { var(req.flowType) -m str 'pfb' }
http-request set-dst-port lua.getDstPort if { var(req.flowType) -m str 'pfb' }
use_backend %[lua.pfbDynamicBackend] if { var(req.flowType) -m str 'pfb' }
```

不难发现，一次 pfb 标识的请求需要调用四次 lua 代码，这个确实有点多。而且官方给出 ha 中使用 lua 至少损失 5%的性能，目前来看可能不止 5%这么少。

其实后面的三个 lua 方法里也没有很复杂的逻辑，纯从上下文读取ip 端口和 backend 名字，其实这块可以用 ha 的 var 语法来实现。开始改造 `flowType` 方法，将写入上下文的部门改成 `set-var` ，然后改造 config，调用 lua 脚本的地方改成读取 var。

改造对比

```diff
--- lua code

-local tb = {
-	pfbBackend = "pfb-" .. backend, -- use backend
- 	ip = ip, -- set dst ip
- 	port = port -- set dst port
- }
- txn:set_priv(tb)

+ txn:set_var("req.be", "pfb-" .. backend)
+ txn:set_var("req.ip", ip)
+ txn:set_var("req.port", port)

--- config

- http-request set-dst lua.getDstIP if { var(req.flowType) -m str 'pfb' }
- http-request set-dst-port lua.getDstPort if { var(req.flowType) -m str 'pfb' }
- use_backend %[lua.pfbDynamicBackend] if { var(req.flowType) -m str 'pfb' }
+ http-request set-dst var(req.ip) if { var(req.flowType) -m str 'pfb' }
+ http-request set-dst-port var(req.port) if { var(req.flowType) -m str 'pfb' }
+ use_backend %[var(req.be)] if { var(req.flowType) -m str 'pfb' }
```

这样下来，一次请求只会调用一次 lua 脚本，其所有变量都是通过 ha 的 var 来传递，crash 问题也解决，连接数也上去了。

## 参考文档
- https://zhuanlan.zhihu.com/p/29317103
- https://www.jianshu.com/p/32f0b17b852c
- http://git.haproxy.org/?p=haproxy-2.2.git;a=commitdiff;h=36cdbee
- https://github.com/haproxy/haproxy/issues/1284
- https://cloud.tencent.com/developer/article/1005003
