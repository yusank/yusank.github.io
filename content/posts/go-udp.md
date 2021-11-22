---
title: "Go UDP Socket"
date: 2017-08-02T19:00:01+08:00
update: 2017-08-03T11:07:54+08:00
categories:
- 网络编程
tags:
- go
- udp
---

udp 和 tcp 的简单比较和用 go 实现最简单的 udp 客户端和服务端 ......

# 用 go 实现简单的 udp

用户数据包协议（英语：User Datagram Protocol，缩写为UDP），又称用户数据报文协议，是一个简单的面向数据报的传输层协议，正式规范为RFC 768。
在TCP/IP模型中，UDP为网络层以上和应用层以下提供了一个简单的接口。UDP只提供数据的不可靠传递，它一旦把应用程序发给网络层的数据发送出去，就不保留数据备份（所以UDP有时候也被认为是不可靠的数据报协议）。UDP在IP数据报的头部仅仅加入了复用和数据校验（字段）。

## UDP 与 TCP 的比较

- UDP -- 用户数据协议包，是一个简单的面向数据报的运输层协议。UDP 不提供可靠性，它只是把应用程序给 IP 层的数据报发送出去，但是并不能保证他们能达到目的地。由于 UDP 在传输数据报之前不用在客户端和服务端之间建立连接，且没有超时机制，故而传输速度很快。

- TCP -- 传输控制协议，提供的是面向连接，可靠的字节流服务。当客户端和服务端彼此交换数据前，必须先在双方之间建立 TCP 连接，之后才能传输数据。TCP 提供超时重发，丢弃重复数据，检验数据，流量控制等功能，保证数据能从一段传到另一端。

-|TCP|UDP
---|---|---
是否连接 | 面向连接 | 面向非连接
传输可靠性 | 可靠 | 会丢包，不可靠
应用场景 | 传输数据量大 | 传输数据量小
速度 | 慢 | 快

## TCP 与 UDP 的选择

当数据传输的性能必须让位于数据传输的完整性、可控制性和可靠性时，TCP协议是当然的选择。当强调传输性能而不是传输的完整性时，如：音频和多媒体应用，UDP是最好的选择。在数据传输时间很短，以至于此前的连接过程成为整个流量主体的情况下，UDP也是一个好的选择，如：DNS交换。把SNMP建立在UDP上的部分原因是设计者认为当发生网络阻塞时，UDP较低的开销使其有更好的机会去传送管理数据。TCP丰富的功能有时会导致不可预料的性能低下，但是我们相信在不远的将来，TCP可靠的点对点连接将会用于绝大多数的网络应用。

## UDP 使用场景

在选择使用协议的时候，选择UDP必须要谨慎。在网络质量令人十分不满意的环境下，UDP协议数据包丢失会比较严重。但是由于UDP的特性：它不属于连接型协议，因而具有资源消耗小，处理速度快的优点，所以通常音频、视频和普通数据在传送时使用UDP较多，因为它们即使偶尔丢失一两个数据包，也不会对接收结果产生太大影响。而且如果在内网的情况下，丢包率也很低，所以内网的数据传输也可以用 UDP 协议。我们常用的 QQ，一部分数据传输功能也是用 UDP协议来实现的。

## 实现

下面分别是服务端和客户端实现代码：
服务端代码 `server.go`:

```go
package main

import (
	"fmt"
	"net"
)

func main() {
	// 解析地址
	addr, err := net.ResolveUDPAddr("udp", ":3017")
	if err != nil {
		fmt.Println("Can't resolve addr:", err.Error())
		panic(err)
	}

	// 监听端口
	conn, err := net.ListenUDP("udp", addr)
	if err != nil {
		fmt.Println("listen error:", err.Error())
		panic(err)
	}
	defer conn.Close()
	for {
		handlerClient(conn)
	}
}

func handlerClient(conn *net.UDPConn) {
	data := make([]byte, 1024)
	// 从 UDP 中读取内容并写到 data
	_, remoteAddr, err := conn.ReadFromUDP(data)
	if err != nil {
		fmt.Println("read udp msg failed with:", err.Error())
		return
	}
	// 给收到消息的 client 写回信息
	conn.WriteToUDP([]byte("a"), remoteAddr)
}

```

客户端代码`client.go`：

```go
package client

import (
	"fmt"
	"net"
)

var (
	// Connection *net.UDPConn
	Connection []*net.UDPConn
)

// Client 创建一个 UDP 连接
func Client() {
	addr, err := net.ResolveUDPAddr("udp", "127.0.0.1:3017")

	if err != nil {
		fmt.Println("Can't resolve address: ", err)

		panic(err)
	}

	conn, err := net.DialUDP("udp", nil, addr)

	if err != nil {
		fmt.Println("Can't dial: ", err)

		panic(err)
	}

	Connection = append(Connection, conn)
}

// WriteTo 像传入参数 conn 写数据
func WriteTo(conn *net.UDPConn) {
	_, err := conn.Write([]byte("hello from the other site"))

	if err != nil {
		fmt.Println("failed:", err)
	}

	data := make([]byte, 1024)
	_, err = conn.Read(data)

	if err != nil {
		fmt.Println("failed to read UDP msg because of ", err)
	}
}
```

## 总结

以上是一个最简单的 UDP 客户端服务器的代码，只有启动服务和收发消息的功能，但实际应用 UDP 协议到具体需求的时候，需要考虑的问题很多，比如包的设计，包头的设计，错误处理，丢包处理，包顺序调换处理等。所以需要用到传输数据协议的时候，请考虑好需求和可能遇到的问题，以及对问题的处理方案。