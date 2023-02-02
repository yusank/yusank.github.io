# Policy based kubernetes admission webhook part 1


> A lightweight but powerful and programmable rule engine for kubernetes admission webhook called `kinitiras` powered by `k-cloud-labs`.

<!--more-->

## 1.Background

{{< admonition type=quote title="Definition" open=true >}}
Admission webhooks are HTTP callbacks that receive admission requests and do something with them. You can define two types of admission webhooks, `validating admission webhook` and `mutating admission webhook`. Mutating admission webhooks are `invoked first`, and can modify objects sent to the API server to enforce custom defaults.

After all object modifications are complete, and after the incoming object is validated by the API server, validating admission webhooks are invoked and can reject requests to enforce custom policies.

{{< /admonition >}}

The above is the definition given by kubernetes. In short, k8s webhooks are divided into two categories `validating` and `mutating` for verifying and modifying k8s resource modification operations, respectively. When a user creates or modifies a resource, the `apiserver` calls (http) the registered `validating` and `mutating` webhooks and does not actually process the modification until after the response of these webhooks.

{{< image src="webhook-process.png" caption="Process" width="800" >}}

For those who are familiar with cloud native development or k8s, webhook should be a very familiar component and should have written more or less relevant code. As a native capability of k8s, the current webhook development/use approach is very unfriendly and primitive. While many of the k8s capabilities can be achieved by modifying existing objects or CRD information (e.g., updating images, rolling upgrades, etc.), webhook requires code to be developed and registered to the `apiserver` and run to achieve the purpose.

However, in daily development, most of the requirements for webhook are limited to some simple capabilities, such as verifying the fields and legality of certain objects, modifying the information of specific objects (label, annotation or modifying resource specifications, etc.), which leads to the need for development to package and release the code every time new requirements are added or modified. This makes the whole process inefficient, and there are too many webhooks registered in a cluster to make the apiserver's response time longer and less reliable.

In order to solve these problems, we developed a new set of rule-based programmable webhooks -- [kinitiras](https://github.com/k-cloud-labs/kinitiras), hoping to replace all the webhooks in a cluster with this component and all the requirements. We hope to use this component to replace all the webhooks in the cluster and all the requirements can be solved by this component without developing new webhooks, improving efficiency and reducing the security risks caused by multiple webhooks.

## 2.Ability

{{< image src="kinitiras.org.png" caption="Feature overview" width="800" >}}

First, lets talk about what this webhook can do.

### 2.1 Validate resources

[Policy example](https://k-cloud-labs.github.io/kinitiras-doc/usage/basic-usage/#clustervalidatepolicy)

We can configure different policies for different resources to reduce the occurrence of some uncontrollable situations or to restrict some special operations, for example.

- For create update operations, some fields of the resource can be restricted (not null or with values equal to or not equal to the specified value, etc.)
- Restrict update or delete operations. For some specific resources (ns or deployment), you can prohibit deletion or secondary confirmation mechanism (deletion is allowed only if the specified annotation exists)
- Field validation

The fields and values of these checks can be the value of the current object or the value of other objects (e.g., compared with other objects such as `cm` or `secret`), and the data obtained by third-party http services can be checked.

### 2.2 Mutate resources

[Policy example](https://k-cloud-labs.github.io/kinitiras-doc/usage/basic-usage/#overridepolicy)

For modifying resources, our strategy can be configured for many different scenarios to meet different needs, such as

- Uniformly add label or annotation to resources.
- Modify the pod resource of limit or request.
- modify the affinity toleration of the resource, etc.

The modified values can be dynamic and can be obtained from other objects (e.g., writing the owner's properties to the pod) or from third-party http services (I have similar needs myself).

## 3.Design

`Kinitiras` is from the Greek `κινητήρας (kini̱tí̱ras)`, meaning engine/motor, and the core capability of the project is also a rules-based engine that provides efficient and powerful capabilities.

### 3.1 Basic concept

|Concept | Explain |
|:---|:---|
|`validating`  | Verifying the legitimacy of objects |
|`mutating` | Modifying objects info |
| `policy`  | a crd object contains rules |
| `override policy` | policy contains mutate object rules|
| `validate policy` | policy contains validate object rules|
| `cue` | an open source program language，[https://cuelang.org](https://cuelang.org) |

### 3.2 Core logic

Here is the core logic of kinitiras：

1. Define the crd corresponding to validating and mutating to represent a policy, record the scope of the policy (specified resource name or label) and the execution rules (verify or modify the content)
2. register a unified webhook configuration and subscribe to all modification and deletion events for resources with a specific label by default (you can customize this configuration during installation)
3. when receiving a callback from apiserver, the current modified resource and the existing policy match to filter the list of hit policies
4. execute policies in a sequential manner

{{< image src="engine-process.png" caption="policy engine core logic(step 3 and step 4 had marked reversely)" width="800" >}}

### 3.3 Api definition

This project has defined three CRD:

- [OverridePolicy](https://doc.crds.dev/github.com/k-cloud-labs/pkg/policy.kcloudlabs.io/OverridePolicy/v1alpha1@v0.4.3): mutate object info(namespace level)
- [ClusterOverridePolicy](https://doc.crds.dev/github.com/k-cloud-labs/pkg/policy.kcloudlabs.io/ClusterOverridePolicy/v1alpha1@v0.4.3): mutate object info(cluster level)
- [ClusterValidatePolicy](https://doc.crds.dev/github.com/k-cloud-labs/pkg/policy.kcloudlabs.io/ClusterValidatePolicy/v1alpha1@v0.4.3): validate object info(cluster level)

Now, lets talk about core part of those CRDs.

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

This structure is used to select a policy to match a resource, either by specifying a particular resource, or by specifying a label or field to take effect for a group of resources.

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

Here is the information that defines the execution logic of the validate policy.

- targetOperations: indicates the type of operation that will take effect, i.e., it can be defined to take effect only for create or delete events
- cue: This field can be filled with a cue code, which will be executed after the policy is hit, see the following Example
- template: defines a simple template that templates some common checks (no need to write a cue anymore)
- renderedCue: the template will eventually be automatically rendered into cue code and stored on this field.

cue example：

```yaml
validateRules:
# This code means, if object has a label `xxx.io/no-delete:true` then reject the delete operation.
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
# It means, it will reject the delete operation if there is a no-delete annotation
validateRules:
- targetOperations:
    - DELETE
    template:
    type: condition # Only one type now, will extend in the future.
    condition:
        affectMode: reject # It means reject the operation if it hit this rule. Can set it to allow to allow the operation only if it hit this rule.
        cond: Exist # Support Exist, NoExist, In, NotIn, Gt, Lt, etc.
        message: "cannot delete this ns" # message when reject
        dataRef: # specify the data source
          from: current # It means get data from current object, also can get it from other object from current cluster.
          path: "/metadata/annotations/no-delete" # data path
```

This templated approach can reduce the cost of learning cue and can satisfy most scenarios such as determining whether a field exists and doing size comparison with other fields.

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

The core part of the Override policy is defined here, i.e. the modification of resource information policy, which means the following.

- plaintext: This is a simple modification method, just fill in the fields and values of the operation
- cue: this field can be filled with a cue code, which will be executed after the policy is hit, see the following Example
- template: defines a simple template that templates some common modifications (no need to write a cue anymore)
- renderedCue: the template will eventually be automatically rendered into cue code and stored on this field.

plaintext example：

```yaml
  overrideRules:
    - targetOperations:
        - CREATE
      overriders:
        plaintext:
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
# Oversell current object resource, set resources.requests to limit * factor
overrideRules:
- targetOperations:
    - CREATE
    overriders:
        template:
            type: resourcesOversell # Also support other types now.
            operation: replace # set remove to reset oversell
            resourcesOversell:
                cpuFactor: "0.5" # use half of limit / set 0 as placeholder when it needed remove
                memoryFactor: "0.2" # use 1/5 of limit
                diskFactor: "0.1" # use 1/10 of limit
```

The template shown above is only a part of the implementation, for more usage you can check the examples on the official website, [click to jump](https://k-cloud-labs.github.io/kinitiras-doc/usage/basic-usage/)

## 4.Implement

The above describes how kinitiras works and the core concepts, from here on the implementation of its core capabilities are briefly described, so that it is easy to debug or understand the underlying implementation when using it.

{{< admonition type=abstract title="Project structure" open=true >}}
The project as a whole is divided into three repo's, namely `kinitiras`, `pkg`, and `pidalio`. Each repo is positioned differently, where `kinitiras` is a more conventional webhook project, responsible for registering itself to the apiserver and handling callbacks, and `pkg` is the implementation of the core modules, such as api definitions, execution policies, and so on. And `pidalio` is the transport middleware for client-go, which can intercept requests and execute policy applications on the client side. This article focuses on the core implementation of the first two repo's.
{{< /admonition >}}

### 4.1 kinitiras

Repo URL: [https://github.com/k-cloud-labs/kinitiras](https://github.com/k-cloud-labs/kinitiras)

The core logic of this project, as a webhook, is to initialize the parameters and register itself to the apiserver, and then call the unified processing method provided by `pkg` in the callback function.

#### 4.1.2 Initialize

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

The above code is quite conventional, only `sm.setupInterrupter()` is mentioned separately. The webhook defines several CRDs as the carrier of the policy, and the policy itself needs to be verified and modified, especially after providing a template (`template`), which needs to be rendered into a `cue` script, so the concept of `interrupter` is introduced in order to be able to verify and render the policy when it is created. `Interrupter`, as the name suggests -- an interceptor, is used to intercept the policy and perform checks on specific fields of the policy and rendering of the template, these logic is not quite the same as the regular object checks and modifications, so it does not go through the ordinary logic, but only through the logical part of `interrupter`. And the above `sm.setupInterrupter()` is used to initialize these `interrupters` with the following code.

```go
func (s *setupManager) setupInterrupter() error {
    // Init template -- render template is implemented based on go tmpl.
    otm, err := templatemanager.NewOverrideTemplateManager(&templatemanager.TemplateSource{
        Content:      templates.OverrideTemplate,
        TemplateName: "BaseTemplate",
    })
    if err != nil {
        klog.ErrorS(err, "failed to setup mutating template manager.")
        return err
    }

    // validate template same as above.
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

Now, lets take a look to the registered handler.

Take mutating as an example：

```go
func (a *MutatingAdmission) Handle(ctx context.Context, req admission.Request) admission.Response {
    obj, oldObj, err := decodeObj(a.decoder, req)
    if err != nil {
        return admission.Errored(http.StatusBadRequest, err)
    }

    newObj := obj.DeepCopy()
    // It will check the object kind then handle it in interrupter.
    patches, err := a.policyInterrupterManager.OnMutating(newObj, oldObj, req.Operation)
    if err != nil {
        return admission.Errored(http.StatusInternalServerError, err)
    }

    if len(patches) != 0 {
        // It means current object is a known policy and there are some changes(probably rendered cue) need to apply.
        klog.V(4).InfoS("patches for policy", "policy", obj.GroupVersionKind(), "patchesCount", len(patches))
        // patch data
        patchedObj, err := json.Marshal(newObj)
        if err != nil {
            return admission.Errored(http.StatusInternalServerError, err)
        }

        return admission.PatchResponseFromRaw(req.Object.Raw, patchedObj)
    }

    // Other objects or policy no need to change
    // It will match with policies and execute it.
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

Here, the core logic of `kinitiras` is basically finished, his responsibility is to initialize, register, and direct callback requests to the implemented processing methods, which are implemented by the `pkg` project.

### 4.2 pkg

Repo URL: [https://github.com/k-cloud-labs/pkg](https://github.com/k-cloud-labs/pkg)

The `pkg` contains most of the logic implementation, as well as the definition of the crd and the generated client code. Following the above, we will focus on the implementation of `interrupter` and the hitting and execution of the policy.

#### 4.2.1 interrupter

definition:

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

`PolicyInterrupterManager` inherits from `PolicyInterrupter` and adds a method to add interrupters to manage multiple interrupters, and each interrupter implements the following three methods.

- OnMutating: Called when the apiserver calls back the `/mutating` interface, mainly to render and supplement policy information
- OnValidating: called when the apiserver calls back the `/validating` interface, mainly to validate policy information
- OnStartUp: called during the webhook startup phase to do some initialization work (pulling cache, etc.)

The implementation of manager is different from the actual interrupter, it first identifies if the current resource is the policy crd we defined, then looks for a corresponding registered interrupter from memory and calls the corresponding method of that interrupter. The code is as follows.

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

#### 4.2.2 Render

The matter of rendering has been mentioned few times before, now lets talk about it.

**About background.**

The project has supported the user to write cue by hand to execute complex logic in the strategy to meet different needs in the early days. However, writing cue requires some knowledge of the syntax and features of the language and there is no good mechanism to verify the legitimacy of cue scripts, which makes it difficult to get started, so we came up with the idea of abstracting some common cases into a structured template, where the user only needs to fill in the necessary parameters, and webhook itself translates the template into cue scripts.

To be able to translate structured data into cue scripts, we wrote a more complex `go/tmpl` ([template link](https://github.com/k-cloud-labs/pkg/tree/main/utils/templatemanager/ templates)), and then proceeded to translate it. The process is as follows.

1. interrupter checks if template information is filled in
2. render according to the template type (tmpl.Execute) to generate the cue script
3. format and lint check the result

This process is called `render`.

**About implement.**

Since there are more related templates and code, instead of showing them here, only the core implementation is illustrated.

1. different `tmpl`s are written for different policies. Since the structure of cue execution results for validate and override policies are different, two `tmpl`s are written to perform different rendering according to the policy. [code link](https://github.com/k-cloud-labs/pkg/blob/main/utils/templatemanager/templatemanager.go) 2.
2. use the official go package provided by cue for formatting and lint. cue is implemented in the go language, so it is friendly to go and provides a package for formatting and linting cue scripts directly in the code to ensure that the rendered cue scripts are legal and runnable. [code link](https://github.com/k-cloud-labs/pkg/blob/main/utils/templatemanager/cuemanager.go)

#### 4.2.3 How to match with policies

The matching process between the current object and the policy is as follows.

1. List all current policies. This is read from informer memory, and the corresponding policy list is read depending on whether it is currently validating or mutating.
2. For policies that do not have a resource selector set, the policy is considered a hit by default.
3. for policies with resource selector set, perform policy matching (code will be shown below.)
4. Match the operation type of the hit policy with the operation type of the current object.
5. Matching is done.

Resource selector matching rules.

*any means no matter if it's empty or not.*

| name | label selector | field selector | result |
|:---- |:----          |:----          |:----   |
| not empty | any       | any       | match name only |
| empty     | empty     | empty     | match all |
| empty     | not empty | empty     | match labels only |
| empty     | empty     | not empty | match fields only |
| empty     | not empty | not empty | match both labels and fields |

Related code:

```go
// ResourceMatchSelectors tells if the specific resource matches the selectors.
func ResourceMatchSelectors(resource *unstructured.Unstructured, selectors ...policyv1alpha1.ResourceSelector) bool {
    for _, rs := range selectors {
        // A policy can config multi resource selector
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

#### 4.2.4 How to execute policies

After the policy is hit in the previous step, the policies are sorted in a dictionary and then executed in order, while the execution process is based on the rules configured for each policy. The process is as follows (using the Override policy as an example).

1. check if the template is configured and rendered, and if so, execute the cue script

{{< admonition type=note title="About cue execution after execution rendering" open=true >}}
The template supports referencing the current object or other objects in the cluster or even external http interface data, so you need to determine what data is referenced and prepare the data in advance before executing cue (i.e., get the object or request http for the response body)

```go
func BuildCueParamsViaOverridePolicy(c dynamiclister.DynamicResourceLister, curObject *unstructured.Unstructured, tmpl *policyv1alpha1.OverrideRuleTemplate) (*CueParams, error) {
    var (
        cp = &CueParams{
            ExtraParams: make(map[string]any),
        }
    )
    if tmpl.ValueRef != nil {
        klog.V(2).InfoS("BuildCueParamsViaOverridePolicy value ref", "refFrom", tmpl.ValueRef.From)
        if tmpl.ValueRef.From == policyv1alpha1.FromOwnerReference {
            obj, err := getOwnerReference(c, curObject)
            if err != nil {
                return nil, fmt.Errorf("getOwnerReference got error=%w", err)
            }
            cp.ExtraParams["otherObject"] = obj
        }
        if tmpl.ValueRef.From == policyv1alpha1.FromK8s {
            obj, err := getObject(c, curObject, tmpl.ValueRef.K8s)
            if err != nil {
                return nil, fmt.Errorf("getObject got error=%w", err)
            }
            cp.ExtraParams["otherObject"] = obj
        }

        if tmpl.ValueRef.From == policyv1alpha1.FromHTTP {
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

Execute cue script:

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
        } // This params will pass to cue, so cue can refer data from go code.

        patches, err := executeCueV2(p.overriders.RenderedCue, params)
        if err != nil {
            metrics.PolicyGotError(policyName, rawObj.GroupVersionKind(), metrics.ErrorTypeCueExecute)
            return err
        }

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

2. Check if a custom cue script is configured, and if so, execute

```go
// applyPolicyOverriders applies OverridePolicy/ClusterOverridePolicy overriders to target object
func (o *overrideManagerImpl) applyPolicyOverriders(rawObj, oldObj *unstructured.Unstructured, p policyOverriders) error {
    // ...ignore code
    if p.overriders.Cue != "" {
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

3. Check if the plaintext form of patch is configured, and if so, apply it directly

```go
// applyPolicyOverriders applies OverridePolicy/ClusterOverridePolicy overriders to target object
func (o *overrideManagerImpl) applyPolicyOverriders(rawObj, oldObj *unstructured.Unstructured, p policyOverriders) error {
    // ...ignore code
    return applyJSONPatch(rawObj, parseJSONPatchesByPlaintext(p.overriders.Plaintext))
}

```

## 5.Summarize

This article introduces the webhook product launched by `k-cloud-labs`, which is excellent in terms of functionality and usability. I am now working as one of the maintainers of the project to add and optimize certain features to the project, and will continue to update new capabilities and solve more problems later.

Main content.

- Introduced the background of developing the webhook and the problem it solves
- Introduced the core design ideas and api definitions
- Introduces the implementation of the core logic

For more detailed design details and use cases and installation methods, please [click here to jump](https://k-cloud-labs.github.io/kinitiras-doc/) the official website to understand.

## 6.Links🔗

- Official Website: [https://k-cloud-labs.github.io/kinitiras-doc/](https://k-cloud-labs.github.io/kinitiras-doc/)
- Github: [https://github.com/k-cloud-labs](https://github.com/k-cloud-labs)

