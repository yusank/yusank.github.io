---
title: "Go 语言实现连接池"
date: 2022-02-22T10:50:00+08:00
lastmod: 2022-02-22T11:50:00+08:00
categories: ["代码技巧"]
tags: ["go", "连接池"]
draft: false
---

> 本篇介绍一个用 go 实现的连接池，针对连接的生命周期的管理十分有帮助。本篇从连接池的设计到实现以及常用场景进行详解。
<!--more-->

## 1. 背景

`连接池` 可以说是在开发中非常的常见，各类我们需要与远端保持长连接从而提高服务性能（减少建立连接过程）。

如：

- 数据库连接池（MySQL，Redis等）
- 消息队列的连接池（即producer端提前建立连接，提升消息产生速率）
- 与其他远端服务保持长连接

如果使用一些常见的组件，其 client 端其实已经做好连接池了，我们初始化的时候仅需要设计池子大小，空闲时间等参数就可以用了。如果我们用的客户端没有做连接池或者因为种种原因我们需要一个连接池的时候应该怎么，怎么说设计好呢？

下面我们开始讲如何设计以及如何实现一个连接池。

## 2. 设计

我们先梳理我的需求，连接池都有什么功能，应该有哪些接口可调用呢？

- `Get` 获取一个连接
- `Put` 连接放回去
- `Close` 释放/关闭连接

这两个属于是核心的能力了，我能拿到一个可用的连接，并且用完放回去或者我需要的话 这个连接能被关闭。除此之外，应该还有一个整个连接池释放的能力，程序退出是需要释放所有的连接。

那我们定义一下这个 `interface`:

```go
// Pool 基本方法
type Pool interface {
    // 获取资源
    Get() (interface{}, error)
    // 资源放回去
    Put(interface{}) error
    // 关闭资源
    Close(interface{}) error
    // 释放所有资源
    Release()
    // 返回当前池子内有效连接数量
    Len() int
}
```

这个就是一个连接池应该对外提供的能力，对于使用者来说足矣。

{{< admonition type=question title="问" open=true >}}
从连接池拿到的连接是从哪儿来的？
{{< /admonition >}}

这个问题是不是也非常重要，光有连接池还不够，需要一个`工厂`可以生成一个新的连接，我需要的时候能从这个`工厂`生成一个连接并放入连接池供使用者获取。

定义一个`工厂`的 `interface`:

```go
// ConnectionFactory 连接工厂
type ConnectionFactory interface {
    //生成连接的方法
    Factory() (interface{}, error)
    //关闭连接的方法
    Close(interface{}) error
    //检查连接是否有效的方法
    Ping(interface{}) error
}
```

工厂的定义很简单，只需要一个产生连接的方法，并且能关闭这个连接和能对这个连接进行探活的方法即可。

定义了 `interface` 之后好处在于，我们可以自己实现连接池和工厂，也可以只实现连接池，工厂由使用者去实现，这样我们的连接池变得更加灵活通用。

## 3. 实现

实现连接池我们需要考虑的问题比设计更全面，不能光考虑能拿/放连接就行，还得考虑管理这些连接并且支持最大连接数、最大空闲连接数、初始连接数以及连接的超时不可用等情况。

### 3.1. 结构体

下面先设计数据结构：

```go
// channelPool 存放连接信息
type channelPool struct {
    mu                       sync.RWMutex
    conns                    chan *idleConn // 存储最大空闲连接
    factory                  ConnectionFactory // 工厂
    idleTimeout, waitTimeOut time.Duration // 连接空闲超时和等待超时
    maxActive                int // 最大连接数
    openingConns             int // 活跃的连接数
    connReqs                 []chan connReq 
    // 连接请求缓冲区，如果无法从 conns 取到连接，则在这个缓冲区创建一个新的元素，之后连接放回去时先填充这个缓冲区
}

type idleConn struct {
    conn interface{}
    t    time.Time
}
```

不难发现，没有字段去存所有的连接，仅存了**最大空闲连接数**，也就是拿的连接超过最大空闲连接数的时候，只会产生一个新的连接返回给使用者，但是不会在任何字段去存这个新的产生的连接。为什么这么做呢？

答：**最大空闲连接数** 这个概念就很明确，我最多只会保留这么多空闲连接，超过这个数的空闲连接直接释放。但是不影响我使用更多的连接，限制最大连接数的字段是 `maxActive`,总连接数在这个限制之下可以一直产生使用。使用的时候可以配置最大连接数 1000，而最大空闲设置为 10，这样空闲时刻不会占用太多的资源，而使用高峰的时候又可以产生达到 1000 个的连接来用。

### 3.2. 初始化

下面实现初始化连接池相关能力：

```go
// PoolConfig 连接池相关配置
type PoolConfig struct {
    //连接池中拥有的最小连接数
    InitialCap int
    //最大并发存活连接数
    MaxCap int
    //最大空闲连接
    MaxIdle int
    // 工厂
    Factory ConnectionFactory
    //连接最大空闲时间，超过该事件则将失效
    IdleTimeout time.Duration
}

// NewChannelPool 初始化连接
func NewChannelPool(poolConfig *PoolConfig) (Pool, error) {
    // 校验参数
    if !(poolConfig.InitialCap <= poolConfig.MaxIdle && poolConfig.MaxCap >= poolConfig.MaxIdle && poolConfig.InitialCap >= 0) {
        return nil, errors.New("invalid capacity settings")
    }
    // 校验参数
    if poolConfig.Factory == nil {
        return nil, errors.New("invalid factory interface settings")
    }

    c := &channelPool{
        conns:        make(chan *idleConn, poolConfig.MaxIdle), // 最大空闲连接数
        factory:      poolConfig.Factory,
        idleTimeout:  poolConfig.IdleTimeout,
        maxActive:    poolConfig.MaxCap,
        openingConns: poolConfig.InitialCap,
    }

    // 初始化初始连接放入 channel 中
    for i := 0; i < poolConfig.InitialCap; i++ {
        conn, err := c.factory.Factory()
        if err != nil {
            c.Release()
            return nil, fmt.Errorf("factory is not able to fill the pool: %s", err)
        }
        c.conns <- &idleConn{conn: conn, t: time.Now()}
    }

    return c, nil
}
```

上面我们定义了一个配置的结构体，方便外部传参。不仅支持了最大连接数、空闲连接数、连接超时，还支持了初始连接数，方便初始化快速使用。

### 3.3. 获取连接

现在实现获取连接的过程：

```go
// Get 从pool中取一个连接
func (c *channelPool) Get() (interface{}, error) {
    conns := c.getConns()
    if conns == nil {
        return nil, ErrClosed
    }
    for {
        select {
            // 优先从空闲连接缓冲取
        case wrapConn := <-conns:
            if wrapConn == nil {
                return nil, ErrClosed
            }
            //判断是否超时，超时则丢弃
            if timeout := c.idleTimeout; timeout > 0 {
                if wrapConn.t.Add(timeout).Before(time.Now()) {
                    //丢弃并关闭该连接
                    _ = c.Close(wrapConn.conn)
                    continue
                }
            }
            //判断是否失效，失效则丢弃，如果用户没有设定 ping 方法，就不检查
            if err := c.Ping(wrapConn.conn); err != nil {
                _ = c.Close(wrapConn.conn)
                continue
            }
            return wrapConn.conn, nil
        default:
        // 没有空闲连接
            c.mu.Lock()
            log.Printf("openConn %v %v", c.openingConns, c.maxActive)
            // 判断连接数是否达到上限
            if c.openingConns >= c.maxActive {
                req := make(chan connReq, 1)
                // 如果达到上限，则创建一个缓冲位置，等待放回去的连接
                c.connReqs = append(c.connReqs, req)
                c.mu.Unlock()
                // 判断是否有连接放回去（放回去逻辑在 put 方法内）
                ret, ok := <-req
                // 如果没有连接放回去，则不能再创建新的连接了，因为达到上限了
                if !ok {
                    return nil, ErrMaxActiveConnReached
                }
                // 如果有连接放回去了 判断连接是否可用
                if timeout := c.idleTimeout; timeout > 0 {
                    if ret.idleConn.t.Add(timeout).Before(time.Now()) {
                        //丢弃并关闭该连接
                        // 重新尝试获取连接
                        _ = c.Close(ret.idleConn.conn)
                        continue
                    }
                }
                return ret.idleConn.conn, nil
            }
            // 到这里说明 没有空闲连接 && 连接数没有达到上限 可以创建新连接
            if c.factory == nil {
                c.mu.Unlock()
                return nil, ErrClosed
            }
            conn, err := c.factory.Factory()
            if err != nil {
                c.mu.Unlock()
                return nil, err
            }
            // 连接数+1
            c.openingConns++
            c.mu.Unlock()
            return conn, nil
        }
    }
}
```

需要注意 `if c.openingConns >= c.maxActive {` 这块的逻辑，当连接数达到上限时，不用马上报错，可以通过 `connReqs` 来复用用完还没 release 的连接，从而节约一个连接 release 然后重新建立连接的时间和资源。

### 3.4. 连接放回

设计连接池的时候设计了放回连接的接口，当使用者拿到一个连接用完后需要放回去，这个连接根据情况会立刻给新的获取连接请求使用，也可能放到空闲连接的缓存或者释放。

实现代码如下：

```go
// Put 将连接放回pool中
func (c *channelPool) Put(conn interface{}) error {
    if conn == nil {
        return errors.New("connection is nil. rejecting")
    }

    c.mu.Lock()
    defer c.mu.Unlock()

    if c.conns == nil {
        return c.Close(conn)
    }

    // 如果有请求连接的缓冲区有等待，则按顺序有限个先来的请求分配当前放回的连接
    if l := len(c.connReqs); l > 0 {
        req := c.connReqs[0]
        copy(c.connReqs, c.connReqs[1:])
        c.connReqs = c.connReqs[:l-1]
        req <- connReq{
            idleConn: &idleConn{conn: conn, t: time.Now()},
        }
        return nil
    }

    // 如果没有等待的缓冲则尝试放入空闲连接缓冲
    select {
    case c.conns <- &idleConn{conn: conn, t: time.Now()}:
        return nil
    default:
        //连接池已满，直接关闭该连接
        return c.Close(conn)
    }
}
```

### 3.5. 释放连接

释放连接有两种情况，释放单个连接和释放整个连接池，而底层只实现释放单个连接的逻辑，释放连接池则一个个调用这个释放方法即可。

实现逻辑如下：

```go
// Close 关闭单条连接
func (c *channelPool) Close(conn interface{}) error {
    if conn == nil {
        return errors.New("connection is nil. rejecting")
    }
    c.mu.Lock()
    defer c.mu.Unlock()
    // 连接数减一
    c.openingConns--
    // 调用工厂的关闭方法
    return c.factory.Close(conn)
}

// Release 释放连接池中所有连接
func (c *channelPool) Release() {
    c.mu.Lock()
    conns := c.conns
    c.conns = nil
    c.mu.Unlock()

    defer func() {
        c.factory = nil
    }()

    if conns == nil {
        return
    }

    close(conns)
    for wrapConn := range conns {
        //log.Printf("Type %v\n",reflect.TypeOf(wrapConn.conn))
        _ = c.factory.Close(wrapConn.conn)
    }
}
```

### 3.6. 其他方法

实现连接池的 `Ping` 和 `Len` 方法也很简单 直接上代码。

```go
// Ping 检查单条连接是否有效
func (c *channelPool) Ping(conn interface{}) error {
    if conn == nil {
        return errors.New("connection is nil. rejecting")
    }

    return c.factory.Ping(conn)
}

// Len 连接池中已有的连接
func (c *channelPool) Len() int {
    return len(c.getConns())
}
```

## 4. 实际使用场景

以一个消息队列的 producer 的连接池为例，下面说明如何使用。

### 4.1. 初始化

初始化指定配置参数即可：

```go
pc := &util.PoolConfig{
    InitialCap:  int(cfg.ProducerConnPoolSize),
    MaxCap:      int(cfg.ProducerConnPoolSize),
    MaxIdle:     int(cfg.ProducerConnPoolSize),
    Factory:     &producerFactory{addr: cfg.MQURL}, // producerFactory 实现了工厂的接口 底层为创建 tcp 连接
    IdleTimeout: time.Minute * 5,
}

pool, err := util.NewChannelPool(pc)
if err != nil {
    return
}
```

### 4.2. 使用

使用方法如下：

```go
func (c *Client) getProducer() (p *mq.Producer, err error) {
    if c.producerPool == nil {
        err = fmt.Errorf("producer pool is not initialized")
        return
    }

    v, err := c.producerPool.Get()
    if err != nil {
        return
    }

    p, ok := v.(*mq.Producer)
    if !ok {
        err = fmt.Errorf("cannot load producer from pool")
        return
    }

    return p, nil
}

func (c *Client) putProducer(p *mq.Producer) {
    _ = c.producerPool.Put(p)
}

// Publish publish msg to topic and wait for the response.
func (c *Client) Publish(topic string, body []byte) error {
    p, err := c.getProducer()
    if err != nil {
        return err
    }
    defer c.putProducer(p)

    return p.Publish(topic, body)
}

func (c *Client) Stop() {
    c.producerPool.Release()
    c.producerPool = nil
}
```

{{< admonition type=warning title="注意" open=true >}}
连接池使用完或者程序退出时，务必释放连接池资源。
{{< /admonition >}}

## 5. 总结

本篇介绍了一个 go 语言实现的连接池的设计、实现以及如何使用。连接池作为程序开发中非常常用的功能模块，即便是不需要自己实现也应该对其底层的实现有个大概的认知。

- 了解连接池的概念
- 了解连接池的主要能力
- 了解工厂模式
- 设计一个连接池
- 根据设计实现连接池
  - 加入了连接数的控制
  - 接入连接超时校验
- 学会使用连接池
