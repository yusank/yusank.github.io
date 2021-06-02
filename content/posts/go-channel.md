---
title: "Go Channel 源码解读"
date: 2020-03-06T17:24:41+08:00
updated: 2020-04-06T17:24:41+08:00
categories:
- 技术
tags:
- go
- channel
---

Go 的 `channel` 作为该语言很重要的特性，作为一个 gopher 有必要详细了解其实现原理。

## 使用

关于如何使用`channel` 我已经在之前一篇文章说过，可以看看，[传送门~](http://blog.yusank.space/Go%20Channel.html/)



## 原理解读

Go 语言的 `channel` 实现源码在`go/src/runtime/chan.go` 文件里。（go version ：1.13.4）

### 数据结构

首先看一下基础数据结构：

```go
// go 语言的 channel 结构以队列的形式实现
type hchan struct {
	qcount   uint           // total data in the queue，队列中元素总数
	dataqsiz uint           // size of the circular queue，循环队列的大小
	buf      unsafe.Pointer // points to an array of dataqsiz elements， 指向循环队列中元素的指针
	elemsize uint16 // 元素 size
	closed   uint32 // channel 是否关闭标志
	elemtype *_type // element type // channel 元素类型
	sendx    uint   // send index // 写入 channel 元素的索引
	recvx    uint   // receive index // 从 channel 读取的元素索引
	recvq    waitq  // list of recv waiters // 读取 channel 的等待队列（即阻塞的协程）
	sendq    waitq  // list of send waiters // 写入 channel 的等待队列

	// lock protects all fields in hchan, as well as several
	// fields in sudogs blocked on this channel.
	lock mutex // 互斥锁
}

// 双向链表结构，其中每一个元素代表着等待读取或写入 channel 的协程
type waitq struct {
	first *sudog
	last  *sudog
}

```

通过源码数据结构，对 go 的 channel 实现有了初步的了解，解答了在我们读取或写入 channel 时，其中元素在哪儿，我们的协程在哪儿等待等数据相关问题。

- channel 底层实现是以队列作为载体，通过互斥锁保证在同一个时间点，只有一个待读取的协程读元素或待写入的协程写入元素。
- 如果有多个协程同时读取 channel 时，他们会进入读取等待队列：`recvq`，反之进入写入等待队列：`sendq`。
- `buf` 作为指针，指向 channel 中存储元素的数组的地址。
- `sendx`,`recvx` 作为channel 队列中写入和读取到元素的索引值。
- `closed` 为 channel 当前是否已被关闭标志。



### 主要方法（func）

以我们常用的 `make(chan Type)`, 写入元素(`chan <- element`)和读取元素(`<-chan`)为例

#### 初始化（make）

在实际使用中 我会用下面的代码初始化一个 channel：

```go
make(chan Type, size int)
```

其实现源码入下：

```go
// t 为 channel 类型，size 为我们传入 channel 大小
func makechan(t *chantype, size int) *hchan {
	elem := t.elem

  // 如果 size 超过声明类型最大值 编译的时候会报错，但是这里多一次判断为了更安全
	if elem.size >= 1<<16 {
    // 抛出异常
		throw("makechan: invalid channel element type")
	}
  // align 为类型的对齐系数，不同平台上对其系数不完全一样，但是都最大值 maxAlign=8
  // 不同类型的对齐系数不一样 但是均以 2^N 形式
	if hchanSize%maxAlign != 0 || elem.align > maxAlign {
		throw("makechan: bad alignment")
	}

  // 检查是否channel 大小值是否溢出
	mem, overflow := math.MulUintptr(elem.size, uintptr(size))
	if overflow || mem > maxAlloc-hchanSize || size < 0 {
		panic(plainError("makechan: size out of range"))
	}

  // 根据 size 和原始是否为指针情况，分配内存初始化 channel
	var c *hchan
	switch {
    // channel size 为 0
	case mem == 0:
		c = (*hchan)(mallocgc(hchanSize, nil, true))
		c.buf = c.raceaddr()
	case elem.ptrdata == 0:
    // 元素不包含指针，则将为元素分配内存，并将 buf 指向该地址
		c = (*hchan)(mallocgc(hchanSize+mem, nil, true))
		c.buf = add(unsafe.Pointer(c), hchanSize)
	default:
		// 元素包含指针，buf 指向该指针指向地址
		c = new(hchan)
		c.buf = mallocgc(mem, elem, true)
	}

	c.elemsize = uint16(elem.size)
	c.elemtype = elem
	c.dataqsiz = uint(size)

	return c
}
```



可以看出，channel 中的元素最终都是以指针的方式存储，即便初始化时 用非指针类型（如 string），在初始化话的时候 会先分配内存 并将 channel 的元素指针字段指向该地址。



#### 写入

先给出源码：

```go

// entry point for c <- x from compiled code
// 代码重 `c <- x` 编译时，会编译成该方法从而被调用
func chansend1(c *hchan, elem unsafe.Pointer) {
	chansend(c, elem, true, getcallerpc())
}

/*
 * generic single channel send/recv
 * If block is not nil,
 * then the protocol will not
 * sleep but return if it could
 * not complete.
 *
 * sleep can wake up with g.param == nil
 * when a channel involved in the sleep has
 * been closed.  it is easiest to loop and re-run
 * the operation; we'll see that it's now closed.
 */
// 向 channel 写入
// c: channel
// ep: 写入元素地址
// block: 表示该 channel 是否被阻塞
// callerpc: 
func chansend(c *hchan, ep unsafe.Pointer, block bool, callerpc uintptr) bool {
	if c == nil {
		// return or panic
	}

	if raceenabled {
    // 不同协程之前竞争写入
		racereadpc(c.raceaddr(), callerpc, funcPC(chansend))
	}


  // 没有阻塞 && 未关闭 && （channel 为空且没有协程读取 或 channel 已满，直接返回 false）
	if !block && c.closed == 0 && ((c.dataqsiz == 0 && c.recvq.first == nil) ||
		(c.dataqsiz > 0 && c.qcount == c.dataqsiz)) {
		return false
	}

	var t0 int64
	if blockprofilerate > 0 {
		t0 = cputicks()
	}

  // 上锁 准备写
	lock(&c.lock)

  // 已关闭 解锁并 panic
	if c.closed != 0 {
		unlock(&c.lock)
		panic(plainError("send on closed channel"))
	}

  // 从等待读取的队列中 拿出第一个协程，写入并发送到该协程
	if sg := c.recvq.dequeue(); sg != nil {
		// Found a waiting receiver. We pass the value we want to send
		// directly to the receiver, bypassing the channel buffer (if any).
		send(c, sg, ep, func() { unlock(&c.lock) }, 3)
		return true
	}

  // 如果 channel 缓存有空间，则向缓存中写入
  // 此时是 channel 是有 buffer channel
	if c.qcount < c.dataqsiz {
		// Space is available in the channel buffer. Enqueue the element to send.
		qp := chanbuf(c, c.sendx)
    // 应该是协程之间竞争，暂时没有完全搞懂
		if raceenabled {
			raceacquire(qp)
			racerelease(qp)
		}
    // 写入缓存
		typedmemmove(c.elemtype, qp, ep)
    // 写入位置加一
		c.sendx++
    // 如果写完 buffer 满了，将位置置位 0
		if c.sendx == c.dataqsiz {
			c.sendx = 0
		}
    // channel 数据总数加一
		c.qcount++
    // 解锁
		unlock(&c.lock)
		return true
	}

  // 如果是非阻塞类型 channel，则只返回
	if !block {
		unlock(&c.lock)
		return false
	}

  // 如果是阻塞类型，则一直阻塞一直到被读取，保证数据在被读取之前不被内存回收
  
	// Block on the channel. Some receiver will complete our operation for us.
	gp := getg()
	mysg := acquireSudog()
	mysg.releasetime = 0
	if t0 != 0 {
		mysg.releasetime = -1
	}

	KeepAlive(ep)

	// someone woke us up.
	if mysg != gp.waiting {
		throw("G waiting list is corrupted")
	}
	gp.waiting = nil
	if gp.param == nil {
		if c.closed == 0 {
			throw("chansend: spurious wakeup")
		}
		panic(plainError("send on closed channel"))
	}
	gp.param = nil
	if mysg.releasetime > 0 {
		blockevent(mysg.releasetime-t0, 2)
	}
	mysg.c = nil
	releaseSudog(mysg)
	return true
}
```



#### 读取
