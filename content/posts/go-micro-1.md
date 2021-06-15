---
date: 2021-06-11T18:22:00+08:00
title: "Go-Micro 的架构及其使用（一）"
categories:
- go
- microservice
- 技术
tag:
- go
- go-micro
---

关于如何使用go的微服务框架 `go-micro/v3` 的使用和其插件的自定义。第一部分将框架的架构大致了解一遍。

## 架构

> 以 `v3.5.1` 分支为例

`go-micor` 项目的目录结构如下：

```shell
$ tree -L 2
.
├── LICENSE
├── README.md
├── _config.yml
├── api // api 接口的定义，包括http、grpc、router等
├── auth // 账号认证接口的定义
├── broker // 消息队列接口定义及默认实现
├── client // 客户端相关接口定义和实现
├── cmd // 可执行命令（包括生成protobuf的命令实现）
├── codec // code encoder
├── config // 动态配置的接口定义
├── debug // debug 模式
├── errors // 错误处理
├── examples // 各个模块的示例代码
├── logger // 日志模块接口定义
├── metadata // 原数据
├── plugins // 各个模块定义的接口的不同实现
├── registry // 服务注册接口定义
├── selector // 负载均衡
├── server // 服务端接口定义
├── store // 数据存储接口定义
├── sync 
├── transport // 请求转发
└── util // 工具类
```

下面按目录将 `go-micro` 的主要核心模块过一遍。

### API

> `api` 层为定义和实现基于http/gRPC的api service。即http请求处理 路由处理 路由注册等。

接口定义：

```go
type Api interface {
	// Initialise options
	Init(...Option) error
	// Get the options
	Options() Options
	// Register a http handler
	Register(*Endpoint) error
	// Register a route
	Deregister(*Endpoint) error
	// Implemenation of api
	String() string
}
```

目录结构：

```shell
$ tree
.
├── api.go
├── api_test.go
├── handler // 接口处理方法
│   ├── api // 实现 http.ServerHTTP() 方法
│   ├── event // 基于消息队列的实现
│   ├── handler.go // 接口定义
│   ├── http // 基于http的实现
│   ├── options.go
│   ├── rpc // 基于rpc的实现
│   └── web // 支持websocket的实现
├── proto
│   ├── api.pb.go
│   ├── api.pb.micro.go
│   └── api.proto // 数据结构定义
├── resolver // 解析请求及路由
│   ├── grpc
│   ├── host
│   ├── options.go
│   ├── path
│   ├── resolver.go
│   └── vpath
├── router // 路由定义和注册
│   ├── options.go
│   ├── registry
│   ├── router.go
│   ├── static
│   └── util
└── server // 服务定义和启动
    ├── acme
    ├── cors
    ├── http
    ├── options.go
    └── server.go
```


### Config

> `config` 作为动态配置中心的接口定义和实现。支持动态加载、插件式配置源、配置合并和观察配置变化。

接口定义：

```go
// Config is an interface abstraction for dynamic configuration
// 配置接口定义
type Config interface {
	// provide the reader.Values interface
    // 读取到的配置的reader
	reader.Values
	// Init the config
	Init(opts ...Option) error
	// Options in the config
	Options() Options
	// Stop the config loader/watcher
	Close() error
	// Load config sources
    // 可以加载多个 Source
	Load(source ...source.Source) error
	// Force a source changeset sync
    // 同步配置变化
	Sync() error
	// Watch a value for changes
    // 订阅配置变化
	Watch(path ...string) (Watcher, error)
}

// Watcher is the config watcher
type Watcher interface {
	Next() (reader.Value, error)
	Stop() error
}

// Source is the source from which config is loaded
// Source 就是配置来源 go-micro 已实现基于consul，etcd，file等多种配置来源，也可以自己实现下面接口来使用
type Source interface {
	Read() (*ChangeSet, error)
	Write(*ChangeSet) error
	Watch() (Watcher, error)
	String() string
}

// Reader is an interface for merging changesets
// 用于配置合并
// go-micro 实现了基于json的Reader,默认用json作为解析配置内容，并在插件目录内实现了 toml yaml xml等格式的Encoder可以按需求替换
type Reader interface {
	Merge(...*source.ChangeSet) (*source.ChangeSet, error)
	Values(*source.ChangeSet) (Values, error)
	String() string
}

// Values is returned by the reader
// 用于读写配置，读取的配置会返回 Value
type Values interface {
	Bytes() []byte
	Get(path ...string) Value
	Set(val interface{}, path ...string)
	Del(path ...string)
	Map() map[string]interface{}
	Scan(v interface{}) error
}

// Value represents a value of any type
// Value 为拿到的配置，可以通过其方法转到基础类型。
type Value interface {
	Bool(def bool) bool
	Int(def int) int
	String(def string) string
	Float64(def float64) float64
	Duration(def time.Duration) time.Duration
	StringSlice(def []string) []string
	StringMap(def map[string]string) map[string]string
	Scan(val interface{}) error
	Bytes() []byte
}
```

目录结构：

```shell
$ tree -L 2
.
├── README.md
├── config.go // Config 接口定义
├── default.go // 默认实现的Config
├── default_test.go
├── encoder // encoder 解析配置内容
│   ├── encoder.go
│   └── json // json实现
├── loader // 加载配置
│   ├── loader.go
│   └── memory // 基于内存的加载，即启动时会将配置加载到内存
├── options.go
├── reader // 定义和实现Reader，内部依赖Encoder
│   ├── json
│   ├── options.go
│   ├── preprocessor.go
│   ├── preprocessor_test.go
│   └── reader.go
├── secrets // 定义和实现需要加解密的配置
│   ├── box
│   ├── secretbox
│   └── secrets.go
├── source // 配置来源
│   ├── changeset.go
│   ├── cli
│   ├── env // 基于环境变量的实现
│   ├── file // 基于本地文件实现
│   ├── flag // 基于启动参数flag实现
│   ├── memory // 基于内存实现
│   ├── noop.go
│   ├── options.go
│   └── source.go
└── value.go
```

`plugins/config/encoder` 目录:
> 实现Encoder接口

```shell
$ tree
plugins/config/encoder
├── cue
├── hcl
├── toml
├── xml
└── yaml
```

`plugins/config/source` 目录：
> 实现Source接口

```shell
$ tree
plugins/config/source
├── configmap
├── consul
├── etcd
├── grpc
├── mucp
├── pkger
├── runtimevar
├── url
└── vault
```

### plugins

> 该目录作为插件目录，实现了大部分预定义的接口，方便使用的时候替换成默认实现的模块代码。
> 该目录下所有子目录均可以作为go mod package 导入使用
> 在之后讲如何使用是 同时演示如何使用插件

目录结构：

```shell
$ tree
plugins
├── LICENSE
├── README.md
├── auth // 用户认真
│   └── jwt // 实现基于jwt的auth接口
├── broker // 支持了市面上大部分消息队列
│   ├── gocloud
│   ├── googlepubsub
│   ├── grpc
│   ├── http
│   ├── kafka
│   ├── memory
│   ├── mqtt
│   ├── nats
│   ├── nsq
│   ├── proxy
│   ├── rabbitmq
│   ├── redis
│   ├── segmentio
│   ├── snssqs
│   ├── sqs
│   ├── stan
│   └── stomp
├── client // 支持了grpc http 等方式的客户端实现
│   ├── grpc
│   ├── http
│   ├── mock
│   └── mucp
├── codec // 消息的编码解码的实现
│   ├── bsonrpc
│   ├── json-iterator
│   ├── jsonrpc2
│   ├── msgpackrpc
│   └── segmentio
├── config // 配置
│    ├── encoder // 配置编码解码
│       ├── cue
│       ├── hcl
│       ├── toml
│       ├── xml
│       └── yaml
│   └── source // 配置数据源
│       ├── configmap
│       ├── consul
│       ├── etcd
│       ├── grpc
│       ├── mucp
│       ├── pkger
│       ├── runtimevar
│       ├── url
│       └── vault
├── logger // 日志库
│   ├── apex
│   ├── logrus
│   ├── zap
│   └── zerolog
├── plugin.go
├── proxy
│   └── http
├── registry // 服务发现服务注册
│   ├── cache
│   ├── consul
│   ├── etcd
│   ├── eureka
│   ├── gossip
│   ├── kubernetes
│   ├── mdns
│   ├── memory
│   ├── multi
│   ├── nats
│   ├── proxy
│   └── zookeeper
├── release.sh
├── selector // 负载均衡
│   ├── dns
│   ├── label
│   ├── registry
│   ├── shard
│   └── static
├── server // 后端服务
│   ├── grpc
│   ├── http
│   └── mucp
├── store // 数据存储的实现
│   ├── cockroach
│   ├── consul
│   ├── file
│   ├── memcached
│   ├── memory
│   ├── mysql
│   └── redis
├── sync // 数据同步
│   ├── etcd
│   └── memory
├── template.go
├── transport // 服务之间通讯模块
│   ├── grpc
│   ├── http
│   ├── memory
│   ├── nats
│   ├── quic
│   ├── rabbitmq
│   ├── tcp
│   └── utp
└── wrapper // 自定义组件 比如监控、限流、熔断、追踪等
    ├── README.md
    ├── breaker // 熔断
    ├── endpoint // 指定服务节点
    ├── monitoring // 监控
    ├── ratelimiter // 限流
    ├── select // 负载均衡
    ├── service
    ├── trace // 链路追踪
    └── validator // 参数校验（处理请求时 可以统一参数校验等工作）
```
