---
title: "Go 项目开发和维护经验之谈"
date: 2022-01-24T10:50:00+08:00
lastmod: 2022-01-24T11:50:00+08:00
categories: ["项目经验"]
tags: ["go", "开发", "维护"]
draft: true
---

> 我想将自己的开发项目的经历以及过程中总结的经验或者一些小技巧整理出来，供自己和看到这篇文章的同学一个参考。内容包括但不限于，项目目录结构，模块拆分，单元测试，`e2e` 测试，`git` 的使用技巧，`GitHub` 的 `actionflow` 的使用技巧等。

<!--more-->

*先画个饼，假期结束前尽量完成发布。。。*

> 果然是画饼，完全没时间写。

## 前言

> 介绍开发和维护过程中重要的或者方便的几个点 从而引出后面的部分。

做 go 开发有几年的时间了，从最开始的只会写一些简单的代码到现在除了日常编码外会考虑一个项目的前前后后(自认为考虑的比较全)，代码管理，项目结构以及相关的工具搭配使用，
走了很多的弯路，做了很多的重复工作，到目前为止积累了一些经验。想通过这篇文章输出一个总结，方便自己以及看到这篇文章的同学们之后在做新项目的时候有一定的启发。

{{< admonition type=note title="温馨提示" open=true >}}
这篇文章可能存在一定的漏洞，如发现任何您认为不对的地方，希望能给我一个留言。
{{< /admonition >}}

## 项目管理

> 非开发内容，对之后开发有帮助

**项目管理** 这个模块我想分享一些，在开发过程中需要注意的或者值得学习的知识点，从而提升开发效率减少一些出错的概率，同时提高对项目的整体的理解。

### 目录结构

> 这块没有对错 讲如何管理目录结构比较好，可以拿一些线上项目目录作为例子。
目录结构在一些语言会有很严格的要求，但是如果你看过的 go 项目比较多你会发现，大家分目录各有各的好处各有各的理由。所以这里并没有对错，我分享几个高分的开源项目以及自己在做一些 web 项目的时候经常用的目录结构，仁者见仁智者见智吧。

#### pkg 式目录

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

#### 按功能分目录

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

#### 裸跑型

以 `gin` 为例，虽然也是一个框架，但是功能集中在根目录，大部分的能力都是 `gin.XXX` 的方式调用，所以这类项目基本不分目录，仅有一些测试和构建相关的几个目录，一般这么用的少之又少。当然你的项目很小，仅提供单个功能的时候不分目录也罢。

#### web 项目

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

### 模块拆分

> 根据功能或管辖的层面来拆分

这个就没什么可说的，单独提出来是为了提醒自己和各位，能拆分尽量拆分，不要一个文件上千行代码，一个方法几百行代码，别人看的时候真的很痛苦。

#### 拆分方法

这个比较好拆，唯一的原则就是`一个方法只做一件事儿`。这个一件事儿可大可小，这是基于当前这个方法所在的层级而定。
如果处于底层操作数据库的层级，那你的方法应该只进行一个数据库操作（不管增删改查），各种组合或者事务应该上层去做。
如果你在业务逻辑层，那你的方法应该只处理一个简单的业务。比如需要下单后发送给用户一个邮件，那你应该拆开下单和发送邮件的方法，不要揉在一起，让上层去组合处理，因为你很有可能添加短信通知/公众号处理。如果揉在一起，需要加新的通知方式的时候你还得去修改完全没有发生变化 `OrderAndSendMessage` 这个方法（随便起了个名字），很有可能会影响到 `Order` 的过程。

总而言之，一个方法只做一件事儿，不要让一个不相干的修改影响到你的逻辑。

#### 拆分模块

这块的话，我觉得重点是逻辑不要掺杂在一起，不同的逻辑尽量抽象出来。dao 层就做数据相关的（MySQL，Redis）不要掺杂逻辑，service 就做业务逻辑的组合，不要在 service 层直接操作底层组件。总结起来就是不要越界，上下不要越级（service -> dao），左右不要越界（用户相关逻辑不要掺杂订单的逻辑，即便是用户信息内需要包含用户的订单总金额，也要在订单模块实现查询方法去调而不是自己去实现，否则以后拆分很痛苦）。我觉得不同的功能之间相互认为是个微服务，不要有底层的依赖，不要认为代码在一个项目内就随便调用，业务升级业务拆分的时候真的非常痛苦（血的教训）。

### 记录任务

> 擅长使用 issue 功能

这块的话，我觉得是一个工具推荐了算是。不管是个人开发或者团队开发，有个任务记录和里程碑是很重要的一点。不管是 GitHub 还是 Gitlab 都有 `issue` 和 `milestone` 的功能，对于一个开发者来说个人觉得非常的好用。

`issue` 你可以记录你要实现的功能、你现在出现的问题、QA 同学给你提的 bug，你每解决一个问题，每实现一个新功能在 git commit 上带上 issue 号就可以关联上。不管是之后定位问题还是查看某个功能的相关的提交都非常清晰，收益很多。

`milestone` 也是非常好用的功能，针对你的一个大功能或者一个新的版本创建一个 milestone 并加上截止日志，之后所有跟这个版本相关的 issue 都可以挂上这个里程碑，当你一个个完成的相关 issue 后，里程碑的完成度逐渐上升，记录了你的开发进度，同时提醒/监督自己。

不管你做的项目是大是小，都应该有个开发计划并在开发前做好准备，不要盲目上手，着急上手只会让你越做越累，而且做不好。都没有计划和开发过程的记录，怎么证明项目的质量，后期怎么维护，出现问题怎么定位。

## 测试

到这里就开始聊代码相关的了。测试是考验你代码的质量和功能的一把好刀，你应该习惯并熟悉写测试代码，并且尽可能包含你代码的所有部分，确保你的项目整体都是经得起推敲的。

我常用的代码测试有以下三种：

- 单元测试 - 测试你的方法在功能上没有问题
- e2e 测试 - end to end 你的一个完整的功能没有问题，比如测试某个接口是否返回预期结果
- 压测 - 测试你的某个方法或者整个系统是否存在性能问题

压测可以在发布新的版本或分支合并的时候跑一下 通过基准线即可。单元测试和e2e 测试应该在每次提交的时候本地或者远端跑一次，确保任意一次的提交都是可用的。

### 单元测试

### e2e 测试

### 压测

## 代码规范

> lint 等工具

## git

### git hook

> 通过 git hook 进行测试或者 lint

### github / gitlab

> cicd,  GitHub action 等

### 分支管理

## 快捷操作

### makefile

```makefile
MSG=$(msg)
IMAGE ?= yusank/godis
TAG ?= latests
BUILDTAGS=$(build_tags)
help:  ## Display this help
    @awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make \033[36m<target>\033[0m\n"} /^[0-9A-Za-z_-]+:.*?##/ { printf "  \033[36m%-45s\033[0m %s\n", $$1, $$2 } /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } ' $(MAKEFILE_LIST)
.PHONY: server-run
server-run: ## run server as default mode
    CGO_ENABLED=0 go run cmd/server/main.go
.PHONY: build-linux
build-linux: ## build server binary for linux
    CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -o go_build_server cmd/server/main.go
.PHONY: lint
lint: ## run golangci-lint for project
    golangci-lint run ./... -v
.PHONY: test
test: ## run all test cases
    CGO_ENABLED=0 go test -v ./...
.PHONEY: cmt
cmt:## git commit with message
ifeq ($(strip $(MSG)),)
    @echo "must input commit msg"
    exit 1
endif
    git add .
    git commit -m '$(MSG)'
    @echo "msg:$(MSG)"
.PHONEY: gen_cmd
gen_cmd: ## gen redis cmd code
    cd cmd/gen_redis_cmd && go install
    go generate ./...
.PHONEY: clean
clean: ## clean all generated code
    rm -rf redis/*.cmd.go

.PHONEY: docker-build
docker-build: ## build docker image
    docker build --build-arg build_tags=$(BUILDTAGS) -t $(IMAGE):$(TAG) .
```

### dockerfile

> dockerfile

## 文档

### 开发文档

### 测试文档

### 维护文档

### 其他相关

> 代码量统计等
