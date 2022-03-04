# Go 语言实现读取 pdf 文件内容


> 本篇介绍一个如何在 go 语言环境下，如何解析/读取 pdf 文件内容从而进行一些业务逻辑。本篇将会介绍两种方案，可以按自己的需求进行对比和最终选择。
<!--more-->

## 1. 背景

最近在帮朋友做一个小的程序，帮他减少一些人工繁琐的工作，将一些机器可以做的事情交给机器，提高效率他效率。

需求也相对简单，就是从大量 pdf/docx 文件内容中读取一些关键信息（这些信息有一定的规律），并输出一个 Excel 表格。听到这个需求我第一个想法是可以做的，我之前在一些招聘网站也是看过解析 pdf 内容的功能。最典型的就是在招聘网站上传个人简历时，会读出来个人信息以及其他信息。既然市面上有人这么干，那就说是肯定有一定的解决方案可以供我利用的。

接下来就是去找解决方案了，调研了一下午后，目标基本明确了。有两个项目进入了最终决赛圈，我需要分别使用，并把一些优缺点列出来就能确定最终胜者了。

这两个方案分别是:

1. [ledongthuc/pdf](https://github.com/ledongthuc/pdf) go语言实现的 pdf 解析库。有不少的 star 和 fork，并且从 demo 上看到确实能读取到内容。

2. [apache/tika](https://tika.apache.org/) `Java` 实现的 pdf 解析库。之所以能进入决赛圈是因为网上大量人推荐并且是 `apache` 的项目，所以我也比较放心使用。

## 2. go 语言方案

首先对 `ledongthuc/pdf` 进行使用测试。先上代码：

```go
package main

import (
    "bytes"
    "fmt"

    "github.com/ledongthuc/pdf"
)

func main() {
    pdf.DebugOn = true
    content, err := readPdf("test.pdf") // Read local pdf file
    if err != nil {
        panic(err)
    }
    fmt.Println(content)
    return
}

func readPdf(path string) (string, error) {
    f, r, err := pdf.Open(path)
    // remember close file
    defer f.Close()
    if err != nil {
        return "", err
    }
    var buf bytes.Buffer
    b, err := r.GetPlainText()
    if err != nil {
        return "", err
    }
    buf.ReadFrom(b)
    return buf.String(), nil
}
```

这是一段项目自己提供 demo，我本地确实也跑起来了。但是我当对一些我朋友提供的测试案例 pdf 文件进行解析时，遇到了问题，报了下面的错：

```
malformed PDF: reading at offset 0: stream not present
```

我第一反应是可能我的 pdf 不是很标准 pdf 格式导致，然后去项目 `issue` 里看到类似的问题，并且作者也给了解决方案，明显比较麻烦的一种解决方案。因为需要对文件进行一些处理，这个方案我不是很能接受。不过我找一些网上标准(所谓的标准就是去找了一些权威的网站上的 pdf 文件)的 pdf 文件的时候，的确能读出内容。这个方案我先标注为 `backup`, 实在没辙我再回来折腾。

## 3. tika + go client 方案

[apache/tika](https://tika.apache.org/) 是一个比较万能的工具集，其能力可以参考官方的说明。

{{< admonition type=quote title="apache/tika" open=true >}}
<font color="red" size=4>**Apache Tika - a content analysis toolkit**</font>

The Apache Tika™ toolkit detects and extracts metadata and text from over a thousand different file types (such as PPT, XLS, and PDF). All of these file types can be parsed through a single interface, making Tika useful for search engine indexing, content analysis, translation, and much more. 
{{< /admonition >}}

虽然说是Java 项目，我不能直接引入到我的 go 项目使用，但是人家提供了 API，这就非常的 nice 了。然后几乎同时我发现了 `Google` 的一个项目 [go-tika](https://github.com/google/go-tika), tika 的 go 语言版 client 端，也就是我不用去写调用 api 相关代码了，简直又省了我不少时间。

### 3.1. 部署

因为 `tika` 是个 server 端项目，那我得用的时候需要把他跑起来才行，但是我本地没有 Java 环境，我也不想去折腾（自己又不懂，瞎搞绝对浪费时间还搞不定）。所以我转向了万能的 docker 部署。找到 tika 的 docker 镜像，本地启动就可以用了。

```shell
$ docker run -d -p 9998:9998 apache/tika:latest
```

部署完事儿。


### 3.2. 使用

使用方面也是非常简单，有了 `go-tika` 项目的加成，我需要写的代码几乎很少，代码如下：

```go
package main

import (
    "fmt"
    "flag"
    "context"
    "os"

    "github.com/google/go-tika/tika"
)

func main() {
    var filePath string
    flag.StringVar(&filePath, "fp", "", "pdf file path.")
    flag.Parse()
    if filePath == "" {
        panic("file path must be provided")
    }
    content, err := readPdf(filePath) // Read local pdf file
    if err != nil {
        panic(err)
    }
    fmt.Println(content)
    return
}

func readPdf(path string) (string, error) {
    f, err := os.Open(path)
    defer f.Close()
    if err != nil {
        return "", err
    }

    client := tika.NewClient(nil, "http://127.0.0.1:9998")
    return client.Parse(context.TODO(), f)
}
```

响应速度完全在可接受范围内（30ms 左右），而且更让我惊喜的是，之前在用 go 语言的库解析出错的 pdf 在这里完全没问题，没有漏掉一个字的给我解析出来了。可以说是完全达到我的要求了。

## 4. 总结

从我个人的需求上面来说 tika 是完胜的，但是速度上的确没有 `ledongthuc/pdf` 快，但是只是快并不能解决问题。`ledongthuc/pdf` 读取标准的 pdf 没问题，如果你的需求是读取一些标准的 pdf ，那 `ledongthuc/pdf` 绝对比 `tika` 好用的，又快又不需要搭建一个 server 端。

如果你遇到的 pdf 不能保证来源和质量，那 tika 更适合，读取内容的概率更高，我自己测了大概 100 来份各种 pdf，成功率也很高，除非是非常模糊的 pdf，否则都能读取到内容，而且延迟 30ms 对于一般需求来说是足够的。况且是 docker 部署的无状态服务，如果你要大量的 pdf 需要处理，那就多搭建几个 server 端同时处理就好了。

其他方面的对比 ，可以参考这篇文章：[https://www.jianshu.com/p/68609f51b6e7](https://www.jianshu.com/p/68609f51b6e7) 讲得比较细，感兴趣的可以去阅读。

如果你有不同的想法，那再评论区见吧~

