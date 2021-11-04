---
title: "apisix 开发自定义插件"
date: 2021-11-03T12:20:00+08:00
categories: 
- 技术
tags:
- lua
- go
- apisix
---

> 分享如何在 docker 环境部署 apisix 和如何开发 lua 和 go 语言的插件以及如何使用这些自定义插件的过程，希望能帮助到你。

## 如何部署


```shell
# 1. 下载官方 docker compose 项目
$ git clone https://github.com/apache/apisix-docker.git
$ cd apisix-docker/example
# 2. run docker compose
$ docker-compose -p docker-apisix up -d
# check docker ps
$  docker ps
CONTAINER ID   IMAGE          COMMAND                  CREATED          STATUS          PORTS                                                                                                                                                 NAMES
629eb9d85656   627d00c649fc   "sh -c '/usr/bin/api…"   24 seconds ago   Up 20 seconds   0.0.0.0:9080->9080/tcp, :::9080->9080/tcp, 0.0.0.0:9091-9092->9091-9092/tcp, :::9091-9092->9091-9092/tcp, 0.0.0.0:9443->9443/tcp, :::9443->9443/tcp   docker-apisix_apisix_1
c3cbca636e65   13afb861111c   "/run.sh"                24 seconds ago   Up 22 seconds   0.0.0.0:3000->3000/tcp, :::3000->3000/tcp                                                                                                             docker-apisix_grafana_1
4a5cb9ad6239   5b0292a5e821   "/usr/local/apisix-d…"   24 seconds ago   Up 22 seconds   0.0.0.0:9000->9000/tcp, :::9000->9000/tcp                                                                                                             docker-apisix_apisix-dashboard_1
6430826c4095   8c7e00e786b8   "/opt/bitnami/script…"   24 seconds ago   Up 21 seconds   0.0.0.0:2379->2379/tcp, :::2379->2379/tcp, 2380/tcp                                                                                                   docker-apisix_etcd_1
c086d6e4fbd9   a618f5685492   "/bin/prometheus --c…"   24 seconds ago   Up 22 seconds   0.0.0.0:9090->9090/tcp, :::9090->9090/tcp                                                                                                             docker-apisix_prometheus_1
1e6ea10c008f   7d0cdcc60a96   "/docker-entrypoint.…"   24 seconds ago   Up 21 seconds   0.0.0.0:9082->80/tcp, :::9082->80/tcp                                                                                                                 docker-apisix_web2_1
d4891bd0744e   7d0cdcc60a96   "/docker-entrypoint.…"   24 seconds ago   Up 22 seconds   0.0.0.0:9081->80/tcp, :::9081->80/tcp                                                                                                                 docker-apisix_web1_1
```

部署完成，可以通过 `localhost:9000` 访问 dashboard。



## 配置

默认配置文件在 `apisix-docker/example/apisix_conf` 目录下。

```yaml
apisix:
  node_listen: 9080              # APISIX listening port
  enable_ipv6: false

  allow_admin:                  # http://nginx.org/en/docs/http/ngx_http_access_module.html#allow
    - 0.0.0.0/0              # We need to restrict ip access rules for security. 0.0.0.0/0 is for test.

  admin_key:
    - name: "admin"
      key: edd1c9f034335f136f87ad84b625c8f1 # 这个值需要改的否则有安全隐患
      role: admin                 # admin: manage all configuration data
                                  # viewer: only can view configuration data
    - name: "viewer"
      key: 4054f7cf07e344346cd3f287985e76a2
      role: viewer
  
  enable_control: true
  control:
    ip: "0.0.0.0"
    port: 9092

etcd:
  host:                           # it's possible to define multiple etcd hosts addresses of the same etcd cluster.
    - "http://etcd:2379"     # multiple etcd address
  prefix: "/apisix"               # apisix configurations prefix
  timeout: 30                     # 30 seconds

plugin_attr:
  prometheus:
    export_addr:
      ip: "0.0.0.0"
      port: 9091
```



## 插件

### lua

[官方开发教程](https://apisix.apache.org/docs/apisix/plugin-develop)

示例插件：

```lua
local ngx = ngx
local core = require("apisix.core")
local plugin = require("apisix.plugin")
local upstream = require("apisix.upstream")

-- 定义配置，即使用插件时 配置一些自定义字段，如鉴权的 key，需要校验的 header 之类的
local schema = {
	type = "object",
	properties = {
		value = {type = "array", minItems = 1}
	},
	required = {"value"}
}

-- 这个需要了解一下干什么的
local metadata_schema = {
	type = "object",
	properties = {
		ikey = {type = "number", minimum = 0},
		skey = {type = "string"}
	},
	required = {"ikey", "skey"}
}

local plugin_name = "block_by_lua"

local _M = {
	version = 0.1,
	priority = 0,
	name = plugin_name,
	schema = schema,
	metadata_schema = metadata_schema
}

function _M.check_schema(conf, schema_type)
	if schema_type == core.schema.TYPE_METADATA then
		return core.schema.check(metadata_schema, conf)
	end
	return core.schema.check(schema, conf)
end

function _M.init()
	-- call this function when plugin is loaded
	core.log.info(plugin_name, "loaded!")
end

function _M.destroy()
	-- call this function when plugin is unloaded
end

-- uri 重写阶段 如果不需要就不用定义这个方法
--[[
function _M.rewrite(conf, ctx)
	core.log.warn("plugin rewrite phase, conf: ", core.json.encode(conf))
	core.log.warn("conf_type: ", ctx.conf_type)
	core.log.warn("conf_id: ", ctx.conf_id)
	core.log.warn("conf_version: ", ctx.conf_version)
end
--]]

--命中服务 & 调服务前
function _M.access(conf, ctx)
	core.log.warn("plugin access phase, conf: ", core.json.encode(conf))
	core.log.warn("plugin access phase, ctx: ", core.json.encode(ctx, true))
	-- return 200, {message = "hit example plugin"}
	-- 1. extract from header
	local pass = core.request.header(ctx, "X-Block-Pass")
	if not pass then
		core.response.set_header("X-Block-Flag", "Block By Lua Ext")
        -- 返回 http 状态码 则这次请求截止到当前插件，不会往下走
		return 403, {message = "Missing pass value in header"}
	end

	for _, val in pairs(conf.value) do
		if val == pass then
            -- return 空表示通过 
			return
		end
	end

	core.response.set_header("X-Block-Flag", "Block By Lua Ext")
	return 403, {message = "Invalid pass value in header."}
end

local function hello()
	local args = ngx.req.get_uri_args()
	if args["json"] then
		return 200, {msg = "world"}
	else
		return 200, "world\n"
	end
end

function _M.control_api()
	return {
		{
            -- 注册 controller api 用于探测插件是否插入成功，也可以用于内部一些返回 token 之类的用处
			methods = {"GET"},
			uris = {"/v1/plugin/example-plugin/hello"},
			handler = hello
		}
	}
end

return _M
```

**如何安装：**

1.   创建目录

```shell
├── example
│   └── apisix
│       ├── plugins
│       │   └── 3rd-party.lua
│       └── stream
│           └── plugins
│               └── 3rd-party.lua
```

2.   配置文件(config.yaml)添加插件目录

```yaml
apisix:
    ...
    extra_lua_path: "/path/to/example/?.lua"
```

3.   开启插件(config.yaml)

```yaml
apisix:
...
plugins: # 从 config-default.yaml 文件复制出来，然后加上自己的插件
  ...
  - your-plugin     
```



Q:如何在dashboard 看到自己的插件？

A: 目前自定义插件不支持自动同步到 dashboard，需要手动添加，步骤如下：

 1.    在 apisix 机器上执行如下命令获取最新 json scheme：

       ```shell
       $ curl 127.0.0.1:9092/v1/schema > scheme.json
       ```

	2.  将 `scheme.json` 复制到 dashboard 机器上 `conf` 目录下与原有的文件替换，重启 dashboard 服务。



### go

[官方开发教程](https://apisix.apache.org/docs/go-plugin-runner/getting-started/)

示例代码：

```go
package plugins

import (
	"encoding/json"
	"net/http"

	pkgHTTP "github.com/apache/apisix-go-plugin-runner/pkg/http"
	"github.com/apache/apisix-go-plugin-runner/pkg/log"
	"github.com/apache/apisix-go-plugin-runner/pkg/plugin"
)

// 初始化
func init() {
    // 注册插件
	err := plugin.RegisterPlugin(&BlockReq{})
	if err != nil {
		log.Fatalf("failed to register plugin block-req: %s", err)
	}
}

// LimitReq is a demo for a real world plugin
type BlockReq struct {
}

// 与 lua 插件内 scheme 一样
type BlockReqConf struct {
	Key   string   `json:"key"`
	Value []string `json:"value"`
}

func (p *BlockReq) Name() string {
	return "blcok-req"
}

// ParseConf is called when the configuration is changed. And its output is unique per route.
func (p *BlockReq) ParseConf(in []byte) (interface{}, error) {
	conf := BlockReqConf{}
	err := json.Unmarshal(in, &conf)

	return conf, err
}

// Filter is called when a request hits the route
func (p *BlockReq) Filter(conf interface{}, w http.ResponseWriter, r pkgHTTP.Request) {
	b := conf.(BlockReqConf)
	val := r.Header().Get(b.Key)
	for _, v := range b.Value {
		if val == v {
			r.Header().Set("X-Block-Value", v)
			return
		}
	}
	// block request
    // 只要写 response 的 header 或body，请求将停在这里不会往下传递，直接响应回去
	w.Header().Add("X-Block-Req", "Block by Go ext.")
	w.WriteHeader(http.StatusForbidden)
}
```



**编译部署**

1.   用官方提供的 `Makefile` 进行 build（注意编译环境和apisix 运行的环境，指定对应的 GOOS，GOARCH）
2.   将编译好的二进制文件打包到 apisix 的容器内
3.   修改配置文件

```yaml
ext-plugin:
  cmd: ["/path/to/apisix-go-plugin-runner/go-runner", "run"]
```



注意：一个 go-runner 内可以注册多个插件，所以不需要拥有多个 go-runner ,所有的插件在一个项目里 然后统一编译部署即可



**使用**

非 `lua` 插件都运行在各自的 runner 内，所以使用的时候不能直接在 dashboard 中使用自定义的插件（lua 的自定义插件是可以的），需要在 `ext-plugin-pre-req`, `ext-plugin-post-req` 两个插件内配置使用，这两插件只有运行时间不一样，一个在所有插件之前 一个在所有插件之后。使用时配置如下:

```json
"plugins": {
    "ext-plugin-pre-req": {
      "conf": [
        {
          "name": "blcok-req", // 注册的 go 插件名字
          "value": "{\"key\":\"pass\", \"value\":[\"word\",\"port\"]}" // 该插件的 conf，这里需要将 json 进行转义
        }
      ],
      "disable": false
    }
  }
```

### wasm

apisix 开始支持 wasm 插件，但是官方给出的示例和文档还不够完善，这块还在研究中，之后会补齐。
