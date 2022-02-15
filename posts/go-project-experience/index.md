# Go 项目开发和维护经验之谈


> 我想将自己的开发项目的经历以及过程中总结的经验或者一些小技巧整理出来，供自己和看到这篇文章的同学一个参考。内容包括但不限于，项目目录结构，模块拆分，单元测试，`e2e` 测试，`git` 的使用技巧，`GitHub` 的 `actionflow` 的使用技巧等。

<!--more-->

## 1. 前言

做 go 开发有几年的时间了，从最开始的只会写一些简单的代码到现在除了日常编码外会考虑一个项目的前前后后(自认为考虑的比较全)，代码管理，项目结构以及相关的工具搭配使用，
走了很多的弯路，做了很多的重复工作，到目前为止积累了一些经验。想通过这篇文章输出一个总结，方便自己以及看到这篇文章的同学们之后在做新项目的时候有一定的启发。

{{< admonition type=note title="温馨提示" open=true >}}
这篇文章可能存在一定的漏洞，如发现任何您认为不对的地方，希望能给我一个留言。
{{< /admonition >}}

## 2. 项目管理

**项目管理** 这个模块我想分享一些，在开发过程中需要注意的或者值得学习的知识点，从而提升开发效率减少一些出错的概率，同时提高对项目的整体的理解。

### 2.1. 目录结构

目录结构在一些语言会有很严格的要求，但是如果你看过的 go 项目比较多你会发现，大家分目录各有各的好处各有各的理由。所以这里并没有对错，我分享几个高分的开源项目以及自己在做一些 web 项目的时候经常用的目录结构，仁者见仁智者见智吧。

#### 2.1.1. pkg 式目录

这类分目录在开源项目内十分常见，尤其是 k8s 以及相关组件的项目结构都是这类，下面看一下大概的目录结构。

以 [KEDA](https://keda.sh) 为例：

> 其中一些目录为了尽量展示常见的目录手动补上的，实际项目中不一定存在。

```shell
➜ tree -L 2
.
├── BUILD.md
├── CHANGELOG.md
├── CONTRIBUTING.md
├── CREATE-NEW-SCALER.md
├── LICENSE
├── Makefile
├── PROJECT
├── README.md
├── RELEASE-PROCESS.MD
├── SECURITY.md
├── api/ ## 公用的 proto api 或 全局结构定义，如 k8s 项目里 api 目录里放入所有资源对象的定义
├── build/  ## 构建相关的脚本(Dockerfile)
├── config/ ## 配置文件
├── cmd/ ## 程序入口
│   ├── controller ## 不同目录实现不同的功能
│   └── admin
├── docs/ ## 生成的文档
├── go.mod
├── go.sum
├── hack/ ## 代码生成相关工具和脚本
├── pkg/ ## 该项目的功能代码
│   ├── eventreason
│   ├── generated
│   ├── metrics
│   ├── mock
│   ├── provider
│   ├── scalers
│   ├── scaling
│   └── util
├── tests/ ## 测试数据或测试工具（并非测试代码在这里）
├── tools/ ## 其他工具，如检查代码风格 统计代码量等
└── third_party/ ## 第三方的protobuf 文件或无法通过 go mod 拉取的代码等
```

最大的特点是，所有的项目功能相关的代码都在 `pkg` 目录下根据功能拆分。`pkg` 之外的目录会放测试，文档，构建，发布，配置等内容。

其中 `cmd` 为程序的入口，根据功能会拆子目录，每个子目录下会有一个 `main` 文件，启动服务。

这个目录结构的项目一般都是体量比较大，测试构建发布过程都比较复杂，所以会有大量的脚本或者工具集来自动化这些复杂的过程。如果代码量比较少或者没有过多的依赖，则这种目录结构就体现不出优势。

#### 2.1.2. 按功能分目录

这种类型的目录结构，在各种框架类型的项目中十分常见，如 `go-micro`, `kratos` 等。

以 [go-micro](https://github.com/yusank/go-micro) 为例：

```shell
➜ tree -L 1
.
├── LICENSE
├── README.md
├── api/ ## 接口定义
├── auth/ ## 认证相关
├── broker/ ## MQ 的 broker
├── client/ ## http/rpc client
├── cmd/ ## 项目相关工具 xxx-generator 等 或启动参数的处理
├── codec/ ## 编码类型定义 json yaml pb 等
├── config/ ## 配置
├── debug/ ## debug
├── errors/ ## 错误类型定义
├── event.go
├── examples/ ## 各个模块的使用案例
├── go.mod
├── go.sum
├── logger/ ## 日志模块的定义
├── metadata/ ## 元数据
├── micro.go ## 在这里提供对外的接口和方法
├── options.go ## 各类可选参数定义
├── plugins/ ## 插件 一般会在这里放起码模块定义的各种实现（如基于 etcd/nacos/consul 的服务发现等）
├── registry/ ## 服务发现相关定义
├── runtime/ ## 运行时相关代码
├── selector/ ## 服务选择相关
├── server/ ## 服务端相关定义
├── service.go ## 服务启动相关
├── service_test.go
├── store/ ## 存储相关
├── sync/ ## 数据同步相关定义
├── transport/ ## 网络转发相关 http/grpc
└── util/ ## 其他工具类
```

这类目录最大的特点就是分目录分模块比较多且相互不影响。由于是框架，所以这种做法十分重要，别人引用的时候根据自己的需要选择引用其中的一部分目录。并且大部分目录都是定义接口 `Interface`, 并且在自己框架内都只会用接口，从而做到使用者可以自己实现并轻松替换调任意模块。作为一个框架的目录结构以及每个目录都定义接口的方式，可以说是非常的高明。这个项目可以说是对我的益处非常多，对于一个 1-3 年的程序员非常有必要好好研究一下这个项目。

#### 2.1.3. 裸跑型

以 `gin` 为例，虽然也是一个框架，但是功能集中在根目录，大部分的能力都是 `gin.XXX` 的方式调用，所以这类项目基本不分目录，仅有一些测试和构建相关的几个目录，一般这么用的少之又少。当然你的项目很小，仅提供单个功能的时候不分目录也罢。

#### 2.1.4. web 项目

web 项目我之前接触的比较多，参加了无数个大大小小的 web 项目，经过无数次的折腾和吸取他人经验，有了比较统一的目录结构，希望能对在这方面有需求的同学有帮助。

```shell
➜ tree
.
├── Makefile ## 聚合各类常用命令
├── app ## 程序入口
│   ├── admin ## admin 端的入口（包含服务初始化，启动）
│   └── server ## server 端（包含服务初始化 服务注册发现 监控等）如果使用任何框架，也在这里进行初始
├── broker ## MQ 的注册和消费
├── cmd ## 常用工具二进制文件，代码生成 文档生成等
├── build ## 构建相关脚本
├── config ## 配置的定义和初始化
├── dao ## DAO 层，根据模块拆分，实现数据的增删改查
│   ├── order
│   └── user
├── docs ## 文档生成目录
├── dto ## 传输层数据定义
├── middleware ## 中间件
├── router ## router 为路由定义，这块目录结构比较深 但是我认为是有必要的 每一层占据路由上的一个位置
│   ├── admin ## 第一层拆分开 admin 和 server 因为该项目最终构建两个程序 分别通过管理端和服务端内容
│   │   ├── register.go ## 注册路由
│   │   ├── v1 ## 一定要加版本号，在发生重大修改时提升版本号 不要直接改掉原有的路由（除非有安全隐患）
│   │   │   ├── order ## 根据模块拆目录
│   │   │   │   ├── manage ## 如果模块包含内容比较多 可以拆子目录
│   │   │   │   │   └── manage.go ## 子目录下的路由 handler，可以包含多个 handler
│   │   │   │   └── statistic
│   │   │   │       └── statistic.go ## 这一层的handler 的路由应该 /admin/v1/order/statistic/xxx
│   │   │   ├── user ## 模块拆分
│   │   │   │   └── user.go ## 如果包含内容不多可以直接放 handler 文件 /admin/v1/user/xxx
│   │   │   └── v1.go ## 注册 v1 版本路由 同时注册这一层的 middleware
│   │   └── v2 ## 与 v1 类似，服务重构或与原接口发生冲突 则升级版本
│   │       ├── order
│   │       ├── share
│   │       ├── user
│   │       └── v2.go
│   └── server ## 服务端的路由注册 整体与 admin 端一致
│       ├── register.go
│       ├── v1
│       │   ├── user
│       │   │   ├── action.go ## /server/v1/user/xxx
│       │   │   └── manage
│       │   │       └── manage.go ## /server/v1/user/manage/xxx
│       │   └── v1.go
│       └── v2
│           ├── order
│           ├── share
│           ├── user
│           └── v2.go
├── service ## service 内包含业务逻辑 衔接上层请求和下层数据的增删改查
│   ├── order ## 按功能拆分目录
│   │   ├── order_service.go ## 不同 dao 层方法的组合 甚至可以通过上下文传 session 的方式 支持不同dao 层方式之间的事务
│   │   └── order_statistic_service.go
│   └── user
│       └── user_service.go
├── tests ## 测试相关工具和脚本
├── logger ## 日志模块
└── thrid_party ## 第三方的 protobuf 一般放这儿
```

整体思路是从上到下的一个结构，一个请求的处理过程为 `router` -> `service` -> `dao`。其中 `middleware` 会出现在 handler 的前后，而 `broker` 出现 `service` 层。对于一个承接业务的服务，这个目录结构不算出色不算很完善，但是实用性上来说还是可以的，功能和业务模块拆分的比较明确，在各个目录的的 `logger` 添加目录和功能，大部分问题可以快速定位。

至于为什么会同时有 `admin` 和 `server` 端，是因为公用代码和数据结构，大部分线上服务是需要背后一套管理端的，如果重新起一个新的项目，那肯定会因为数据结构或者代码逻辑的不及时同时出现问题，这种放在一套代码内编译出两个程序是保守且比较可靠的方式。

`router` 部分，如果你的接口比较少的情况下，体会不出来优势。但是如果接口和模块比较多的情况下这种结构是很明智的选择:

- 每个模块几乎都有子模块（比如订单逻辑分 订单的统计，管理，追踪等）且接口比较多，那我可以拆子目录来分别管理和实现
- 不同模块有不同的中间件（用户需要校验登录状态，订单需要验证 id，管理端需鉴权），那可以在不同层级添加对应的中间件

> 当然这一切都是我个人的一些经验总结，不一定适合你，但是找到一个比较合理且适合自己的才是最重要的，可以互相借鉴嘛！

### 2.2. 模块拆分

这个就没什么可说的，单独提出来是为了提醒自己和各位，能拆分尽量拆分，不要一个文件上千行代码，一个方法几百行代码，别人看的时候真的很痛苦。

#### 2.2.1. 拆分方法

这个比较好拆，唯一的原则就是`一个方法只做一件事儿`。这个一件事儿可大可小，这是基于当前这个方法所在的层级而定。
如果处于底层操作数据库的层级，那你的方法应该只进行一个数据库操作（不管增删改查），各种组合或者事务应该上层去做。
如果你在业务逻辑层，那你的方法应该只处理一个简单的业务。比如需要下单后发送给用户一个邮件，那你应该拆开下单和发送邮件的方法，不要揉在一起，让上层去组合处理，因为你很有可能添加短信通知/公众号处理。如果揉在一起，需要加新的通知方式的时候你还得去修改完全没有发生变化 `OrderAndSendMessage` 这个方法（随便起了个名字），很有可能会影响到 `Order` 的过程。

总而言之，一个方法只做一件事儿，不要让一个不相干的修改影响到你的逻辑。

#### 2.2.2. 拆分模块

这块的话，我觉得重点是逻辑不要掺杂在一起，不同的逻辑尽量抽象出来。dao 层就做数据相关的（MySQL，Redis）不要掺杂逻辑，service 就做业务逻辑的组合，不要在 service 层直接操作底层组件。总结起来就是不要越界，上下不要越级（service -> dao），左右不要越界（用户相关逻辑不要掺杂订单的逻辑，即便是用户信息内需要包含用户的订单总金额，也要在订单模块实现查询方法去调而不是自己去实现，否则以后拆分很痛苦）。我觉得不同的功能之间相互认为是个微服务，不要有底层的依赖，不要认为代码在一个项目内就随便调用，业务升级业务拆分的时候真的非常痛苦（血的教训）。

### 2.3. 记录任务

这块的话，我觉得是一个工具推荐了算是。不管是个人开发或者团队开发，有个任务记录和里程碑是很重要的一点。不管是 GitHub 还是 Gitlab 都有 `issue` 和 `milestone` 的功能，对于一个开发者来说个人觉得非常的好用。

`issue` 你可以记录你要实现的功能、你现在出现的问题、QA 同学给你提的 bug，你每解决一个问题，每实现一个新功能在 git commit 上带上 issue 号就可以关联上。不管是之后定位问题还是查看某个功能的相关的提交都非常清晰，收益很多。

`milestone` 也是非常好用的功能，针对你的一个大功能或者一个新的版本创建一个 milestone 并加上截止日志，之后所有跟这个版本相关的 issue 都可以挂上这个里程碑，当你一个个完成的相关 issue 后，里程碑的完成度逐渐上升，记录了你的开发进度，同时提醒/监督自己。

不管你做的项目是大是小，都应该有个开发计划并在开发前做好准备，不要盲目上手，着急上手只会让你越做越累，而且做不好。都没有计划和开发过程的记录，怎么证明项目的质量，后期怎么维护，出现问题怎么定位。

## 3. 测试

到这里就开始聊代码相关的了。测试是考验你代码的质量和功能的一把好刀，你应该习惯并熟悉写测试代码，并且尽可能包含你代码的所有部分，确保你的项目整体都是经得起推敲的。

我常用的代码测试有以下三种：

- 单元测试 - 测试你的方法在功能上没有问题
- e2e 测试 - end to end 你的一个完整的功能没有问题，比如测试某个接口是否返回预期结果
- 压测 - 测试你的某个方法或者整个系统是否存在性能问题

压测可以在发布新的版本或分支合并的时候跑一下 通过基准线即可。单元测试和e2e 测试应该在每次提交的时候本地或者远端跑一次，确保任意一次的提交都是可用的。

### 3.1. 单元测试

单元测试作为最基础的测试方法，应该在你的项目内尽可能覆盖大部分的方法，但是需要注意以下几点

- 任意一个单元测试应该都是独立，不能有依赖
- 任意一个单元测试执行前后不应该对数据有影响，如果这个单元测试需要修改数据库数据或文件，应该在测试结束后恢复发生变化的数据
- 不应该长时间阻塞，不应该有 `select{}` 或死循环，等待手动停止的情况

最简单的单元测试示例：

```go
func Test_ParseInt(t *testing.T) {
    var (
        input = "12"
        output int64 =12
    )
    v, err := strconv.ParseInt("12", 10, 64)
    if err != nil {
        t.Error(err)
        return
    }

    if v != output {
        t.Errorf("want:%v, got:%v\n", output, v)
        return
    }

    t.Log("ok")
}
```

这是一个校验 `strconv.ParseInt` 方法的单元测试，可以直接运行。从上面的代码来说，有些啰嗦，而且错误信息的输出也得自己写，这里推荐比较流行的测试框架
`github.com/stretchr/testify/assert`,该库对错误信息的格式化和遍历对比都毕竟成熟，而且提供很多方法，来简化你的测试代码量，下面看一下改版：

```go

func Test_ParseInt(t *testing.T) {
    v, err := strconv.ParseInt("12", 10, 64)
    // 如果有错误 这里会返回 false
    if !assert.NoError(t, err) {
        return
    }

    // Equal 方法支持对比所有的类型，不需要根据类型判断
    // 并且报错时，日志信息也非常丰富
    assert.Equal(t, int64(12), v)
}
```

这里我不会细讲这个库，如果看过比较主流的开源库，有很多库都使用这个测试框架，非常值得学习和使用。

一般来说，测试一个方法不止一个情况，大部分情况下会有多个各种输入，多方面来确保方法的可用性，这种情况下，可以采用下面的写法：

```go
func Test_zSkipList_rank(t *testing.T) {
    type args struct {
        score float64
        value string
    }
    tests := []struct {
        name string
        args args
        want int
    }{
        {
            name: "c",
            args: args{
                score: 1,
                value: "clang",
            },
            want: 1,
        },
        {
            name: "java",
            args: args{
                score: 2,
                value: "java",
            },
            want: 2,
        },
        {
            name: "w",
            args: args{
                score: 5,
                value: "world",
            },
            want: 3,
        },
        {
            name: "js",
            args: args{
                score: 8,
                value: "javascript",
            },
            want: 4,
        },
        {
            name: "h",
            args: args{
                score: 10,
                value: "hello",
            },
            want: 5,
        },
        {
            name: "go",
            args: args{
                score: 12,
                value: "golang",
            },
            want: 6,
        },
    }
    zs := prepareZSetForTest()
    zs.zsl.print()
    for _, tt := range tests {
        t.Run(tt.name, func(t *testing.T) {
            got := zs.zsl.rank(tt.args.score, tt.args.value)
            assert.Equal(t, tt.want, int(got))
        })
    }
}
```

这里我直接从我的现成的代码里复制出来一个测试案例，这种写法特点是定义好输入输出的结构，然后批量赋值，最终一个个执行。
如果测试过程中发现，输入的数据还不够，可以随时增加n个例子，其他部分不用动，*重要的是，可以在 GoLand idea 中执行任意一个测试数据，更加方便调试*。

### 3.2. e2e 测试

e2e 测试，相对于单元测试来说更加系统性测试，针对某个模块的整体功能的校验。没有一个必要的代码框架，代码量也会更多一些。比如测试用户注册流程的测试，那启动时需要准备该功能需要的环境（启动或者链接测试数据库，创建表或者创建测试数据等），调用对用的方法后，对结果进行校验，校验成功后需要删除测试用的数据和环境。

对于web项目，可能针对接口也需要写测试，这个时候就需要启动当前的服务，准备环境，进行接口调用，完成后恢复涉及到的变更。

e2e 测试更多关注当前程序的整体的功能，可以确保任意的代码改动没有对当前程序的整体能力（或核心功能）没有带来负面影响，所以e2e测试也是非常重要的。

### 3.3. 压测

压测(Benchmark) 不同于上述两个测试，关注的是函数或程序整体的性能情况。

#### 3.3.1. 函数的压测

这块可以通过 go 的原生能力进行测试，写压测方法也很简单，如下：

```go
/*
goos: darwin
goarch: amd64
pkg: github.com/yusank/godis/util
cpu: Intel(R) Core(TM) i7-9750H CPU @ 2.60GHz
BenchmarkStringConcat
BenchmarkStringConcat-12    14886952        70.91 ns/op
PASS
*/
func BenchmarkStringConcat(b *testing.B) {
    var slice = []string{
        "$",
        "10",
        "\r\n",
        "12345123456",
        "\r\n",
    }

    for i := 0; i < b.N; i++ {
        StringConcat(16, slice...)
    }
}
```

这是go 提供的压测函数的写法，执行后，输出上面代码中的注释部分，可以看到当前机器的信息和执行次数以及每次执行时需要的时间。通过这种方法，可以针对我们的一些高频率调用的方法进行压测，确保这些方法不是性能的瓶颈，并且遇到瓶颈或者优化时，通过压测的方式，对比优化前后的差异。

#### 3.3.2. 整体压测

在GitHub上有很多项目，尤其是对性能要求高的项目都会有一个性能对比的图，对自己项目进行一个压测，对程序整体的吞吐进行全方面的压测，从而体现出该程序的高性能和稳定性。
这个其实对于tcp或者web服务来说非常好做，而且有很多现成的工具，可进行压测并输出结果。

以 `wrk` 为例，支持指定客户端数，并发数，请求次数等，甚至支持脚本执行，定制化压测，这里贴出[链接](https://www.jianshu.com/p/ac185e01cc30),希望看到这里的同学，花几分钟去了解一下如何使用。

## 4. 代码规范

> lint 等工具

代码规范这块我之前写过专门的文章([点击传送](../go-standard/))。但是实际开发过程中不能保证所有人（包括自己）都能完成的遵循代码规范的，所以需要一个自动化工具来校验/限制不规范的代码。

**[golangci-lint](https://github.com/golangci/golangci-lint)** 是一个绝大多数 go 开发者都熟悉的一个工具，可以校验任何 go 项目的代码规范，能够指出不规范的部分，并且支持指定开启/关闭部分类型的校验。下面从一个简单的例子说明如何使用。

这是我在某个 main 方法里加了一些不规范的语法：

```go
var abc string

func main() {        
    var t = 0 == 0
    if t == true {
        // do
    }
    core.Service(":8081")
}
```

执行 `golangci-lint` 看一下结果：

```shell
➜ golangci-lint run ./... -v
INFO [config_reader] Config search paths: [./ /Users/shan.yu/workspace/yusank/klyn-examp /Users/shan.yu/workspace/yusank /Users/shan.yu/workspace /Users/shan.yu /Users /] 
INFO [lintersdb] Active 10 linters: [deadcode errcheck gosimple govet ineffassign staticcheck structcheck typecheck unused varcheck] 
INFO [loader] Go packages loading at mode 575 (deps|types_sizes|compiled_files|exports_file|files|imports|name) took 429.72546ms 
INFO [runner/filename_unadjuster] Pre-built 0 adjustments in 3.196848ms 
INFO [linters context/goanalysis] analyzers took 0s with no stages 
INFO [runner] Issues before processing: 7, after processing: 4 
INFO [runner] Processors filtering stat (out/in): skip_dirs: 7/7, exclude: 7/7, uniq_by_line: 4/7, max_per_file_from_linter: 4/4, cgo: 7/7, filename_unadjuster: 7/7, source_code: 4/4, severity-rules: 4/4, skip_files: 7/7, max_from_linter: 4/4, nolint: 7/7, diff: 4/4, max_same_issues: 4/4, path_shortener: 4/4, path_prefixer: 4/4, autogenerated_exclude: 7/7, exclude-rules: 7/7, sort_results: 4/4, path_prettifier: 7/7, identifier_marker: 7/7 
INFO [runner] processing took 1.708654ms with stages: path_prettifier: 661.569µs, nolint: 614.546µs, exclude-rules: 185.12µs, identifier_marker: 110.421µs, source_code: 48.813µs, autogenerated_exclude: 48.499µs, skip_dirs: 16.894µs, cgo: 6.783µs, max_same_issues: 3.182µs, uniq_by_line: 2.679µs, filename_unadjuster: 2.498µs, path_shortener: 2.444µs, max_per_file_from_linter: 2.015µs, max_from_linter: 1.59µs, sort_results: 348ns, exclude: 291ns, diff: 268ns, skip_files: 260ns, severity-rules: 244ns, path_prefixer: 190ns 
INFO [runner] linters took 85.727899ms with stages: goanalysis_metalinter: 83.919309ms 
main.go:81:5: `abc` is unused (deadcode)
var abc string
    ^
main.go:78:14: Error return value of `core.Service` is not checked (errcheck)
        core.Service(":8081")
                    ^
main.go:75:5: S1002: should omit comparison to bool constant, can be simplified to `t` (gosimple)
        if t == true {
           ^
main.go:74:10: SA4000: identical expressions on the left and right side of the '==' operator (staticcheck)
        var t = 0 == 0
                ^
INFO File cache stats: 1 entries of total size 4.3KiB 
INFO Memory: 7 samples, avg is 72.4MB, max is 73.1MB 
INFO Execution took 594.401598ms
```

可以看到，一开始会打印相关的一些信息后，开始一个个打印遍历到的不规范的语法，并且指出问题所在的位置。虽然说现在的代码编辑器会对代码进行扫描也会指出不规范的语法，但是不会影响我们的日常开发和提交，而 `golangci-lint` 比编辑器更全面且可以通过 `CICD` 或者命令行的方式一次性遍历整个项目代码，所有的不规范可以一次性列出来。

如果去看一些 go 语言的开源项目，你会发现很多项目的 GitHub action 里会配置 lint 的工作流，如果 lint 过不去拒绝合并到正式分支的。

## 5. git

上面提到了一些代码规范/单元测试和 GitHub action 等概念，从这里开始讲一下如何将这些概念串联起来，让更多的工作变成自动化。

git 作为版本管理工具，除了版本管理外其他相关方面的能力也是非常的强。本地的git 可以分支开发，打 tag，git hook 等。远端（GitHub/Gitlab）可以有 issue，milestone，PR，MR，CICD 等能力。

### 5.1. git hook

[git hook](https://git-scm.com/book/zh/v2/%E8%87%AA%E5%AE%9A%E4%B9%89-Git-Git-%E9%92%A9%E5%AD%90)是git 提供的钩子方法，可以配置很多事件的回调，让我们的一些手动工作配置到对应的 hook 上自动执行。我们打开任意的一个 git 项目进行下面的命令查看支持的 hooks：

```shell
➜  ls .git/hooks 
applypatch-msg.sample     post-update.sample        pre-merge-commit.sample   pre-receive.sample        update.sample
commit-msg.sample         pre-applypatch.sample     pre-push.sample           prepare-commit-msg.sample
fsmonitor-watchman.sample pre-commit.sample         pre-rebase.sample         push-to-checkout.sample
```

可以看到很多 `pre` 或 `post` 开头的文件，表示对应的事件前或后执行对应的脚本。如果需要启动任意一个钩子，只需要编辑对应的文件然后把后缀 `.sample` 去掉即可。

下面是我在自己某个项目内启用了 `pre-commit` hook 的例子：

```shell
#!/bin/sh
#
# An example hook script to verify what is about to be committed.
# Called by "git commit" with no arguments.  The hook should
# exit with non-zero status after issuing an appropriate message if
# it wants to stop the commit.
#
# To enable this hook, rename this file to "pre-commit".

# 执行 make test 命令
if ! make test; then
    echo "Go test failed, please check your code."
    exit 1
fi
# 执行 make lint 命令
if ! make lint; then
    echo "Go lint failed, please check your code style."
    exit 1
fi
```

启用后我的任何一次 commit 都会先进行一次全局的测试和 lint 校验通过后，才会 commit 成功否则本次 commit 失败。这种做法对于个人或少数几个人开发者来说，实用性蛮高的，一种自我约束并且保证不会提交一些垃圾代码。最重要的是不需要自己手动去检查代码质量和规范，不通过测试和规范的提交都不会产生一次 commitID。

### 5.2. github / gitlab

除了上述本地的一些 git hook 的限制外，GitHub 和 Gitlab 提供一套完整的 CICD 的能力，用户可以配置针对提交，MR，PR 等各种事件运行特定的脚本，在远端服务器进行校验，构建，部署等能力。

CICD 对于现在的开发者来说应该很熟悉，对于热衷于工作自动化的程序员来说，CICD 可以说是非常好用的一个手段，我个人的大部分项目都会配置远端的代码测试代码规范校验的脚本。包括本博客也在 GitHub 上自动部署的,我只管提交剩余的工作都是自动化，感兴趣可以[点击查看](https://github.com/yusank/yusank.github.io/actions)。

## 6. 构建与运行

项目的开发和调试过程我们免不了无数次的构建、编译、运行等过程，并且会依赖很多变量。这个时候我们应该有一个比较完善的解决方案来减少我们的敲各种命令的次数提升效率。

### 6.1. makefile

`make`命令是GNU的工程化编译工具，用于编译众多相互关联的源代码文件，以实现工程化的管理，提高开发效率。我们应该对 make 有一定的了解，并学会使用它，从而提升效率。

> [点击这里](https://www.ruanyifeng.com/blog/2015/02/make.html)学习/复习相关知识，本篇文章不再讲述相关内容。

下面以当前博客项目的 Makefile 为例：

```makefile
TAG = latest
help:  ## Display this help
    @awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make \033[36m<target>\033[0m\n"} /^[0-9A-Za-z_-]+:.*?##/ { printf "  \033[36m%-45s\033[0m %s\n", $$1, $$2 } /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } ' $(MAKEFILE_LIST)
.PHONY: docker-build
docker-build: ## build docker image
    ## change config
    cat config.toml > config.backup.toml
    rm -f config.toml
    mv config.docker.toml config.toml
    
    docker build -t yusank/hugo_blog:$(TAG) .
    # recover
    mv config.toml config.docker.toml
    cat config.backup.toml > config.toml
    rm -f config.backup.toml
.PHONY: docker-run
docker-run: ## run latest docker image localy
    docker rm -f blog
    docker run -d -p 8088:80 --name blog yusank/hugo_blog:$(TAG)

.PHONY: docker-push
docker-push: docker-build ## bulid and push newest docker image
    docker push docker.io/yusank/hugo_blog:$(TAG)

.PHONY: docker-release
docker-release: docker-push ## relaese newest version of image to aliyun
    ssh aliyun_d1 "./restart.sh latest"
```

可以看到定义了几个命令，并且可以发现有些命令是有依赖关系的。当执行 `make docker-release` 时，会先进行 `docker-push`的逻辑，而 `docker-push` 又有其依赖，以此类推。如果没有定义这个 `makefile`, 那为了一个 release 操作，我需要你手动敲很多命令且还得确保顺序。

这个只是一个十几行的 `make` 命令的示例，如果你的构建/编译的依赖更多（环境变量，上下文等），那更得写一个 `Makefile` 来减少人工操作次数。况且一次测好后，之后就避免人工操作失误的情况。

`help` 命令会打印当前 `Makefile` 支持的所有子命令，效果如下：

```shell
➜ make help      
Usage:
  make <target>
  help                                           Display this help
  docker-build                                   build docker image
  docker-run                                     run latest docker image localy
  docker-push                                    bulid and push newest docker image
  docker-release                                 relaese newest version of image to aliyun
```

写好一个 Makefile 可以说是一个一劳永逸，对自己和他人都有百益无一害的事儿了。你可以有个模板，有新的项目可以直接 copy 进去修改即可用的那种。

### 6.2. dockerfile

`dockerfile` 的用处很简单，就是为了构建 docker 镜像。现在大部分人的项目都在容器内运行了，二进制裸跑在物理机或虚拟机的情况很少，所以 dockerfile 也是需要我们在项目中加好，方便自动化构建镜像。

还是以本博客系统的镜像为例（引用本博客系统的文件不是因为夸自己写的好，纯属因为方便）：

```dockerfile
ARG HUGO_DIR=.
ARG HUGO_ENV_ARG=production
FROM klakegg/hugo:0.90.1-alpine-onbuild AS hugo

FROM nginx
COPY nginx.conf /etc/nginx/conf.d/nginx.conf
COPY yusank.space.pem /etc/nginx/conf.d/yusank.space.pem
COPY yusank.space.key /etc/nginx/conf.d/yusank.space.key
COPY --from=hugo /target /usr/share/nginx/html
EXPOSE 80
EXPOSE 443
```

典型的 go 项目的dockerfile：

```dockerfile
FROM golang:1.17-alpine as builder

WORKDIR /app/godis
COPY . .

# args
ARG build_tags
RUN CGO_ENABLED=0 go build -tags "${build_tags}" -o godis cmd/server/main.go

FROM scratch
WORKDIR /app/godis
COPY --from=builder /app/godis .

EXPOSE 7379
CMD ["./godis"]
```

## 7. 总结

本篇文章主要讲述了我个人在开个项目过程积累的一些经验，不一定是最好的而且肯定露了很多地方，若有不正确的地方请指出。想通过这篇文章首先给自己一个总结，其次想给对项目的管理（开发方向）方面有疑惑有疑虑的同学一些启发。

本篇文章的主要内容：

- 介绍常见的项目目录结构，请按自己的实际情况选择
- 如何拆分模块
- 应该重视代码测试项目测试相关
- 介绍 git,github,gitlab 的一些好用的特性，希望能带来效率的提升
- 介绍 makefile,dockerfile 帮助提升开发效率

## 8. 链接🔗

- [keda](https://keda.sh)
- [golangci-lint](https://github.com/golangci/golangci-lint)
- [git hook](https://git-scm.com/book/zh/v2/%E8%87%AA%E5%AE%9A%E4%B9%89-Git-Git-%E9%92%A9%E5%AD%90)
- [Makefile](https://www.ruanyifeng.com/blog/2015/02/make.html)

