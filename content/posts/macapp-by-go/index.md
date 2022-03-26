---
title: "Golang 开发 mac app"
subtitle: "记录如何用 go 语言开发 mac app 的过程"
date: 2022-03-23T10:10:00+08:00
lastmod: 2022-03-23T10:10:00+08:00
categories: ["其他"]
tags: ["mac-app","go"]
---

> 最近意外发现一个文章，说是可以通过 go 语言控制 `object-c`，从而实现用 go 语言开发出简单的 `mac app`。我就是试着尝试一下的想法去把文章里说的 repo 下载下来本地运行了一下里面的示例，居然**运行成功**了。很意外也很惊喜，作为一个后端开发者，用后端语言写出简单的客户端页面简直就是开启了一个新时代的大门一样，以后可以制作一些简单的 mac app，满足自己的需求了（久坐提醒、定时器之类的，一时半会儿想不到太多）。本篇文章讲述如何开发、部署以及需要注意的问题。

<!--more-->

## 1. 背景

最近在帮一个朋友写一些程序把一些繁琐的工作做成自动化，帮他节省时间和精力。但是作为一个后端程序员，做出来的东西对外来说无非就是 http 接口
或者一个可执行的二进制文件。如果 http 接口还好，找个自己的服务器部署上去，写个简单的页面（我能力仅限于简单的页面）交给他人使用即可。但是有些需求可能在对方的电脑运行更方便（比如处理本地的一些文件，或者涉及到敏感信息等），这个时候就麻烦了，我给对方一个二进制文件让他用，对方也是一脸懵逼，运行失败了，报错了或者其他情况对方都不知道发生了什么，就**很不友好**。

所以我迫切希望一个可以通过后端语言生成一些简单页面化的 app（一开始相关 terminal gui，但还是太 geek）。试着搜了一下 go 语言开发 mac app，居然搜到了一个对我帮助很大的文章（[原文连接](https://polarisxu.studygolang.com/posts/go/translation/use-mac-apis-and-build-mac-apps-with-go/)）。看到里面提到的第二个例子，简直就是我想要的，直接在 mac 的 status bar 多一个入口，点击下来多个菜单，我可以把我开发的能力放到这里，用户一点就触发，就觉得很 nice。

官方例子如下：

{{< image src="https://camo.githubusercontent.com/707db8e6d47c31ed90f0a65aeea1b805c718b1c18a2cd61b94e1ebb932b091af/68747470733a2f2f7062732e7477696d672e636f6d2f6d656469612f4571616f4f324d584941454a4e4b323f666f726d61743d6a7067266e616d653d6c61726765" caption="hello world" width="800" >}}

{{< image src="https://camo.githubusercontent.com/dd24a8e100964d5f9241e6be5a21cd9469bbc5fbbf26af691ea5f0f71dbb1d6d/68747470733a2f2f7062732e7477696d672e636f6d2f6d656469612f45716859446d6c573841454243362d3f666f726d61743d6a7067266e616d653d6c61726765" caption="always on top webview" width="800" >}}

这是我开发后的效果：

{{< image src="statusbar.png" caption="status bar" width="500" >}}

其中状态栏显示的文字，可以在运行时实时更新，这样可以在状态栏就可以看到当前运行情况和进度了。

项目叫 [MacDriver](https://github.com/progrium/macdriver)，是通过 go 语言调用 mac api的框架。

{{< admonition type=quote title="MacDriver" open=true >}}
*MacDriver is a toolkit for working with Apple/Mac APIs and frameworks in Go.*
{{< /admonition >}}

## 2. 开发

> 我本人对 Mac APP 的开发以及 Mac 的 API 几乎完全不懂，所以本项目对这现有的 example 慢慢啃下来然后实现了自己的需求。
>
>而 MacDriver 项目提供的能力和能做出来的东西远比我在这里实现的复杂和高级，如果有同学对这个十分感兴趣可以先看看项目的源码，大概了解一下已有的能力。

我需求比较简单，就是拉取最近未读邮件然后对其中需要处理的（自己指定了一些匹配规则）进行后台处理并回复一条自动邮件。

因为我的处理需求和匹配规则跟邮件内容有关，所以没办法使用邮箱提供的收信规则简单处理，所以自己动手写了一个程序。

### 2.1. 初始化 APP

```go
func main() {
    runtime.LockOSThread()

    cocoa.TerminateAfterWindowsClose = false
    app := cocoa.NSApp_WithDidLaunch(func(n objc.Object) {
        // all code in here
    }
    app.Run()
}
```

所有的逻辑在 `cocoa.NSApp_WithDidLaunch` 传参的函数里。

### 2.2. 初始化 status bar

这里是定义程序启动时，默认是展示文字。

```go
app := cocoa.NSApp_WithDidLaunch(func(n objc.Object) {
    obj := cocoa.NSStatusBar_System().StatusItemWithLength(cocoa.NSVariableStatusItemLength)
    obj.Retain()
    obj.Button().SetTitle("📧  准备就绪") // 初始化 status bar 的展示文本
    // ...省略 code
    }
```

### 2.3. 运行时动态更新 status bar

运行过程中我希望能实时更新处理的进度以及状态。

```go
app := cocoa.NSApp_WithDidLaunch(func(n objc.Object) {
    obj := cocoa.NSStatusBar_System().StatusItemWithLength(cocoa.NSVariableStatusItemLength)
    obj.Retain()
    obj.Button().SetTitle("📧  准备就绪")

    var (
        eventChan = make(chan string, 1)
        indexChan = make(chan int, count)
    )
    go func() {
        for {
            select {
            case <-time.After(1 * time.Second):
            case e := <-eventChan:
                // 这里我更新各类事件的实时情况和状态
                core.Dispatch(func() {
                    obj.Button().SetTitle(fmt.Sprintf("🏷 %s", e))

                })
            case i := <-indexChan:
                // 这里我实时更新处理到第几封邮件
                core.Dispatch(func() {
                    obj.Button().SetTitle(fmt.Sprintf("✴️ 处理邮件中 %d/%d", i, count))

                })
            }
        }
    }()
    // .. 省略 code
```

### 2.4. 添加 menu

上面初始化了展示的 status bar 的文字，现在我们添加 menu 菜单，不同的 menu 处理不同的事件。

```go
app := cocoa.NSApp_WithDidLaunch(func(n objc.Object) {
    // ... 省略code

    // set quit action
    itemQuit := cocoa.NSMenuItem_New()
    itemQuit.SetTitle("退出")
    itemQuit.SetAction(objc.Sel("terminate:"))

    // 设置自定义 menu 和处理方法
    checkAndSetSeen := cocoa.NSMenuItem_New()
    checkAndSetSeen.SetTitle(fmt.Sprintf("处理最新%d封邮件✉️(并且设为已读)", count))
    checkAndSetSeen.SetAction(objc.Sel("checkAndSet:"))
    cocoa.DefaultDelegateClass.AddMethod("checkAndSet:", func(_ objc.Object) {
        // 这里就可以放我们自己的逻辑了
        go func() {
            defer deferFunc(obj)
            log.Println("email start")
            run(indexChan, eventChan, onlyCheckMode|setSeenMode)
        }()
    })

    setAndReply := cocoa.NSMenuItem_New()
    setAndReply.SetTitle(fmt.Sprintf("处理最新%d封邮件✉️(并且设为已读和回复邮件)", count))
    setAndReply.SetAction(objc.Sel("setAndReply:"))
    cocoa.DefaultDelegateClass.AddMethod("setAndReply:", func(_ objc.Object) {
        go func() {
            defer deferFunc(obj)
            log.Println("email start")
            run(indexChan, eventChan, onlyCheckMode|setSeenMode|replyMailMode)
        }()
    })

    // menu 注册进去
    menu := cocoa.NSMenu_New()
    menu.AddItem(checkAndSetSeen)
    menu.AddItem(setAndReply)
    menu.AddItem(itemQuit)
    obj.SetMenu(menu)
}
```

到这里 status bar 的开发就完成了，业务逻辑代码我就不贴了。

## 3. 编译部署

我一开始以为是需要各类的开发者账号或者 xcode 才能将代码运行起来，但是实际上简单的让人我怀疑（因为我知道苹果由于生态封闭 app 的开发就比较复杂）

编译：

```shell
go build main.go
```

运行：

```shell
./main
```

这就 OK 了，完全不需要其他任何操作，非常清爽。

## 4. 总结

本篇讲述内容如下：

- 讲述用 go 开发 mac app 的背景
- 介绍基于 go 语言调用 Mac api 的开源库 MacDriver
- 讲述基于 MacDriver 开发一个简单状态栏 app 的过程
- 讲述如何编译部署开发的 app

## 5.链接🔗

- [MacDriver](https://github.com/progrium/macdriver)
- [Go 终于可以开发原生 Mac APP 了](https://polarisxu.studygolang.com/posts/go/translation/use-mac-apis-and-build-mac-apps-with-go/)
