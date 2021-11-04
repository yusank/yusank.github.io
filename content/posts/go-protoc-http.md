---
date: 2021-07-08T18:22:00+08:00
title: "如何自定义 protoc 插件"
categories:
- 技术
- protobuf
tags:
- go
- grpc
- protoc
---

## 前言

如果大家接触过 grpc 和 protobuf ，那对 `protoc` 这个命令应该不陌生。

`protoc` 为基于 proto buffer 文件生成不同语言代码的工具，在日常业务开发中能经常用到。那先抛出一个问题，你有没有基于 pb 文件生成满足自己特殊要求的需求？比如生成对应的 http 代码或校验参数等。

我个人需求为，除了生成正常的 `grpc` 代码外，需要生成一套对应的 `http` 代码，而且最好是能直接在 gin/iris 这种主流 web 框架内注册使用。

其实 `golang/protobuf` 包支持自定义插件的，而且还提供很多好用的方法，方便我们读写 pb 文件。我们写好自己的插件安装到 `$GOPATH/bin` 下，然后在调用 `protoc` 命令时，指定我们自己的插件名和输出位置即可。

**关于这个插件：我现有的需求然后一直找不到比较好的解决方案，直到看到 [kratos](https://github.com/go-kratos/kratos) 项目的 http 代码生成插件后豁然开朗，基于 `kratos` 的逻辑实现的自己需求，感谢 `kratos` 作者们。**

## 效果

先看原始 pb 文件。

test.proto

```protobuf
syntax = "proto3";

package hello.service.v1;
option go_package = "api/hello/service/v1;v1";

// 下载 `github.com/googleapis/googleapis` 至`GOPATH`, 生成 http 代码需要。
import "google/api/annotations.proto";

service Hello {
    rpc Add(AddRequest) returns (AddResponse) {
        option (google.api.http) = {
            post: "/api/hello/service/v1/add"
            body: "*"
        };
    }

    rpc Get(GetRequest) returns (GetResponse) {
        option (google.api.http) = {
            get: "/api/hello/service/v1/get"
        };
    }
}

message AddRequest {
    uint32 id = 1;
    string name = 2;
}

message AddResponse {
    uint32 id = 1;
    string name = 2;
}

message GetRequest {
    uint32 id = 1;
}

message GetResponse {
    uint32 id = 1;
    string name = 2;
    float score = 3;
    bytes bs = 4;
    map<string, string> m = 5;
}
```

因为我需要生成 http 代码，所以定义 rpc 时，http 路由和method 需要在 pb 文件指定。

我实现的插件起码叫 `protoc-gen-go-http`, 必须以 `protoc-gen` 开头否则 protoc 不认。

执行命令：

```shell
# --go-http 为我自己的插件
# 其中参数是 key=v,key2=v2 方式传，最后冒号后面写输出目录
protoc -I$GOPATH/src/github.com/googleapis/googleapis --proto_path=$GOPATH/src:. --go_out=. --go-http_out=router=gin:. --micro_out=. test.proto
```

执行完命令后，会生成三个文件分别为 `test.pb.go`,`test.pb.micro.go`和`test.http.pb.go`， 生成的文件名是可以自定义的。

`test.pb.micro.go` 文件是由 go-micro 提供的工具生成 grpc 代码文件。

看一下 `test.http.pb.go` 文件

```go
// Code generated by protoc-gen-go-http. DO NOT EDIT.
// versions:
// protoc-gen-go-http v0.0.9

package v1

import (
    context "context"
    gin "github.com/gin-gonic/gin"
)

// This is a compile-time assertion to ensure that this generated file
// is compatible with the galaxy package it is being compiled against.
var _ context.Context
const _ = gin.Version

type HelloHTTPHandler interface {
    Add(context.Context, *AddRequest, *AddResponse) error
    Get(context.Context, *GetRequest, *GetResponse) error
}

// RegisterHelloHTTPHandler define http router handle by gin.
func RegisterHelloHTTPHandler(g *gin.RouterGroup, srv HelloHTTPHandler) {
    g.POST("/api/hello/service/v1/add", _Hello_Add0_HTTP_Handler(srv))
    g.GET("/api/hello/service/v1/get", _Hello_Get0_HTTP_Handler(srv))
}

func _Hello_Add0_HTTP_Handler(srv HelloHTTPHandler) func(c *gin.Context) {
    return func(c *gin.Context) {
        var (
            in  AddRequest
            out AddResponse
        )

        if err := c.ShouldBind(&in); err != nil {
            c.AbortWithStatusJSON(400, gin.H{"err": err.Error()})
            return
        }

        err := srv.Add(context.Background(), &in, &out)
        if err != nil {
            c.AbortWithStatusJSON(500, gin.H{"err": err.Error()})
            return
        }

        c.JSON(200, &out)
    }
}

func _Hello_Get0_HTTP_Handler(srv HelloHTTPHandler) func(c *gin.Context) {
    return func(c *gin.Context) {
        var (
            in  GetRequest
            out GetResponse
        )

        if err := c.ShouldBind(&in); err != nil {
            c.AbortWithStatusJSON(400, gin.H{"err": err.Error()})
            return
        }

        err := srv.Get(context.Background(), &in, &out)
        if err != nil {
            c.AbortWithStatusJSON(500, gin.H{"err": err.Error()})
            return
        }

        c.JSON(200, &out)
    }
}
```

重点是 `RegisterHelloHTTPHandler` 方法，这样我就注册一个 gin.RouterGroup 和 HelloHTTPHandler 就可以直接提供一个 http 服务 `HelloHTTPHandler` 接口里方法的签名与`go-micro`生成的 grpc 方法保持了一致， 这样我只需要实现 grpc 的代码里对应的 Interface{} 接口，就可以服用，完全不会产生多余代码。

go-micro 生成的 pb 代码片段：

```go
type HelloHandler interface {
    Add(context.Context, *AddRequest, *AddResponse) error
    Get(context.Context, *GetRequest, *GetResponse) error
}

func RegisterHelloHandler(s server.Server, hdlr HelloHandler, opts ...server.HandlerOption) error {}
```

我在 main 函数注册的时候也只需要多注册一次 http handler 即可，

main.go

```go

// 它实现了 HelloHandler
type implHello struct{}

RegisterHelloHandler(micro.Server, &implHello)
g := gin.New()
// implHello 实现HelloHandler 那就是实现了HelloHTTPHandler
RegisterHelloHTTPHandler(g.Group("/"), &implHello)
```

所以我就很容易通过 http 接口调试 grpc 方法，甚至可以对外提供服务，一举两得。

## 如何实现

### 程序入口

main.go

```go
package main

import (
    "flag"

    "google.golang.org/protobuf/compiler/protogen"
    "google.golang.org/protobuf/types/pluginpb"
)

// protoc-gen-go-http 工具版本
// 与 GalaxyMicroVersion 保持一致
const version = "v0.0.12"

func main() {
    // 1. 传参定义
    // 即 插件是支持自定义参数的，这样我们可以更加灵活，针对不同的场景生成不同的代码
    var flags flag.FlagSet
    // 是否忽略没有指定 google.api 的方法
    omitempty := flags.Bool("omitempty", true, "omit if google.api is empty")
    // 我这里同时支持了 gin 和 iris 可以通过参数指定生成
    routerEngine := flags.String("router", "gin", "http router engine, choose between gin and iris")
    // 是否生校验代码块
    // 发现了一个很有用的插件 github.com/envoyproxy/protoc-gen-validate
    // 可以在 pb 的 message 中设置参数规则，然后会生成一个 validate.go 的文件 针对每个 message 生成一个 Validate() 方法
    // 我在每个 handler 处理业务前做了一次参数校验判断，通过这个 flag 控制是否生成这段校验代码
    genValidateCode := flags.Bool("validate", false, "add validate request params in handler")
    // 生成代码时参数 这么传：--go-http_out=router=iris,validate=true:.

    gp := &GenParam{
        Omitempty:       omitempty,
        RouterEngine:    routerEngine,
        GenValidateCode: genValidateCode,
    }
    // 这里就是入口，指定 option 后执行 Run 方法 ，我们的主逻辑就是在 Run 方法
    protogen.Options{
        ParamFunc: flags.Set,
    }.Run(func(gen *protogen.Plugin) error {
        gen.SupportedFeatures = uint64(pluginpb.CodeGeneratorResponse_FEATURE_PROTO3_OPTIONAL)
        for _, f := range gen.Files {
            if !f.Generate {
                continue
            }
            // 这里是我们的生成代码方法
            generateFile(gen, f, gp)
        }
        return nil
    })
}

type GenParam struct {
    Omitempty       *bool
    RouterEngine    *string
    GenValidateCode *bool
}

```

### 读取 pb 文件定义

http.go

```go

import (
    "fmt"
    "strings"

    "google.golang.org/genproto/googleapis/api/annotations"
    "google.golang.org/protobuf/compiler/protogen"
    "google.golang.org/protobuf/proto"
    "google.golang.org/protobuf/types/descriptorpb"
)

const (
    contextPackage = protogen.GoImportPath("context")
    ginPackage     = protogen.GoImportPath("github.com/gin-gonic/gin")
    irisPackage    = protogen.GoImportPath("github.com/kataras/iris/v12")
)

var methodSets = make(map[string]int)

// generateFile generates a _http.pb.go file containing gin/iris handler.
func generateFile(gen *protogen.Plugin, file *protogen.File, gp *GenParam) *protogen.GeneratedFile {
    if len(file.Services) == 0 || (*gp.Omitempty && !hasHTTPRule(file.Services)) {
        return nil
    }
    // 这里我们可以自定义文件名
    filename := file.GeneratedFilenamePrefix + ".pb.http.go"
    g := gen.NewGeneratedFile(filename, file.GoImportPath)
    // 写入一些警告之类的 告诉用户不要修改
    g.P("// Code generated by protoc-gen-go-http. DO NOT EDIT.")
    g.P("// versions:")
    g.P(fmt.Sprintf("// protoc-gen-go-http %s", version))
    g.P()
    g.P("package ", file.GoPackageName)
    g.P()
    generateFileContent(gen, file, g, gp)
    return g
}

// generateFileContent generates the _http.pb.go file content, excluding the package statement.
func generateFileContent(gen *protogen.Plugin, file *protogen.File, g *protogen.GeneratedFile, gp *GenParam) {
    if len(file.Services) == 0 {
        return
    }
    // import
    // 这里有个插曲：其实 import 相关的代码我们这么不需要特殊指定，protogen 包会帮我们处理，
    // 但是import 的 path 前的别名默认取 path 最后一个 `/` 之后的字符，
    // 比如：github.com/kataras/iris/v12 被处理成 v12 "github.com/kataras/iris/v12"
    // 这个我不太愿意接受 所以自己写入 import
    g.P("// This imports are custom by galaxy micro framework.")
    g.P("import (")
    switch *gp.RouterEngine {
    case "gin":
        g.P("gin", " ", ginPackage)
    case "iris":
        g.P("iris", " ", irisPackage)
    }
    g.P(")")
    
    // 注： 我们难免有一些 _ "my/package" 这种需求，这其实不用自己写 直接调 g.Import("my/package") 就可以

    // 这里定义一堆变量是为了程序编译的时候确保这些包是正确的，如果包不存在或者这些定义的包变量不存在都会编译失败
    g.P("// This is a compile-time assertion to ensure that this generated file")
    g.P("// is compatible with the galaxy package it is being compiled against.")
    // 只要调用这个 Ident 方法 就会自动写入到 import 中 ，所以如果对 import 的包名没有特殊要求，那就直接使用 Ident
    g.P("var _ ", contextPackage.Ident("Context"))

    // 像我自己自定义 import 的包就不要使用 Ident 方法，否则生成的代码文件里有两个同一个包的引入导致语法错误
    switch *gp.RouterEngine {
    case "gin":
        g.P("const _ = ", "gin.", "Version")
    case "iris":
        g.P("const _ = ", "iris.", "Version")
    }
    g.P()

    // 到这里我们就把包名 import 和变量写入成功了，剩下的就是针对 rpc service 生成对应的 handler
    for _, service := range file.Services {
        genService(gen, file, g, service, gp)
    }
}


// rpc service 信息
type serviceDesc struct {
    ServiceType string // Greeter
    ServiceName string // helloworld.Greeter
    Metadata    string // api/helloworld/helloworld.proto
    GenValidate bool
    Methods     []*methodDesc
    MethodSets  map[string]*methodDesc
}

// rpc 方法信息
type methodDesc struct {
    // method
    Name    string
    Num     int
    Request string
    Reply   string
    // http_rule
    Path            string
    Method          string
    CamelCaseMethod string
    HasVars         bool
    HasBody         bool
    Body            string
    ResponseBody    string
}

// 生成 service 相关代码
func genService(gen *protogen.Plugin, file *protogen.File, g *protogen.GeneratedFile, service *protogen.Service, gp *GenParam) {
    if service.Desc.Options().(*descriptorpb.ServiceOptions).GetDeprecated() {
        g.P("//")
        g.P(deprecationComment)
    }

    // HTTP Server.
    // 服务的主要变量，比如服务名 服务类型等
    sd := &serviceDesc{
        ServiceType: service.GoName,
        ServiceName: string(service.Desc.FullName()),
        Metadata:    file.Desc.Path(),
        GenValidate: *gp.GenValidateCode,
    }
    // 开始遍历服务的方法
    for _, method := range service.Methods {
        // 不处理
        if method.Desc.IsStreamingClient() || method.Desc.IsStreamingServer() {
            continue
        }
        // annotations 这个就是我们在 rpc 方法里 option 里定义的 http 路由
        rule, ok := proto.GetExtension(method.Desc.Options(), annotations.E_Http).(*annotations.HttpRule)
        if rule != nil && ok {
            for _, bind := range rule.AdditionalBindings {
                // 拿到 option里定义的路由， http method等信息
                sd.Methods = append(sd.Methods, buildHTTPRule(g, method, bind))
            }
            sd.Methods = append(sd.Methods, buildHTTPRule(g, method, rule))
        } else if !*gp.Omitempty {
            path := fmt.Sprintf("/%s/%s", service.Desc.FullName(), method.Desc.Name())
            sd.Methods = append(sd.Methods, buildMethodDesc(g, method, "POST", path))
        }
    }

    // 拿到了 n 个 rpc 方法，开始生成了
    if len(sd.Methods) != 0 {
        // 渲染
        g.P(sd.execute(*gp.RouterEngine))
    }
}

// 检查是否有 http 规则 即 
// option (google.api.http) = {
//      get: "/user/query"
//    };
func hasHTTPRule(services []*protogen.Service) bool {
    for _, service := range services {
        for _, method := range service.Methods {
            if method.Desc.IsStreamingClient() || method.Desc.IsStreamingServer() {
                continue
            }
            rule, ok := proto.GetExtension(method.Desc.Options(), annotations.E_Http).(*annotations.HttpRule)
            if rule != nil && ok {
                return true
            }
        }
    }
    return false
}

// 解析 http 规则，读取内容
func buildHTTPRule(g *protogen.GeneratedFile, m *protogen.Method, rule *annotations.HttpRule) *methodDesc {
    var (
        path         string
        method       string
        body         string
        responseBody string
    )
    // 读取 路由和方法
    switch pattern := rule.Pattern.(type) {
    case *annotations.HttpRule_Get:
        path = pattern.Get
        method = "GET"
    case *annotations.HttpRule_Put:
        path = pattern.Put
        method = "PUT"
    case *annotations.HttpRule_Post:
        path = pattern.Post
        method = "POST"
    case *annotations.HttpRule_Delete:
        path = pattern.Delete
        method = "DELETE"
    case *annotations.HttpRule_Patch:
        path = pattern.Patch
        method = "PATCH"
    case *annotations.HttpRule_Custom:
        path = pattern.Custom.Path
        method = pattern.Custom.Kind
    }
    body = rule.Body
    responseBody = rule.ResponseBody
    md := buildMethodDesc(g, m, method, path)
    if method == "GET" {
        md.HasBody = false
    } else if body == "*" {
        md.HasBody = true
        md.Body = ""
    } else if body != "" {
        md.HasBody = true
        md.Body = "." + camelCaseVars(body)
    } else {
        md.HasBody = false
    }
    if responseBody == "*" {
        md.ResponseBody = ""
    } else if responseBody != "" {
        md.ResponseBody = "." + camelCaseVars(responseBody)
    }
    return md
}

// 构建 每个方法的基础信息
// 到这里我们拿到了 我们需要生成一个 handler 的所有信息
// 名称，输入，输出，方法类型，路由
func buildMethodDesc(g *protogen.GeneratedFile, m *protogen.Method, method, path string) *methodDesc {
    defer func() { methodSets[m.GoName]++ }()
    return &methodDesc{
        Name:            m.GoName,
        Num:             methodSets[m.GoName],
        Request:         g.QualifiedGoIdent(m.Input.GoIdent), // rpc 方法中的 request
        Reply:           g.QualifiedGoIdent(m.Output.GoIdent), // rpc 方法中的 response
        Path:            path,
        Method:          method,
        CamelCaseMethod: camelCase(strings.ToLower(method)),
        HasVars:         len(buildPathVars(m, path)) > 0,
    }
}

// 处理 路由中 /api/user/{name} 这种情况
func buildPathVars(method *protogen.Method, path string) (res []string) {
    for _, v := range strings.Split(path, "/") {
        if strings.HasPrefix(v, "{") && strings.HasSuffix(v, "}") {
            name := strings.TrimRight(strings.TrimLeft(v, "{"), "}")
            res = append(res, name)
        }
    }
    return
}
```

### 模板渲染

```go
// execute 方法实现也其实不复杂，总起来就是 go 的 temple 包的使用
// 提前写好模板文件，然后拿到所有需要的变量，进行模板渲染，写入文件
func (s *serviceDesc) execute(routerEngine string) string {
    var (
        name = routerEngine
        tmp  string
    )
    switch routerEngine {
    case "gin":
        tmp = ginTemplate
    case "iris":
        tmp = irisTemplate
    default:
        panic("unknown http engine")
    }
    s.MethodSets = make(map[string]*methodDesc)
    for _, m := range s.Methods {
        s.MethodSets[m.Name] = m
    }
    buf := new(bytes.Buffer)
    tmpl, err := template.New(name).Parse(strings.TrimSpace(tmp))
    if err != nil {
        panic(err)
    }
    if err = tmpl.Execute(buf, s); err != nil {
        panic(err)
    }

    return strings.Trim(buf.String(), "\r\n")
}
```

### 模板内容

```go

var ginTemplate = `
{{$svrType := .ServiceType}}
{{$svrName := .ServiceName}}
{{$validate := .GenValidate}}
// 这里定义 handler interface
type {{.ServiceType}}HTTPHandler interface {
{{- range .MethodSets}}
    {{.Name}}(context.Context, *{{.Request}}, *{{.Reply}}) error
{{- end}}
}

// Register{{.ServiceType}}HTTPHandler define http router handle by gin. 
// 注册路由 handler
func Register{{.ServiceType}}HTTPHandler(g *gin.RouterGroup, srv {{.ServiceType}}HTTPHandler) {
    {{- range .Methods}}
    g.{{.Method}}("{{.Path}}", _{{$svrType}}_{{.Name}}{{.Num}}_HTTP_Handler(srv))
    {{- end}}
}

// 定义 handler
// 遍历之前解析到所有 rpc 方法信息
{{range .Methods}}
func _{{$svrType}}_{{.Name}}{{.Num}}_HTTP_Handler(srv {{$svrType}}HTTPHandler) func(c *gin.Context) {
    return func(c *gin.Context) {
        var (
            in  = new({{.Request}})
            out = new({{.Reply}})
            ctx = middleware.GetContextFromGinCtx(c)
        )

        if err := c.ShouldBind(in{{.Body}}); err != nil {
            c.AbortWithStatusJSON(400, gin.H{"err": err.Error()})
            return
        }
        
        // 这里就是最开始提到的判断是否启用 validate
        // 其中这个 api.Validator 接口只有一个方法 Validate() error
        // 所以需要在一个统一的地方定义好引入使用，建议不要在生成的时候写入，因为这个是通用的 interface{}
        {{if $validate -}} 
        // check param
        if v, ok := interface{}(in).(api.Validator);ok {
            if err := v.Validate();err != nil {
                c.AbortWithStatusJSON(400, gin.H{"err": err.Error()})
                return
            }
        }
        {{end -}}

        // 执行方法
        err := srv.{{.Name}}(ctx, in, out)
        if err != nil {
            c.AbortWithStatusJSON(500, gin.H{"err": err.Error()})
            return
        }
        
        c.JSON(200, out)
    }
}
{{end}}
`
```

iris 的模板基本类似。

到这里代码部分完全结束，做一个简单的总结：

1. 构思需求，即我需要什么样的插件，它需要给我生成什么的代码块？

2. 根据需求先自己写一个预期代码，然后把这份代码拆解成一个模板，提取里面的可以渲染的变量。

3. 模板里可以有逻辑，也就是可以做一些参数校验的方式，生成不同的代码，比如针对不同的 http 方法，做不同的处理，针对不同的插件参数生成不同的代码块。

4. 程序入口到渲染文件前这段代码，基本都用 `protogen` 包提供的方法，可以对这个包做一些调研阅读文档，看看它都提供什么能力, 说不定可以少走很多弯路。

基本就这些了，我也是各种琢磨琢磨出来的，建议大家多动手，只要不写永远学不到精髓。