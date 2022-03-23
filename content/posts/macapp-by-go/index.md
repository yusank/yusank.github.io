---
title: "Golang 开发 mac app"
subtitle: "记录如何用 go 语言开发 mac app 的过程"
date: 2022-03-23T10:10:00+08:00
lastmod: 2022-03-23T10:10:00+08:00
categories: ["其他"]
tags: ["mac-app","go"]
draft: true
---

> 最近意外发现一个文章，说是可以通过 go 语言控制 `object-c`，从而实现用 go 语言开发出简单的 `mac app`。我就是试着尝试一下的想法去把文章里说的 repo 下载下来本地运行了一下里面的示例，居然**运行成功**了。很意外也很惊喜，作为一个后端开发者，用后端语言写出简单的客户端页面简直就是开启了一个新时代的大门一样，以后可以制作一些简单的 mac app，满足自己的需求了（久坐提醒、定时器之类的，一时半会儿想不到太多）。本篇文章讲述如何开发、部署以及需要注意的问题。

<!--more-->

## 1. 背景

最近在帮一个朋友写一些程序把一些繁琐的工作做成自动化，帮他节省时间和精力。但是作为一个后端程序员，做出来的东西对外来说无非就是 http 接口
或者一个可执行的二进制文件。如果 http 接口还好，找个自己的服务器部署上去，写个简单的页面（我能力仅限于简单的页面）交给他人使用即可。但是有些需求可能在对方的电脑运行更方便（比如处理本地的一些文件，或者涉及到敏感信息等），这个时候就麻烦了，我给对方一个二进制文件让他用，对方也是一脸懵逼，运行失败了，报错了或者其他情况对方都不知道发生了什么，就**很不友好**。

所以我迫切希望一个可以通过后端语言生成一些简单页面化的 app（一开始相关 terminal gui，但还是太 geek）。试着搜了一下 go 语言开发 mac app，居然搜到了一个对我帮助很大的文章（[原文连接](https://polarisxu.studygolang.com/posts/go/translation/use-mac-apis-and-build-mac-apps-with-go/)）。看到里面提到的第二个例子，简直就是我想要的，直接在 mac 的 status bar 多一个入口，点击下来多个菜单，我可以把我开发的能力放到这里，用户一点就触发，就觉得很 nice。

这是我开发后的效果：

//todo 放图片

项目叫 [MacDriver](https://github.com/progrium/macdriver)，是通过 go 语言调用 mac api的框架。

{{< admonition type=quote title="MacDriver" open=true >}}
*MacDriver is a toolkit for working with Apple/Mac APIs and frameworks in Go.*
{{< /admonition >}}


## 2. 开发

## 3. 部署

## 4. 遇到的问题

## 5. 总结

## 6.链接🔗
