---
title: "好用且实用的写文章技巧"
subtitle: "记录在当前 Theme(loveIt) 下写文章常用或好用的技巧"
date: 2021-11-23T10:10:00+08:00
lastmod: 2021-11-23T10:10:00+08:00
categories: ["Markdown"]
tags: ["技巧"]
---

> 这里我会记录一些 `Markdown` 和 `Shortcut` 的使用技巧以及常用的模块，方便后期写文章时查看和使用。

<!--more-->

## shortcuts

### admonition

{{< admonition type=note title="Note" open=true >}}
This is *Note* .
{{< /admonition >}}

{{< admonition type=abstract title="Abstract" open=true >}}
This is *Abstract* .
{{< /admonition >}}

{{< admonition type=inf title="Info" open=true >}}
This is *Info* .
{{< /admonition >}}

{{< admonition type=tip title="Tip" open=true >}}
This is *Tip* .
{{< /admonition >}}

{{< admonition type=success title="Success" open=true >}}
This is *Success* .
{{< /admonition >}}

{{< admonition type=question title="Question" open=true >}}
This is *Question* .
{{< /admonition >}}

{{< admonition type=warning title="Warning" open=true >}}
This is *Warning* .
{{< /admonition >}}

{{< admonition type=failure title="Failure" open=true >}}
This is *Failure* .
{{< /admonition >}}

{{< admonition type=danger title="Danger" open=true >}}
This is *Danger* .
{{< /admonition >}}

{{< admonition type=bug title="Bug" open=true >}}
This is *Bug* .
{{< /admonition >}}

{{< admonition type=example title="Example" open=true >}}
This is *Example* .
{{< /admonition >}}

{{< admonition type=quote title="Quote" open=true >}}
This is *Quete* .
{{< /admonition >}}

### typeit

#### markdown

{{< typeit >}}
This is a *paragraph* with **typing animation** based on [TypeIt](https://typeitjs.com/)...
{{< /typeit >}}

#### code

{{< admonition type=bug title="Bug" open=true >}}
这块目前发现是有 bug 的，不会换行，所以暂时不可用。
{{< /admonition >}}

{{< typeit code=go >}}
import "fmt"

func main() {
    fmt.Println("Hello, world")
}
{{< /typeit >}}

#### graph

{{< typeit group=paragraph >}}
**First** this paragraph begins
{{< /typeit >}}

{{< typeit group=paragraph >}}
**Then** this paragraph begins
{{< /typeit >}}
