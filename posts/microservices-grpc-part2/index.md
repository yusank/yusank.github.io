# [系列]微服务·深入了解gRPC Part2


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

而数据流模式从细节上可以有三种情况，而这三种情况各有一些细节上的区别，下面我们来看看这三种情况。

### 2.1 客户端单向数据流

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

### 2.2 服务端单向数据流

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

### 2.3 双向数据流

双向数据流可以理解为上面两种数据流模型的组合，客户端和服务端均可以向 socket 写入流数据，同时可以从 socket 读取流数据。

首先定义 rpc 方法：

```proto
service OrderService {
  rpc BothWayStream(stream Empty) returns (stream Empty) {}
}
```

生成的客户端侧代码如下：

```go
// For semantics around ctx use and closing/ending streaming RPCs, please refer to https://pkg.go.dev/google.golang.org/grpc/?tab=doc#ClientConn.NewStream.
type OrderServiceClient interface {
    BothWayStream(ctx context.Context, opts ...grpc.CallOption) (OrderService_BothWayStreamClient, error)
}

type OrderService_BothWayStreamClient interface {
    Send(*Empty) error
    Recv() (*Empty, error)
    grpc.ClientStream
}
```

客户端发起请求后，拿到一个 `OrderService_BothWayStreamClient` 对象，然后调用 `Send` 方法，向服务端写入数据，然后调用 `Recv` 方法，接收服务端的数据流，一直到报错或自己逻辑中断。

服务端侧生成的代码如下：

```go
type OrderServiceServer interface {
    BothWayStream(OrderService_BothWayStreamServer) error
}

type OrderService_BothWayStreamServer interface {
    Send(*Empty) error
    Recv() (*Empty, error)
    grpc.ServerStream
}
```

而服务端的定义的方式接受的参数是 `OrderService_BothWayStreamServer` 对象，通过该对象的 `Send` 方法向客户端写入数据，通过 `Recv` 方法接收客户端的数据流。

以实现一个 ssh proxy 的例子来介绍双向数据流模式的使用：

客户端的实现：

```go
func client(stdin io.Reader, stdout io.Writer) error {
    // 定义一个双向数据流
    stream, err := orderpb.NewOrderServiceClient(grpcConn).BothWayStream(ctx)
    if err != nil {
        return
    }

    // read from stdin
    go func() {
        buf := make([]byte, 1024)
        for {
            n, err := stdin.Read(buf)
            if err != nil {
                return
            }
            err = stream.Send(&orderpb.Empty{buf})
            if err != nil {
                return
            }
        }
    }()

    // write to stdout
    for {
        empty, err := stream.Recv()
        if err != nil {
            return err
        }
        _, err = stdout.Write(empty.Data)
        if err != nil {
            return err
        }
    }
}
```

服务端的实现：

```go
func server(stream orderpb.OrderService_BothWayStreamServer) error {
    for {
        req, err := stream.Recv()
        if err != nil {
            return err
        }
        // do something with req
        resp := doSomething(req)
        err = stream.Send(resp)
        if err != nil {
            return err
        }
    }
}
```

以上就是三种数据流模式的定义和使用示例，下面我们从源码层面去理解，客户端/服务端是如何实现的读写流数据的。

### 2.4 数据流的实现

数据流的实现我们分成客户端和服务端来讲解。

#### 2.4.1 客户端读写数据流

客户端的数据流通过 `ClientStream` 接口实现，客户端对当前数据流的操作都是通过 `ClientStream` 接口来实现的，比如 `Send`、`Recv` 这些方法都是基于 `SendMsg`、`RecvMsg` 方法封装的。

```go
// ClientStream defines the client-side behavior of a streaming RPC.
//
// All errors returned from ClientStream methods are compatible with the
// status package.
type ClientStream interface {
    // Header returns the header metadata received from the server if there
    // is any. It blocks if the metadata is not ready to read.
    Header() (metadata.MD, error)
    // Trailer returns the trailer metadata from the server, if there is any.
    // It must only be called after stream.CloseAndRecv has returned, or
    // stream.Recv has returned a non-nil error (including io.EOF).
    Trailer() metadata.MD
    // CloseSend closes the send direction of the stream. It closes the stream
    // when non-nil error is met. It is also not safe to call CloseSend
    // concurrently with SendMsg.
    CloseSend() error
    // Context returns the context for this stream.
    //
    // It should not be called until after Header or RecvMsg has returned. Once
    // called, subsequent client-side retries are disabled.
    Context() context.Context
    // SendMsg is generally called by generated code. On error, SendMsg aborts
    // the stream. If the error was generated by the client, the status is
    // returned directly; otherwise, io.EOF is returned and the status of
    // the stream may be discovered using RecvMsg.
    //
    // SendMsg blocks until:
    //   - There is sufficient flow control to schedule m with the transport, or
    //   - The stream is done, or
    //   - The stream breaks.
    //
    // SendMsg does not wait until the message is received by the server. An
    // untimely stream closure may result in lost messages. To ensure delivery,
    // users should ensure the RPC completed successfully using RecvMsg.
    //
    // It is safe to have a goroutine calling SendMsg and another goroutine
    // calling RecvMsg on the same stream at the same time, but it is not safe
    // to call SendMsg on the same stream in different goroutines. It is also
    // not safe to call CloseSend concurrently with SendMsg.
    SendMsg(m interface{}) error
    // RecvMsg blocks until it receives a message into m or the stream is
    // done. It returns io.EOF when the stream completes successfully. On
    // any other error, the stream is aborted and the error contains the RPC
    // status.
    //
    // It is safe to have a goroutine calling SendMsg and another goroutine
    // calling RecvMsg on the same stream at the same time, but it is not
    // safe to call RecvMsg on the same stream in different goroutines.
    RecvMsg(m interface{}) error
}
```

我们现在一起过一下一次 `SendMsg` 的流程：

1. 客户端调用 `OrderServiceClient.BothWayStream` 方法。
2. `BothWayStream` 调用 `grpcConn.NewStream` 方法创建一个新的数据流。而 `grpcConn.NewStream` 方法主要做以下几件事：
   1. 解析服务端的地址，并创建一个连接。
   2. 初始化 http2 transport，并创建一个新的 http2 stream。
   3. 将 http2 stream, http2 transport 和其他 dial 参数封装成一个 `clientStream` 对象。
3. 调用 `clientStream.SendMsg` 方法发送数据。而 `clientStream.SendMsg` 方法内主要做以下几件事：
   1. 将消息 encode, compress 和处理 header
   2. 将消息写入到 http2 transport 中。从这里开始往下逻辑与上一篇讲到的应答模式实现时一样的，都是由 http2 client 来实现的。

{{< image src="grpc-stream-send.png" caption="客户端写入数据流程(点击放大)" width="1200" >}}

下面我们看一下接受消息 `RecvMsg` 的流程：

1. 与上面一样，先初始化 `grpcConn.ClientStream` 对象。
2. 调用 `clientStream.Recv.Msg` 方法读取数据。而 `clientStream.Recv.Msg` 方法内主要做以下几件事：
   1. 从 http2 transport 中读取数据。
   2. 解析数据，并将数据解压和 decode。
   3. 将数据解析成消息。

读取消息的相关代码：

```go
// parser reads complete gRPC messages from the underlying reader.
type parser struct {
    // r is the underlying reader.
    // See the comment on recvMsg for the permissible
    // error types.
    r io.Reader

    // The header of a gRPC message. Find more detail at
    // https://github.com/grpc/grpc/blob/master/doc/PROTOCOL-HTTP2.md
    header [5]byte
}

func (p *parser) recvMsg(maxReceiveMessageSize int) (pf payloadFormat, msg []byte, err error) {
    // p.r 是 http2 stream 的 reader。
    if _, err := p.r.Read(p.header[:]); err != nil {
        return 0, nil, err
    }

    // 第一位记录消息类型
    pf = payloadFormat(p.header[0])
    // 会四位记录消息长度
    length := binary.BigEndian.Uint32(p.header[1:])

    if length == 0 {
        return pf, nil, nil
    }
    if int64(length) > int64(maxInt) {
        return 0, nil, status.Errorf(codes.ResourceExhausted, "grpc: received message larger than max length allowed on current machine (%d vs. %d)", length, maxInt)
    }
    if int(length) > maxReceiveMessageSize {
        return 0, nil, status.Errorf(codes.ResourceExhausted, "grpc: received message larger than max (%d vs. %d)", length, maxReceiveMessageSize)
    }
    // TODO(bradfitz,zhaoq): garbage. reuse buffer after proto decoding instead
    // of making it for each message:
    msg = make([]byte, int(length))
    if _, err := p.r.Read(msg); err != nil {
        if err == io.EOF {
            err = io.ErrUnexpectedEOF
        }
        return 0, nil, err
    }
    return pf, msg, nil
}
```

{{< image src="grpc-stream-recv.png" caption="客户端读取数据流程(点击放大)" width="400" >}}

{{< admonition type=warning title="注意" open=true >}}
我们在前面的单向流过程中看到了类似 `CloseAndRecv` 的方法，而这种带有 close 的方法是由 `ClientStream` 的 `CloseSend` 方法来实现的。
而这个方法的实现也相对简单，是在向 http2 transport 写入消息的同时带上一个 option 值来实现的，源码如下：

```go
func (cs *clientStream) CloseSend() error {
    if cs.sentLast {
        // TODO: return an error and finish the stream instead, due to API misuse?
        return nil
    }
    cs.sentLast = true
    op := func(a *csAttempt) error {
        // 在这里带上一个 Last 标记，表示这是最后一个消息。
        a.t.Write(a.s, nil, nil, &transport.Options{Last: true})
        // Always return nil; io.EOF is the only error that might make sense
        // instead, but there is no need to signal the client to call RecvMsg
        // as the only use left for the stream after CloseSend is to call
        // RecvMsg.  This also matches historical behavior.
        return nil
    }
    cs.withRetry(op, func() { cs.bufferForRetryLocked(0, op) })
    // We never returned an error here for reasons.
    return nil
}
```

而 http2 transport 在写入消息时，如果这个标志位是 true，则将这个 stream（这个连接）标记为写入完成的标识，表示不再写新的消息。源码如下：

```go
// Write formats the data into HTTP2 data frame(s) and sends it out. The caller
// should proceed only if Write returns nil.
func (t *http2Client) Write(s *Stream, hdr []byte, data []byte, opts *Options) error {
    if opts.Last {
        // If it's the last message, update stream state.
        // 这里！！！
        // 如果当前状态是 active 则，将其置位 streamWriteDone， 然后下面写操作继续执行。
        if !s.compareAndSwapState(streamActive, streamWriteDone) {
            return errStreamDone
        }
        // 下次有新消息要写时，会报错
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
    // 这个就是上面流程提到的 buffer
    return t.controlBuf.put(df)
}
```

{{< /admonition >}}

#### 2.4.2 服务端读写流数据

与客户端逻辑类似，服务端的数据流读写也是基于一个接口定义(`ServerStream`)调用的，这个接口定义如下：

```go
// ServerStream defines the server-side behavior of a streaming RPC.
//
// Errors returned from ServerStream methods are compatible with the status
// package.  However, the status code will often not match the RPC status as
// seen by the client application, and therefore, should not be relied upon for
// this purpose.
type ServerStream interface {
    // SetHeader sets the header metadata. It may be called multiple times.
    // When call multiple times, all the provided metadata will be merged.
    // All the metadata will be sent out when one of the following happens:
    //  - ServerStream.SendHeader() is called;
    //  - The first response is sent out;
    //  - An RPC status is sent out (error or success).
    SetHeader(metadata.MD) error
    // SendHeader sends the header metadata.
    // The provided md and headers set by SetHeader() will be sent.
    // It fails if called multiple times.
    SendHeader(metadata.MD) error
    // SetTrailer sets the trailer metadata which will be sent with the RPC status.
    // When called more than once, all the provided metadata will be merged.
    SetTrailer(metadata.MD)
    // Context returns the context for this stream.
    Context() context.Context
    // SendMsg sends a message. On error, SendMsg aborts the stream and the
    // error is returned directly.
    //
    // SendMsg blocks until:
    //   - There is sufficient flow control to schedule m with the transport, or
    //   - The stream is done, or
    //   - The stream breaks.
    //
    // SendMsg does not wait until the message is received by the client. An
    // untimely stream closure may result in lost messages.
    //
    // It is safe to have a goroutine calling SendMsg and another goroutine
    // calling RecvMsg on the same stream at the same time, but it is not safe
    // to call SendMsg on the same stream in different goroutines.
    SendMsg(m interface{}) error
    // RecvMsg blocks until it receives a message into m or the stream is
    // done. It returns io.EOF when the client has performed a CloseSend. On
    // any non-EOF error, the stream is aborted and the error contains the
    // RPC status.
    //
    // It is safe to have a goroutine calling SendMsg and another goroutine
    // calling RecvMsg on the same stream at the same time, but it is not
    // safe to call RecvMsg on the same stream in different goroutines.
    RecvMsg(m interface{}) error
}
```

与 `ClientStream` 类似，但是少了一些方法，比如 `CloseSend` 。

我们先看一下，一次请求是如何进入到我们实现的方法，然后再看数据流的读写。由于 http2 中所有的请求都是 stream，所以这块接受请求的流程与上篇讲述的很类似而且前面几步都是公用的代码，而不同点从 `processStreamingRPC` 方法开始(前面的步骤不再重复讲解)。

1. 在 `processStreamingRPC` 方法内，先根据上下文创建 `serverStream`, 它包含了 transport, stream, encode 等需要的信息。
2. 通过 header 读取 compress 方法。
3. 调用注册的 handler 来处理请求。
4. handler 结束或者报错后，打日志然后向 stream 写入 status 并关闭 stream。

{{< image src="grpc-handle.png" caption="接受请求过程" >}}

{{< image src="grpc-stream-server-init.png" caption="调用实现的方法过程" >}}

下面我们看一下 `SendMsg` 的实现。server 端的写入消息的实现与 client 端基本一致，并且底层调用的方法是一样的，这里过一下流程，流程图就不再重复画了。

1. 调用 `SendMsg` 方法后，根据消息内容和 encode 方法，进行消息的 encode ，压缩和写入 header
2. 然后调用 http2 transport 的write 方法，这个方法我们已经遇到好几次了，所有涉及到写操作的底层都是这个方法。
3. 检查写入是否报错，如果有则将错误 status 写入 stream 并结束 stream。

而 `RecvMsg` 方法的实现也是公用的，底层与 client 端基本一致，都使用 `recv()` 方法实现数据的接受和解码。请移步到 client 端接受数据的实现。

## 4. 性能调优

`MaxSendMsgSizeGRPC` 最大允许发送的字节数，默认4MiB，如果超过了GRPC会报错。如果有传输大数据的需求，请适当调高这个参数。

`MaxRecvMsgSizeGRPC`  最大允许接收的字节数，默认4MiB，如果超过了GRPC会报错。同上。

`InitialWindowSize` 基于Stream的滑动窗口，类似于TCP的滑动窗口，用来做流控，默认64KiB，吞吐量上不去，根据自己的流量往上调整。

`InitialConnWindowSize` 基于Connection的滑动窗口，默认 64KiB，吞吐量上不去，同上。

至于 `MaxConcurrentStreams` 的配置（一个连接上的并发 stream 数量），很多文章指出默认是 100，会影响性能，其实不对的。从源码层面来看， http2 server 端支持配置这个参数，但是默认是 0，而该值为 0 的时候，server 端 transport 初始化时做了判断的，如果是 0，则会设置为 `math.MaxUint32`。

```go
    // TODO(zhaoq): Have a better way to signal "no limit" because 0 is
    // permitted in the HTTP2 spec.
    maxStreams := config.MaxStreams
    if maxStreams == 0 {
        // 注意看这里！
        maxStreams = math.MaxUint32
    } else {
        isettings = append(isettings, http2.Setting{
            // 请记住这个 ID
            ID:  http2.SettingMaxConcurrentStreams,
            Val: maxStreams,
        })
    }
```

而 client 端初始化一个新的 http2 client 时，也有一个 `maxConcurrentStreams` 参数且默认值的确是 `100`，这个参数是用来限制 client 端的并发 stream 数量的，如果超过了这个值，则会报错。但是这个 100 并非是最终的值，在 client 初始化方法中有个异步处理的流程：

```go
    // http2_client.go:newHTTP2Client()
    // 
    // Start the reader goroutine for incoming message. Each transport has
    // a dedicated goroutine which reads HTTP2 frame from network. Then it
    // dispatches the frame to the corresponding stream entity.
    go t.reader()

    // http2_client.go:http2Client.reader()
    t.handleSettings(sf, true/*isFirst*/)
```

而这个 `t.handleSettings` 是关键方法，它给 client 的一些参数进行了重新赋值，让我们看一下源码：

```go
// http2_client.go:http2Client.handleSettings()
// http2.SettingFrame 是从服务端读取的数据
func (t *http2Client) handleSettings(f *http2.SettingsFrame, isFirst bool) {
    if f.IsAck() {
        return
    }
    var maxStreams *uint32
    var ss []http2.Setting
    var updateFuncs []func()
    f.ForeachSetting(func(s http2.Setting) error {
        switch s.ID {
            // 请注意这个 ID，这是服务端设置的
        case http2.SettingMaxConcurrentStreams:
            maxStreams = new(uint32)
            *maxStreams = s.Val // 也就是这个值现在是 math.MaxUint32
            // 这也是从服务端设置的参数
        case http2.SettingMaxHeaderListSize:
            updateFuncs = append(updateFuncs, func() {
                t.maxSendHeaderListSize = new(uint32)
                *t.maxSendHeaderListSize = s.Val
            })
        default:
            ss = append(ss, s)
        }
        return nil
    })
    // 此时 maxStreams != nil
    if isFirst && maxStreams == nil {
        maxStreams = new(uint32)
        *maxStreams = math.MaxUint32
    }
    sf := &incomingSettings{
        ss: ss,
    }
    if maxStreams != nil {
        updateStreamQuota := func() {
            delta := int64(*maxStreams) - int64(t.maxConcurrentStreams)
            t.maxConcurrentStreams = *maxStreams // 这里重新赋值了 现在 t.maxConcurrentStreams == math.MaxUint32
            t.streamQuota += delta
            if delta > 0 && t.waitingStreams > 0 {
                close(t.streamsQuotaAvailable) // wake all of them up.
                t.streamsQuotaAvailable = make(chan struct{}, 1)
            }
        }
        updateFuncs = append(updateFuncs, updateStreamQuota)
    }
    // executeAndPut 会直接执行这个方法
    t.controlBuf.executeAndPut(func(interface{}) bool {
        for _, f := range updateFuncs {
            f()
        }
        return true
    }, sf)
}
```

也就是说虽然client 端的确默认值是 0，但是由于服务端默认不赋值从而设置的是 `math.MaxUint32`，所以 client 端的默认值也是 `math.MaxUint32`。

对于想更进一步优化性能的同学，建议最好看一下 `grpc/transport` 包下的实现 `http2` 客户端/服务端的代码，了解一下连接管理和数据传输过程，看一下哪些参数会对数据传输大小延迟有影响，从而针对性的优化。

## 6. 总结

本篇主要讲述：

1. 了解 grpc 的流式编程模式的使用，包括单向流和双向流。
2. 了解 grpc 的客户端和服务端如何实现流式数据的读写并了解客户端服务端的读写数据时的函数调用流程。
3. 了解常见 grpc 的性能调优并澄清一个常见的关于 `maxConcurrentStreams` 的误解。

