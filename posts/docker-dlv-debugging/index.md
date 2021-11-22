# 如何在 docker 环境下进行远程 dlv 调试


`dlv` 作为程序调试工具功能非常强大，日常开发和测试中几乎离不开 debug 调试。但是有的时候由于本地环境与线上环境不一致或有些问题在本地无法复现的时候，我们需要在线上/测试环境做 debug，同时希望 debug 体验能与本地 debug 体验一致。`dlv` 其实是支持这种需求的，线上运行线本地 debug。以下是基于 docker 环境的远程调试步骤，希望能对遇到这种情况的码友们友帮助。

所需工具：
- docker
- goland
- dlv

## docker file

```dockerfile
# Compile stage
FROM golang:1.13.8 AS build-env

# Build Delve
RUN go get github.com/go-delve/delve/cmd/dlv

ADD . /dockerdev
WORKDIR /dockerdev

# 编译需要 debug 的程序
RUN go build -gcflags="all=-N -l" -o /server

# Final stage
FROM debian:buster

# 分别暴露 server 和 dlv 端口
EXPOSE 8000 40000

WORKDIR /
COPY --from=build-env /go/bin/dlv /
COPY --from=build-env /server /

CMD ["/dlv", "--listen=:40000", "--headless=true", "--api-version=2", "--accept-multiclient", "exec", "/server"]
```

## 启动 docker 镜像

```shell
$ docker run -d -p 8000:8000 -p 40000:40000 --privileged --name=dlv-debug $(ImageName):$(ImageVersion)
```

## goland 配置

在 `Goland -> Run -> Edit Configuration` 添加 `Go Remote` 配置 docker 镜像的 ip:port, 本地的 docker 环境则 `localhost:40000` 即可。

现在就可以在本地 Goland 环境下启动配置 debug 就可以，本地 debug 远程程序，与本地 debug 毫无区别。

这种方式在一些特定环境（test 环境、远程办公等）非常方便。

**参考文献：**
- https://blog.jetbrains.com/go/2020/05/06/debugging-a-go-application-inside-a-docker-container/

