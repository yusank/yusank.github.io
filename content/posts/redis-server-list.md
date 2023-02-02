---
title: "[系列]Redis Server 实现·链表篇"
date: 2021-12-24T10:50:00+08:00
lastmod: 2021-13-24T11:50:00+08:00
categories: ["Redis"]
tags: ["redis", "系列篇", "数据结构"]
---

> 本篇讲述 `Redis` 中的基础数据结构 `List` 的底层实现原理和如何通过 go 语言实现一个 `List` 的过程以及需要注意的问题。

<!--more-->

{{< admonition type=quote title="说明" open=true >}}
本文章为该系列的`链表`，如果需要阅读其他相关文章， 请点击[这里](https://yusank.github.io/posts/redeis-server-introduction/)跳转查看
{{< /admonition >}}

## 1 前言

众所周知，Redis 中有五大数据结构，在各种面试中也会经常遇到相关的问题，从这一篇开始，我把这个五大数据结构（`string`, `list`, `set`, `sorted_set`, `hash_map`）的底层原理和如何用 go 语言实现讲明白。

## 2 list能力

`list` 是一个我们常用的一个 Redis 特性，特定就是先进后出 `FILO` 。并且支持双端的读写，所以也可以在使用过程中也能实现基于 list 的 先进先出 `FIFO` 模型。

总结一下，Redis 支持的能力：

- 双端读写
- 批量读写
- list 内部元素的增删改
- 阻塞读取

## 3 list 底层原理

Redis 实现 list 的是双向链表(`linked-list`)。这个数据结构大家应该非常的熟悉，且经常拿链表和数组进行对比。相对于数组，链表最大的优势在于写入元素时不需要考虑数组一样 `grow` 过程，只需要将新元素连接到链表最后即可，而数组是需要考虑扩容缩容时数组 grow 问题的。

数据结构：

```go
type List struct {
    // 记录头和尾
    head, tail *listNode
}

type listNode struct {
    // 双向链表
    // 相对于单向链表 多记录一个 prev 指向前一个元素
    next, prev *listNode
    value      string
}
```

从数据结构来看，其实一点都不复杂，只需要记录第一个和最后一个元素，元素内部记录前一个和后一个元素的指针即可。读写都是基于修改元素内指向的指针来完成。

配合下面图看代码就更好理解了：

![wikipeida 示例图](https://upload.wikimedia.org/wikipedia/commons/5/5e/Doubly-linked-list.svg)

## 4 list的实现

下面我们开始用 go 语言来实现 Redis 中的 list 数据结构的特性。

### 4.1 定义和初始化

list 定义：

```go
type List struct {
    length     int // 记录总长度
    head, tail *listNode
}

type listNode struct {
    next, prev *listNode
    value      string
}
```

初始化：

```go
func newList() *List{
    return new(List)
}

func newListNode(val string) *listNode {
    return &listNode{
        value: val,
    }
}
```

### 4.2 增查元素

#### 4.2.1 增加元素

```go
// n 为 head 时调用
// 即新增一个元素并把该元素置位 head
func (n *listNode) addToHead(val string) *listNode {
    node := newListNode(val)
    n.prev = node
    node.next = n

    return node
}

// n 为 tail 时调用
// 即新增一个元素并把该元素置位 tail
func (n *listNode) addToTail(val string) *listNode {
    node := newListNode(val)
    n.next = node
    node.prev = n

    return node
}
```

以上两个方法配合下面两个 LPush和 RPush 方法使用：

```go
func (l *List) LPush(val string) {
    l.length++
    // 如果list 内已经有元素，则把新增元素置位 head
    if l.head != nil {
        l.head = l.head.addToHead(val)
        return
    }

    // 当前 list 为空，则将新元素置位 head 和 tail
    node := newListNode(val)
    l.head = node
    l.tail = node
}

// 逻辑与上面一致 sssss
func (l *List) RPush(val string) {
    l.length++
    if l.tail != nil {
        l.tail = l.tail.addToTail(val)
        return
    }

    node := newListNode(val)
    l.head = node
    l.tail = node
}
```

#### 4.2.2 pop元素

基础方法：

```go
// pop head 元素 并返回下一个元素
// pop current node and return next node
func (n *listNode) popAndNext() *listNode {
    var next = n.next

    // 将当前节点的 next 置位空
    n.next = nil
    if next != nil {
        next.prev = nil
    }

    return next
}

// pop tail 元素 并返回下一个元素
// pop current node and return prev node
func (n *listNode) popAndPrev() *listNode {
    var prev = n.prev

    n.prev = nil
    if prev != nil {
        prev.next = nil
    }

    return prev
}
```

下面是真正实现 LPop, RPop 方法：

```go
// left pop 从左边 pop 一个元素
func (l *List) LPop() (val string, ok bool) {
    if l.head == nil {
        return "", false
    }

    l.length--
    val = l.head.value
    l.head = l.head.popAndNext()
    if l.head == nil {
        l.tail = nil
    }

    return val, true
}

// right pop 从右边 pop 一个元素
func (l *List) RPop() (val string, ok bool) {
    if l.tail == nil {
        return "", false
    }

    l.length--
    val = l.tail.value
    l.tail = l.tail.popAndPrev()
    if l.tail == nil {
        l.head = nil
    }

    return val, true
}
```

#### 4.2.3 查询元素

根据 value 查询第一个元素（list 内元素值是可以重复的，所以查询第一个值相同的元素）

```go
func (l *List) findNode(val string) *listNode {
    var cur = l.head
    for cur != nil {
        if cur.value == val {
            return cur
        }
        cur = cur.next
    }

    return nil
}
```

根绝 index 查询元素

```go
func (l *List) lIndexNode(i int) *listNode {
    if l.head == nil {
        return nil
    }

    // 支持反向查，即如果 i 小于 0 则认为是倒数第 i 个元素，把 i 该为正数第 i 个
    if i < 0 {
        i += l.length
    }

    if i >= l.length || i < 0 {
        return nil
    }

    var (
        idx     int
        cur     = l.head
        reverse = i > l.length/2+1
    )

    // 为了查询效率，做一个小小的优化
    // 如果 i 在前半段则从头到尾的遍历，反之从尾到头
    if reverse {
        idx = l.length - 1
        cur = l.tail
    }

    for i != idx {
        if reverse {
            idx--
            cur = cur.prev
        } else {
            idx++
            cur = cur.next
        }
    }

    return cur
}
```

#### 4.2.4 删除元素

已经支持通过 value/index 查询元素了，就可以删除 list 内元素了，下面以从尾部开始删除 n 个元素为例：

```go
// i 表示 index 删除第 i 个元素
func (l *List) Rem(i int) int {
    node := l.lIndexNode(i)
    if node == nil {
        return 0
    }

    p := node.prev
    n := node.next
    if p != nil {
        p.next = nil
    } else {
        // node 是 head 所以没有 prev
        l.head = n
    }

    if n != nil {
        n.prev = nil
    } else {
        // node 是 tail 所以没有 next
        l.tail = p
    }

    if l.head == nil || l.tail == nil {
        // 删除了最后一个元素了
        l.head = nil
        l.tail = nil
    }
    l.length--

    return 1
}
```

### 4.3 高级特性

配合上面的一些基础方法以及链表的特性，可以写出不少花样玩法.

#### 4.3.1 某个元素前后插入新元素

{{< admonition type=tip title="场景 1" open=true >}}
Q: 假如我想在 list 内已知的元素的前面或后面新增一个元素，仅通过增删改查是做不到，有什么好的方法呢？

A: 其实还是通过遍历链表找到插入的位置 修改前后指向指针即可。
{{< /admonition >}}

实现源码如下：

```go
// flag 大于 0 插入到 target 后面 小于 0 插入前面
func (l *List) LInsert(target, newValue string, flag int) bool {
    if l.head == nil {
        return false
    }

    // 找到元素
    node := l.findNode(target)
    if node == nil {
        return false
    }

    if flag == 0 {
        node.value = newValue
        return true
    }

    newNode := &listNode{value: newValue}
    l.length++
    // insert after
    if flag > 0 {
        next := node.next
        node.next = newNode
        newNode.prev = node
        if next == nil {
            l.tail = newNode
        } else {
            newNode.next = next
            next.prev = newNode
        }

        return true
    }

    // insert before
    prev := node.prev
    node.prev = newNode
    newNode.next = node
    if prev == nil {
        l.head = newNode
    } else {
        newNode.prev = prev
        prev.next = newNode
    }

    return true
}
```

#### 4.3.2 批量删除元素

从某个元素开始往后删除 N 个或删除所有元素。

```go
// 从head 开始遍历删除 n 个值等于 value 的元素
func (l *List) LRemCountFromHead(value string, n int) (cnt int) {
    var (
        dumbHead = &listNode{
            next: l.head,
        }
        // 引入虚拟 head 是为了 防止从第一个元素删除，然后需要频繁修改 l.head 的值
        // 同时为了减少过多的特殊判断
        prev = dumbHead
        cur  = l.head
        next = l.head.next
    )

    // 开始遍历
    for cur != nil && n > 0 {
        // 找打元素
        if cur.value == value {
            // cur 前后的元素连接起来
            prev.next = next
            if next != nil {
                next.prev = prev
            }
            
            // cur 指向前后的指针置位空
            cur.prev, cur.next = nil, nil

            cnt++
            n--
        } else {
            // 只有在没有被删除元素时才移动 prev
            // *注意：prev 不能每次都移动，因为不确定下一个元素是不是也是要被删除的，
            //   只有确保 cur 不是我们要找的元素时候 才会同时移动三个指针*
            prev = prev.next
        }

        // dumHead   1      2     2    4     5 
        //   ^       ^      ^   ->>
        //  prev    cur    next

        // cur 和 next 往后移动
        cur = next
        if next != nil {
            next = next.next
        }
    }

    // remove last element
    if prev.next == nil {
        l.tail = prev
    }

    l.head = dumbHead.next
    if l.head != nil {
        // if remove first element from, dumbHead.next.prev will be point to dumbHead
        // // In other words, l.head.tail will be not nil
        l.head.prev = nil
    }
    l.length -= cnt
    return
}
```

#### 4.3.3 局部遍历

{{< admonition type=tip title="场景 2" open=true >}}
Q: 需要读取前几个或者后几个或者从第 N 个到第 M 个元素，但是不想 pop 出来怎么办？
{{< /admonition >}}

局部遍历的实现：

```go
func (l *List) LRange(start, stop int) (values []string) {
    if l.head == nil {
        return nil
    }

    // 这里需要支持负数，因为 Redis lrange 是支持负数
    //  负数代表倒数第 N 个
    if start < 0 {
        start = start + l.length
        if start < 0 {
            start = 0
        }
    }

    // 需要处理一下负数 虽然客户端表达式倒数第 N 个 但是实现的时候都是统一从头遍历到尾
    //  全部转换为正数
    if stop < 0 {
        stop = stop + l.length
    }

    // start already >=0 , so if stop < 0 then this case is true
    if start > stop || start > l.length {
        return nil
    }
    if stop >= l.length {
        stop = l.length - 1
    }

    var (
        head = l.head
        idx  int
    )

    for head != nil && idx <= stop {
        if idx >= start {
            values = append(values, head.value)
        }

        idx++
        head = head.next
    }

    return
}
```

## 5 总结

目前位置除了阻塞读取外，其他数据结构特性都以全部实现或者实现了底层方法 ，上面封装即可，完整代码请看 GitHub 项目。关于阻塞这块，由于服务端和客户端是长链接，所以实现其实比较简单，而且也属于数据结构的范畴，所以不再这里细讲，下面给出思路。

- 起一个 `goroutine`, 监听对应 key 的数据
- 有数据之前这次请求时不响应，知道返回正确结果或者客户端主动断开连接
- 拿到数据后，停止 `goroutine`, 响应客户端。

整体下来因为数据处理都是单进程，不需要考虑进程间资源竞争问题，代码相对简洁很多，注意增删元素时前后关系以及极限情况（边界的元素的修改）。

## 6 项目链接🔗

- [https://github.com/yusank/godis](https://github.com/yusank/godis)
