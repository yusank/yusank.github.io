---
title: "[系列]微服务·深入了解gRPC"
date: 2022-06-29T10:10:00+08:00
lastmod: 2022-06-29T10:10:00+08:00
categories: ["microservice"]
tags: ["微服务","系列篇","grpc"]
draft: true
---

> 本文为系列篇`微服务`的关于 深入 gRPC 的文章。本篇将会从 gRPC 的基本概念、gRPC 的使用、gRPC 的编程模型、gRPC 的编程模型的实现、gRPC 的编程模型的实现的细节等多个角度来了解。

<!--more-->

## 1. 前言

`gRPC` 作为一个 Google 开源的 RPC 框架，由于其优异的性能和支持多种流行语言的特点，被众多的开发者所熟悉。我接触 `gRPC` 也有至少五年的时间，但是由于种种原因，在很长时间内对 `gRPC` 的了解处于一个入门或者只是知道个大概的水平。直到大概 2~3 年前在上家公司机缘巧合的缘故，需要对部门内做一次关于 `gRPC` 的知识分享，而那次我花了 2 周多的时间去了解去背后的原理、实现、数据流向。那时候我记得是白班分享没有写 PPT，所以那时候对这些知识点有了比较深刻的理解。

然而，我上家我所在部门的业务几乎没有涉及到 `gRPC` 的开发，因此这些理解只是变成一个知道的概念，并没有在实际开发工作中提到实际的应用。但是从那次分享后，我对 `gRPC` 有了一些迷恋现象，想做一些实际的 `gRPC` 相关项目，从实际项目中提炼自己的知识面。

到现在，我回过头来看，以及参与了几个基于 `gRPC` 通信的项目以及基于 `gRPC` 的微服务框架，最近也在写一个比较完整的微服务项目，也是基于 `gRPC` 通信。的确从实践中提炼到了一定的知识，自己对整体的理解也有了一定的提升。

今天想写这篇文章的原因有两个，其一是我前前后后对 `gRPC` 有了很多的交集并且也在上家极力推荐使用（但是能力不够，没能推广起来），我对这块有了一些自己的看法和观点，但是一直没有一个比较完整的记录。其二是之前与大学同学做一次线上分享的时候，有人提问关于 `gRPC` 的性能问题（由于其基于 `HTTP/2`,所以对其性能持怀疑态度），我觉得这个问题确实也是需要一个深究的问题，所以这篇文章也会提到相关内容。

因此，这篇文件将会从 `gRPC` 的基本概念、`gRPC` 的使用、`gRPC` 的编程模型、`gRPC` 的编程模型的实现、`gRPC` 的编程模型的实现的细节等多个角度来一一进行讲解，给自己一个总结，给对这方面有疑问的同学一定的帮助。

{{< admonition type=warning title="注意" open=true >}}

1. 本篇所有的示例代码均用 Go
2. 本篇完全以个人的理解和官方文档为准，若有错误不准之处，请帮忙支持评论一下，谢谢！

{{< /admonition >}}

## 2. gRPC 的基本概念

{{< admonition type=note title="Definition by official" open=true >}}
gRPC is a modern open source high performance Remote Procedure Call (RPC) framework that can run in any environment. It can efficiently connect services in and across data centers with pluggable support for load balancing, tracing, health checking and authentication. It is also applicable in last mile of distributed computing to connect devices, mobile applications and browsers to backend services.
{{< /admonition >}}

简单来说，`gRPC` 是一个高性能的远程过程调用框架，可以在任何环境中运行，可以在数据中心之间高效地连接服务，并且支持负载均衡、跟踪、健康检查和身份验证。它还适用于分布式计算，将设备、移动应用和浏览器连接到后端服务。 `gRPC` 是由 `CNCF` 孵化的项目,目前在 GitHub 上有 `43.8k` 的 star 和 `9.2k` 的 fork。`gRPC` 有以下几个核心特点：

1. 简单的服务定义。通过 `Protocol Buffer` 去定义数据结构和服务的接口 (关于 pb 更详细的介绍请查这篇：[[系列]微服务·如何通过 protobuf 定义数据和服务](../microservices-protobuf))。
2. 快速使用。仅通过一行代码就进行服务注册和远程调用。
3. 跨语言和平台。`gRPC` 支持众多主流语言，可以在不同语言之间无缝远程调用且均可通过 pb 生成对应语言的相关代码。
4. 支持双向流。`gRPC` 支持基于 `HTTP/2` 的双向流，即客户端和服务端均可以向对方读写流数据。
5. 插件化。内置可插拔的负载均衡、跟踪、健康检查和身份验证插件。
6. 微服务。`gRPC` 非常适合微服务框架，且有众多微服务框架均支持 `gRPC`。
7. 高性能。得益于 `HTTP/2` 的链路复用能力，`gRPC` 可以在同一个连接上同时处理多个请求，同时得益于 `pb` 为编码出包更快更小的二进制数据包，从而提高了性能。

这些特性使得 `gRPC` 在微服务架构中的应用非常广泛。以 Go 语言为例，主流的微服务框架 `go-micro`, `go-zero`, `go-kit`, `kratos` 等都是默认支持 `gRPC` 的。

## 3. gRPC 的使用

### 3.1 生成 gRPC 代码

在 `proto` 文件定义服务后，我们通过 `protoc` 工具生成 `gRPC` 的代码。此时需要在生成命令中添加 `--go-grpc_out` 参数来指定生成代码的路径和其他参数。以下面的简单 `proto` 文件为例：

```protobuf
// 为了演示，这里返回值定义为空的结构
message Empty {
}

// 定义服务和其方法
// 为确保生成的代码尽量简单，我们只定义了两个方法
service OrderService {
  rpc GetOrder(Empty) returns (Empty) {}
  rpc CreateOrder(Empty) returns (Empty) {}
}
```

我们执行 `protoc --go_out=paths=source_relative:. --go-grpc_out=paths=source_relative:. proto_file` 命令，生成代码后，我们可以看到在当前目录下会生成两个文件，分别是 `order_service.pb.go` 和 `order_service_grpc.pb.go`。第一个文件包含所以定义的 `enmu`, `message` 以及 pb 文件的信息所对应的 Go 代码，第二个文件包含所以定义的 `service` 和 `rpc` 所对应的 Go 代码。本篇不讨论第一个文件内容。我们现在来看一下 `order_service_grpc.pb.go` 文件和核心内容（篇幅原因会忽略一些非必要代码的展示）。

#### 3.1.1 客户端相关代码

客户端代码相对来说比较简单好理解，定了 `OrderServiceClient` 之后实现这个接口，而显示方式就是通过 `gRPC` 连接去调用服务端的 `OrderService` 服务的对应的方法。我们看的类似这种 `/api.user.session.v1.OrderService/GetOrder` 字符串可以理解为路由地址，server 端代码生成时会将同样的字符串与其对应的方法共同注册上去，从而确定唯一的方法。

```go
type OrderServiceClient interface {
    GetOrder(ctx context.Context, in *Empty, opts ...grpc.CallOption) (*Empty, error)
    CreateOrder(ctx context.Context, in *Empty, opts ...grpc.CallOption) (*Empty, error)
}

type orderServiceClient struct {
    cc grpc.ClientConnInterface
}

func NewOrderServiceClient(cc grpc.ClientConnInterface) OrderServiceClient {
    return &orderServiceClient{cc}
}

func (c *orderServiceClient) GetOrder(ctx context.Context, in *Empty, opts ...grpc.CallOption) (*Empty, error) {
    out := new(Empty)
    err := c.cc.Invoke(ctx, "/api.user.session.v1.OrderService/GetOrder", in, out, opts...)
    if err != nil {
        return nil, err
    }
    return out, nil
}

func (c *orderServiceClient) CreateOrder(ctx context.Context, in *Empty, opts ...grpc.CallOption) (*Empty, error) {
    out := new(Empty)
    err := c.cc.Invoke(ctx, "/api.user.session.v1.OrderService/CreateOrder", in, out, opts...)
    if err != nil {
        return nil, err
    }
    return out, nil
}
```

我们在自己程序内如果需要调用第三发服务的话，只需要通过 `NewOrderServiceClient` 函数生成 `OrderServiceClient` 实例，然后调用对应的方法即可。如：

```go
// conn 为 grpc connection，可以通过 grpc.Dial 来生成或大部分微服务狂框架都提供了连接方法
resp,err := NewOrderServiceClient(conn).GetOrder(context.Background(), &Empty{})
if err != nil {
    fmt.Println(err)
}
// end of rpc call, do own biz
```

#### 3.1.2 服务端相关代码

服务端代码相对客户端代码会多一些，生成代码分为两部分，一部分是定义 `interface` 然后由一个默认实现类来实现，另一部分是提供注册实现接口的方法。因为我们需要自己去实现定义的服务逻辑，然后注册上去，这样才能让客户端调用。

第一部分代码：

```go
// OrderServiceServer is the server API for OrderService service.
// All implementations must embed UnimplementedOrderServiceServer
// for forward compatibility
// 这里需要说明一下，为了确保服务的稳定性，实现该接口的结构必需包含 UnimplementedOrderServiceServer，这样即便我们只实现其中一部分的方法，也不会导致服务崩溃或不可用。
type OrderServiceServer interface {
    GetOrder(context.Context, *Empty) (*Empty, error)
    CreateOrder(context.Context, *Empty) (*Empty, error)
    mustEmbedUnimplementedOrderServiceServer()
}

// UnimplementedOrderServiceServer must be embedded to have forward compatible implementations.
type UnimplementedOrderServiceServer struct {
}

func (UnimplementedOrderServiceServer) GetOrder(context.Context, *Empty) (*Empty, error) {
    return nil, status.Errorf(codes.Unimplemented, "method GetOrder not implemented")
}
func (UnimplementedOrderServiceServer) CreateOrder(context.Context, *Empty) (*Empty, error) {
    return nil, status.Errorf(codes.Unimplemented, "method CreateOrder not implemented")
}
func (UnimplementedOrderServiceServer) mustEmbedUnimplementedOrderServiceServer() {}

// UnsafeOrderServiceServer may be embedded to opt out of forward compatibility for this service.
// Use of this interface is not recommended, as added methods to OrderServiceServer will
// result in compilation errors.
type UnsafeOrderServiceServer interface {
    mustEmbedUnimplementedOrderServiceServer()
}
```

第二部分代码：

```go
// 这里是我们外部注册入口
func RegisterOrderServiceServer(s grpc.ServiceRegistrar, srv OrderServiceServer) {
    s.RegisterService(&OrderService_ServiceDesc, srv)
}
// 每个接口的处理方法，内部调用的是这个方法
func _OrderService_GetOrder_Handler(srv interface{}, ctx context.Context, dec func(interface{}) error, interceptor grpc.UnaryServerInterceptor) (interface{}, error) {
    in := new(Empty)
    if err := dec(in); err != nil {
        return nil, err
    }
    if interceptor == nil {
        return srv.(OrderServiceServer).GetOrder(ctx, in)
    }
    info := &grpc.UnaryServerInfo{
        Server:     srv,
        FullMethod: "/api.user.session.v1.OrderService/GetOrder",
    }
    handler := func(ctx context.Context, req interface{}) (interface{}, error) {
        return srv.(OrderServiceServer).GetOrder(ctx, req.(*Empty))
    }
    return interceptor(ctx, in, info, handler)
}

func _OrderService_CreateOrder_Handler(srv interface{}, ctx context.Context, dec func(interface{}) error, interceptor grpc.UnaryServerInterceptor) (interface{}, error) {
    in := new(Empty)
    if err := dec(in); err != nil {
        return nil, err
    }
    if interceptor == nil {
        return srv.(OrderServiceServer).CreateOrder(ctx, in)
    }
    info := &grpc.UnaryServerInfo{
        Server:     srv,
        FullMethod: "/api.user.session.v1.OrderService/CreateOrder",
    }
    handler := func(ctx context.Context, req interface{}) (interface{}, error) {
        return srv.(OrderServiceServer).CreateOrder(ctx, req.(*Empty))
    }
    return interceptor(ctx, in, info, handler)
}

// OrderService_ServiceDesc is the grpc.ServiceDesc for OrderService service.
// It's only intended for direct use with grpc.RegisterService,
// and not to be introspected or modified (even as a copy)
var OrderService_ServiceDesc = grpc.ServiceDesc{
    ServiceName: "api.user.session.v1.OrderService",
    HandlerType: (*OrderServiceServer)(nil),
    Methods: []grpc.MethodDesc{
        {
            // 内部实现时，先根据 serviceName 确定 service，再根据 methodName 确定 method，然后调用 Handler
            MethodName: "GetOrder", 
            Handler:    _OrderService_GetOrder_Handler,
        },
        {
            MethodName: "CreateOrder",
            Handler:    _OrderService_CreateOrder_Handler,
        },
    },
    Streams:  []grpc.StreamDesc{},
    Metadata: "user/session/v1/session.proto",
}
```

服务端作为实现者，需要定义一个 `struct` 类型且包含 `UnimplementedOrderServiceServer` 的结构体，然后实现 `OrderServiceServer` 的方法，并在服务启动时 注册到 `grpc.Server` 中。如：

```go
// --- service package
package service
// ...
type BizOrder struct {
    // orderpb 包包含我们之前生成的文件
    orderpb.UnimplementedOrderServiceServer
}

func (s *BizOrder) GetOrder(ctx context.Context, in *Empty) (*Empty, error) {
    // do something
    return &Empty{}, nil
}

func (s *BizOrder) CreateOrder(ctx context.Context, in *Empty) (*Empty, error) {
    // do something
    return &Empty{}, nil
}
// --- main package
package main

func main() {
    // ... init gprc server

    // register service
    orderpb.RegisterOrderServiceServer(grpcServer, &service.BizOrder{})
}
```

## 4. gRPC 的编程模型

grpc 编程模型可以分为三种情况，分别是应答模式，单向流模式，双向流模式。应答模式是指客户端发送一个请求，服务端返回一个响应（常见的 http request-response 模式）。单向流模式是客户端和服务端其中一方以流的形式持续读/写数据，另一方只需要一次请求或响应。双向流模式，顾名思义，是客户端和服务端双方均以流的形式持续读/写数据，直到其中一方关闭连接。下面分别讲解这三种模式的使用和实现细节。

### 4.1 应答模式

这个模式属于是最常见大家最熟悉的一种模式，在我们定义服务的方法的时候也是基本用的是应答模式。我们上面提到的 `GetOrder` 方法，就是一个应答模式的例子。请求时构造输入参数，然后等到响应返回，然后结束这次远程调用，这就是应答模式。

#### 4.1.1 使用

该方式的使用我们在上面其实以及演示过了，这里不再赘述。点击这里[跳回查看](#311-客户端相关代码)

#### 4.1.2 实现

一次客户端远程调用服务端方法的流程步骤大致如下：


### 4.2 单向流模式

#### 4.2.1 使用

#### 4.2.2 实现

### 4.3 双向流模式

#### 4.3.1 使用

#### 4.3.2 实现

## 5. gRPC 中数据传输

## 6. 其他补充

## 7. 总结

## 8. 链接🔗

- [https://grpc.io/](https://grpc.io/)
