---
title: "nginx 中使用 lua 动态加载服务配置"
date: 2021-09-17 12:22:33+08:00
categories:
- 技术
tags:
- nginx
- lua
---

> 本文简单介绍如何通过 lua 脚本和 ngx_shared_dict 在 nginx 中动态加载后端服务配置以及动态更新服务配置.

## nginx

### 加载 lua 脚本

在 Nginx 中需要引入和加载 lua 脚本，从而在路由转发时运行 lua 脚本进行我们的逻辑。初始化代码如下：

```vim
http {
    lua_shared_dict endpoints_data 5m; #定义upstream共享内存空间
    lua_shared_dict cache 1m; #定义计数共享空间
    access_log  nginx_access.log;

    lua_package_path "/etc/nginx/lua/?.lua;;";
    init_by_lua_block {
        collectgarbage("collect")
        local ok, res

        # 加载脚本 configuration.lua
        ok, res = pcall(require, "configuration")
        if not ok then
          error("require failed: " .. tostring(res))
        else
          configuration = res
        end
    }
    # 执行脚本内初始化方法，这里为可选项，如果没有可初始化的代码部分 这里可以不要
    init_worker_by_lua_block {
        configuration.prepare()
    }
}
```

### 执行 lua 脚本

如何在 Nginx 配置中执行 lua 脚本，从而实现一些特殊逻辑？这里给出一个简单的示例:

```vim
server {
        # 执行最简单的 lua 脚本
        location /hello {
            default_type 'text/plain'; 
            content_by_lua 'ngx.say("hello, lua")'; 
        }
        # 配置接口
        # 这里是执行加载的 lua 脚本中方法
        location /configuration {
            client_max_body_size                    5m;
            client_body_buffer_size                 1m;
            proxy_buffering                         off;

            content_by_lua_block {
              configuration.call() # 调用 call() 方法
            }
        }
        # 执行较为复杂的 lua 逻辑
        location /lua {
            default_type 'text/plain'; 
            # 读取请求中的 path 参数 并从共享 dict 中查询这个值，
            # 返回查询到的结果
            content_by_lua '
                local path = ngx.req.get_uri_args()["path"]
                if path == nil then
                    ngx.say("path not found")
                    return
                end
                local data = ngx.shared.endpoints_data:get("/"..path)
                if not data then
                    ngx.say("unkonw path")
                    return
                end
                ngx.say("paths: "..data)
            ';
        }
}
```

`lua` 的语法相对简单好上手，实现一些简单的逻辑也很方便，非常值得学习。

### 完整配置

先给出 Nginx 的完整配置，里面包括动态配置后端服务列表和动态加载服务转发的逻辑，然后再给出 lua 部分详细实现的代码。

```vim
user  nginx;
worker_processes  1;

pid        /var/run/nginx.pid;
error_log  nginx_error.log;

events {
    worker_connections  1024;
}


http {
    lua_shared_dict endpoints_data 5m; #定义upstream共享内存空间
    lua_shared_dict cache 1m; #定义计数共享空间
    access_log  nginx_access.log;

    lua_package_path "/etc/nginx/lua/?.lua;;";
    init_by_lua_block {
        collectgarbage("collect")
        local ok, res

        ok, res = pcall(require, "configuration")
        if not ok then
          error("require failed: " .. tostring(res))
        else
          configuration = res
        end
    }
    # 执行脚本内初始化方法，这里为可选项，如果没有可初始化的代码部分 这里可以不要
    init_worker_by_lua_block {
        configuration.prepare()
    }
    include       /etc/nginx/mime.types;
    default_type  application/octet-stream;

    sendfile        on;
    #tcp_nopush     on;

    keepalive_timeout  65;

    #gzip  on;
    server {
        # 执行最简单的 lua 脚本
        location /hello {
            default_type 'text/plain'; 
            content_by_lua 'ngx.say("hello, lua")'; 
        }
        # 配置接口
        # 这里是执行加载的 lua 脚本中方法
        location /configuration {
            client_max_body_size                    5m;
            client_body_buffer_size                 1m;
            proxy_buffering                         off;

            content_by_lua_block {
              configuration.call() # 调用 call() 方法
            }
        }
        # 执行较为复杂的 lua 逻辑
        location /lua {
            default_type 'text/plain'; 
            # 读取请求中的 path 参数 并从共享 dict 中查询这个值，
            # 返回查询到的结果
            content_by_lua '
                local path = ngx.req.get_uri_args()["path"]
                if path == nil then
                    ngx.say("path not found")
                    return
                end
                local data = ngx.shared.endpoints_data:get("/"..path)
                if not data then
                    ngx.say("unkonw path")
                    return
                end
                ngx.say("paths: "..data)
            ';
        }

        # other path
        location / {
            set $load_ups "";
            # 动态设置当前 upstream, 未找到返回404
            rewrite_by_lua '
                local ups = configuration.getEndpoints()
                if ups ~= nil then
                    ngx.log(ngx.ERR,"got upstream", ups)
                    ngx.var.load_ups = ups
                    return
                end
                ngx.status = ngx.HTTP_NOT_FOUND
                ngx.exit(ngx.status)
            ';
            proxy_pass http://$load_ups$uri;
            add_header  X-Upstream  $upstream_addr always; # 添加 backend ip
        }
    }
}
```

## lua

### 定义变量

因为需要用到 shared_dict 特性，在 lua 和 Nginx 之间公用内存块 从而实现数据的同步共享，所以需要预定义一些变量。

```lua
-- 引入变量
local io = io
local ngx = ngx
local table = table
-- 当前包的对象，类似 go 语言的定义结构体 让给这个结构体实现方法
local _M = {}
-- 与 Nginx 共享的空间 可读写
local Endpoints = ngx.shared.endpoints_data
```

### 动态更新服务列表

服务列表是通过被调接口实现，即有别的服务区监听服务节点(endpoint)的变化,然后调用`/configuration/backends` 接口，被 Nginx 配置的 `/configuration` 规则命中后调用 `configuration.call()` 方法，我们看一下这个 `call` 方法的实现。

```lua
-- call called by ngx
function _M.call()
    -- 只处理 GET 和 POST
    if ngx.var.request_method ~= "POST" and ngx.var.request_method ~= "GET" then
        ngx.status = ngx.HTTP_BAD_REQUEST
        ngx.print("Only POST and GET requests are allowed!")
        return
      end
    -- 目前只处理后端服务的配置 所以判断路由
    if ngx.var.request_uri == "/configuration/backends" then
        -- 调用内部方法
        handle_backends()
        return
    end
    -- 非法请求 返回 404
    ngx.status = ngx.HTTP_NOT_FOUND
    ngx.print("Not found!")
end
```

多说一句，调用 `/configuration/backends` 时传参是在请求 body 里，格式为 `json` 所以需要引入第三方的 json 解析包。`handle_backends` 方法的实现：

```lua
-- handle_backends .
local function handle_backends()
    if ngx.var.request_method == "GET" then
        ngx.status = ngx.HTTP_OK
        -- 返回查询的服务列表
        local path = ngx.req.get_uri_args()["path"]
        ngx.print(Endpoints:get("path"))
        return
    end

    -- 读取请求 body
    local obj = fetch_request_body()
    if not obj then
        ngx.log(ngx.ERR, "dynamic-configuration: unable to read valid request body")
        ngx.status = ngx.HTTP_BAD_REQUEST
        return
    end

    -- 通过 第三方包 json 解析 body到 lua table
    local rule, err = json.decode(obj)
    if not rule then
        ngx.log(ngx.ERR, "could not parse backends data: ", err)
        return
    end

    ngx.log(ngx.ERR, "decoed rule", obj)

    -- 清空共享空间
    Endpoints:flush_all()
    -- 遍历并写入
    for _, new_rule in ipairs(rule.rules) do
        -- 更新
        -- 将数组合并
        local succ, err1, forcible = Endpoints:set(new_rule.path, table.concat(new_rule.upstreams, ","))
        ngx.log(ngx.ERR, "set result", succ, err1,forcible)
    end

    ngx.status = ngx.HTTP_CREATED
    ngx.say("ok")
end

-- 读取请求 body 部分
local function fetch_request_body()
    ngx.req.read_body()
    local body = ngx.req.get_body_data()
  
    if not body then
      -- request body might've been written to tmp file if body > client_body_buffer_size
        local file_name = ngx.req.get_body_file()
        local file = io.open(file_name, "rb")
    
        if not file then
            return nil
        end
    
        body = file:read("*all")
        file:close()
    end
  
    return body
end

```

请求 body 的 json 结构如下：

```go
type NginxRuleConf struct {
	Rules []struct{
        Path        string   `json:"path"`
	    ServiceName string   `json:"serviceName"`
	    Port        int32    `json:"-"`
	    Upstreams   []string `json:"upstreams"`
    } `json:"rules"`
}
```

### 动态读取后端服务

上面已经通过接口的方式动态更新服务节点列表并写入到共享空间 `endpoints_data` 内，我们现在实现读取服务列表并选择其中一个节点进行接口转发。

代码如下：

```lua
-- 轮顺的方式取节点
function _M.getEndpoints() 
    local cache = ngx.shared.cache
    local path = ngx.var.request_uri
    local eps =  Endpoints:get(path)
    if not eps then
        return nil
    end

    local tab = split(eps,",")
    local index = cache:get(path)
    if index ==  nil or index > #tab then
        index = 1
    end
    -- 加一
    cache:set(path,index+1)
    return tab[index]
end
```

## 结论

至此实现的效果是，可以动态配置多个后端服务和后端服务节点列表，外部服务请求 Nginx 时，会尝试从已有的服务中匹配转发，如果服务有多个节点则轮顺的方法去转发。如有服务信息发生变化，则通过调用 Nginx 中配置的 `configuration` 接口更新即可，无需修改 Nginx 配置。
