# [系列]Redis Server 实现·网络篇


> 这一篇主要是将如何定义一个比较完善的服务入口以及如何管理服务的生命周期、如何处理 `tcp` 的连接管理和请求处理等相关内容。

<!--more-->

{{< admonition type=quote title="说明" open=true >}}
本文章为该系列的`网络篇`，如果需要阅读其他相关文章， 请点击[这里](https://yusank.github.io/posts/redeis-server-introduction/)跳转查看
{{< /admonition >}}

## 定义服务

该项目作为 `Redis Server`, 需要定义一个 Server 对象 作为服务启动关闭及请求处理的的入口。

```go
type Server struct {
    addr     string // 监听 ip:port
    handler  api.Handler // 请求处理方法
    listener net.Listener // 监听入口
}


func NewServer(addr string, h api.Handler) *Server {
    return &Server{
        addr:    addr,
        handler: h,
    }
}
```

## 启动服务

正常监听 tcp 服务，并处理连接即可。

```go
func (s *Server) Start() error {
    l, err := net.Listen("tcp", s.addr)
    if err != nil {
        log.Println("listen err:", err)
        return err
    }
    log.Println("listen: ", l.Addr())
    s.listener = l

    // 阻塞处理
    s.handleListener()
    return nil
}
```

## 处理连接

之后便可以 `accept` 连接请求，处理请求。在每建立一个新的连接的时候，启动一个 `goroutine` 来处理该连接，从而支持高并发的请求。

```go
// Server 内保存 net.Listener 等服务必要参数
func (s *Server) handleListener() {
    for {
        conn, err := s.listener.Accept()
        if err != nil {
            // 如果 listener 已被关闭则退出
            if errors.Is(err, net.ErrClosed) {
                log.Println("closed")
                break
            }

            log.Println("accept err:", err)
            continue
        }

        log.Println("new conn from:", conn.RemoteAddr().String())
        // 处理该请求
        go s.handleConn(conn)
    }
}

```

处理逻辑如下：

```go
// handle by a new goroutine
func (s *Server) handleConn(conn net.Conn) {
    defer func() {
        _ = conn.Close()
    }()

    // 初始化 Server 时，将 handler 也注册进来
    // Handle 方法的核心逻辑时，读取请求内容，根据到 Redis 协议解析内容
    //  并对这次请求做出响应并返回 reply 
    reply, err := s.handler.Handle(reader)
    if err == io.EOF {
        return
    }

    if err != nil {
        log.Println("handle err:", err)
        return
    }

    if len(reply) == 0 {
        return
    }

    _, err = conn.Write(reply)
    if err != nil {
        log.Println("write err:", err)
        return
    }
}
```

## 处理请求

上述处理逻辑中比较重要的一个逻辑是 `handler.Handle(reader)`, 这里面是如何读取请求内容并解析协议的，下面将会以简化的代码逻辑
讲述处理逻辑：

```go
func (TCPHandler) Handle(r api.Reader) ([]byte, error) {
    // io data to protocol msg
    rec, err := protocol.DecodeFromReader(r)
    if err != nil {
        return nil, err
    }
    log.Println(rec)

    rsp := redis.NewCommandFromReceive(rec).Execute(context.Background())
    log.Println("rsp:", debug.Escape(string(rsp.Encode())))
    return rsp.Encode(), err
}

// 1. 读取内容decode协议

type Receive []string

func DecodeFromReader(r api.Reader) (rec Receive, err error) {
    rec = make([]string, 0)
    // read first line
    b, err := r.ReadBytes('\n')
    if err != nil {
        log.Println("readBytes err:", err)
        return nil, err
    }

    // decode line content
    str, length, desc, err := decodeSingleLine(b)
    if err != nil {
        log.Println("init message err:", err)
        return nil, err
    }
    // 如果是 bulk 或者 array 则需要往下读取 length 行
    // length 从第一行内容中解析出来

    if desc == DescriptionBulkStrings {
        temp, err1 := readBulkStrings(r, length)
        if err1 != nil {
            log.Println("read bulk str err:", err1)
            return nil, err1
        }

        rec = append(rec, string(temp))
        return
    }

    if desc == descriptionArrays {
        // won't sava array element
        items, err1 := readArray(r, length)
        if err1 != nil {
            log.Println("read bulk str err:", err1)
            return nil, err1
        }

        rec = append(rec, items...)
        return
    }

    rec = append(rec, str)
    return
}

// 2. 处理请求（处理 Redis 命令）
 rsp := redis.NewCommandFromReceive(rec).Execute(context.Background())
// 3. 处理结果 encode 成 Redis 协议
 return rsp.Encode(), err
```

{{< admonition type=inf title="小结总结" open=true >}}
至此，一个简单的 server 端的能力基本都有了，从服务启动到监听端口、处理连接、处理请求以及响应。
但是问题也很多：

- 请求处理完连接会断开，需要支持长链接
- 服务启动后直接阻塞主线程，且没有优雅退出逻辑，导致服务关闭时可能存在请求未处理完的情况
- `goroutine` 无限开启并不能更好的处理和管理
{{< /admonition >}}

下面针对以上问题进行一步步优化。

## 更完善的服务定义

```go
type Server struct {
    addr     string
    // 新增支持 context 从而更好的控制上下文和下游 goroutine
    ctx      context.Context
    cancel   context.CancelFunc
    handler  api.Handler
    listener net.Listener
    // 新增 WaitGroup 更好控制并发和退出逻辑
    wg       *sync.WaitGroup
}
```

{{< admonition type=question title="Question" open=true >}}
单从服务定义看不出来太多的变化，即便新增几个字段又能如何解决上面的问题呢？
{{< /admonition >}}

## 更优雅的服务启停

服务启动和运行过程中感知到服务以外的一些数据才能在一些特殊情况下更从容的 handle 住问题。这个服务以外的数据一般就是系统的信号量(Signal) .除此之外还需要关心下游的 goroutine 的情况，在下游服务遇到不可控的 Fatel 事件时，上游服务需要做判断是否要关闭服务。在主 server 需要关停时，需要让下游服务感知到且给下游 goroutine 处理的时间但又得有一定的时间控制 不能无限期等待，这些都是需要考虑的问题。

### 主 server 的启停

```go
func (s *Server) Start() error {
    // 监听信号量
    sigChan := make(chan os.Signal, 1)
    signal.Notify(sigChan, syscall.SIGTERM, syscall.SIGINT, syscall.SIGQUIT)

    l, err := net.Listen("tcp", s.addr)
    if err != nil {
        log.Println("listen err:", err)
        return err
    }
    log.Println("listen: ", l.Addr())
    s.listener = l

    // 起一个 goroutine 去等待信号量或 ctx 的结束
    go func() {
        select {
        case <-s.ctx.Done():
            log.Println("kill by ctx")
            return
        case sig := <-sigChan:
            s.Stop()
            log.Printf("kill by signal:%s", sig.String())
            return
        }
    }()

    //阻塞处理连接
    s.handleListener()
    return nil
}

// Stop 可以被 Start 方法调用也可以被 main 的其他协程调用
func (s *Server) Stop() {
    s.cancel()
    _ = s.listener.Close()
}
```

### 下游 handler 的启停

处理连接时，由`sync.WaitGroup` 控制 goroutine，这样可以在某个连接还未处理完成时，可以继续阻塞，
从而做到服务关闭时等待未处理的请求。

```go
func (s *Server) handleListener() {
    for {
        conn, err := s.listener.Accept()
        if err != nil {
            if errors.Is(err, net.ErrClosed) {
                log.Println("closed")
                break
            }

            log.Println("accept err:", err)
            continue
        }

        log.Println("new conn from:", conn.RemoteAddr().String())
        s.wg.Add(1)
        go s.handleConn(conn)
    }

    // wait for unDone connections
    s.wg.Wait()
}
```

在处理连接上的请求时，通过 `for` 循环一直读取连接上的内容，如果客户端没有写入消息则会阻塞，如何客户端主动关闭连接则会读取 EOF 错误。没处理完一次请求先判断服务是否已关闭，因为上次很有可能已经关闭且停止监听端口，等待下游剩下请求处理完成。

```go
// handle by a new goroutine
func (s *Server) handleConn(conn net.Conn) {
    reader := bufio.NewReader(conn)
    // ReceiveDataAsync 返回一个结构体包含两个 channel，实际读取数据是异步的
    ar := protocol.ReceiveDataAsync(reader)
loop:
    for {
        select {
            // ctx
            // 处理完上一个请求后 如果 ctx 已经被 cancel 了 则退出循环结束这个 connection
        case <-s.ctx.Done():
            break loop
        case <-ar.ErrorChan:
            log.Println("handle err:", err)
            break loop
        case rec := <-ar.ReceiveChan:
            rsp := handleRequest(rec)
            reply := rsp.Encode()

            if len(reply) == 0 {
                continue
            }

            _, err := conn.Write(reply)
            if err != nil {
                log.Println("write err:", err)
                break loop
            }
        }
    }

    _ = conn.Close()
    s.wg.Done()
}

func ReceiveDataAsync(r Reader) *AsyncReceive {
    var ar = &AsyncReceive{
        ReceiveChan: make(chan Receive, 1),
        ErrorChan:   make(chan error, 1),
    }
    go func() {
        defer func() {
            close(ar.ReceiveChan)
            close(ar.ErrorChan)
        }()

        for {
            rec, err := DecodeFromReader(r)
            if err != nil {
                ar.ErrorChan <- err

                if errors.Is(err, io.EOF) || errors.Is(err, net.ErrClosed) {
                    return
                }
                log.Println(err)
                continue
            }

            ar.ReceiveChan <- rec
        }
    }()

    return ar
}

```

{{< admonition type=inf title="总结" open=true >}}
到这里本篇内容结束了，总结一下讲述的内容：

1. 作为一个 server 端，在定义和提供服务时需要注意哪些方面？
2. 在处理连接和请求时需要注意哪些问题？
3. 如何管理一个服务的生命周期，如从从上到下都能确保统一的启停，相互作用彼此感知？
{{< /admonition >}}

{{< admonition type=quote title="项目地址" open=true >}}
:heart: `https://github.com/yusank/godis`
{{< /admonition >}}

