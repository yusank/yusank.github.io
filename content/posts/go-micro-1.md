---
date: 2021-06-11T18:22:00+08:00
title: "Go-Micro 的架构及其使用（一）"
categories:
- 技术
- microservice
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
    // 可以加载多个Source
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

### Logger

> `Logger` 包为全局日志库，默认实现了一套，并在`plugins` 内实现了基于 logrus，zap的个主流的日志的实现。

接口定义：

```go
// Logger is a generic logging interface
type Logger interface {
	// Init initialises options
	Init(options ...Option) error
	// The Logger options
	Options() Options
	// Fields set fields to always be logged
	Fields(fields map[string]interface{}) Logger
	// Log writes a log entry
	Log(level Level, v ...interface{})
	// Logf writes a formatted log entry
	Logf(level Level, format string, v ...interface{})
	// String returns the name of logger
	String() string
}
```

若需要自己定义日志格式和日志库，可以实现上面接口，并初始化的时候指定即可。

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

### Registry

> 服务发现/服务注册相关逻辑均在 `registry` 包内实现。

核心接口定义：

```go
// The registry provides an interface for service discovery
// and an abstraction over varying implementations
// {consul, etcd, zookeeper, ...}
type Registry interface {
	Init(...Option) error
	Options() Options
    // 服务注册
	Register(*Service, ...RegisterOption) error
    // 服务注销
	Deregister(*Service, ...DeregisterOption) error
    // 查询服务
	GetService(string, ...GetOption) ([]*Service, error)
    // 列出服务列表
	ListServices(...ListOption) ([]*Service, error)
    // 监控服务
	Watch(...WatchOption) (Watcher, error)
	String() string
}

// Watcher is an interface that returns updates
// about services within the registry.
type Watcher interface {
	// Next is a blocking call
	Next() (*Result, error)
	Stop()
}
```

### Selector

> 负载均衡逻辑，即客户端请求其他服务时如何选取服务节点都是在该包内实现。可以通过option指定策略，随机，轮询等。

接口定义：

```go
// Selector builds on the registry as a mechanism to pick nodes
// and mark their status. This allows host pools and other things
// to be built using various algorithms.
type Selector interface {
	Init(opts ...Option) error
	Options() Options
	// Select returns a function which should return the next node
	Select(service string, opts ...SelectOption) (Next, error)
	// Mark sets the success/error against a node
	Mark(service string, node *registry.Node, err error)
	// Reset returns state back to zero for a service
	Reset(service string)
	// Close renders the selector unusable
	Close() error
	// Name of the selector
	String() string
}

// Next is a function that returns the next node
// based on the selector's strategy
type Next func() (*registry.Node, error)
```

### Server

> server 包为定义和实现管理服务相关逻辑。

server的定义：

```go
// Server is a simple micro server abstraction
type Server interface {
	// Initialise options
	Init(...Option) error
	// Retrieve the options
	Options() Options
	// Register a handler
	Handle(Handler) error
	// Create a new handler
	NewHandler(interface{}, ...HandlerOption) Handler
	// Create a new subscriber
	NewSubscriber(string, interface{}, ...SubscriberOption) Subscriber
	// Register a subscriber
	Subscribe(Subscriber) error
	// Start the server
	Start() error
	// Stop the server
	Stop() error
	// Server implementation
	String() string
}

// Router handle serving messages
type Router interface {
	// ProcessMessage processes a message
    // 处理消息队列消息
	ProcessMessage(context.Context, Message) error
	// ServeRequest processes a request to completion
    // 处理 http/rpc 请求
	ServeRequest(context.Context, Request, Response) error
}
```

默认实现了rpc和消息队列，http服务 可以使用`plugins/server/http` 包。

### Store

> 该包定义了数据存储的接口。

接口定义：

```go
// Store is a data storage interface
type Store interface {
	// Init initialises the store. It must perform any required setup on the backing storage implementation and check that it is ready for use, returning any errors.
	Init(...Option) error
	// Options allows you to view the current options.
	Options() Options
	// Read takes a single key name and optional ReadOptions. It returns matching []*Record or an error.
	Read(key string, opts ...ReadOption) ([]*Record, error)
	// Write() writes a record to the store, and returns an error if the record was not written.
	Write(r *Record, opts ...WriteOption) error
	// Delete removes the record with the corresponding key from the store.
	Delete(key string, opts ...DeleteOption) error
	// List returns any keys that match, or an empty list with no error if none matched.
	List(opts ...ListOption) ([]string, error)
	// Close the store
	Close() error
	// String returns the name of the implementation.
	String() string
}
```

具体使用数据库类型，在`plugins/store` 内初始化对应的实例。

### Sync

> `sync` 包为定义分布式选举和分布式锁的定义。

接口定义：

```go
// Sync is an interface for distributed synchronization
type Sync interface {
	// Initialise options
	Init(...Option) error
	// Return the options
	Options() Options
	// Elect a leader
    // 选举
	Leader(id string, opts ...LeaderOption) (Leader, error)
	// Lock acquires a lock
    // 上锁
	Lock(id string, opts ...LockOption) error
	// Unlock releases a lock
    // 释放锁
	Unlock(id string) error
	// Sync implementation
	String() string
}

// Leader provides leadership election
// 提供分布式选举
type Leader interface {
	// resign leadership
    // 辞职 即放弃Leader状态
	Resign() error
	// status returns when leadership is lost
    // 在leader 状态失去时，channel内可读取
	Status() chan bool
}
```
