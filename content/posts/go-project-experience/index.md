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

## 前言

> 介绍开发和维护过程中重要的或者方便的几个点 从而引出后面的部分。

## 项目管理

> 非开发内容，对之后开发有帮助

### 目录结构

> 这块没有对错 讲如何管理目录结构比较好，可以拿一些线上项目目录作为例子

### 模块拆分

> 根据功能或管辖的层面来拆分

### 记录任务

> 擅长使用 issue 功能

## 测试

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
