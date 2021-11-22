---
title: "Go Channel 源码解读"
date: 2020-03-06T17:24:41+08:00
updated: 2020-04-06T17:24:41+08:00
categories:
- 源码解读
tags:
- go
- channel
---

Go 的 `channel` 作为该语言很重要的特性，作为一个 gopher 有必要详细了解其实现原理。

# 原理解读

Go 语言的 `channel` 实现源码在`go/src/runtime/chan.go` 文件里。（go version ：1.13.4）

## 数据结构

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



## 主要方法（func）

以我们常用的 `make(chan Type)`, 写入元素(`chan <- element`)和读取元素(`<-chan`)为例

### 初始化（make）

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



### 写入

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



### 读取

> 近期补充。。。


# 使用

Channel是Go中的一个核心类型，你可以把它看成一个管道，通过它并发核心单元就可以发送或者接收数据进行通讯(communication)。

它的操作符是箭头 **<-** 。

```go
ch <- v    
v := <-ch  
```

(箭头的指向就是数据的流向)

就像 map 和 slice 数据类型一样, channel必须先创建再使用:

```go
ch := make(chan int)
```

## Channel 类型

Channel类型的定义格式如下：

```go
ChannelType = ( "chan" | "chan" "<-" | "<-" "chan" ) ElementType .
```

它包括三种类型的定义。可选的`<-`代表channel的方向。如果没有指定方向，那么Channel就是双向的，既可以接收数据，也可以发送数据。

```go
chan T          // 可以接收和发送类型为 T 的数据
chan<- float64  // 只可以用来发送 float64 类型的数据
<-chan int      // 只可以用来接收 int 类型的数据
```

`<-`总是优先和最左边的类型结合。(The <- operator associates with the leftmost chan possible)

```go
chan<- chan int    // 等价 chan<- (chan int)
chan<- <-chan int  // 等价 chan<- (<-chan int)
<-chan <-chan int  // 等价 <-chan (<-chan int)
chan (<-chan int)
```

使用`make`初始化Channel,并且可以设置容量:

```go
make(chan int, 100)
```

容量(capacity)代表Channel容纳的最多的元素的数量，代表Channel的缓存的大小。
如果没有设置容量，或者容量设置为0, 说明Channel没有缓存，只有sender和receiver都准备好了后它们的通讯(communication)才会发生(Blocking)。如果设置了缓存，就有可能不发生阻塞， 只有buffer满了后 send才会阻塞， 而只有缓存空了后receive才会阻塞。一个nil channel不会通信。

可以通过内建的`close`方法可以关闭Channel。

你可以在多个goroutine从/往 一个channel 中 receive/send 数据, 不必考虑额外的同步措施。

Channel可以作为一个先入先出(FIFO)的队列，接收的数据和发送的数据的顺序是一致的。

channel的 receive支持 *multi-valued assignment*，如

```go
v, ok := <-ch
```

它可以用来检查Channel是否已经被关闭了。

1. **send语句**
   send语句用来往Channel中发送数据， 如`ch <- 3`。
   它的定义如下:

```go
SendStmt = Channel "<-" Expression .
Channel  = Expression .
```

在通讯(communication)开始前channel和expression必选先求值出来(evaluated)，比如下面的(3+4)先计算出7然后再发送给channel。

```go
c := make(chan int)
defer close(c)
go func() { c <- 3 + 4 }()
i := <-c
fmt.Println(i)
```

send被执行前(proceed)通讯(communication)一直被阻塞着。如前所言，无缓存的channel只有在receiver准备好后send才被执行。如果有缓存，并且缓存未满，则send会被执行。

往一个已经被close的channel中继续发送数据会导致**run-time panic**。

往nil channel中发送数据会一致被阻塞着。

1. receive 操作符
   `<-ch`用来从channel ch中接收数据，这个表达式会一直被block,直到有数据可以接收。

从一个nil channel中接收数据会一直被block。

从一个被close的channel中接收数据不会被阻塞，而是立即返回，接收完已发送的数据后会返回元素类型的零值(zero value)。

如前所述，你可以使用一个额外的返回参数来检查channel是否关闭。

```go
x, ok := <-ch
x, ok = <-ch
var x, ok = <-ch
```

## blocking

缺省情况下，发送和接收会一直阻塞着，知道另一方准备好。这种方式可以用来在gororutine中进行同步，而不必使用显示的锁或者条件变量。

如官方的例子中`x, y := <-c, <-c`这句会一直等待计算结果发送到channel中。

```go
import "fmt"
func sum(s []int, c chan int) {
	sum := 0
	for _, v := range s {
		sum += v
	}
	c <- sum 
}
func main() {
	s := []int{7, 2, 8, -9, 4, 0}
	c := make(chan int)
	go sum(s[:len(s)/2], c)
	go sum(s[len(s)/2:], c)
	x, y := <-c, <-c // receive from c
	fmt.Println(x, y, x+y)
}
```

## Buffered Channels

make的第二个参数指定缓存的大小：`ch := make(chan int, 100)`。

通过缓存的使用，可以尽量避免阻塞，提供应用的性能。



## Range

`for …… range`语句可以处理Channel。

```go
func main() {
	go func() {
		time.Sleep(1 * time.Hour)
	}()
	c := make(chan int)
	go func() {
		for i := 0; i < 10; i = i + 1 {
			c <- i
		}
		close(c)
	}()
	for i := range c {
		fmt.Println(i)
	}
	fmt.Println("Finished")
}
```

`range c`产生的迭代值为Channel中发送的值，它会一直迭代知道channel被关闭。上面的例子中如果把`close(c)`注释掉，程序会一直阻塞在`for …… range`那一行。



## select

`select`语句选择一组可能的send操作和receive操作去处理。它类似`switch`,但是只是用来处理通讯(communication)操作。
它的`case`可以是send语句，也可以是receive语句，亦或者`default`。

`receive`语句可以将值赋值给一个或者两个变量。它必须是一个receive操作。

最多允许有一个`default case`,它可以放在case列表的任何位置，尽管我们大部分会将它放在最后。

```go
import "fmt"
func fibonacci(c, quit chan int) {
	x, y := 0, 1
	for {
		select {
		case c <- x:
			x, y = y, x+y
		case <-quit:
			fmt.Println("quit")
			return
		}
	}
}
func main() {
	c := make(chan int)
	quit := make(chan int)
	go func() {
		for i := 0; i < 10; i++ {
			fmt.Println(<-c)
		}
		quit <- 0
	}()
	fibonacci(c, quit)
}
```

如果有同时多个case去处理,比如同时有多个channel可以接收数据，那么Go会伪随机的选择一个case处理(pseudo-random)。如果没有case需要处理，则会选择`default`去处理，如果`default case`存在的情况下。如果没有`default case`，则`select`语句会阻塞，直到某个case需要处理。

需要注意的是，nil channel上的操作会一直被阻塞，如果没有default case,只有nil channel的select会一直被阻塞。

`select`语句和`switch`语句一样，它不是循环，它只会选择一个case来处理，如果想一直处理channel，你可以在外面加一个无限的for循环：

```go
for {
	select {
	case c <- x:
		x, y = y, x+y
	case <-quit:
		fmt.Println("quit")
		return
	}
}
```

### timeout

`select`有很重要的一个应用就是超时处理。 因为上面我们提到，如果没有case需要处理，select语句就会一直阻塞着。这时候我们可能就需要一个超时操作，用来处理超时的情况。
下面这个例子我们会在2秒后往channel c1中发送一个数据，但是`select`设置为1秒超时,因此我们会打印出`timeout 1`,而不是`result 1`。

```go
import "time"
import "fmt"
func main() {
    c1 := make(chan string, 1)
    go func() {
        time.Sleep(time.Second * 2)
        c1 <- "result 1"
    }()
    select {
    case res := <-c1:
        fmt.Println(res)
    case <-time.After(time.Second * 1):
        fmt.Println("timeout 1")
    }
}
```

其实它利用的是`time.After`方法，它返回一个类型为`<-chan Time`的单向的channel，在指定的时间发送一个当前时间给返回的channel中。

## Timer 和 Ticker

我们看一下关于时间的两个Channel。
timer是一个定时器，代表未来的一个单一事件，你可以告诉timer你要等待多长时间，它提供一个Channel，在将来的那个时间那个Channel提供了一个时间值。下面的例子中第二行会阻塞2秒钟左右的时间，直到时间到了才会继续执行。

```go
timer1 := time.NewTimer(time.Second * 2)
<-timer1.C
fmt.Println("Timer 1 expired")
```

当然如果你只是想单纯的等待的话，可以使用`time.Sleep`来实现。

你还可以使用`timer.Stop`来停止计时器。

```go
timer2 := time.NewTimer(time.Second)
go func() {
	<-timer2.C
	fmt.Println("Timer 2 expired")
}()
stop2 := timer2.Stop()
if stop2 {
	fmt.Println("Timer 2 stopped")
}
```

`ticker`是一个定时触发的计时器，它会以一个间隔(interval)往Channel发送一个事件(当前时间)，而Channel的接收者可以以固定的时间间隔从Channel中读取事件。下面的例子中ticker每500毫秒触发一次，你可以观察输出的时间。

```go
ticker := time.NewTicker(time.Millisecond * 500)
go func() {
	for t := range ticker.C {
		fmt.Println("Tick at", t)
	}
}()
```

类似timer, ticker也可以通过`Stop`方法来停止。一旦它停止，接收者不再会从channel中接收数据了。



## close

内建的close方法可以用来关闭channel。

总结一下channel关闭后sender的receiver操作。
如果channel c已经被关闭,继续往它发送数据会导致`panic: send on closed channel`:

```go
import "time"
func main() {
	go func() {
		time.Sleep(time.Hour)
	}()
	c := make(chan int, 10)
	c <- 1
	c <- 2
	close(c)
	c <- 3
}
```

但是从这个关闭的channel中不但可以读取出已发送的数据，还可以不断的读取零值:

```go
c := make(chan int, 10)
c <- 1
c <- 2
close(c)
fmt.Println(<-c) //1
fmt.Println(<-c) //2
fmt.Println(<-c) //0
fmt.Println(<-c) //0
```

但是如果通过`range`读取，channel关闭后for循环会跳出：

```go
c := make(chan int, 10)
c <- 1
c <- 2
close(c)
for i := range c {
	fmt.Println(i)
}
```

通过`i, ok := <-c`可以查看Channel的状态，判断值是零值还是正常读取的值。

```go
c := make(chan int, 10)
close(c)

i, ok := <-c
fmt.Printf("%d, %t", i, ok) //0, false
```



## 同步

channel可以用在goroutine之间的同步。
下面的例子中main goroutine通过done channel等待worker完成任务。 worker做完任务后只需往channel发送一个数据就可以通知main goroutine任务完成。

```go
import (
	"fmt"
	"time"
)
func worker(done chan bool) {
	time.Sleep(time.Second)
	// 通知任务已完成
	done <- true
}
func main() {
	done := make(chan bool, 1)
	go worker(done)
	// 等待任务完成
	<-done
}
```

**[参考资料]：**

1. [https://gobyexample.com/channels](https://gobyexample.com/channels)
2. [https://tour.golang.org/concurrency/2](https://tour.golang.org/concurrency/2)
3. [https://golang.org/ref/spec#Select_statements](https://golang.org/ref/spec#Select_statements)
4. [https://github.com/a8m/go-lang-cheat-sheet](https://github.com/a8m/go-lang-cheat-sheet)
5. [http://devs.cloudimmunity.com/gotchas-and-common-mistakes-in-go-golang/](http://devs.cloudimmunity.com/gotchas-and-common-mistakes-in-go-golang/)