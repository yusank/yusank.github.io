# Go 泛型提前尝试


> `Go` 已经确实在 `1.18` 版本支持泛型了，预计 2022 年 2 月份发布 1.18 正式版，到目前为止泛型相关规范已确定且可以在开发分支的 go 版本中尝试使用了，这篇文章带你领略 `go` 的泛型.

<!--more-->

## 安装 go 开发版

{{< admonition type=question title="没有发版我怎么提前尝试呢？" open=true >}}
在这里分享一个小技巧，学会了之后以后每个新版本发布前都可以提前尝试新版的特性，提前学习好。
{{< /admonition >}}

可以通过下面的命令安装最新的 `master` 分支：

```shell
go install golang.org/dl/gotip
gotip download
```

现在可以把 `gotip` 这个命令当做 go 命令来使用了，

```shell
gotip version

go version devel go1.18-d6c4583 Wed Dec 8 23:38:20 2021 +0000 linux/amd64
```

{{< admonition type=tip title="灵活使用 bash alias" open=true >}}
`gotip` 敲起来麻烦，总是习惯性打 go build/run , 我就在 `.bashrc` 添加了一行配置

```shell
alias go18="gotip"
# 如果你有单独的 workspace 直接用 go="gotip" 也可以
```

{{< /admonition >}}

## 泛型

### 基础用法

**终于可以不用为 `int/uint/int8/int16/int32/int64` 写一堆代码类似的代码了！**

```go
type Integer interface{
    ~uint|~uint8|~uint16|~uint32|~uint64|~int|~int8|~int16|~int32|~int64
}

func Max[T Integer](a, b T) T {
    if a > b {
        return a
    }

    return b
}

func main() {
    fmt.Println(Max(1, 2)) // 2
    fmt.Println(Max(uint(1), uint(2))) // uint(2)
    fmt.Println(Max(int64(1), int64(2))) // 2
}
```

定义支持的类型 `Integer`,  `|` 表示并集， `~` 表示底层是该类型也可以(`type CustomInt int` 这种情况)。这个就是最基础的基于泛型的代码了，是不是看着都不太像 go 代码了，哈哈。

其实， `Integer` 类型不需要我们定义了，go 官方新增了 `constraints` 包，放了一些常用的泛型类型，后期应该也会扩展。

```go
// Copyright 2021 The Go Authors. All rights reserved.
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

// Package constraints defines a set of useful constraints to be used
// with type parameters.
package constraints

// Signed is a constraint that permits any signed integer type.
// If future releases of Go add new predeclared signed integer types,
// this constraint will be modified to include them.
type Signed interface {
    ~int | ~int8 | ~int16 | ~int32 | ~int64
}

// Unsigned is a constraint that permits any unsigned integer type.
// If future releases of Go add new predeclared unsigned integer types,
// this constraint will be modified to include them.
type Unsigned interface {
    ~uint | ~uint8 | ~uint16 | ~uint32 | ~uint64 | ~uintptr
}

// Integer is a constraint that permits any integer type.
// If future releases of Go add new predeclared integer types,
// this constraint will be modified to include them.
type Integer interface {
    Signed | Unsigned
}

// Float is a constraint that permits any floating-point type.
// If future releases of Go add new predeclared floating-point types,
// this constraint will be modified to include them.
type Float interface {
    ~float32 | ~float64
}

// Complex is a constraint that permits any complex numeric type.
// If future releases of Go add new predeclared complex numeric types,
// this constraint will be modified to include them.
type Complex interface {
    ~complex64 | ~complex128
}

// Ordered is a constraint that permits any ordered type: any type
// that supports the operators < <= >= >.
// If future releases of Go add new ordered types,
// this constraint will be modified to include them.
type Ordered interface {
    Integer | Float | ~string
}
```

上面的代码可以简化为如下：

```go
import (
    "constraints"
)

func Max[T constraints.Integer](a, b T) T {
    if a > b {
        return a
    }

    return b
}

func main() {
    fmt.Println(Max(1, 2)) // 2
    fmt.Println(Max(uint(1), uint(2))) // uint(2)
    fmt.Println(Max(int64(1), int64(2))) // 2
}
```

当然如果想扩展也是完全可以，比如上面的 Max 方法要支持 `float` 类型的话，自己定义一个新的 `interface` 即可。

```go
type Number interface{
    constraints.Integer | constraints.Float
}
```

### 花式玩法

#### slice

如果你写 go 的时间长的话， 应该经历过写很多长得很像排序算法，也应该羡慕过`python/js`的直接 `string.sort()`这种写法的，现在用泛型也可以玩出同样的姿势了。废话不多说直接上货：

```go
type Slice[T constraints.Ordered] []T

func (s Slice[T]) Sort() {
    sort.Slice(s,func (i,j int)  bool {
        return s[i] < s[j]
    })
}

func main() {
    // 随时定义随时调用，没有过多的方法调用或者额外的条件判断了
    ss := Slice[string]{"b","d","c","a"}
    ss.Sort()
    fmt.Println(ss)
    
    is := Slice[int]{2,4,1,3}
    is.Sort()
    fmt.Println(is)
}
```

这块代码运行成功后，我反正是很爽的，以后起码少些很多长得像功能还一样的代码了，等正式发版后可以搞一波支持泛型的基础库了。

#### map

`map` 的 `key-value` 均可以指定泛型，从而灵活的做一些处理，下面以返回某个 map 的 key 作为数组的例子：

```go
// 定义一个 key 可以做对比的类型 value 作为任意类型
// 注： any == interface{}
type Map[K constraints.Ordered, V any] map[K]V

func (m Map[K,V]) Keys() []K {
    var result []K
    for k := range m {
        result = append(result, k)
    }

    return result
}

func main() {
    sm := Map[string,int]{"a":1,"b":2}
    fmt.Println(sm.Keys()) // [a, b]

    im := Map[int,string]{1:"a",2:"b"}
    fmt.Println(im.Keys()) // [1, 2]
}
```

这样减少了很多类型判断类型转换的过程了，只要初始化的时候声明好了后返回的就是对应类型的数组而不是 `[]interface{}` .

#### chan

`chan` 作为在高并发异步编程中非常常用的特性，之前也面领着同样类型转换类型判断的困扰，设想一个场景，如果我有个需求，将数组转换成 channel，异步的去处理这组数据，如果数组类型是单个还好 如果我又有 string 的又有 int 的未来可能还会有别的类型，那只能一个类型一个方法或者统一 `interface` 然后使用时类型转换。如果用泛型实现呢？

```go
// 类型也可以按需求限制在 Ordered 或 comparable 等范围
func convertChan[T any](slice []T) chan T {
    ch := make(chan T, 1)
    go func() {
        defer close(ch)
        for _, v := range slice {
            ch <- v
        }
    }()

    return ch
}

func main() {
    s1 := []string{"a", "b", "c"}
    // s2 := []float64{1.1, 1.2, 1.3}
    ch := convertChan(s1)
    // ch => chan string
    for v := range ch {
        fmt.Println(v)
    }
    // a, b, c
}

```

## 总结

{{< admonition type=note title="总结" open=true >}}
整体而言，新增的泛型我觉得利大于弊的，看起来是语法复杂了很多其实并没有，定义的时候限制一些可用的基础类型或者直接用 `any` 来表示接受任何类型的参数即可。

对于开发者来说绝对会减少一部分重复代码的，也可以做一些更好的抽象，从长远来说对开发者还是好处很多的。

 `1.18`是第一个支持泛型的版本，肯定会谨慎一些，之后的版本该功能说不定会得到更多的扩展和支持，所以还是很期待的。
{{< /admonition >}}

{{< admonition type=question title="最后" open=true >}}
如果你对泛型有自己不一样的看法或者用法，也可以来讨论讨论。
{{< /admonition >}}

## 参考文档

- [https://bitfieldconsulting.com/golang/generics](https://bitfieldconsulting.com/golang/generics)
- [https://colobu.com/2021/10/24/go-generic-eliding-interface/](https://colobu.com/2021/10/24/go-generic-eliding-interface/)

