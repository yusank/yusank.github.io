---
title: "GO interface"
date: 2017-06-08T15:07:00+08:00
lastmod: 2017-06-08T15:07:01+08:00
categories: ["源码解读"]
tags: ["go"]
---

go 的 interface 的实现和原理。

# Go interface

## interface

在 Golang 中 interface 是一个很重要的概念和特性。

### 什么是 interface？

> In [object-oriented programming](https://en.wikipedia.org/wiki/Object-oriented_programming), a **protocol** or **interface** is a common means for unrelated [objects](https://en.wikipedia.org/wiki/Object_(computer_science)) to communicate with each other. These are definitions of [methods](https://en.wikipedia.org/wiki/Method_(computer_science)) and values which the objects agree upon in order to co-operate. — wikipedia

这是 wikipedia 关于 protocal 的定义，将 interface 类比如 protocal 是一种非常助于理解的方式。protocol，中文一般叫做协议，比如网络传输中的 TCP 协议。protocol 可以认为是一种双方为了交流而做出的约定，interface 可以类比如此。



在 Golang 中，interface 是一种抽象类型，相对于抽象类型的是具体类型（concrete type）：int，string。如下是 io 包里面的例子。

```go
// Writer is the interface that wraps the basic Write method.
//
// Write writes len(p) bytes from p to the underlying data stream.
// It returns the number of bytes written from p (0 <= n <= len(p))
// and any error encountered that caused the write to stop early.
// Write must return a non-nil error if it returns n < len(p).
// Write must not modify the slice data, even temporarily.
//
// Implementations must not retain p.
type Writer interface {
    Write(p []byte) (n int, err error)
}

// Closer is the interface that wraps the basic Close method.
//
// The behavior of Close after the first call is undefined.
// Specific implementations may document their own behavior.
type Closer interface {
    Close() error
}
```



在 Golang 中，interface 是一组 method 的集合，是 [duck-type programming](https://zh.wikipedia.org/wiki/%E9%B8%AD%E5%AD%90%E7%B1%BB%E5%9E%8B) (鸭子类型)的一种体现。不关心属性（数据），只关心行为（方法）。具体使用中你可以自定义自己的 struct，并提供特定的 interface 里面的 method 就可以把它当成 interface 来使用。下面是一种 interface 的典型用法，定义函数的时候参数定义成 interface，调用函数的时候就可以做到非常的灵活。

```go
type MyInterface interface{
    Print()
}

func TestFunc(x MyInterface) {}
type MyStruct struct {}
func (me MyStruct) Print() {}

func main() {
    var me MyStruct
    TestFunc(me)
}
```



###  为什么 interface

Gopher China 上给出了下面的三个理由：

- writing generic algorithm （泛型编程）
- hiding implementation detail （隐藏具体实现）
- providing interception points （提供监听点/拦截点？）

#### write generic algorithm

严格来说，在 Golang 中并不支持泛型编程。在 C++ 等高级语言中使用泛型编程非常的简单，所以泛型编程一直是 Golang 诟病最多的地方。但是使用 interface 我们可以实现泛型编程，我这里简单说一下，具体可以参考我前面给出来的那篇文章。比如我们现在要写一个泛型算法，形参定义采用 interface 就可以了，以标准库的 sort 为例。

```go
package sort

// A type, typically a collection, that satisfies sort.Interface can be
// sorted by the routines in this package.  The methods require that the
// elements of the collection be enumerated by an integer index.
type Interface interface {
    // Len is the number of elements in the collection.
    Len() int
    // Less reports whether the element with
    // index i should sort before the element with index j.
    Less(i, j int) bool
    // Swap swaps the elements with indexes i and j.
    Swap(i, j int)
}

...

// Sort sorts data.
// It makes one call to data.Len to determine n, and O(n*log(n)) calls to
// data.Less and data.Swap. The sort is not guaranteed to be stable.
func Sort(data Interface) {
    // Switch to heapsort if depth of 2*ceil(lg(n+1)) is reached.
    n := data.Len()
    maxDepth := 0
    for i := n; i > 0; i >>= 1 {
        maxDepth++
    }
    maxDepth *= 2
    quickSort(data, 0, n, maxDepth)
}
```

Sort 函数的形参是一个 interface，包含了三个方法：`Len()`，`Less(i,j int)`，`Swap(i, j int)`。使用的时候不管数组的元素类型是什么类型（int, float, string…），只要我们实现了这三个方法就可以使用 Sort 函数，这样就实现了“泛型编程”。有一点比较麻烦的是，我们需要将数组自定义一下。下面是一个例子。

```go
type Person struct {
    Name string
    Age  int
}

func (p Person) String() string {
    return fmt.Sprintf("%s: %d", p.Name, p.Age)
}

// ByAge implements sort.Interface for []Person based on
// the Age field.
type ByAge []Person //自定义

func (a ByAge) Len() int           { return len(a) }
func (a ByAge) Swap(i, j int)      { a[i], a[j] = a[j], a[i] }
func (a ByAge) Less(i, j int) bool { return a[i].Age < a[j].Age }

func main() {
    people := []Person{
        {"Bob", 31},
        {"John", 42},
        {"Michael", 17},
        {"Jenny", 26},
    }

    fmt.Println(people)
    sort.Sort(ByAge(people))
    fmt.Println(people)
}
```

另外 Gopher China 上还提到了一个比较有趣的东西和大家分享一下。在我们设计函数的时候，下面是一个比较好的准则。

> Be **conservative** in what you send, be **liberal** in what you accept. — Robustness Principle

对应到 Golang 就是：

> Return **concrete types**, receive **interfaces** as parameter. — Robustness Principle applied to Go

话说这么说，但是当我们翻阅 Golang 源码的时候，有些函数的返回值也是 interface。



#### hiding implement detail

隐藏具体实现，这个很好理解。比如我设计一个函数给你返回一个 interface，那么你只能通过 interface 里面的方法来做一些操作，但是内部的具体实现是完全不知道的。Francesc 举了个 context 的例子。 context 最先由 google 提供，现在已经纳入了标准库，而且在原有 context 的基础上增加了：cancelCtx，timerCtx，valueCtx。语言的表达有时候略显苍白无力，看一下 context 包的代码吧。

```go
func WithCancel(parent Context) (ctx Context, cancel CancelFunc) {
    c := newCancelCtx(parent)
    propagateCancel(parent, &c)
    return &c, func() { c.cancel(true, Canceled) }
}
```

表明上 WithCancel 函数返回的还是一个 Context interface，但是这个 interface 的具体实现是 cancelCtx struct。

```go
// newCancelCtx returns an initialized cancelCtx.
func newCancelCtx(parent Context) cancelCtx {
    return cancelCtx{
        Context: parent,
        done:    make(chan struct{}),
    }
}

// A cancelCtx can be canceled. When canceled, it also cancels any children
// that implement canceler.
type cancelCtx struct {
    Context     //注意一下这个地方

    done chan struct{} // closed by the first cancel call.
    mu       sync.Mutex
    children map[canceler]struct{} // set to nil by the first cancel call
    err      error                 // set to non-nil by the first cancel call
}

func (c *cancelCtx) Done() <-chan struct{} {
    return c.done
}

func (c *cancelCtx) Err() error {
    c.mu.Lock()
    defer c.mu.Unlock()
    return c.err
}

func (c *cancelCtx) String() string {
    return fmt.Sprintf("%v.WithCancel", c.Context)
}
```

尽管内部实现上下面三个函数返回的具体 struct （都实现了 Context interface）不同，但是对于使用者来说是完全无感知的。

```go
func WithCancel(parent Context) (ctx Context, cancel CancelFunc)    //返回 cancelCtx
func WithDeadline(parent Context, deadline time.Time) (Context, CancelFunc) //返回 timerCtx
func WithValue(parent Context, key, val interface{}) Context    //返回 valueCtx
```



#### providing interception points

这里的 interception 想表达的意思应该是 wrapper 或者装饰器，他给出了一个例子如下：

```go
type header struct {
    rt  http.RoundTripper
    v   map[string]string
}

func (h header) RoundTrip(r *http.Request) *http.Response {
    for k, v := range h.v {
        r.Header.Set(k,v)
    }
    return h.rt.RoundTrip(r)
}
```

通过 interface，我们可以通过类似这种方式实现动态分配 (dynamic dispatch)。

### 非侵入式

什么是侵入式呢？比如 Java 的 interface 实现需要显示的声明。

```java
public class MyWriter implements io.Writer {}
```

这样就意味着如果要实现多个 interface 需要显示地写很多遍，同时 package 的依赖还需要进行管理。Dependency is evil。比如我要实现 io 包里面的 Reader，Writer，ReadWriter 接口，代码可以像下面这样写。

```go
type MyIO struct {}

func (io *MyIO) Read(p []byte) (n int, err error) {...}
func (io *MyIO) Write(p []byte) (n int, err error) {...}

// io package
type Reader interface {
    Read(p []byte) (n int, err error)
}

type Writer interface {
    Write(p []byte) (n int, err error)
}

type ReadWriter interface {
    Reader
    Writer
}
```

这种写法真的很方便，而且不用去显示的 import io package，interface 底层实现的时候会动态的检测。这样也会引入一些问题：

1. 性能下降。使用 interface 作为函数参数，runtime 的时候会动态的确定行为。而使用 struct 作为参数，编译期间就可以确定了。
2. 不知道 struct 实现哪些 interface。这个问题可以使用 guru 工具来解决。

综上，Golang interface 的这种非侵入实现真的很难说它是好，还是坏。但是可以肯定的一点是，对开发人员来说代码写起来更简单了。

### interface type assertion

interface 像其他类型转换的时候一般我们称作断言，举个例子。

```go
func do(v interface{}) {
    n := v.(int)    // might panic
}
```

这样写的坏处在于：一旦断言失败，程序将会 panic。一种避免 panic 的写法是使用 type assertion。

```go
func do(v interface{}) {
    n, ok := v.(int)
    if !ok {
        // 断言失败处理
    }
}
```

对于 interface 的操作可以使用 reflect 包来处理，关于 reflect 包的原理和使用可以参考我的文章。

### 总结

interface 是 Golang 的一种重要的特性，但是这是以 runtime 为代价的，也就意味着性能的损失（关于 interface 的底层实现之后有时间再写）。抛开性能不谈，interface 对于如何设计我们的代码确实给了一个很好的思考。

##  参考

1. [Golang “泛型编程”](http://legendtkl.com/2015/11/25/go-generic-programming/)
2. [谈一谈 Golang 的 interface 和 reflect](http://legendtkl.com/2015/11/28/go-interface-reflect/)
3. [understanding golang interface(Gopher China) — youtube](https://www.youtube.com/watch?v=F4wUrj6pmSI&t=2319s)
4. [understanding golang interface(Gopher China) — slide](https://github.com/gopherchina/conference/blob/master/2017/1.4%20interface.presented.pdf)