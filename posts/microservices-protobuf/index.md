# [系列]微服务·如何通过 protobuf 定义数据和服务


> 本文为系列篇`微服务`的关于 protobuf 定义数据和服务的文章。本篇将会介绍如何通过 pb 定义数据结构和服务以及 pb 的一些另类玩法。

<!--more-->

## 1. 前言

{{< admonition type=note title="Definition by Google" open=true >}}
&ensp;&ensp;Protocol buffers provide a language-neutral, platform-neutral, extensible mechanism for serializing structured data in a forward-compatible and backward-compatible way. It’s like JSON, except it's smaller and faster, and it generates native language bindings.

&ensp;&ensp;Protocol buffers are a combination of the definition language (created in .proto files), the code that the proto compiler generates to interface with data, language-specific runtime libraries, and the serialization format for data that is written to a file (or sent across a network connection).
{{< /admonition >}}

`Protocol buffer`(下面使用 pb 来代替) 是一个 接口定义语言(`Interface Definition Language -- IDL`)和消息编码格式。旨在提供一种简单、易于使用、可扩展的方式来定义数据结构和服务。pb 是一种纯文本格式，而其内部是纯二进制格式，比其他编码格式(如：json，xml)更加精炼。pb 包含一个或多个消息类型，每个消息类型包含一个或多个字段。其主要特性为：

- 编码速度快
- 编码后数据更小
- 根据 pb 生成各个语言代码(本文以 Go 为例)
- 支持类型定义
- 支持定义服务
- 语法简单

而 `gRPC` 作为 Google 推出的 rpc 协议，将 pb 作为默认的数据传输格式，也说明了 pb 作为消息编码格式的优秀性。

{{< admonition type=question title="Pb 解决了什么问题？" open=true >}}

1. pb 提供序列化的消息格式定义，适用于短连接和长连接
2. 适用于微服务中服务之间通信和数据落盘
3. 消息格式由服务提供者定义，而使用者可根据自身条件生成不同语言的代码，免去编码和解码的工作和其中可能出现各类问题
4. 消息定义可以随时修改，而不会影响使用者的代码，使用者只需要保持最新的 pb 文件即可

{{< /admonition >}}

下面我们从简单到复杂的介绍，如何使用 pb 定义数据结构和服务。

## 2. 数据定义

首先，我们需要看一下 pb 支持的数据类型有哪些，以及这些数据类型生成的代码中的类型的对照。

| Pb  | Go |
| :---- | :---- |
|double | float64 |
|float | float32 |
|int32 | int32 |
|int64 | int64 |
|uint32 | uint32 |
|uint64 | uint64 |
|sint32 | int32 |
|sint64 | int64 |
|fixed32 | uint32 |
|fixed64 | uint64 |
|sfixed32 | int32 |
|sfixed64 | int64 |
|bool | bool |
|string | string |
|bytes | []byte |
|map | map |
|enum | int32 |
|message | struct |

可以看出 pb 定义的数据类型几乎与大部分编程语言很相似，因此入门 pb 的门槛可以说是很低。

### 2.1 基础用法

下面分别以枚举和消息的角度，来介绍 pb 的基本用法。

{{< admonition type=warning title="注意" open=true >}}

1. 下面所有提到的 pb 定义均是以 `proto3`为准，本文不讨论 `proto2` 以及 `proto2` 与 `proto3` 的区别。
2. 下面提到的代码生成规则均是基于 `Go 语言`版本的，且经过本人测试验证，但是**不会对其他语言生成代码规则做任何保证。**
3. 写本文时，使用的工具版本如下：
   1. `protoc --version` :`libprotoc 3.19.4`
   2. `protoc-gen-go` : `v1.28.0`

{{< /admonition >}}

在定义数据之前，先说一下 `.proto` 文件的头部规则：

```proto
syntax = "proto3"; // 表示使用 proto3 的语法

// 包名，如果其他 proto 文件引用该文件时，使用该值去引用， 如：
//  import "api.user.v1.proto";
//  message xxx {
//    api.user.v1.Person person= 1;
//    ...
//  } 
package api.user.v1; 
// go 的包名，可以根据在当前项目的路径定义，需要注意的是，如果其他包引入当前 proto 文件，
// 则其他 proto 文件生成 go 代码时，会以 go_package 作为包包名引入使用,因此如果当前项目的 proto 文件会被其他项目引入
// 或者 项目包名是以 github.com/xx/xx 的方式定义，那这里也按这个格式定义完整的路径
option go_package = "api/user/v1";
```

#### 2.1.1 枚举

```proto
enum Sex {
    Unknown = 0;
    Male = 1;
    Female = 2;
    Other = 3;
    Alien = -1;
}
```

上面我们定义了一个枚举类型(`enum`) `Sex` ，并定义了几个枚举值。这个枚举类型可以作为一个数据类型，可以在当前 proto 文件内被引用。定义使用枚举有几点需要注意：

1. 枚举的值只能是整数
2. 枚举值不能重复
3. 枚举的第一个元素的值必须是 0，且不能不定义
4. 从第二个元素开始，其值可以为任意整数，不需要严格的递增，甚至可以定义为负数

通过 `protoc` 命令行工具，我们可以根据 `.proto` 文件不同语言的代码，下面是根据上述定义的枚举值生成的代码一部分：

```go
type Sex int32

const (
  Sex_Unknown Sex = 0
  Sex_Male    Sex = 1
  Sex_Female  Sex = 2
  Sex_Other   Sex = 3
  Sex_Alien   Sex = -1
)

// Enum value maps for Sex.
var (
  Sex_name = map[int32]string{
    0:  "Unknown",
    1:  "Male",
    2:  "Female",
    3:  "Other",
    -1: "Alien",
  }
  Sex_value = map[string]int32{
    "Unknown": 0,
    "Male":    1,
    "Female":  2,
    "Other":   3,
    "Alien":   -1,
  }
)

// 还会生成 Sex 的 String() Type() 等方法，这里忽略不贴代码了
```

可以看到定义 `const` 类型和值之外，还会生成两个 map，枚举的名字和值可互相转换。这里也可以更加确定为什么枚举值不能重复的原因了。

#### 2.1.2 消息

```proto
message Person {
  string name = 1;
  Sex sex = 3;
  int32 age = 2;
  float score = 4;
  map<string,bytes> extra_data = 5;
}
```

我们定义了一个简单的消息(`message`)为 `Person` 并且包含了上面定义的枚举值。定义消息也是有一套自己的规则：

1. 消息的名字必须以字母开头，后面可以跟字母、数字、下划线，且大小写不明感，生成的代码中会自动将消息名字转换为大写
2. 消息字段定义是，先指定类型，再指定字段名，最后需要指定索引值
3. 消息索引值必须是整数，且不重复即可，无需要严格的递增
4. 消息字段名可以是`小写` 或 `snake case`,生成的代码会转换成首字母大写的 `Camel Case`

下面看一下基于这个消息结构生成的代码：

```go
type Person struct {
  state         protoimpl.MessageState
  sizeCache     protoimpl.SizeCache
  unknownFields protoimpl.UnknownFields

  Name      string            `protobuf:"bytes,1,opt,name=name,proto3" json:"name,omitempty"`
  Sex       Sex               `protobuf:"varint,3,opt,name=sex,proto3,enum=api.user.session.v1.Sex" json:"sex,omitempty"`
  Age       int32             `protobuf:"varint,2,opt,name=age,proto3" json:"age,omitempty"`
  Score     float32           `protobuf:"fixed32,4,opt,name=score,proto3" json:"score,omitempty"`
  ExtraData map[string][]byte `protobuf:"bytes,5,rep,name=extra_data,json=extraData,proto3" json:"extra_data,omitempty" protobuf_key:"bytes,1,opt,name=key,proto3" protobuf_val:"bytes,2,opt,name=value,proto3"`
}

// 同时会生成一堆方法，这里忽略不贴代码了
```

可以看到，消息会生成一个结构体，并每个字段都会带上 `protobuf` 和 `json` 的 tag，方便序列化更方便。`protobuf` tag 会详细记录字段的在 `proto` 文件定义的名字，索引值、proto 版本等信息，用于编码和解码。而 `json` tag 仅记录字段名。

### 2.2 高级玩法

#### 2.2.1 组合使用

上面定义了些简单的使用方式，但是实际开发过程中需要更复杂的场景，下面我们以一个比较复杂的场景为例，讲解如何定义复杂的消息类型。

```proto

enum Sex {
  Unknown = 0;
  Male = 1;
  Female = 2;
  Other = 3;
  Alien = -1;
}

message School {
  string name = 1;
  string grade  = 2;
  int64 graduated_at = 3;
  repeated string teachers = 4;
}

message Person {
  optional string name = 1;
  Sex sex = 3;
  int32 age = 2;
  float score = 4;
  map<string,bytes> extra_data = 5;
  repeated School schools = 6;
  oneof contact {
    string email = 7;
    string phone = 8;
  }
  message Company {
    string name = 1;
    string address = 2;
    int32 salary = 3;
    repeated string employees = 4;
  }
  Company company = 9;
}
```

在之前的 `Person` 基础上做了一个更复杂的消息结构，新增了`学校`、`联系方式`、`公司`三个字段，并且各个字段的类型并不相同，下面一个个进行讲解。

**school** 这个字段引入了两个特性，第一个是 `repeated` ，表示这个字段是一个数组，而数组的元素类型就是 `repeated` 之后的值 `School`。第二个特性是消息的嵌套，可以看到上面已经定义了一个 `School` 的消息，然后在`Person` 消息内嵌套使用。

**contact** 这个字段引入了 `oneof` 这个特性，`oneof` 可以看做是一个 `switch` 的语句，它的作用是根据 `contact` 字段的值，来选择使用哪个字段。你可以赋值 `email` 也可以赋值 `phone` 或者均不赋值，在生成的代码里，是有 `GetEmail()`, `GetPhone` 方法来获取这个字段的值。

**company** 字段引入了一个特性，也就是可以在消息内定义另一个消息并用在某个字段上。最终生成的代码里会有一个 `Person_Company` 的结构体，表示这个结构体属于 `Person`.

除此之外， `name` 字段也加了一个 `option` 的标识，在生成代码时会生成 `*string` 的类型，可以区分nil 和空值。

下面我们看一下，生成的代码（仅展现核心部分,忽略其他无关部分）：

```go
type School struct {
  // ...ignored...
  Name        string   `protobuf:"bytes,1,opt,name=name,proto3" json:"name,omitempty"`
  Grade       string   `protobuf:"bytes,2,opt,name=grade,proto3" json:"grade,omitempty"`
  GraduatedAt int64    `protobuf:"varint,3,opt,name=graduated_at,json=graduatedAt,proto3" json:"graduated_at,omitempty"`
  Teachers    []string `protobuf:"bytes,4,rep,name=teachers,proto3" json:"teachers,omitempty"`
}

type Person struct {
  // ...ignored...
  Name      *string           `protobuf:"bytes,1,opt,name=name,proto3,oneof" json:"name,omitempty"`
  Sex       Sex               `protobuf:"varint,3,opt,name=sex,proto3,enum=api.user.session.v1.Sex" json:"sex,omitempty"`
  Age       int32             `protobuf:"varint,2,opt,name=age,proto3" json:"age,omitempty"`
  Score     float32           `protobuf:"fixed32,4,opt,name=score,proto3" json:"score,omitempty"`
  ExtraData map[string][]byte `protobuf:"bytes,5,rep,name=extra_data,json=extraData,proto3" json:"extra_data,omitempty" protobuf_key:"bytes,1,opt,name=key,proto3" protobuf_val:"bytes,2,opt,name=value,proto3"`
  Schools   []*School         `protobuf:"bytes,6,rep,name=schools,proto3" json:"schools,omitempty"`
  // Types that are assignable to Contact:
  // *Person_Email
  // *Person_Phone
  Contact isPerson_Contact `protobuf_oneof:"contact"` // 注意这个字段
  Company *Person_Company  `protobuf:"bytes,9,opt,name=company,proto3" json:"company,omitempty"`
}

type isPerson_Contact interface {
  isPerson_Contact()
}

type Person_Email struct {
  Email string `protobuf:"bytes,7,opt,name=email,proto3,oneof"`
}

type Person_Phone struct {
  Phone string `protobuf:"bytes,8,opt,name=phone,proto3,oneof"`
}

func (*Person_Email) isPerson_Contact() {}

func (*Person_Phone) isPerson_Contact() {}

type Person_Company struct {
  // ...ignored...
  Name      string   `protobuf:"bytes,1,opt,name=name,proto3" json:"name,omitempty"`
  Address   string   `protobuf:"bytes,2,opt,name=address,proto3" json:"address,omitempty"`
  Salary    int32    `protobuf:"varint,3,opt,name=salary,proto3" json:"salary,omitempty"`
  Employees []string `protobuf:"bytes,4,rep,name=employees,proto3" json:"employees,omitempty"`
}
```

{{< admonition type=tip title="关于 oneof" open=true >}}
需要注意的时上面生成的 contact 的字段值 `isPerson_Contact` 是一个接口定义，它的实现是 `Person_Email` 和 `Person_Phone` 两个结构体。
而 `Person` 结构会同时生成一下代码，从而实现了 `oneof` 的功能：

```go

func (m *Person) GetContact() isPerson_Contact {
  if m != nil {
    return m.Contact
  }
  return nil
}

func (x *Person) GetEmail() string {
  if x, ok := x.GetContact().(*Person_Email); ok {
    return x.Email
  }
  return ""
}

func (x *Person) GetPhone() string {
  if x, ok := x.GetContact().(*Person_Phone); ok {
    return x.Phone
  }
  return ""
}
```

{{< /admonition >}}

#### 2.2.2 项目内 proto 的引用

作为一个合格的程序员，代码是需要根据功能、类型等因素进行拆分的，每个文件/模块 负责一部分的逻辑，各个模块之间可以有相互的依赖关系。

> 因此引进来一个问题是，我不同的 proto 文件之间如何相互引用？如果有第三方的 proto 文件又怎么引入使用呢？

答案是，pb 是支持 import 能力的。自己的 proto 文件之间可以互相引用，也可以引入其他 proto 文件。但是需要注意不要在不同 package 之间循环引用（写 go 的都知道这个是坑，不用过多解释）。

**先说一下引入自己项目内的其他 proto 文件的情况。**

假设我现在有两个 proto 文件，其路径入下：

```shell
api
|--user
|   |--user.proto
|-- order
|   |--order.proto
```

而这个项目的 go mod 定义是 `github.com/a/b`, `order.proto` 要引入使用 `user.proto` 定义的消息。

user.proto 的头部定义的应该是这样的：

```proto
syntax = "proto3";

package api.user; // 项目根目录到当前文件，这样定义方便引入，但是不是固定规则
option go_package = "github.com/a/b/user"; // 这里请确保你的项目根目录到当前文件的路径是一致的，否则会导致引入失败

message User {
  string name = 1;
}
```

order.proto 的头部定义的应该是这样的：

```proto
syntax = "proto3";

package api.order; // 项目根目录到当前文件，这样定义方便引入，但是不是固定规则
option go_package = "github.com/a/b/order"; // 这里请确保你的项目根目录到当前文件的路径是一致的，否则会导致引入失败

import "api.user.proto";

message Order {
  api.user.User user = 1;
  // ...
}
```

这种方式就可以实现项目不同包之间的引用，`order.proto` 生成引入包代码如下：

```go
import (
  // ...
  user "github.com/a/b/user"
  // ...
)
```

#### 2.2.3 引用第三方包

如果你对 pb 比较熟悉的话，应该对 pb 官方开源的这个项目不陌生：[https://github.com/protocolbuffers/protobuf](https://github.com/protocolbuffers/protobuf),该项目为 pb 的源码。当然这里不介绍源码相关的东西，但是在其 `src/google/protobuf` 目录下，定义了很多高级数据类型，方便我们日常使用。

下面以 `Duration 为例`：

```proto
import "google/protobuf/duration.proto"; 
// 需要注意的是，protoc 命令里需要指定该包所在目录。我是放到项目内 `third_party` 目录下,并在生成代码的名利指定
//  `--proto_path=./third_party` 参数。

message Config {
  string addr = 1;
  google.protobuf.Duration timeout = 2; // 定义一个超时
}
```

此时生成代码的时候会发现，生成字段类型并非是原生 `time.Duration`，而是 `google.protobuf.Duration`。这里需要注意下，但是这个类型有个
`AsDuration()` 的方法，会返回原生 `time.Duration`。

与此同时，`Google` 的这个扩展包，提供了很多其他的数据类型，比如`Timestamp`、`FieldMask`、`StringValue`、`BytesValue` 等等。用法与上面一致，引入对应的包即可，具体有哪些类型，可从官方文档查阅：[https://developers.google.com/protocol-buffers/docs/reference/google.protobuf](https://developers.google.com/protocol-buffers/docs/reference/google.protobuf) 。

### 2.3 消息校验

在业务正常的业务开发中，我们需要对接口传参的数据进行数据合法性验证，一般是通过结构体注入 tag 的方式统一处理。大家最熟悉的应该是 `github.com/go-playground/validator` 这个包，通过在 tag 上定义验证规则，然后用统一的方法进行规则验证。用习惯了可以说是很方便，而且很多主流的http 框架也对这个库进行支持的（比如 gin）。

但是在基于 gRPC & pb 的场景下，这个库就只是个摆设了，因为代码是自动生成的，没办法改动，更没办法注入 tag 信息（当然不能说不行，你可以自己开发一个 `protoc` 的插件去做这个事儿，但是这个过程比你想想的要麻烦多，可以看一下 [如何自定义 protoc 插件](../go-protoc-http/) 这篇文件）。

所以想验证数据的合法性好像只能挨个字段去去判断，为了解决这个问题，出现另一个非常 nb 的插件 -- [github.com/envoyproxy/protoc-gen-validate](https://github.com/envoyproxy/protoc-gen-validate)。

该库定义了每个基础类型（包括 Google 提供 `duration`, `timestamp` 等类型）的验证规则，并生成对应的代码。使用时直接调用结构体的 `Validate()` 方法即可。

#### 2.3.1 基础类型

对于**基础类型**，比如 int32、int64、string、bool 等等，会有大于小于等于，必须，非必须，空，非空等等的验证规则。

如：

```proto
message UpdateUserRequest {
  string uid = 1 [(validate.rules).string = {min_len: 20, max_len: 24}];
  string name = 2 [(validate.rules).string = {min_len: 2, max_len: 20, ignore_empty: true}];
  string email = 3 [(validate.rules).string = {email: true,ignore_empty: true}];
  string phone = 4 [(validate.rules).string = {pattern: "^1[3-9]\\d{9}$", ignore_empty: true}];
  string avatar = 5 [(validate.rules).string = {max_len:128, ignore_empty: true}];
}
```

生成的代码比较多，就不再这里展示。但是生成代码逻辑是，一个个判断字段上的规则，不符合规则时，会返回很详细的错误信息，包括字段名，规则等，一眼就能看出哪个字段不符合哪个规则。

其他基础类型也类似，建议阅读官方文档或者直接看 proto 文件，因为 proto 文件比文档看起来更简单明了。

#### 2.3.2 高级类型

对于 `oneof`, `message` 这种**高级用法**，他也有对应的检验规则，这里提一下 `oneof`。因为原生的 `oneof` 可以传其中一个字段或者不传，但是我们希望我定义了 n 个，你必选传其中一个，这个时候只需要在 `oneof` 上第一行加上 `option (validate.required) = true;` 即可。如：

```proto
oneof id {
  // either x, y, or z must be set.
  option (validate.required) = true;

  string x = 1;
  int32  y = 2;
  Person z = 3;
}
```

#### 2.3.3 扩展类型

对于**第三方包**（如 `google/protobuf/duration`, `google/protobuf/timestamps`）也支持了规则配置，可以要求必传，可以要求传的值必须等于某个指定值或者是在一定的时间范围内。如：

```proto
message config {
  // range [10ms, 10s]
  google.protobuf.Duration dial_timeout_sec = 3 [(validate.rules).duration = {
    gte: {nanos: 1000000, seconds: 0},
    lte:  {seconds: 10}
  }];
}
```

该包的能力比较强，由于篇幅只讲了几个类型，所以不再展示。这个库的潜力我个人认为是很大的，强烈推荐大家使用。

## 3. 服务定义

### 3.1 常规服务定义

聊了这么多 pb 中消息的定义，现在聊一聊 pb 中的服务定义，毕竟服务才是核心部分。

pb 中服务定义是定义一个服务和其下面的方法，而这些方法需要一个请求和一个响应。如：

```proto
service UserService {
  rpc CreateUser(CreateUserRequest) returns (CreateUserResponse);
  // ...
}

message CreateUserRequest {
  Person person = 1;
}

message CreateUserResponse {
  string id = 1;
}
```

这是一个最简的服务定义，其包含一个创建用户的方法，输入输出也分别定义了。需要注意的是，方法必须要有输入输出且不支持多个参数，如果需要多个参数，请嵌套一个结构体。如果方法没有返回值，则可以定义一个空的 `message` 即可。而我的做法是定义一个通用的 response，在没有返回值的方法返回这个 response，有返回值的方法则嵌套一层，response 作为参数。

```proto
// BaseResponse use as define response code and message
message BaseResponse {
  Code code = 1;
  string reason = 2;
  string message = 3;
}
```

### 3.2 stream 流服务定义

处了上述的定义服务之外，还可以定义输入或输出位 stream 的方法，如：

```proto
service UserService {
  rpc CreateUser1(stream CreateUserRequest) returns (CreateUserResponse);
  rpc CreateUser2(CreateUserRequest) returns (stream CreateUserResponse);
  rpc CreateUser3(stream CreateUserRequest) returns (stream CreateUserResponse);
}
```

表示请求或响应可以是个 stream 流，而不同的 stream 的定义生成的代码也不一样，如(以 client 端代码为例)：

```go
// For semantics around ctx use and closing/ending streaming RPCs, please refer to https://pkg.go.dev/google.golang.org/grpc/?tab=doc#ClientConn.NewStream.
type UserServiceClient interface {
  CreateUser1(ctx context.Context, opts ...grpc.CallOption) (UserService_CreateUser1Client, error)
  CreateUser2(ctx context.Context, in *CreateUserRequest, opts ...grpc.CallOption) (UserService_CreateUser2Client, error)
  CreateUser3(ctx context.Context, opts ...grpc.CallOption) (UserService_CreateUser3Client, error)
}

type UserService_CreateUser1Client interface {
  Send(*CreateUserRequest) error
  CloseAndRecv() (*CreateUserResponse, error)
  grpc.ClientStream
}

type UserService_CreateUser2Client interface {
  Recv() (*CreateUserResponse, error)
  grpc.ClientStream
}

type UserService_CreateUser3Client interface {
  Send(*CreateUserRequest) error
  Recv() (*CreateUserResponse, error)
  grpc.ClientStream
}
```

三个方法返回的值均不一样，分别为：发送端为 stream 流，接收端为 stream 流，双向 stream 流。同样的 server 端实现这些方式时，也需要实现相应的接口。

### 3.3 服务定义中嵌套 http 定义

在 `google/api/annotations.proto` 库的支持下， pb 支持服务中嵌套 http 定义，如：

```proto
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
```

可以通过 `grpc-gateway` (官方项目)生成对应的 http 接口并注册到 `grpc-gateway` 中。也可以通过其他插件去生成 http 代码。而 `kratos` 这个框架就做了这个事儿，单独生成 `.http.go` 文件，可以将生成的路由注册到 `kratos` 中。我之前也写过类似的插件，可以参考这篇文章：[如何自定义 protoc 插件](../go-protoc-http/)。

不管那种方式，最终目标都是多生产一套 http 接口，方便调试或者对外提供 grpc & http 服务。

## 4. 总结

到这里本篇文章就结束了，基本讲完我对 pb 的理解和使用上遇到的经验都写出来了。当然由于篇幅原因，没有讲述太多 grpc 相关的问题，因为 grpc 也算是个大头，我想以后单独写一篇讲述 grpc 的原理和通信以及使用的文章。

本篇主要讲述了：

- pb 的定义和解决的问题
- pb 的基础类型定义和花样玩法
- pb 类型的数据校验（介绍了一个第三方库：[protoc-gen-validate](https://github.com/envoyproxy/protoc-gen-validate)）
- pb 定义普通服务
- pb 定义 stream 流服务
- pb 定义 http 服务

如果你有任何问题或者有不一样的想法，请通过评论区或者邮件联系我。

{{< admonition type=tip title="如果在使用 pb 过程中有什么不明白的" open=true >}}
本文中的知识点，大部分都是我在写项目的时候积累下来的，如果你有什么不明白的地方，可以参考我的一个项目: [goim/api](https://github.com/go-goim/api)。

本文提到的能力我在这个项目基本都用到了，你可以同时看代码和本文，应该对你有一定的帮助。
{{< /admonition >}}

## 5. 链接🔗

- [系列篇](../../categories/microservice/)
- [如何自定义 protoc 插件](../go-protoc-http/)
- [https://developers.google.com/protocol-buffers/docs/overview](https://developers.google.com/protocol-buffers/docs/overview)
- [https://www.grpc.io/docs/what-is-grpc/introduction/](https://www.grpc.io/docs/what-is-grpc/introduction/)
- [https://github.com/envoyproxy/protoc-gen-validate](https://github.com/envoyproxy/protoc-gen-validate)

