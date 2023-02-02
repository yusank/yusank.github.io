# 基于策略的 kubernetes admission webhook · 一


> 本篇介绍一款基于策略/规则的 kubernetes webhook - `kinitiras`, 一个轻量，强大且可编程的策略引擎。该引擎提供强大的编程和模板能力，可以通过规则完成绝大部分的对 webhook 的需求。

<!--more-->

## 1.背景

{{< admonition type=quote title="Definition" open=true >}}
准入 Webhook 是一种用于接收准入请求并对其进行处理的 HTTP 回调机制。 可以定义两种类型的准入 webhook，即 `验证性质的准入` Webhook 和 `修改性质的准入` Webhook。 `修改性质的准入 Webhook 会先被调用`。它们可以更改发送到 API 服务器的对象以执行自定义的设置默认值操作。

在完成了所有对象修改并且 API 服务器也验证了所传入的对象之后， 验证性质的 Webhook 会被调用，并通过拒绝请求的方式来强制实施自定义的策略。
{{< /admonition >}}

以上是 kubernetes 给出的定义，简单来说，k8s 的 webhook 分为两类 `validating` 和 `mutating` 分别用于校验和修改 k8s 资源的修改操作。当用户创建 or 修改资源时，`apiserver` 会调用(http)已注册的 `validating` 和 `mutating` webhook，在这些 webhook 响应后才真正处理这次修改操作。

{{< image src="webhook-process.png" caption="执行流程" width="800" >}}

对于熟悉云原生开发或熟悉 k8s 的开发来说，webhook 应该是非常熟悉的一块，也应该写过多多少少的相关代码。作为 k8s 原生提供的能力，目前的 webhook 开发/使用方式可以说是非常不友好且很原始，k8s 很多能力都可以通过修改已有的对象或 CRD 的信息达到目的（如更新镜像，滚动升级等），唯有 webhook 需要写代码开发且注册到 `apiserver` 并运行程序来达到目的。

然而在日常开发中，大多数对于 webhook 的需求仅限于很简单的一些能力，比如校验某些对象的字段和合法性、修改特定的对象的信息（打 label、annotation or 修改资源规格等），这就导致了每次新增需求或者修改需求时都需要开发改代码打包发版。这使得整个过程效率很低，同时会存在一个集群内注册了过多的 webhook 使 apiserver 的响应时间被拉长，可靠性降低。

为了解决以上的提到的这些问题，我们开发了一套全新的基于规则的可编程的 webhook -- [kinitiras](https://github.com/k-cloud-labs/kinitiras)，希望能通过该组件来代替集群内所有的 webhook 并且所有的需求可以通过该组件来解决无需自己开发新的 webhook，提升效率的同时减少因多个 webhook 带来的安全隐患。

## 2.能力

{{< image src="kinitiras.org.png" caption="特性" width="800" >}}

在讲述其设计与实现之前，这里先讲述一下 kinitiras 能干什么，具备哪些能力。

### 2.1 校验资源

[策略例子](https://k-cloud-labs.github.io/kinitiras-doc/usage/basic-usage/#clustervalidatepolicy)

我们可以对不同的资源配置不同的策略，从而减少出现一些不可控情况或者限制一些特殊操作，比如：

- 对于创建更新操作，可以对资源的一些字段进行限制（不可空 或者 其值等于不等于指定的值等等）
- 限制更新或删除操作。可以对一些特定的资源（ns or deployment）进行禁止删除或者二次确认机制（只有存在指定的 annotation 才允许删除）
- 字段校验

这些校验的字段和值可以为当前的 object 的值 也可以跟其他 object 的值（比如与 cm 或者 secret 等其他 object 对比）也为第三方 http 服务获取的数据进行对比校验。

### 2.2 修改资源

[策略例子](https://k-cloud-labs.github.io/kinitiras-doc/usage/basic-usage/#overridepolicy)

对于修改资源，我们的策略可以配置很多不同场景，满足不同的需求，比如：

- 给资源统一打标签打 annotation
- 修改资源规格
- 修改资源的 affinity toleration 等

而这个修改的值，均可以为动态的，可以从别的 object 获取（比如把 owner 的属性写到 pod 上）也可以从第三方 http 服务获取（我自己有类似的需求）。

## 3.设计

`Kinitiras` 是来自希腊语 `κινητήρας (kini̱tí̱ras)`，意思为发动机（engine/motor），该项目的核心能力也是一个基于策略/规则的引擎，提供高效强大的能力。

### 3.1 基础概念

|概念 | 意义 | 说明 |
|:---|:---|:---|
|`validating` | 校验 | 验证资源对象的合法性 |
|`mutating` | 修改 | 修改资源对象的字段 |
| `policy` | 策略/规则 | 一条可执行的策略/规则 |
| `override policy` | 修改策略 | 表示用于修改资源的策略|
| `validate policy` | 校验策略 | 表示用于校验资源的策略|
| `cue` | cue 语言 | 是一个开源的可编程的 json 超集，[https://cuelang.org](https://cuelang.org) |

### 3.2 核心逻辑

kinitiras 核心逻辑如下：

1. 分别定义 validating 和 mutating 对应的 crd 表示一条策略（policy），记录策略生效的范围（指定资源名称或 label）和执行规则（校验或修改内容）
2. 注册统一的 webhook configuration，默认订阅所有带有特定 label 的资源的修改删除事件（安装时可自定义该配置）
3. 在收到 apiserver 的回调时，当前被修改的资源和已有的策略匹配筛选命中的策略列表
4. 按循序执行策略

{{< image src="engine-process.png" caption="策略引擎核心逻辑(流程中步骤 3 和步骤 4 标反了)" width="800" >}}

### 3.3 Api definition

本项目定义了三个 CRD：

- [OverridePolicy](https://doc.crds.dev/github.com/k-cloud-labs/pkg/policy.kcloudlabs.io/OverridePolicy/v1alpha1@v0.4.3): 用来修改资源信息（namespace 级别）
- [ClusterOverridePolicy](https://doc.crds.dev/github.com/k-cloud-labs/pkg/policy.kcloudlabs.io/ClusterOverridePolicy/v1alpha1@v0.4.3): 用来修改资源信息（cluster 级别）
- [ClusterValidatePolicy](https://doc.crds.dev/github.com/k-cloud-labs/pkg/policy.kcloudlabs.io/ClusterValidatePolicy/v1alpha1@v0.4.3): 用来校验资源信息（cluster 级别）

下面将定义的 crd 的核心部分简单讲解一下。

#### 3.3.1 Resource selector

ResourceSelector the resources will be selected.

| Field |type| required |Description|
|:--- | :---| :---:| :---|
|apiVersion | string | Y |APIVersion represents the API version of the target resources.|
|kind |string |Y |Kind represents the Kind of the target resources.|
|namespace|string| N |Namespace of the target resource. Default is empty, which means inherit from the parent object scope.|
|name |string|N|Name of the target resource. Default is empty, which means selecting all resources.|
|labelSelector|[Kubernetes meta/v1.LabelSelector](https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.24/#labelselector-v1-meta)|N|A label query over a set of resources. If name is not empty, labelSelector will be ignored.|
|fieldSelector |[FieldSelector](https://k-cloud-labs.github.io/kinitiras-doc/CRD/api-reference/#policy.kcloudlabs.io/v1alpha1.FieldSelector)|N|A field query over a set of resources. If name is not empty, fieldSelector wil be ignored.|

该结构是用于选择策略匹配资源，可以指定特定的某个资源，也可以选择指定 label 或 field 的方式对一组资源都生效。

for example:

```yaml
# match with all the pod which contains label webhook:enabled
resourceSelectors:
  - apiVersion: v1
    kind: Pod
    labelSelector:
      matchLabels:
        webhook: enabled
```

#### 3.3.2 Validate rule

Defines validate rules on operations.

| Field |type| required |Description|
|:--- | :---| :---:| :---|
|targetOperations |[[]Kubernetes admission/v1.Operation](https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.24/#operation-v1-admission)|Y|Operations is the operations the admission hook cares about - CREATE, UPDATE, DELETE, CONNECT or `*` for all of those operations and any future admission operations that are added. If `*` is present, the length of the slice must be one.|
|cue|string|N|Cue represents validate rules defined with cue code.|
|template |[ValidateRuleTemplate](https://k-cloud-labs.github.io/kinitiras-doc/CRD/api-reference/#policy.kcloudlabs.io/v1alpha1.ValidateRuleTemplate)|N|Template of condition which defines validate cond, and it will be rendered to CUE and store in RenderedCue field, so if there are any data added manually will be erased.|
|renderedCue |string | N |RenderedCue represents validate rule defined by Template. Don’t modify the value of this field, modify Rules instead of.|

这里是定义 validate 策略的执行逻辑相关信息。

- targetOperations：表示生效的操作类型，即可以定义只对创建 or delete 事件生效
- cue：该字段可填写一段 cue 代码，会在命中策略后执行该代码，请看下面 Example
- template：定义了一个简单的模板，将一些常见的校验常见模板化（无需写 cue 了）
- renderedCue：模板最终会自动渲染成 cue 代码并存储到该字段上。

cue example：

```yaml
validateRules:
# 这段代码表示，检查当前资源的 label 如果有不可删除的标识，则拒绝这次删除操作
- cue: |-
    object: _ @tag(object)
    reject: object.metadata.labels != null && object.metadata.labels["xxx.io/no-delete"] == "true"
    validate: {
        if reject{
                reason: "operation rejected"
        }
        if !reject{
                reason: ""
        }
        valid: !reject
    }
  targetOperations:
   - DELETE
```

template example:

```yaml
# 表示 存在 no-delete annotation 时 拒绝本次删除操作
validateRules:
- targetOperations:
    - DELETE
    template:
    type: condition # 当前只有 condition 一个类型，后续扩展
    condition:
        affectMode: reject # 表示命中该规则是拒绝，可以设置为 allow 表示只有命中时才准入，默认是 reject
        cond: Exist # 支持存在 不存在 大于 小于 等操作
        message: "cannot delete this ns" # 命中时返回的信息
        dataRef: # 校验的数据来源
          from: current # current 表示当前 object 中获取，支持从当前集群的其他资源或者通过 http 请求获取数据
          path: "/metadata/annotations/no-delete" # 数据 path
```

这种模板化的方式，可以减少学习 cue 的成本，能满足大部分判断字段是否存在，与其他字段做大小对比等场景。

#### 3.3.3 Override rule

Overriders offers various alternatives to represent the override rules.

If more than one alternative exist, they will be applied with following order:

- RenderCue
- Cue
- Plaintext

| Field |type| required |Description|
|:--- | :---| :---:| :---|
|plaintext |[[]PlaintextOverrider](https://k-cloud-labs.github.io/kinitiras-doc/CRD/api-reference/#policy.kcloudlabs.io/v1alpha1.PlaintextOverrider)|N |Plaintext represents override rules defined with plaintext overriders.|
|cue|string| N |Cue represents override rules defined with cue code.|
|template|[OverrideRuleTemplate](https://k-cloud-labs.github.io/kinitiras-doc/CRD/api-reference/#policy.kcloudlabs.io/v1alpha1.OverrideRuleTemplate)|N|Template of rule which defines override rule, and it will be rendered to CUE and store in RenderedCue field, so if there are any data added manually will be erased.|
|renderedCue|string|N|RenderedCue represents override rule defined by Template. Don’t modify the value of this field, modify Rules instead of.|

这里定义 Override policy 的核心部分，即修改资源信息策略，其含义如下：

- plaintext：为简单的修改方式，填写操作的字段和值即可
- cue：该字段可填写一段 cue 代码，会在命中策略后执行该代码，请看下面 Example
- template：定义了一个简单的模板，将一些常见的修改模板化（无需写 cue 了）
- renderedCue：模板最终会自动渲染成 cue 代码并存储到该字段上。

plaintext example：

```yaml
  overrideRules:
    - targetOperations:
        - CREATE
      overriders:
        plaintext: # 为数组，可同时修改多个字段值，会直接 apply 到对象上
          - path: /metadata/annotations/added-by
            op: add
            value: op
```

cue example:

```yaml
  overrideRules:
    - targetOperations:
        - CREATE
      overriders:
        # cue 部分，可以写相关逻辑，可以先判断当前 object 的值再进行操作，只要写入到 patches 的数组即可，可有多个
        cue: |-
          object: _ @tag(object)
          patches: [
            if object.metadata.annotations == _|_ {
              {
                op: "add"
                path: "/metadata/annotations"
                value: {}
              }
            },
            {
              op: "add"
              path: "/metadata/annotations/added-by"
              value: "cue"
            }
          ]
```

template example:

```yaml
# 对当前资源进行超卖，即修改资源的request为 limit * factor，从而可以达到集群内资源超卖的效果
overrideRules:
- targetOperations:
    - CREATE
    overriders:
        template:
            type: resourcesOversell # 以超售为例
            operation: replace # set remove to reset oversell
            resourcesOversell:
                cpuFactor: "0.5" # use half of limit / set 0 as placeholder when it needed remove
                memoryFactor: "0.2" # use 1/5 of limit
                diskFactor: "0.1" # use 1/10 of limit
```

以上展示的 template 只是实现的一部分，更多使用方式可以查看官网的例子，[点击跳转](https://k-cloud-labs.github.io/kinitiras-doc/usage/basic-usage/)

## 4.实现

上面把 kinitiras 的工作原理和核心概念进行了讲述，从这里开始将其核心能力的实现镜像简单的描述，方便使用时debug 或了解底层实现。

{{< admonition type=abstract title="项目结构" open=true >}}
项目整体来说分三个 repo，分别是 `kinitiras`, `pkg`, `pidalio`。每个 repo 的定位不同，其中 `kinitiras` 为比较常规的 webhook 项目，负责将自己注册到 apiserver，处理回调，`pkg`则为核心模块的实现，比如 api 定义，执行策略等。而 `pidalio` 为 client-go 的 transport 中间件，可以在客户端拦截请求执行策略的应用。本篇重点讲述前两个 repo 的核心实现。
{{< /admonition >}}

### 4.1 kinitiras

项目地址：[https://github.com/k-cloud-labs/kinitiras](https://github.com/k-cloud-labs/kinitiras)

本项目作为一个 webhook，核心逻辑就是，初始化各个参数和将自己注册到 apiserver，然后在回调函数里调用 `pkg` 提供的统一处理方法即可。

#### 4.1.2 初始化

```go
// Run runs the webhook server with options. This should never exit.
func Run(ctx context.Context, opts *options.Options) error {
    klog.InfoS("kinitiras webhook starting.", "version", version.Get())
    config, err := controllerruntime.GetConfig()
    if err != nil {
        panic(err)
    }
    config.QPS, config.Burst = opts.KubeAPIQPS, opts.KubeAPIBurst

    hookManager, err := controllerruntime.NewManager(config, controllerruntime.Options{
        // ... set options
    })
    if err != nil {
        klog.ErrorS(err, "failed to build webhook server.")
        return err
    }

    // init clients, informer, lister
    sm := &setupManager{}
    if err := sm.init(hookManager, ctx.Done()); err != nil {
        klog.ErrorS(err, "init setup manager failed")
        return err
    }

    if err := sm.waitForCacheSync(ctx); err != nil {
        klog.ErrorS(err, "wait for cache sync failed")
        return err
    }

    if err := sm.setupInterrupter(); err != nil {
        klog.ErrorS(err, "setup interrupter failed")
        return err
    }

    setupCh, err := cert.SetupCertRotator(hookManager, cert.Options{
        // ... set options
    })
    if err != nil {
        klog.ErrorS(err, "failed to setup cert rotator controller.")
        return err
    }

    go func() {
        <-setupCh

        // register handler here
        hookServer := hookManager.GetWebhookServer()
        hookServer.Register("/mutate", &webhook.Admission{Handler: pkgwebhook.NewMutatingAdmissionHandler(sm.overrideManager, sm.policyInterrupterManager)})
        hookServer.Register("/validate", &webhook.Admission{Handler: pkgwebhook.NewValidatingAdmissionHandler(sm.validateManager, sm.policyInterrupterManager)})
        hookServer.WebhookMux.Handle("/readyz", http.StripPrefix("/readyz", &healthz.Handler{}))
    }()

    // blocks until the context is done.
    if err := hookManager.Start(ctx); err != nil {
        klog.ErrorS(err, "webhook server exits unexpectedly.")
        return err
    }

    // never reach here
    return nil
}
```

上述代码比较常规，只有 `sm.setupInterrupter()` 这块单独说一下。本 webhook 自定义了几个 CRD 作为策略的载体，而策略本身也需要进行校验和修改，尤其是提供了模板化(`template`)后，模板需要渲染成 `cue` 脚本，为了能够在策略创建时进行校验和渲染，引进了 `interrupter`的概念。`Interrupter` 顾名思义 -- 拦截器，用来拦截策略并对策略的特定字段进行校验和对模版进行渲染，这些逻辑与常规的对象的校验和修改不太一样，因此不走普通的逻辑，只经过 `interrupter`的逻辑部分。而上述的的 `sm.setupInterrupter()` 是用来初始化这些 `interrupter` 的，代码如下：

```go

func (s *setupManager) setupInterrupter() error {
    // 初始化模板 -- 模板渲染是基于 go.tmpl 实现的，因此这里初始化 tmpl
    otm, err := templatemanager.NewOverrideTemplateManager(&templatemanager.TemplateSource{
        Content:      templates.OverrideTemplate,
        TemplateName: "BaseTemplate",
    })
    if err != nil {
        klog.ErrorS(err, "failed to setup mutating template manager.")
        return err
    }

    // 初始化模板 -- 模板渲染是基于 go.tmpl 实现的，因此这里初始化 tmpl
    vtm, err := templatemanager.NewValidateTemplateManager(&templatemanager.TemplateSource{
        Content:      templates.ValidateTemplate,
        TemplateName: "BaseTemplate",
    })
    if err != nil {
        klog.ErrorS(err, "failed to setup validate template manager.")
        return err
    }

    // base
    baseInterrupter := interrupter.NewBaseInterrupter(otm, vtm, templatemanager.NewCueManager())

    // op
    overridePolicyInterrupter := interrupter.NewOverridePolicyInterrupter(baseInterrupter, s.tokenManager, s.client, s.opLister)
    // register interrupter to manager
    s.policyInterrupterManager.AddInterrupter(schema.GroupVersionKind{
        Group:   policyv1alpha1.SchemeGroupVersion.Group,
        Version: policyv1alpha1.SchemeGroupVersion.Version,
        Kind:    "OverridePolicy",
    }, overridePolicyInterrupter)
    // cop
    s.policyInterrupterManager.AddInterrupter(schema.GroupVersionKind{
        Group:   policyv1alpha1.SchemeGroupVersion.Group,
        Version: policyv1alpha1.SchemeGroupVersion.Version,
        Kind:    "ClusterOverridePolicy",
    }, interrupter.NewClusterOverridePolicyInterrupter(overridePolicyInterrupter, s.copLister))
    // cvp
    s.policyInterrupterManager.AddInterrupter(schema.GroupVersionKind{
        Group:   policyv1alpha1.SchemeGroupVersion.Group,
        Version: policyv1alpha1.SchemeGroupVersion.Version,
        Kind:    "ClusterValidatePolicy",
    }, interrupter.NewClusterValidatePolicyInterrupter(baseInterrupter, s.tokenManager, s.client, s.cvpLister))

    return s.policyInterrupterManager.OnStartUp()
}
```

#### 4.1.2 admission handler

再来看看，注册的 handler 的逻辑了具体干了什么？

以 mutating 为例：

```go
func (a *MutatingAdmission) Handle(ctx context.Context, req admission.Request) admission.Response {
    obj, oldObj, err := decodeObj(a.decoder, req)
    if err != nil {
        return admission.Errored(http.StatusBadRequest, err)
    }

    newObj := obj.DeepCopy()
    // if obj is known policy, then run policy interrupter
    // 这里先调用拦截器逻辑，内部识别是否为已知的策略 crd 以及是否需要对其进行模版渲染等
    patches, err := a.policyInterrupterManager.OnMutating(newObj, oldObj, req.Operation)
    if err != nil {
        return admission.Errored(http.StatusInternalServerError, err)
    }

    // 如果有需要修改的信息，则以 patches 的形式返回，这里就确定是已知的 crd，打 patch
    if len(patches) != 0 {
        klog.V(4).InfoS("patches for policy", "policy", obj.GroupVersionKind(), "patchesCount", len(patches))
        // patch data
        patchedObj, err := json.Marshal(newObj)
        if err != nil {
            return admission.Errored(http.StatusInternalServerError, err)
        }

        return admission.PatchResponseFromRaw(req.Object.Raw, patchedObj)
    }

    // 其他资源或当前策略crd
    // 这里是另一个核心点，匹配&&执行 策略
    cops, ops, err := a.overrideManager.ApplyOverridePolicies(newObj, oldObj, req.Operation)
    if err != nil {
        return admission.Errored(http.StatusInternalServerError, err)
    }

    if req.Operation == admissionv1.Delete {
        return admission.Allowed("")
    }

    patchedObj, err := json.Marshal(newObj)
    if err != nil {
        return admission.Errored(http.StatusInternalServerError, err)
    }

    return admission.PatchResponseFromRaw(req.Object.Raw, patchedObj)
}
```

到这里为止，`kinitiras` 的核心逻辑基本讲述完毕，他的职责就是初始化，注册，并把回调请求引导到已实现的处理方法里，这些处理方法均由 `pkg` 项目来实现的。

### 4.2 pkg

项目地址： [https://github.com/k-cloud-labs/pkg](https://github.com/k-cloud-labs/pkg)

`pkg` 包含了大部分逻辑的实现，同时也包含了 crd 的定义和生成的 client 代码。接上面的提到的内容，这里主要讲述`interrupter`的实现部分和策略的命中和执行部分。

#### 4.2.1 interrupter

先看定义:

```go
// PolicyInterrupterManager manage multi PolicyInterrupter and decide which one to use by gvk.
type PolicyInterrupterManager interface {
    PolicyInterrupter
    // AddInterrupter add a PolicyInterrupter to manager,
    //  it will replace interrupter if already add with same gvk.s
    AddInterrupter(gvk schema.GroupVersionKind, pi PolicyInterrupter)
}

// PolicyInterrupter defines interrupt process for policy change
// It validate and mutate policy.
type PolicyInterrupter interface {
    // OnMutating called on "/mutating" api to complete policy
    // return nil means obj is not defined policy
    OnMutating(obj, oldObj *unstructured.Unstructured, operation admissionv1.Operation) ([]jsonpatchv2.JsonPatchOperation, error)
    // OnValidating called on "/validating" api to validate policy
    // return nil means obj is not defined policy or no invalid field
    OnValidating(obj, oldObj *unstructured.Unstructured, operation admissionv1.Operation) error
    // OnStartUp called when webhook process initialize
    // return error if initial phase get any error
    OnStartUp() error
}
```

`PolicyInterrupterManager` 继承了 `PolicyInterrupter` 并新增一个添加 interrupter 的方法，用来管理多个 interrupter。而每一个 interrupter 都会实现下面的三个方法：

- OnMutating: 在 apiserver 回调 `/mutating` 接口时调用，主要用来渲染和补充策略信息
- OnValidating: 在 apiserver 回调 `/validating` 接口时调用，主要用来校验策略信息
- OnStartUp: 在 webhook 启动阶段调用，可做一些初始化工作（拉取缓存等）

而 manager 的实现与实际 interrupter 不同，它首先识别当前的资源是不是我们定义的策略 crd，然后从内存找有没有对应的注册的 interrupter 再去调用该 interrupter 的对应方法。代码如下：

```go

type policyInterrupterManagerImpl struct {
    interrupters sync.Map
}

func (p *policyInterrupterManagerImpl) OnValidating(obj, oldObj *unstructured.Unstructured, operation admissionv1.Operation) error {
    if interrupter := p.getInterrupter(obj); interrupter != nil {
        return interrupter.OnValidating(obj, oldObj, operation)
    }

    return nil
}

func (p *policyInterrupterManagerImpl) getInterrupter(obj *unstructured.Unstructured) PolicyInterrupter {
    if !p.isKnownPolicy(obj) {
        klog.V(5).InfoS("unknown policy", "gvk", obj.GroupVersionKind())
        return nil
    }

    i, ok := p.interrupters.Load(obj.GroupVersionKind())
    if ok {
        klog.V(4).InfoS("sub interrupter found", "gvk", obj.GroupVersionKind())
        return i.(PolicyInterrupter)
    }

    return nil
}

func (p *policyInterrupterManagerImpl) isKnownPolicy(obj *unstructured.Unstructured) bool {
    group := strings.Split(obj.GetAPIVersion(), "/")[0]
    return group == policyv1alpha1.SchemeGroupVersion.Group
}
```

#### 4.2.2 渲染

渲染这个事儿前面已经提了无数遍，这里将一次性将渲染相关的设计和实现都讲清楚。

**先说背景。**

本项目在早期就支持了用户手写 cue 的方式在策略中执行复杂逻辑，从而满足不同的需求。但是写 cue 需要对这个语言的语法和特性有一定了解加上没有比较好的验证 cue 脚本合法性的机制，导致上手难度比较高，因此想到了把一些常见的情况抽象出来一个结构化的模板，使用者只需要在模板填写必要的参数，由 webhook 本身把这个模板翻译成 cue 脚本。

为了能够将结构化数据翻译成 cue 脚本，我们写了一个比较复杂的 `go/tmpl` ([template link](https://github.com/k-cloud-labs/pkg/tree/main/utils/templatemanager/templates))，然后继续翻译。流程如下：

1. interrupter 检查是否填写模板信息
2. 根据模板类型进行渲染(tmpl.Execute) 生成 cue 脚本
3. 对结果进行 format 和 lint 检查

这个过程被称之为`渲染`。

**再说实现。**

由于相关模板和代码比较多，这里不进行展示，只把核心实现进行说明：

1. 为不同的 policy 写了不同的 `tmpl`。由于 validate 和 override 策略的 cue 执行结果的结构要求不同，因此写了两份 `tmpl` 根据 policy 去执行不同的渲染。[code link](https://github.com/k-cloud-labs/pkg/blob/main/utils/templatemanager/templatemanager.go)
2. 使用 cue 官方提供的 go package 进行 format 和 lint。cue 底层是 go 语言实现的，因此对 go 的支持比较友好，提供了相关 package，可以在代码中直接 format 和 lint cue 脚本，确保渲染后后的 cue 脚本时合法可运行的。[code link](https://github.com/k-cloud-labs/pkg/blob/main/utils/templatemanager/cuemanager.go)

#### 4.2.3 策略命中

当前 object 和策略的匹配过程如下：

1. 列出当前所有的策略。这块从 informer 内存读取，且根据当前是 validating 还是 mutating 的情况读取相对应的 policy 列表。
2. 对于没有设置 resource selector 的策略，默认认为命中。
3. 对于设置 resource selector 的策略，进行策略匹配（代码下面会展示。）
4. 再对命中的策略中设置操作类型与当前 object 的操作类型进行匹配。
5. 匹配完成。

resource selector 匹配规则：

*any means no matter if it's empty or not*

| name | label selector | field selector | result |
|:---- |:----          |:----          |:----   |
| not empty | any       | any       | match name only |
| empty     | empty     | empty     | match all |
| empty     | not empty | empty     | match labels only |
| empty     | empty     | not empty | match fields only |
| empty     | not empty | not empty | match both labels and fields |

相关代码：

```go
// ResourceMatchSelectors tells if the specific resource matches the selectors.
func ResourceMatchSelectors(resource *unstructured.Unstructured, selectors ...policyv1alpha1.ResourceSelector) bool {
    for _, rs := range selectors {
        // 一个策略可以配置多个 selector，只要其中任意一个命中即可
        if ResourceMatches(resource, rs) {
            return true
        }
    }
    return false
}

// ResourceMatches tells if the specific resource matches the selector.
func ResourceMatches(resource *unstructured.Unstructured, rs policyv1alpha1.ResourceSelector) bool {
    if resource.GetAPIVersion() != rs.APIVersion ||
        resource.GetKind() != rs.Kind ||
        (len(rs.Namespace) > 0 && resource.GetNamespace() != rs.Namespace) {
        return false
    }

    // name not empty, don't need to consult selector.
    if len(rs.Name) > 0 {
        return rs.Name == resource.GetName()
    }

    // all empty, matches all
    if rs.LabelSelector == nil && rs.FieldSelector == nil {
        return true
    }

    // matches with field selector
    if rs.FieldSelector != nil {
        match, err := rs.FieldSelector.MatchObject(resource)
        if err != nil {
            klog.ErrorS(err, "match fields failed")
            return false
        }

        if !match {
            // return false if not match
            return false
        }
    }

    // matches with selector
    if rs.LabelSelector != nil {
        var s labels.Selector
        var err error
        if s, err = metav1.LabelSelectorAsSelector(rs.LabelSelector); err != nil {
            // should not happen because all resource selector should be fully validated by webhook.
            klog.ErrorS(err, "match labels failed")
            return false
        }

        return s.Matches(labels.Set(resource.GetLabels()))
    }

    return true
}
```

#### 4.2.4 策略执行

在上一步命中策略后，会将这批策略进行一次字典排序然后按顺序执行，而执行过程根据每个策略的配置的规则进行。流程如下（以 Override 策略为例）：

1. 检查是否配置模板且已渲染完成，如果是 则执行 cue 脚本

{{< admonition type=note title="关于执行渲染后 cue 执行" open=true >}}
模板支持引用当前 object 或集群内其他 object 甚至外部 http 接口数据，因此在执行 cue 之前需要判断引用了哪些数据并提前准备好相关数据（即获取 object 或 请求 http 获取响应 body）

```go
func BuildCueParamsViaOverridePolicy(c dynamiclister.DynamicResourceLister, curObject *unstructured.Unstructured, tmpl *policyv1alpha1.OverrideRuleTemplate) (*CueParams, error) {
    var (
        cp = &CueParams{
            ExtraParams: make(map[string]any),
        }
    )
    if tmpl.ValueRef != nil {
        klog.V(2).InfoS("BuildCueParamsViaOverridePolicy value ref", "refFrom", tmpl.ValueRef.From)
        if tmpl.ValueRef.From == policyv1alpha1.FromOwnerReference { // 引用 owner，如 pod 的 owner 为 replicaset
            obj, err := getOwnerReference(c, curObject)
            if err != nil {
                return nil, fmt.Errorf("getOwnerReference got error=%w", err)
            }
            cp.ExtraParams["otherObject"] = obj
        }
        if tmpl.ValueRef.From == policyv1alpha1.FromK8s { // 引用当前集群其他 object
            obj, err := getObject(c, curObject, tmpl.ValueRef.K8s)
            if err != nil {
                return nil, fmt.Errorf("getObject got error=%w", err)
            }
            cp.ExtraParams["otherObject"] = obj
        }

        if tmpl.ValueRef.From == policyv1alpha1.FromHTTP { // 引用 http 数据
            obj, err := getHttpResponse(nil, curObject, tmpl.ValueRef.Http)
            if err != nil {
                return nil, fmt.Errorf("getHttpResponse got error=%w", err)
            }
            cp.ExtraParams["http"] = obj
        }
    }

    return cp, nil
}
```

{{< /admonition >}}

执行 cue 脚本：

```go
// applyPolicyOverriders applies OverridePolicy/ClusterOverridePolicy overriders to target object
func (o *overrideManagerImpl) applyPolicyOverriders(rawObj, oldObj *unstructured.Unstructured, p policyOverriders) error {
    policyName := p.name
    if p.namespace != "" {
        policyName = p.namespace + "/" + p.name
    }
    if p.overriders.Template != nil && p.overriders.RenderedCue != "" {
        cp, err := cue.BuildCueParamsViaOverridePolicy(o.dynamicLister, rawObj, p.overriders.Template)
        if err != nil {
            metrics.PolicyGotError(policyName, rawObj.GroupVersionKind(), metrics.ErrTypePrepareCueParams)
            return fmt.Errorf("BuildCueParamsViaOverridePolicy error=%w", err)
        }
        cp.Object = rawObj
        cp.OldObject = oldObj
        if cp.OldObject == nil {
            cp.OldObject = &unstructured.Unstructured{Object: map[string]interface{}{}}
        }
        params := []cue.Parameter{
            {
                Object: cp,
                Name:   utils.DataParameterName,
            },
        } // 该参数将传参到 cue 中，从而达到 cue 内引入外部数据

        patches, err := executeCueV2(p.overriders.RenderedCue, params)
        if err != nil {
            metrics.PolicyGotError(policyName, rawObj.GroupVersionKind(), metrics.ErrorTypeCueExecute)
            return err
        }

        // 执行后可获取cue 内部的所有定义的数据，我们只取 patches 这个数组
        if len(patches) > 0 {
            metrics.OverridePolicyOverride(policyName, rawObj.GroupVersionKind())
        }

        if err := applyJSONPatch(rawObj, patches); err != nil {
            return err
        }
    }

    // ... ignore code
}    
```

cue example:

```go
// simple cue code
data: _ @tag(data)
object := data.object

patches: [
    if object.metadata.annotations == _|_ {
        {
        op: "add"
        path: "/metadata/annotations"
        value: {}
        }
    },
    {
        op: "add"
        path: "/metadata/annotations/added-by"
        value: "cue"
    }
]
```

2. 检查是否配置自定义的 cue 脚本，如果有 则执行

```go
// applyPolicyOverriders applies OverridePolicy/ClusterOverridePolicy overriders to target object
func (o *overrideManagerImpl) applyPolicyOverriders(rawObj, oldObj *unstructured.Unstructured, p policyOverriders) error {
    // ...ignore code
    if p.overriders.Cue != "" {
        // 用户自定义 cue 脚本只传参当前 object 不支持引用外部 object
        patches, err := executeCue(rawObj, p.overriders.Cue)
        if err != nil {
            metrics.PolicyGotError(policyName, rawObj.GroupVersionKind(), metrics.ErrorTypeCueExecute)
            return err
        }
        if patches != nil && len(*patches) > 0 {
            metrics.OverridePolicyOverride(policyName, rawObj.GroupVersionKind())
        }
        if err := applyJSONPatch(rawObj, *patches); err != nil {
            return err
        }
    }

    // ...ignore code
}

```

3. 检查是否配置 plaintext 形式的 patch， 如果有则直接 apply

```go
// applyPolicyOverriders applies OverridePolicy/ClusterOverridePolicy overriders to target object
func (o *overrideManagerImpl) applyPolicyOverriders(rawObj, oldObj *unstructured.Unstructured, p policyOverriders) error {
    // ...ignore code
    return applyJSONPatch(rawObj, parseJSONPatchesByPlaintext(p.overriders.Plaintext))
}

```

## 5.总结

本篇介绍了 `k-cloud-labs` 推出的 webhook 产品，其功能和实用性方面都非常优秀，我现在作为该项目的其中一个维护者 对项目进行了一定的特性增加和优化，后期将持续更新新的能力，解决更多的问题。

主要内容：

- 介绍了开发该 webhook 的背景和其解决的问题
- 介绍了核心设计思路和 api 定义
- 介绍了其核心逻辑的实现

关于更详细的设计细节和使用案例以及安装方法，请[点击这里跳转](https://k-cloud-labs.github.io/kinitiras-doc/)官网去了解。

## 6.链接🔗

- 官方：[https://k-cloud-labs.github.io/kinitiras-doc/](https://k-cloud-labs.github.io/kinitiras-doc/)
- Github：[https://github.com/k-cloud-labs](https://github.com/k-cloud-labs)

