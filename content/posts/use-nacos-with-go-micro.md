---
date: 2021-06-23T18:22:00+08:00
title: "Go-Micro 中使用Nacos"
categories:
- 技术
- microservice
tag:
- go
- go-micro
---

`go-micro` 作为比较流行的微服务框架，其良好的接口设计为后期扩展使用带来了非常好的便利性。本文章主要讲在 `go-micro` 中用 `nacos` 作为服务注册中心和配置中心。

## 配置中心

先看一下 `go-micro` 定义的服务注册接口。

registry.go

```go
// 服务注册接口
type Registry interface {
    // 初始化
	Init(...Option) error
    // 返回可选参数
	Options() Options
    // 服务注册
	Register(*Service, ...RegisterOption) error
    // 服务注销
	Deregister(*Service, ...DeregisterOption) error
    // 查询服务
	GetService(string, ...GetOption) ([]*Service, error)
    // 列出服务
	ListServices(...ListOption) ([]*Service, error)
    // 监听服务
	Watch(...WatchOption) (Watcher, error)
	String() string
}
```

只要基于任意一个服务注册服务实现以上接口，即可在 `go-micro` 中作为注册中心使用。假如我用一个 `customRegistry` 实现接口后，在 `go-micro` 初始化的时候或服务启动时候通过启动参数指定实现接口的接口的 `String() string`方法的返回值接口。

如：

```go
// 假如该结构体已实现 Registry 接口
type customRegistry struct {}

func (c *customRegistry) String() string {
    return "custom"
}

// 代码中指定
func main() {
    micro.NewService(micro.Registry(&customRegistry{}))
}

// 启动参数指定
./myApp -- registry custom

```

如此一看，发现非常方便和好扩展，接下来贴出如何使用nacos 实现该 `Registry` 接口。