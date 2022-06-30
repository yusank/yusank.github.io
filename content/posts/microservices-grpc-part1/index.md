---
title: "[系列]微服务·深入了解gRPC Part1"
date: 2022-06-29T10:10:00+08:00
lastmod: 2022-06-29T10:10:00+08:00
categories: ["microservice"]
tags: ["微服务","系列篇","grpc"]
draft: false
lightgallery: true
---

> 本文为系列篇`微服务`的关于 深入 gRPC 的文章。本篇将会从 gRPC 的基本概念、gRPC 的使用、gRPC 的编程模型、gRPC 的编程模型的实现、gRPC 的编程模型的实现的细节等多个角度来了解。
>
> 本篇为 `深入了解gRPC` 的下篇，篇幅原因，将这篇文章拆分成上下篇，下篇继续更新中。

<!--more-->

## 1. 前言

gRPC 作为一个 Google 开源的 RPC 框架，由于其优异的性能和支持多种流行语言的特点，被众多的开发者所熟悉。我接触 gRPC 也有至少五年的时间，但是由于种种原因，在很长时间内对 gRPC 的了解处于一个入门或者只是知道个大概的水平。直到大概 2~3 年前在上家公司机缘巧合的缘故，需要对部门内做一次关于 gRPC 的知识分享，而那次我花了 2 周多的时间去了解去背后的原理、实现、数据流向。那时候我记得是白班分享没有写 PPT，所以那时候对这些知识点有了比较深刻的理解。

然而，我上家我所在部门的业务几乎没有涉及到 gRPC 的开发，因此这些理解只是变成一个知道的概念，并没有在实际开发工作中提到实际的应用。但是从那次分享后，我对 gRPC 有了一些迷恋现象，想做一些实际的 gRPC 相关项目，从实际项目中提炼自己的知识面。

到现在，我回过头来看，以及参与了几个基于 gRPC 通信的项目以及基于 gRPC 的微服务框架，最近也在写一个比较完整的微服务项目，也是基于 gRPC 通信。的确从实践中提炼到了一定的知识，自己对整体的理解也有了一定的提升。

今天想写这篇文章的原因有两个，其一是我前前后后对 gRPC 有了很多的交集并且也在上家极力推荐使用（但是能力不够，没能推广起来），我对这块有了一些自己的看法和观点，但是一直没有一个比较完整的记录。其二是之前与大学同学做一次线上分享的时候，有人提问关于 gRPC 的性能问题（由于其基于 `HTTP/2`,所以对其性能持怀疑态度），我觉得这个问题确实也是需要一个深究的问题，所以这篇文章也会提到相关内容。

因此，这篇文件将会从 gRPC 的基本概念、gRPC 的使用、gRPC 的编程模型、gRPC 的编程模型的实现、gRPC 的编程模型的实现的细节等多个角度来一一进行讲解，给自己一个总结，给对这方面有疑问的同学一定的帮助。

{{< admonition type=warning title="注意" open=true >}}

1. 本篇所有的示例代码均用 Go
2. 本篇完全以个人的理解和官方文档为准，若有错误不准之处，请帮忙支持评论一下，谢谢！

{{< /admonition >}}

## 2. gRPC 的基本概念

{{< admonition type=note title="Definition by official" open=true >}}
gRPC is a modern open source high performance Remote Procedure Call (RPC) framework that can run in any environment. It can efficiently connect services in and across data centers with pluggable support for load balancing, tracing, health checking and authentication. It is also applicable in last mile of distributed computing to connect devices, mobile applications and browsers to backend services.
{{< /admonition >}}

简单来说，gRPC 是一个高性能的远程过程调用框架，可以在任何环境中运行，可以在数据中心之间高效地连接服务，并且支持负载均衡、跟踪、健康检查和身份验证。它还适用于分布式计算，将设备、移动应用和浏览器连接到后端服务。 gRPC 是由 `CNCF` 孵化的项目,目前在 GitHub 上有 `43.8k` 的 star 和 `9.2k` 的 fork。gRPC 有以下几个核心特点：

1. 简单的服务定义。通过 `Protocol Buffer` 去定义数据结构和服务的接口 (关于 pb 更详细的介绍请查这篇：[[系列]微服务·如何通过 protobuf 定义数据和服务](../microservices-protobuf))。
2. 快速使用。仅通过一行代码就进行服务注册和远程调用。
3. 跨语言和平台。gRPC 支持众多主流语言，可以在不同语言之间无缝远程调用且均可通过 pb 生成对应语言的相关代码。
4. 支持双向流。gRPC 支持基于 `HTTP/2` 的双向流，即客户端和服务端均可以向对方读写流数据。
5. 插件化。内置可插拔的负载均衡、跟踪、健康检查和身份验证插件。
6. 微服务。gRPC 非常适合微服务框架，且有众多微服务框架均支持 gRPC。
7. 高性能。得益于 `HTTP/2` 的链路复用能力，gRPC 可以在同一个连接上同时处理多个请求，同时得益于 `pb` 为编码出包更快更小的二进制数据包，从而提高了性能。

这些特性使得 gRPC 在微服务架构中的应用非常广泛。以 Go 语言为例，主流的微服务框架 `go-micro`, `go-zero`, `go-kit`, `kratos` 等都是默认支持 gRPC 的。

## 3. gRPC 的使用

### 3.1 生成 gRPC 代码

在 `proto` 文件定义服务后，我们通过 `protoc` 工具生成 gRPC 的代码。此时需要在生成命令中添加 `--go-grpc_out` 参数来指定生成代码的路径和其他参数。以下面的简单 `proto` 文件为例：

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

我们执行 `protoc --go_out=paths=source_relative:. --go-grpc_out=paths=source_relative:. proto_file` 命令，生成代码后，我们可以看到在当前目录下会生成两个文件，分别是 `order_service.pb.go` 和 `order_service_grpc.pb.go`。第一个文件包含所以定义的 enum, message 以及 pb 文件的信息所对应的 Go 代码，第二个文件包含所以定义的 service 所对应的 Go 代码。本篇不讨论第一个文件内容。我们现在来看一下 `order_service_grpc.pb.go` 文件和核心内容（篇幅原因会忽略一些非必要代码的展示）。

#### 3.1.1 客户端相关代码

客户端代码相对来说比较简单好理解，定了 `OrderServiceClient` 之后实现这个接口，而显示方式就是通过 gRPC 连接去调用服务端的 `OrderService` 服务的对应的方法。我们看的类似这种 `/api.user.session.v1.OrderService/GetOrder` 字符串可以理解为路由地址，server 端代码生成时会将同样的字符串与其对应的方法共同注册上去，从而确定唯一的方法。

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

grpc 编程模型可以从大体上分为两种情况，分别是应答模式，数据流模式。应答模式是指客户端发送一个请求，服务端返回一个响应（常见的 http request-response 模式），然后这次请求完成。而数据流模式是客户端和服务端其中一方以流的形式持续读/写数据（也可能双方都是持续读写，双向流），另一方只需要一次请求或响应（如果是双向流则均可以多次读写）。

### 4.1 应答模式

这个模式属于是最常见大家最熟悉的一种模式，在我们定义服务的方法的时候也是基本用的是应答模式。我们上面提到的 `GetOrder` 方法，就是一个应答模式的例子。请求时构造输入参数，然后等到响应返回，然后结束这次远程调用，这就是应答模式。

#### 4.1.1 使用

该方式的使用我们在上面其实以及演示过了，这里不再赘述。点击这里[跳回查看](#311-客户端相关代码)

#### 4.1.2 实现

**一次客户端远程调用服务端方法的流程步骤大体如下：**

1. 客户端调用对应的 Client 方法
2. client 方法实现内调用 `invoke` 方法 并带上对应的 method 和其他参数
3. `invoke` 方法内总共分三步：
    1. 创建一个 `ClientStream` 对象，初始化请求需要的参数，确定请求 endpoint 地址，初始化 buffer size，获取 http2 transport 对象等
    2. 调用 `ClientStream.SendMsq` 方法。首先初始化请求 header, payload 和 data， 然后调用 http2 client 的 `Write` 方法，该方法是异步处理请求的，会把 send request 写入到一个单向链表内，然后由一个单独的 goroutine 去消费这个链表上的数据，然后批量写入到 socket 中。

   write:

   ```go
   // Write formats the data into HTTP2 data frame(s) and sends it out. The caller
    // should proceed only if Write returns nil.
    func (t *http2Client) Write(s *Stream, hdr []byte, data []byte, opts *Options) error {
        if opts.Last {
            // If it's the last message, update stream state.
            if !s.compareAndSwapState(streamActive, streamWriteDone) {
                return errStreamDone
            }
        } else if s.getState() != streamActive {
            return errStreamDone
        }
        df := &dataFrame{
            streamID:  s.id,
            endStream: opts.Last,
            h:         hdr,
            d:         data,
        }
        if hdr != nil || data != nil { // If it's not an empty data frame, check quota.
            if err := s.wq.get(int32(len(hdr) + len(data))); err != nil {
                return err
            }
        }
        // controlBuf 底层为一个缓冲区，用于存储控制数据，比如 header 和 data。基于单向链表实现
        return t.controlBuf.put(df)
    }
    // writeLoop 内部调用 write 方法，循环发送数据
   ```

   read from buf and write to socket:

   ```go
    // 这段注释其实写的很详细了，我们可以看到，这里的 writeLoop 内部调用了 write 方法，然后再调用了一个单独的 goroutine，这个 goroutine 就
    // 是一个单向链表的消费者，直到链表为空，然后再一次性写入到 socket 中。
    // run should be run in a separate goroutine.
    // It reads control frames from controlBuf and processes them by:
    // 1. Updating loopy's internal state, or/and
    // 2. Writing out HTTP2 frames on the wire.
    //
    // Loopy keeps all active streams with data to send in a linked-list.
    // All streams in the activeStreams linked-list must have both:
    // 1. Data to send, and
    // 2. Stream level flow control quota available.
    //
    // In each iteration of run loop, other than processing the incoming control
    // frame, loopy calls processData, which processes one node from the activeStreams linked-list.
    // This results in writing of HTTP2 frames into an underlying write buffer.
    // When there's no more control frames to read from controlBuf, loopy flushes the write buffer.
    // As an optimization, to increase the batch size for each flush, loopy yields the processor, once
    // if the batch size is too low to give stream goroutines a chance to fill it up.
    func (l *loopyWriter) run() (err error) {
        defer func() {
            if err == ErrConnClosing {
                // Don't log ErrConnClosing as error since it happens
                // 1. When the connection is closed by some other known issue.
                // 2. User closed the connection.
                // 3. A graceful close of connection.
                if logger.V(logLevel) {
                    logger.Infof("transport: loopyWriter.run returning. %v", err)
                }
                err = nil
            }
        }()
        for {
            it, err := l.cbuf.get(true)
            if err != nil {
                return err
            }
            if err = l.handle(it); err != nil {
                return err
            }
            if _, err = l.processData(); err != nil {
                return err
            }
            gosched := true
        hasdata:
            for {
                it, err := l.cbuf.get(false)
                if err != nil {
                    return err
                }
                if it != nil {
                    // 根据数据类型做不同的处理
                    // 如果是stream data，则会把数据写入到 loopWriter 的 activeStreams 中， 也是个单向链表
                    if err = l.handle(it); err != nil {
                        return err
                    }
                    // 从 activeStreams 中读取一个数据 然后把数据写入到 loopWriter 的 frameBuf 中
                    // 该方法的第一参数为 bool，当 activeStreams 为空是返回true，否则返回false
                    if _, err = l.processData(); err != nil {
                        return err
                    }
                    // 读完读取下一个
                    continue hasdata
                }
                isEmpty, err := l.processData()
                if err != nil {
                    return err
                }
                // activeStreams 中依然有数据还没 process
                if !isEmpty {
                    continue hasdata
                }
                if gosched {
                    gosched = false
                    // 如果当前处理的数据大小小于 minBatchSize（1000），则休眠一下，等待下一次的数据
                    if l.framer.writer.offset < minBatchSize {
                        runtime.Gosched()
                        continue hasdata
                    }
                }
                // 数据 flush 到 socket
                l.framer.writer.Flush()
                break hasdata

            }
        }
    }
    ```

    3. 调用 `ClientStream.RecvMsg` 方法。该方法会先响应的 header 消息，从 header 读取数据 encoding，然后根据 encoding 读取数据解压数据，并把数据绑定到这次请求响应的 pb message 结构上。最后会调用 `ClientStream.finish` 方法，表示结束该请求。

{{< image src="grpc-invoke.png" caption="客户端请求流程(点击放大)" width="1200" >}}

**一次服务端收到一个请求，然后处理完响应回去的流程是这样的：**

1. grpc 服务启动，开始监听端口
2. net.Listener.Accept() 获取到一个连接
3. 启动一个 `goroutine`, 调用 `s.handleRawConn` 方法去处理这个连接
4. `s.handleRawConn` 方法先创建一个 `http2Transport` 实例，并把这个实例存到server 的conns 字段中
5. `s.handleRawConn` 方法起一个 `goroutine`, 调用 `s.serveStreams` 方法去处理这个连接，这个方法结束后调用 `s.removeConn` 方法，从 server 的 conns 字段中删除这个连接

```go
// handleRawConn forks a goroutine to handle a just-accepted connection that
// has not had any I/O performed on it yet.
func (s *Server) handleRawConn(lisAddr string, rawConn net.Conn) {
    if s.quit.HasFired() {
        rawConn.Close()
        return
    }
    rawConn.SetDeadline(time.Now().Add(s.opts.connectionTimeout))

    // Finish handshaking (HTTP2)
    st := s.newHTTP2Transport(rawConn)
    rawConn.SetDeadline(time.Time{})
    if st == nil {
        return
    }

    if !s.addConn(lisAddr, st) {
        return
    }
    go func() {
        s.serveStreams(st)
        s.removeConn(lisAddr, st)
    }()
}
```

6. `s.serveStreams` 方法是服务端处理连接的主要逻辑，它会调用 `transport.HandleStreams`，然后等待该方法结束
7. `HandleStreams` 方法会处理这次请求的数据和 header，并构造一个 `Stream` 对象，然后调用 `HandleStreams` 传参的 handler

```go
func (ht *serverHandlerTransport) HandleStreams(startStream func(*Stream), traceCtx func(context.Context, string) context.Context) {
    // With this transport type there will be exactly 1 stream: this HTTP request.
    // ...ominous code here...
    s := &Stream{
        id:             0, // irrelevant
        requestRead:    func(int) {},
        cancel:         cancel,
        buf:            newRecvBuffer(),
        st:             ht,
        method:         req.URL.Path,
        recvCompress:   req.Header.Get("grpc-encoding"),
        contentSubtype: ht.contentSubtype,
    }
    pr := &peer.Peer{
        Addr: ht.RemoteAddr(),
    }
    if req.TLS != nil {
        pr.AuthInfo = credentials.TLSInfo{State: *req.TLS, CommonAuthInfo: credentials.CommonAuthInfo{SecurityLevel: credentials.PrivacyAndIntegrity}}
    }
    ctx = metadata.NewIncomingContext(ctx, ht.headerMD)
    s.ctx = peer.NewContext(ctx, pr)
    if ht.stats != nil {
        s.ctx = ht.stats.TagRPC(s.ctx, &stats.RPCTagInfo{FullMethodName: s.method})
        inHeader := &stats.InHeader{
            FullMethod:  s.method,
            RemoteAddr:  ht.RemoteAddr(),
            Compression: s.recvCompress,
        }
        ht.stats.HandleRPC(s.ctx, inHeader)
    }
    // data reader
    s.trReader = &transportReader{
        reader:        &recvBufferReader{ctx: s.ctx, ctxDone: s.ctx.Done(), recv: s.buf, freeBuffer: func(*bytes.Buffer) {}},
        windowHandler: func(int) {},
    }

    // readerDone is closed when the Body.Read-ing goroutine exits.
    readerDone := make(chan struct{})
    go func() {
        defer close(readerDone)

        // TODO: minimize garbage, optimize recvBuffer code/ownership
        const readSize = 8196
        for buf := make([]byte, readSize); ; {
            n, err := req.Body.Read(buf)
            if n > 0 {
                s.buf.put(recvMsg{buffer: bytes.NewBuffer(buf[:n:n])})
                buf = buf[n:]
            }
            if err != nil {
                s.buf.put(recvMsg{err: mapRecvMsgError(err)})
                return
            }
            if len(buf) == 0 {
                buf = make([]byte, readSize)
            }
        }
    }()

    // startStream is provided by the *grpc.Server's serveStreams.
    // It starts a goroutine serving s and exits immediately.
    // The goroutine that is started is the one that then calls
    // into ht, calling WriteHeader, Write, WriteStatus, Close, etc.
    startStream(s)

    ht.runStream()
    close(requestOver)

    // Wait for reading goroutine to finish.
    req.Body.Close()
    <-readerDone
}
```

8. 而 `HandleStreams` 传参的 handler 是主要处理 stream 并调用用户实现的方法。

```go
st.HandleStreams(func(stream *transport.Stream) {
        wg.Add(1)
        // 注意 numServerWorkers 默认是 0，所以不会启动 goroutine
        if s.opts.numServerWorkers > 0 {
            data := &serverWorkerData{st: st, wg: &wg, stream: stream}
            select {
                // 如果配置多个 worker，则一个连接由多个 worker 处理，这些 worker 在初始化时 启动 goroutine，
                // 并读取各自 channel 的值，然后还是会调用 handleStream 方法
            case s.serverWorkerChannels[atomic.AddUint32(&roundRobinCounter, 1)%s.opts.numServerWorkers] <- data:
            default:
                // If all stream workers are busy, fallback to the default code path.
                go func() {
                    s.handleStream(st, stream, s.traceInfo(st, stream))
                    wg.Done()
                }()
            }
        } else {
            // 默认情况下走这个逻辑
            go func() {
                defer wg.Done()
                s.handleStream(st, stream, s.traceInfo(st, stream))
            }()
        }
    }, func(ctx context.Context, method string) context.Context {
        if !EnableTracing {
            return ctx
        }
        tr := trace.New("grpc.Recv."+methodFamily(method), method)
        return trace.NewContext(ctx, tr)
    })
```

9. `s.handleStream` 方法是从 stream 读取 serviceName 和 method，并查找对应的handler，然后调用 `s.processUnaryRPC` 去处理之后的逻辑。如果没有找到服务或方法，则调用 `processStreamingRPC` 并传空的服务信息，由该方法去处理，这个方法在下面的单向流的实现中提到。
10. `s.processUnaryRPC` 从请求 header 读取压缩算法解压数据，读取 encode 类型 unmarshal 数据，然后调用我们实现的方法。调用完成后，将 reply 用同样的压缩算法和 encode 类型进行编码压缩，然后写入到 response 中。

{{< image src="grpc-handle.png" caption="服务端请求处理(点击放大)" width="1200" >}}

## 7. 总结

> 由于篇幅原因，本篇将在这里结束，关于 grpc 的数据流变成模式和相关实现以及其他更多关于 grpc 的内容，请持续关注，我会在下一篇中进行详细的介绍。

本篇主要讲述了：

1. grpc 的概念
2. grpc 的在 go 语言环境下的使用
3. grpc 的常见编程模式之一的应答模式的使用和实现源码解析
