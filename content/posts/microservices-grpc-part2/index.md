---
title: "[系列]微服务·深入了解gRPC Part2"
date: 2022-06-30T10:10:00+08:00
lastmod: 2022-06-30T10:10:00+08:00
categories: ["microservice"]
tags: ["微服务","系列篇","grpc"]
draft: true
lightgallery: true
---

> 本文为系列篇`微服务`的关于 深入 gRPC 的文章。本篇将会从 gRPC 的基本概念、gRPC 的使用、gRPC 的编程模型、gRPC 的编程模型的实现、gRPC 的编程模型的实现的细节等多个角度来了解。
>
> 本篇为 `深入了解gRPC` 的下篇，篇幅原因，将这篇文章拆分成上下篇，点击这里[查看上篇](../microservices-grpc-part1)

<!--more-->

## 1. 前言

上一篇文章介绍了 grpc 的基本概念，基础用法和其基本编程模式 -- `应答模式` 相关的内容，这篇将会继续讲解 grpc 下的编程模式。本篇将会介绍 `数据流编程模式` 的使用和实现，之后介绍 grpc 其他核心逻辑和使用经验。

## 2. 数据流流模式

数据流模式是服务端或客户端以流的形式持续向对方读/写数据，直到任意一方结束这次通信。这种模式的使用场景也比较多，比如：

1. 客户端上传文件，文件被客户端切分成多个块，然后发送给服务端
2. 服务端想客户端下发一个数据流（类似 tail -f 远端文件 or log）或者下载一个较大文件，由服务端分片下发给客户端。
3. 客户端订阅服务端数据。
4. 客户端与服务端进行交互式通信，像聊天一样。

下面我们分别以客户端和服务端为例，来看看客户端和服务端的处理流程。

### 2.1 使用

#### 2.1.1 客户端数据流

首先定义 rpc 方法：

```proto
// 假如批量创建大量订单
rpc CreateOrder(stream Empty) returns (Empty) {}
```

生成的客户端侧代码如下：

```go
type OrderServiceClient interface {
    CreateOrder(ctx context.Context, opts ...grpc.CallOption) (OrderService_CreateOrderClient, error)
}

type OrderService_CreateOrderClient interface {
    Send(*Empty) error
    CloseAndRecv() (*Empty, error)
    grpc.ClientStream
}
```

客户端请求服务端后，得到一个 `OrderService_CreateOrderClient` 对象，然后调用 `Send` 方法，向服务端持续写入 `Empty` 数据，直到最后一次的时候，调用 `CloseAndRecv` 方法，返回服务端的响应。服务端仅在最后一次进行响应。

而服务端侧生成的代码如下：

```go
type OrderServiceServer interface {
    CreateOrder(OrderService_CreateOrderServer) error
}

type OrderService_CreateOrderServer interface {
    SendAndClose(*Empty) error // 实际上并不会执行任何 close 操作，由客户端在 recv 时 close
    Recv() (*Empty, error)
    grpc.ServerStream
}
```

那么对用使用者来说应该如何使用这些生成的代码来实现自己的需求呢？请看使用案例：

```go
// client
func createOrder() error {
    c,err := orderpb.NewOrderServiceClient(grpcConn).CreateOrder(ctx)
    if err != nil {
        return err
    }

    for someCondition {
        if err := c.Send(&orderpb.Empty{});err != nil {
            return err
        }
    }
    // finish send
    empty,err := c.CloseAndRecv()
    if err != nil {
        return err
    }
    // finish recv
    // do something with empty
    return nil
}

// server
func handleCreateOrder(s orderpb.OrderService_CreateOrderServer) error {
    for someCondition {
        empty,err := s.Recv()
        if err != nil {
            return err
        }
        // do something with empty
    }
    // finish recv
    if err := s.SendAndClose(&orderpb.Empty{});err != nil {
        return err
    }
    // finish send
    return nil
}
```

### 2.1.2 服务端数据流

首先定义 rpc 方法：

```proto
// 假如返回的数据量很多 or 需要持续返回最新数据，更多的像一种 订阅模式
rpc GetOrderList(Empty) returns (stream Empty) {}
```

生成的客户端侧代码如下：

```go
type OrderServiceClient interface {
    GetOrderList(ctx context.Context, in *Empty, opts ...grpc.CallOption) (OrderService_GetOrderListClient, error)
}

type OrderService_GetOrderListClient interface {
    Recv() (*Empty, error)
    grpc.ClientStream
}
```

客户端请求服务端后拿到一个 `OrderService_GetOrderListClient` 对象，然后调用 `Recv` 方法，接收服务端的数据流，一直到报错或自己逻辑中断。

服务端侧生成的代码如下：

```go
type OrderServiceServer interface {
    GetOrderList(*Empty, OrderService_GetOrderListServer) error
}

type OrderService_GetOrderListServer interface {
    Send(*Empty) error
    grpc.ServerStream
}
```

服务端收到请求时，会传参 `Empty` 和 `OrderService_GetOrderListServer` 对象，第一个参数是由客户端传过来，第二个参数用来写入数据流。服务端向 `OrderService_GetOrderListServer` 持续写入数据，直到报错或自己逻辑中断。

那么对用使用者来说应该如何使用这些生成的代码来实现自己的需求呢？请看使用案例：

```go
// client
func listOrder() error {
    c,err := orderpb.NewOrderServiceClient(grpcConn).GetOrderList(ctx)
    if err != nil {
        return err
    }

    for someCondition {
        empty,err := c.Recv()
        if err != nil {
            return err
        }
        // do something with empty
    }
    // finish recv
    return nil
}

// server
func handleListOrder(e *orderpb.Empty, s orderpb.OrderService_CreateOrderServer) error {
    for someCondition {
        if err := s.Send(e);err != nil {
            return err
        }
    }
    // finish send
    return nil
}
```

### 2.2 实现

## 3. gRPC 中数据传输

## 4. 性能调优

## 5. 性能对比

## 6. 总结
