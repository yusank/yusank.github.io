---
title: "Go Format"
date: 2017-06-04T17:59:00+08:00
update: 2017-06-05T09:18:24+08:00
categories:
- 技术
tags:
- go 
- 代码规范
---
go 代码的一些规范和命名规则......

# Golang 代码规范

## 项目目录结构

``` sh
PROJECT_NAME
├── README.md 介绍软件及文档入口
├── bin 编译好的二进制文件,执行./build.sh自动生成，该目录也用于程序打包
├── build.sh 自动编译的脚本
├── doc 该项目的文档
├── pack 打包后的程序放在此处
├── pack.sh 自动打包的脚本，生成类似xxxx.20170713_14:45:35.tar.gz的文件，放在pack文件下
└── src 该项目的源代码
    ├── main 项目主函数
    ├── model 项目代码
    ├── research 在实现该项目中探究的一些程序
    └── vendor 存放go的库
        ├── github.com/xxx 第三方库
        └── xxx.com/obc 公司内部的公共库
```

项目的目录结构尽量做到简明、层次明确。

## 命名规范

### 文件名命名规范

用小写，尽量见名思义，看见文件名就可以知道这个文件下的大概内容，对于源代码里的文件，文件名要很好的代表了一个模块实现的功能。

### 包名

包名用小写，使用短命名，尽量不要和标准库冲突。

### 接口名

单个函数的接口以 `er` 作为后缀，如 Reader， Writer

接口的实现则去掉后缀

``` go
type Reader interface {
    Read(p []byte) (int, error)
}
```

两个函数的接口名综合两个函数名

``` go
type WriteFlusher interface {
    Write([]byte) (int, error)
    Flush() error
}
```

三个以上函数的接口名，类似于结构体名

``` go
type Car interface {
    Start([]byte) 
    Stop() error
    Recover()
}
```

### 变量

全局变量：采用驼峰命名法，仅限在包内的全局变量，包外引用需要写接口，提供调用；

局部变量：驼峰式，第一个单词的首字母小写，如有两个以上单词组成的变量名，第二个单词开始首字母大写。

### 常量

全局：驼峰命名，每个单词的首字母大写

局部：与变量的风格一样

## 函数名

函数名采用驼峰命名法，不要使用下划线。

## import 规范

import在多行的情况下，goimports 会自动帮你格式化，在一个文件里面引入了一个package，建议采用如下格式：

``` go
import (
    "fmt"
)
```

如果你的包引入了三种类型的包，标准库包，程序内部包，第三方包，建议采用如下方式进行组织你的包：

``` go
import {
    "net"
    "strings"

    "github.com/astaxie/beego"
    "gopkg.in/mgo.v2"

    "myproject/models"
    "myproject/utils"
}
```

项目中最好不要使用相对路径导入包：

// 这是不好的导入

``` go
import “../net”
```

// 这是正确的做法

``` go
import “xxxx.com/proj/net”
```

## 错误处理

error作为函数的值返回,必须尽快对error进行处理

采用独立的错误流进行处理

不要采用这种方式

``` go
    if err != nil {
        // error handling
    } else {
        // normal code
    }
```

而采用以下方式

``` go
 if err != nil {
        // error handling
        return // or continue, etc.
    }
    // normal code
```

如果返回值需要初始化，则采用以下方式

``` go
x, err := f()
if err != nil {
    // error handling
    return
}
// use x
```

### panic

在逻辑处理中禁用panic

在 main 包中只有当实在不可运行的情况采用 panic，例如文件无法打开，数据库无法连接导致程序无法 正常运行，但是对于其他的 package 对外的接口不能有 panic，只能在包内采用。 建议在 main 包中使用 log.Fatal 来记录错误，这样就可以由 log 来结束程序。

## Recover

recover 用于捕获 runtime 的异常，禁止滥用 recover，在开发测试阶段尽量不要用 recover，recover 一般放在你认为会有不可预期的异常的地方。

``` go
func server(workChan <-chan *Work) {
    for work := range workChan {
        go safelyDo(work)
    }
}

func safelyDo(work *Work) {
    defer func() {
        if err := recover(); err != nil {
            log.Println("work failed:", err)
        }
    }()
    // do 函数可能会有不可预期的异常
    do(work)
}
```

## Defer

defer 在函数 return 之前执行，对于一些资源的回收用 defer 是好的，但也禁止滥用 defer，defer 是需要消耗性能的,所以频繁调用的函数尽量不要使用 defer。

``` go
// Contents returns the file's contents as a string.
func Contents(filename string) (string, error) {
    f, err := os.Open(filename)
    if err != nil {
        return "", err
    }
    defer f.Close()  // f.Close will run when we're finished.

    var result []byte
    buf := make([]byte, 100)
    for {
        n, err := f.Read(buf[0:])
        result = append(result, buf[0:n]...) // append is discussed later.
        if err != nil {
            if err == io.EOF {
                break
            }
            return "", err  // f will be closed if we return here.
        }
    }
    return string(result), nil // f will be closed if we return here.
}
```

## 控制结构

### if

if接受初始化语句，约定如下方式建立局部变量

``` go
if err := file.Chmod(0664); err != nil {
    return err
}
```

### for

采用短声明建立局部变量

```go
sum := 0
for i := 0; i < 10; i++ {
    sum += i
}
```

### range

如果只需要第一项（key），就丢弃第二个：

``` go
for key := range m {
    if key.expired() {
        delete(m, key)
    }
}
```

如果只需要第二项，则把第一项置为下划线

``` go
sum := 0
for _, value := range array {
    sum += value
}
```

### return

尽早return：一旦有错误发生，马上返回

``` go
f, err := os.Open(name)
if err != nil {
    return err
}
d, err := f.Stat()
if err != nil {
    f.Close()
    return err
}
codeUsing(f, d)
```

## 方法接收器

名称一般采用 struct 的第一个字母且为小写， 而不是 this，me 或 self

``` go
type Transfer struct{}
func(t *Transfer) Get() {}
```

如果接收者是 map， slice 或者 chan，不要用指针传递

``` go
//Map
package main

import (
    "fmt"
)

type mp map[string]string

func (m mp) Set(k, v string) {
    m[k] = v
}

func main() {
    m := make(mp)
    m.Set("k", "v")
    fmt.Println(m)
}
```

``` go
//Channel
package main

import (
    "fmt"
)

type ch chan interface{}

func (c ch) Push(i interface{}) {
    c <- i
}

func (c ch) Pop() interface{} {
    return <-c
}

func main() {
    c := make(ch, 1)
    c.Push("i")
    fmt.Println(c.Pop())
}
```

如果需要对 slice 进行修改，通过返回值的方式重新复制

``` go
//Slice
package main

import (
    "fmt"
)

type slice []byte

func main() {
    s := make(slice, 0)
    s = s.addOne(42)
    fmt.Println(s)
}

func (s slice) addOne(b byte) []byte {
    return append(s, b)
}
```

如果接收者是含有 sync.Mutex 或者类似同步字段的结构体，必须使用指针传递避免复制

``` go
package main

import (
    "sync"
)

type T struct {
    m sync.Mutex
}

func (t *T) lock() {
    t.m.Lock()
}

/*
Wrong !!!
func (t T) lock() {
    t.m.Lock()
}
*/

func main() {
    t := new(T)
    t.lock()
}
```

如果接收者是大的结构体或者数组，使用指针传递会更有效率。

``` go
package main

import (
    "fmt"
)

type T struct {
    data [1024]byte
}

func (t *T) Get() byte {
    return t.data[0]
}

func main() {
    t := new(T)
    fmt.Println(t.Get())
}
```

## 一键代码规范

使用 JetBrain 系列 IDE 的同学，可以按快捷键或者鼠标右键来一键使用 go 提供的 `format` 命令;

快捷键：

cmd + option + shift + f 对当前文件进行 format

cmd + option + shift + p 对当前项目所有 go 文件进行 format

鼠标右键：

在 IDE 内点击鼠标右键，选择 `Go Tools`,然后可以选择对单个文件或项目进行 format。



用 vscode 的同学，在设置里面加上以下语句即可以保存文件后自动进行 format

``` json
"go.formatOnSave": true
```

## 总结

代码风格和代码规范是体现一个程序员的基本素质的一项指标，也是对自己的代码和他人的一个最基本的尊重。