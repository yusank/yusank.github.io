# [系列]Redis Server 实现·协议篇


{{< admonition type=quote title="说明" open=true >}}
本文章为该系列的`协议篇`，如果需要阅读其他相关文章， 请点击[这里](https://yusank.github.io/posts/redeis-server-introduction/)跳转查看
{{< /admonition >}}

<!--more-->

## 前言

`Redis` 作为一个当下最流行的 `NoSQL` 或 `KV` 数据库，几乎嵌入到大部对性能、时效性高的项目内，变成了每个程序员尤其是后端程序必需了解的一个知识点。
我是无形在 GitHub 上发现一个 `Godis` 项目，是实现了大部分 Redis 服务器的功能。
然后瞬间激发了我的兴趣，既然用了 Redis 这些年了而且对核心逻辑和数据结构也是有所了解的，那我为什么不也写一个基于 `Go` 的 Redis 服务器代码，实现我能实现的核心功能逻辑。目的无外乎以下几点：

1. 更全面且系统的了解Redis 核心逻辑并把自己的了解通过代码输出出来
2. 提高自己的代码水平
3. 提高自己的算法水平（涉及到实现 Redis 核心五大数据结构）

所以我也起了一个项目叫 `Godis`,一步步将 Redis 的逻辑通过Go 代码写出来，并且在性能上尽可能的追赶 Redis 的性能。

前期我更专注于最核心的 `请求处理`, `协议处理`, `数据结构处理`, `命令处理` 等这些基础核心的模块一个个攻破，至于数据持久化，分布式部署，主从模式等这些高级特性，我在确保之前的功能都达到预期后再考虑，目前计划是数据持久化可能优先考虑。

## 协议

想实现 `Redis` 服务器首先想到的问题是，如何通信？其实都知道是 tcp 连接，所以更准确的问题是，客户端和服务端用的什么协议去传输数据？答案是 RESP (REdis Serialization Protocol）。

该协议从内容来说还是比较简单的，对于服务端去解析也是相对友好且消耗性能很低。官方给出的优点为以下三点：

- 容易实现
- 解析快
- 可读性高

RESP 协议为一个 request-response 模型的协议，客户端发出请求并等待服务器响应，服务器按同样的协议返回数据。下面我们来看一下协议具体内容。

## 基础说明

在 RESP 协议中，所有的数据的第一字符都是以下五种类型之一：

- `+` : 简单字符串.
- `-` : 错误.
- `:` : 整数.
- `$` : 复杂字符串或大块字符串(bulk string).
- `*` : 数组.

{{< admonition type=tip title="数据结尾" open=true >}}
任何一个类型的数据都是以 `"\r\n"(CRLF)`作为结束符.
{{< /admonition >}}

> 本文中的大部分示例均来自官方文档。

## 简单字符串(Simple Strings)

简单字符串以 `+` 符号开始，然后字符内容（不能包含 CR 或 LF，即不能有换行符），以 `CRLF("\r\n")` 结尾。简单字符不适合传输数据(non binary safa)，在 Redis 内基本用于响应 `"OK"` 或成功标识。

{{< admonition type=example title="简单字符串" open=true >}}
"+OK\r\n"
{{< /admonition >}}

为了安全起见，Redis 内传输数据会用 Bulk Strings  .

## 错误(Errors)

RESP 预留专门的错误类型。其实错误类型与简单字符串几乎没区别，只是第一个字符是 `-`, 除此之外在处理和编码过程均无区别，更多的区别在于客户端处理上。

{{< admonition type=example title="Errors" open=true >}}
"-Error Message\r\n"
{{< /admonition >}}

`Errors` 类型只用于在处理请求遇到错误时，响应到客户端，比如命令不存在或命令与 key 的类型不符合等。客户端应该针对错误做一层处理，方便使用者感知到错误。

{{< admonition type=example title="另一个 Errors 的例子" open=true >}}
-ERR unknown command 'foobar'<br>
-WRONGTYPE Operation against a key holding the wrong kind of value
{{< /admonition >}}

从 `-` 到第一个空格或新一行的单词代表返回的错误的`类型`。这个是 `Redis` 的一个响应习惯(convention)，将错误分类型，方便客户端更灵活的处理。

以上面的例子为例， `ERR` 是一个通用的错误，而 `WRONGTYPE` 是一个具体的错误类型，代表命令和 key 的类型不匹配,这个叫错误前缀`Error Prefix`。站在客户端角度来说，相对于一串错误字符串，拿到一个具体的错误类型无异于拿到一个 error code 一样，可以做一个具体的操作来消化这个错误。

当然如果分的错误类型很细 那客户端就得写的更复杂反而可能会导致得不偿失，抛开 `Redis` 的习惯从协议的角度来说，可以在非常简单的返回一个 false 来说明一个错误或者就一行错误内容，返回给用户，这个更多的取决于客户端实现的时候的取舍。

## 整数(Integers)

该类型与上述两个类型也没有很大的区别，是为了专门传输整数而定的，以`:` 字符为开头，内容为整数且以`\r\n` 结尾，如 `":100\r\n"` 。

{{< admonition type=warning title="数字范围" open=true >}}
有符号 64 位整数
{{< /admonition >}}

`Redis` 中像 `INCR`, `LLEN` 和 `LASTSAVE` 等命令都返回整数。当然返回整数没有别的意义，只是这些命令的结果是数字。

除了命令结果是整数时返回 `Integer` 类型外，一些命令用整数 `0 or 1` 来表示 `true or false`,如 `EXISTS`, `SISMEMBER`。

还有一些命令是返回 `1` 表示操作真正执行(这么说是因为，一些操作因为数据已存在或已被操作所以不会再次操作数据而直接返回),否则返回 `0` ，像 `SADD`, `SREM`, `SETNX` 等。

## 复杂字符串(Bulk Strings)

复杂字符串为 `RESP` 中二进制安全的字符串类型，最大容量为 512MB。bulk string 编码方式如下：

- 以 `$`为开头写入实际字符串长度并以 CRLF 结尾
- 实际字符串
- CRLF 结束

{{< admonition type=example title="以 Hello 为例" open=true >}}
"$5\r\nHello\r\n"
{{< /admonition >}}

{{< admonition type=example title="空字符" open=true >}}
"$0\r\n\r\n"
{{< /admonition >}}

前面说到`简单字符串` 不能包好换行符，然而 `Bulk String`是允许包含这类特殊字符的，因为读取 `Bulk String` 是根据其定义的长度来读取的，而不是根据换行符。

{{< admonition type=example title="包含换行符的例子" open=true >}}
"$4\r\nOK\r\n\r\n"<br>
这是一个有效的复杂字符串其内容是 `OK\r\n`包含四个字符。<br>
**注意：$4\r\n<u>OK\r\n</u>\r\n, 下划线才是字符串内容**
{{< /admonition >}}


Bulk String 支持 Null 值（注意不是空字符）以此来区分数据不存在的情况。Null 的情况下不存在数据，所以长度为-1（-1 是协议定的，具体为什么是-1 *I hava no idea .*), 没有数据部分也没有数据最后的 CRLF（**空字符是有的，这个需要注意的**）

{{< admonition type=example title="Null 响应" open=true >}}
"$-1\r\n"
{{< /admonition >}}

官方原文：

This is called a **Null Bulk String**.

## 数组(Arrays)

客户端的所有请求都是以数组的方式传到服务端的，而服务端的响应如果是多个值也都是以数组的方式响应。比如 `ZRANGE`, `LRANGE`, `MGET` 等。

数组(Arrays) 是以下方式编码的：

- 以 `*` 作为第一个字符，然后写入数组的长度，最后以 CRLF 结尾.
- 一组 RESP 类型的数据作为数组的元素.

{{< admonition type=example title="空数组" open=true >}}
"*0\r\n"
{{< /admonition >}}

{{< admonition type=example title="包含 foo 和 bar 两个 bulk string 作为元素的数组" open=true >}}
"*2\r\n$3\r\nfoo\r\n$3\r\nbar\r\n"<br>
**为了阅读方便加上换行符：**<br>
*2\r\n<br>
$3\r\n<br>
foo\r\n<br>
$3\r\n<br>
bar\r\n
{{< /admonition >}}

不难发现，数组只需要声明长度即可，后面拼接元素就可以，元素之前无需有任何分隔符，元素可以是`简单字符串`, `Errors`, `整型`,`复杂字符串`。下面例子更明显体现如何使用包含不用元素的数组：

{{< admonition type=example title="混合元素例子" open=true >}}
*5\r\n<br>
:1\r\n<br>
:2\r\n<br>
+SimpleString\r\n<br>
-Err Message\r\n<br>
`$6\r\n`<br>
foobar\r\n<br>
{{< /admonition >}}

### Null数组

与复杂字符串一样，数组也支持表示 Null 值，在 `BLPOP` 命令中，如果操作超时，则返回一个 Null 数组表示结果：

{{< admonition type=example title="Null Array" open=true >}}
"*-1\r\n"
{{< /admonition >}}

实现客户端时，应该考虑并区分开空数组和 Null 数组（如无数据或操作超时）应该有不同的处理方式。

### 嵌套

数组是支持其元素也是数组的，如下面是一个包含两个数组作为元素的数组：

{{< admonition type=example title="嵌套数组" open=true >}}
*2\r\n<br>
*3\r\n<br>
:1\r\n<br>
:2\r\n<br>
:3\r\n<br>
*2\r\n<br>
+Foo\r\n<br>
-Bar\r\n<br>
{{< /admonition >}}

把 RESP 协议转换成可读性更高的数据后：

{{< admonition type=tip title="解码后" open=true >}}
`[[1, 2, 3], ["Foo", Error("Bar")]]`
{{< /admonition >}}

### 包含 Null 元素的数组

在与 `Redis` 交互时, 一部分命令是操作多个 key，返回多个值的，这个时候就有个问题，其中一些操作不成功或数据不存在，
该不该影响这次请求的整体结果呢？

以 `MGET` 这个命令为例，如果获取多个 key 的值，而其中有一部分 key 是不存在时，`Redis` 在响应中留 null 值从而不影响其他 key 的读取，协议如下：

{{< admonition type=example title="包含 Null 元素" open=true >}}
*3\r\n<br>
`$3\r\n`<br>
foo\r\n<br>
`$-1\r\n`<br>
`$3\r\n`<br>
bar\r\n<br>
{{< /admonition >}}

客户端针对该响应解析出来的结果应该如下：

{{< admonition type=tip title="解码后" open=true >}}
`["foo", nil, "bar"]`
{{< /admonition >}}

## 客户端服务端交互

到目前为止，RESP 协议的内容全部说完了，发现其实蛮简单的。其实现在去实现一个客户端的代码比实现服务端的简单很多，因为只需要编码解码协议内容即可。
服务端和客户单交互最核心就是以下两点：

- 客户端向服务端发起请求均为以 `Bulk Strings` 作为元素的数组.
- 服务端向客户端响应任意合法的 RESP 数据类型.

以 `LLEN mylist` 为例：

{{< admonition type=abstract title="一次交互过程" open=true >}}
C:  `*2\r\n`<br>
C:  `$4\r\n`<br>
C:  `LLEN\r\n`<br>
C:  `$6\r\n`<br>
C:  `mylist\r\n`<br><br>

S:  `:48293\r\n`

> C: client， S:server
{{< /admonition >}}

## 高效解析协议

该协议可读性相对高，与此同时解析效率也很高，下面给出如何解析该协议.

```go
import (
    "bytes"
    "log"
    "io"
)

func main() {
    var p = []byte("$5\r\nHello\r\n")
    buf := bytes.NewBuffer(p)
    // read first line
    b, err := buf.ReadBytes('\n')
    if err != nil {
        panic(err)
    }
    // read length
    ln := readBulkOrArrayLength(b)
    log.Println("string len: ",ln)
    // string len: 5

    // read value
    value,err := readBulkStrings(buf, ln)
    if err != nil {
        panic(err)
    }

    log.Println("value: ", string(value))
    // value: Hello
}
// 解析长度
func readBulkOrArrayLength(line []byte) int {
    var (
        ln int
    )
    for i := 1; line[i] != '\r'; i++ {
        ln = (ln * 10) + int(line[i]-'0')
    }

    return ln
}

// 读取内容
func readBulkStrings(r io.Reader, ln int) (val []byte, err error) {
    if ln <= 0 {
        return
    }

    // 读取时 将 \r\n 也读出来，保证 offset 在新的一行第一个字符
    val = make([]byte, ln+2)
    _, err = r.Read(val)

    // trim last \r\n
    val = val[:ln]
    return
}
```

## 参考文献

- https://redis.io/topics/protocol

