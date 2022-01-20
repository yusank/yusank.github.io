---
title: "HPA controller 源码解读"
date: 2022-01-20T10:50:00+08:00
lastmod: 2022-01-20T11:50:00+08:00
categories: ["kubernetes"]
tags: ["go", "k8s", "源码解读"]
draft: false
---

> 本篇讲述 `kubernetes` 的横向 pod 伸缩(HorizontalPodAutoscaler) 控制器的数据结构，逻辑处理，metrics 计算以及相关细节的源码解读。

<!--more-->

## 1. 前言

在 `k8s` 环境内弹性伸缩并不是一个陌生的概念，是一个常见且不难理解的事件。就是根据特定的事件或数据来触发可伸缩资源的伸缩能力。一般有 HPA 和 VPA 两个概念，HPA 全称 [Horizontal Pod Autoscaler](https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale/) 即横向 pod 的自动伸缩，VPA 全称 [Vertical Pod Autoscaler](https://github.com/kubernetes/autoscaler/tree/master/vertical-pod-autoscaler) 即纵向 pod 的自动伸缩。

### 1.1. HPA

`HPA` 关注 pod 的数量，根据现有 pod 的数据(cpu, memory)或外部数据(metrics)来计算实际需要的 pod 数量，从而调整 pod 的总数。`HPA` 操作的对象需要实现 `ScaleInterface` 。

{{< admonition type=quote title="ScaleInterface" open=true >}}

```go
// ScaleInterface can fetch and update scales for
// resources in a particular namespace which implement
// the scale subresource.
type ScaleInterface interface {
    // Get fetches the scale of the given scalable resource.
    Get(ctx context.Context, resource schema.GroupResource, name string, opts metav1.GetOptions) (*autoscalingapi.Scale, error)

    // Update updates the scale of the given scalable resource.
    Update(ctx context.Context, resource schema.GroupResource, scale *autoscalingapi.Scale, opts metav1.UpdateOptions) (*autoscalingapi.Scale, error)

    // Patch patches the scale of the given scalable resource.
    Patch(ctx context.Context, gvr schema.GroupVersionResource, name string, pt types.PatchType, data []byte, opts metav1.PatchOptions) (*autoscalingapi.Scale, error)
}
```

{{< /admonition >}}

k8s 原生资源中 HPA 可操作性的对象是以下三个:

- `Deployment`
- `ReplicaSet`
- `StatefulSet`

一般业务场景用 HPA 能满足需求，即业务高峰增加 pod 数更好处理业务，业务低峰降低pod 数节省资源。

### 1.2. VPA

`VPA` 关注的是 pod 的资源，根据当前资源利用率等数据为 pod 提供更多的资源（cpu，memory 等）。本人对 VPA 也是表面理解，所以这里不做详细的解读。

`VPA` 更适合大计算、离线计算、机器学习等场景，需要大量的 CPU，GPU，内存来进行计算。

## 2. 基础用法

通过以下命令开启对某个资源的 HPA 能力：

```shell
➜ kubectl autoscale (-f FILENAME | TYPE NAME | TYPE/NAME) [--min=MINPODS] --max=MAXPODS [--cpu-percent=CPU] [options]
```

{{< admonition type=warning title="Warning" open=true >}}
需要开启 `metric server` 才能读取到cpu 利用率，默认是不开启的。详情请看官方文档: https://github.com/kubernetes-sigs/metrics-server
{{< /admonition >}}

实际使用如下：

```shell
# 对 deployment/klyn-deploy 进行 CPU 监控，超过 10%的平均利用率即进行scale up，最大 3 个 pod 最小 1 个
➜ kubectl autoscale deployment klyn-deploy --cpu-percent=10 --min=1 --max=3
```

然后可以通过 `describe` 命令查看创建后 HPA 的详情：

```shell
➜ kubectl describe hpa klyn-deploy
Warning: autoscaling/v2beta2 HorizontalPodAutoscaler is deprecated in v1.23+, unavailable in v1.26+
Name:                                                  klyn-deploy
Namespace:                                             default
Labels:                                                <none>
Annotations:                                           <none>
CreationTimestamp:                                     Thu, 20 Jan 2022 11:43:43 +0800
Reference:                                             Deployment/klyn-deploy
Metrics:                                               ( current / target )
  resource cpu on pods  (as a percentage of request):  4% (10m) / 10% # 可以看到已经读到 cpu 数据
Min replicas:                                          1
Max replicas:                                          3
Deployment pods:                                       1 current / 1 desired
Conditions:
  Type            Status  Reason              Message
  ----            ------  ------              -------
  AbleToScale     True    ReadyForNewScale    recommended size matches current size
  ScalingActive   True    ValidMetricFound    the HPA was able to successfully calculate a replica count from cpu resource utilization (percentage of request)
  ScalingLimited  False   DesiredWithinRange  the desired count is within the acceptable range
Events:           <none>
```

可以从上述详情看到 HPA 资源的详细信息以及最下面的步骤信息，当进行伸缩时会同步伸缩过程和原因到 `Events` 字段上。

之后可以通过压测的方式将 cpu 的利用率提升然后可以到 `Deployment` 的 replicas 数量的提升，并压测结束一段时间(会有冷却时间)后又降到 1 个 replicas.

## 3. 数据结构

HPA 资源 YAML 结构：

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  creationTimestamp: "2022-01-20T03:43:43Z"
  name: klyn-deploy
  namespace: default
  resourceVersion: "6602029"
  uid: 385f4234-025b-453d-8270-788f7ce3ced6
spec:
  maxReplicas: 3
  metrics:
  - resource:
      name: cpu
      target:
        averageUtilization: 10
        type: Utilization
    type: Resource
  minReplicas: 1
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: klyn-deploy
status:
  conditions:
  - lastTransitionTime: "2022-01-20T03:43:58Z"
    message: recommended size matches current size
    reason: ReadyForNewScale
    status: "True"
    type: AbleToScale
  - lastTransitionTime: "2022-01-20T03:43:58Z"
    message: the HPA was able to successfully calculate a replica count from cpu resource
      utilization (percentage of request)
    reason: ValidMetricFound
    status: "True"
    type: ScalingActive
  - lastTransitionTime: "2022-01-20T03:43:58Z"
    message: the desired count is within the acceptable range
    reason: DesiredWithinRange
    status: "False"
    type: ScalingLimited
  currentMetrics:
  - resource:
      current:
        averageUtilization: 3
        averageValue: 9m
      name: cpu
    type: Resource
  currentReplicas: 1
  desiredReplicas: 1
  lastScaleTime: "2022-01-20T03:51:44Z"
```

上面对 `HPA` 的概念和如何使用有了一定的认知，从这里开始对 HPA Controller 的源码进行解读。

数据结构：

```go
// HorizontalController is responsible for the synchronizing HPA objects stored
// in the system with the actual deployments/replication controllers they
// control.
type HorizontalController struct {
    // Scale 资源的读写（如 Deployment 的 Scale）
    scaleNamespacer scaleclient.ScalesGetter
    // HorizontalPodAutoscaler 资源的读写
    hpaNamespacer   autoscalingclient.HorizontalPodAutoscalersGetter
    // 用于根据类型和版本获取资源信息
    mapper          apimeta.RESTMapper
     
    // 计算 replica 数量
    replicaCalc   *ReplicaCalculator
    // 订阅 HPA 资源，处理资源变化
    eventRecorder record.EventRecorder
 
    // 每次缩容之间等待时间
    downscaleStabilisationWindow time.Duration
 
    // hpaLister is able to list/get HPAs from the shared cache from the informer passed in to
    // NewHorizontalController.
    // 用于读取 hpa 对象
    hpaLister       autoscalinglisters.HorizontalPodAutoscalerLister
    hpaListerSynced cache.InformerSynced
 
    // podLister is able to list/get Pods from the shared cache from the informer passed in to
    // NewHorizontalController.
    // 用于读取 pod 资源
    podLister       corelisters.PodLister
    podListerSynced cache.InformerSynced
 
    // Controllers that need to be synced
    // 只会启动一个 worker，即如果有大量的 HPA 资源时，一部分资源的扩缩容可能不那么及时
    queue workqueue.RateLimitingInterface
 
    // Latest unstabilized recommendations for each autoscaler.
    // 记录推荐伸缩数量
    recommendations map[string][]timestampedRecommendation
 
    // Latest autoscaler events
    // 记录伸缩事件
    scaleUpEvents   map[string][]timestampedScaleEvent
    scaleDownEvents map[string][]timestampedScaleEvent
}
```

## 4. 控制器逻辑

### 4.1. 伸缩过程

伸缩过程的触发不是实时的，而是从 `queue` 里消费数据，进行一次伸缩流程，再次将资源名放入 `queue`, 完成一次循环。

详细流程如下：

#### 4.1.1. 从 `queue` 读取一条消息，根据消息中的信息，获取 `hpa` 对象

```go
func (a *HorizontalController) processNextWorkItem() bool {
    key, quit := a.queue.Get()
    if quit {
        return false
    }
    // 处理完标记完成
    defer a.queue.Done(key)

    // 处理函数入口
    deleted, err := a.reconcileKey(key.(string))
    if err != nil {
        utilruntime.HandleError(err)
    }
    // Add request processing HPA to queue with resyncPeriod delay.
    // Requests are always added to queue with resyncPeriod delay. If there's already request
    // for the HPA in the queue then a new request is always dropped. Requests spend resyncPeriod
    // in queue so HPAs are processed every resyncPeriod.
    // Request is added here just in case last resync didn't insert request into the queue. This
    // happens quite often because there is race condition between adding request after resyncPeriod
    // and removing them from queue. Request can be added by resync before previous request is
    // removed from queue. If we didn't add request here then in this case one request would be dropped
    // and HPA would processed after 2 x resyncPeriod.
    if !deleted {
        // 如果 hpa 没有被删除，再次放回队列里，经过默认时间间隔（15s，k8s 启动参数可配置）后再读取处理一次
        a.queue.AddRateLimited(key)
    }

    return true
}

func (a *HorizontalController) reconcileKey(key string) (deleted bool, err error) {
    namespace, name, err := cache.SplitMetaNamespaceKey(key)
    if err != nil {
        return true, err
    }

    // 读取 hpa 对象 `*autoscalingv1.HorizontalPodAutoscaler`
    hpa, err := a.hpaLister.HorizontalPodAutoscalers(namespace).Get(name)
    if errors.IsNotFound(err) {
        klog.Infof("Horizontal Pod Autoscaler %s has been deleted in %s", name, namespace)
        delete(a.recommendations, key)
        delete(a.scaleUpEvents, key)
        delete(a.scaleDownEvents, key)
        return true, nil
    }
    if err != nil {
        return false, err
    }

    // 处理本次伸缩逻辑
    return false, a.reconcileAutoscaler(hpa, key)
}
```

#### 4.1.2. 为了兼容老版本，读取时 hpa 对象为 v1 版本，读取后在代码里会先统一转换为 v2 版本,从而之后的逻辑统一

```go
func (a *HorizontalController) reconcileAutoscaler(hpav1Shared *autoscalingv1.HorizontalPodAutoscaler, key string) error {
    // make a copy so that we never mutate the shared informer cache (conversion can mutate the object)
    hpav1 := hpav1Shared.DeepCopy()
    // then, convert to autoscaling/v2, which makes our lives easier when calculating metrics
    hpaRaw, err := unsafeConvertToVersionVia(hpav1, autoscalingv2.SchemeGroupVersion)
    if err != nil {
        a.eventRecorder.Event(hpav1, v1.EventTypeWarning, "FailedConvertHPA", err.Error())
        return fmt.Errorf("failed to convert the given HPA to %s: %v", autoscalingv2.SchemeGroupVersion.String(), err)
    }
    hpa := hpaRaw.(*autoscalingv2.HorizontalPodAutoscaler)
    ...
}
```

#### 4.1.3. 根据 `hpa.Spec.ScaleTargetRef` 信息读到需要伸缩的资源

```go
func (a *HorizontalController) reconcileAutoscaler(hpav1Shared *autoscalingv1.HorizontalPodAutoscaler, key string) error {
    ...
    // 省略部分代码
    hpa := hpaRaw.(*autoscalingv2.HorizontalPodAutoscaler)

    reference := fmt.Sprintf("%s/%s/%s", hpa.Spec.ScaleTargetRef.Kind, hpa.Namespace, hpa.Spec.ScaleTargetRef.Name)

    // 解析资源 api version
    targetGV, err := schema.ParseGroupVersion(hpa.Spec.ScaleTargetRef.APIVersion)
    if err != nil {
        a.eventRecorder.Event(hpa, v1.EventTypeWarning, "FailedGetScale", err.Error())
        setCondition(hpa, autoscalingv2.AbleToScale, v1.ConditionFalse, "FailedGetScale", "the HPA controller was unable to get the target's current scale: %v", err)
        a.updateStatusIfNeeded(hpaStatusOriginal, hpa)
        return fmt.Errorf("invalid API version in scale target reference: %v", err)
    }

    // 资源类型
    targetGK := schema.GroupKind{
        Group: targetGV.Group,
        Kind:  hpa.Spec.ScaleTargetRef.Kind,
    }

    // 查询资源对象
    mappings, err := a.mapper.RESTMappings(targetGK)
    if err != nil {
        a.eventRecorder.Event(hpa, v1.EventTypeWarning, "FailedGetScale", err.Error())
        setCondition(hpa, autoscalingv2.AbleToScale, v1.ConditionFalse, "FailedGetScale", "the HPA controller was unable to get the target's current scale: %v", err)
        a.updateStatusIfNeeded(hpaStatusOriginal, hpa)
        return fmt.Errorf("unable to determine resource for scale target reference: %v", err)
    }

    // 根据 ns 资源类型 资源版本和资源名称 确定最终唯一的操作的对象 scale
    // scale 是一个抽象的概念，表示可伸缩的资源(Deployment, replicaSet StatefulSet 等等)
    scale, targetGR, err := a.scaleForResourceMappings(hpa.Namespace, hpa.Spec.ScaleTargetRef.Name, mappings)
    if err != nil {
        a.eventRecorder.Event(hpa, v1.EventTypeWarning, "FailedGetScale", err.Error())
        setCondition(hpa, autoscalingv2.AbleToScale, v1.ConditionFalse, "FailedGetScale", "the HPA controller was unable to get the target's current scale: %v", err)
        a.updateStatusIfNeeded(hpaStatusOriginal, hpa)
        return fmt.Errorf("failed to query scale subresource for %s: %v", reference, err)
    }
    //  记录信息
    setCondition(hpa, autoscalingv2.AbleToScale, v1.ConditionTrue, "SucceededGetScale", "the HPA controller was able to get the target's current scale")
    // 获取当前副本数
    currentReplicas := scale.Spec.Replicas
    a.recordInitialRecommendation(currentReplicas, key)
    // 省略部分代码
    ...
}
```

#### 4.1.4. 确定当前副本数，最大最小可伸缩的副本数

```go

func (a *HorizontalController) reconcileAutoscaler(hpav1Shared *autoscalingv1.HorizontalPodAutoscaler, key string) error {
    ...
    // 省略部分代码
    currentReplicas := scale.Spec.Replicas

    var (
        metricStatuses        []autoscalingv2.MetricStatus
        metricDesiredReplicas int32
        metricName            string
    )

    desiredReplicas := int32(0)
    rescaleReason := ""

    var minReplicas int32

    if hpa.Spec.MinReplicas != nil {
        minReplicas = *hpa.Spec.MinReplicas
    } else {
        // Default value
        minReplicas = 1
    }

    rescale := true

    // 如果当前副本数为 0 但是 hpa 定义的最小 replicas 不等0 时，被认识是关闭弹性伸缩的能力，不会进行伸缩操作
    if scale.Spec.Replicas == 0 && minReplicas != 0 {
        // Autoscaling is disabled for this resource
        desiredReplicas = 0
        rescale = false
        setCondition(hpa, autoscalingv2.ScalingActive, v1.ConditionFalse, "ScalingDisabled", "scaling is disabled since the replica count of the target is zero")
    } else if currentReplicas > hpa.Spec.MaxReplicas {
        // 如果当前副本数超过预设最大数，目标副本数设定为预设最大值，不会去进行计算操作
        rescaleReason = "Current number of replicas above Spec.MaxReplicas"
        desiredReplicas = hpa.Spec.MaxReplicas
    } else if currentReplicas < minReplicas {
        // 如果当前副本数超低于预设最小值，目标副本数设定为预设最小值，不会去进行计算操作
        rescaleReason = "Current number of replicas below Spec.MinReplicas"
        desiredReplicas = minReplicas
    } else {
        // 需要通过计算获得目标副本数
        ...
    }
    ...
}
```

#### 4.1.5. 计算并处理副本数

```go
...
} else {
    var metricTimestamp time.Time
    // 获取 metric 数据并根据 metrics 计算目标副本数
    metricDesiredReplicas, metricName, metricStatuses, metricTimestamp, err = a.computeReplicasForMetrics(hpa, scale, hpa.Spec.Metrics)
    if err != nil {
        a.setCurrentReplicasInStatus(hpa, currentReplicas)
        if err := a.updateStatusIfNeeded(hpaStatusOriginal, hpa); err != nil {
            utilruntime.HandleError(err)
        }
        a.eventRecorder.Event(hpa, v1.EventTypeWarning, "FailedComputeMetricsReplicas", err.Error())
        return fmt.Errorf("failed to compute desired number of replicas based on listed metrics for %s: %v", reference, err)
    }

    klog.V(4).Infof("proposing %v desired replicas (based on %s from %s) for %s", metricDesiredReplicas, metricName, metricTimestamp, reference)

    rescaleMetric := ""
    // 此时 desiredReplicas == 0 
    // 如果计算出结果大于 0，则赋值给 desiredReplicas
    if metricDesiredReplicas > desiredReplicas {
        desiredReplicas = metricDesiredReplicas
        rescaleMetric = metricName
    }
    // 准备 rescaleReason 用于记录到 hpa 的 Conditions 字段，可以查看
    if desiredReplicas > currentReplicas {
        rescaleReason = fmt.Sprintf("%s above target", rescaleMetric)
    }
    if desiredReplicas < currentReplicas {
        rescaleReason = "All metrics below target"
    }
    if hpa.Spec.Behavior == nil {
        // 默认规则限制一次伸缩的数量 单次伸缩比例不会超过 Max(currentReplicas * 2, 4)
        desiredReplicas = a.normalizeDesiredReplicas(hpa, key, currentReplicas, desiredReplicas, minReplicas)
    } else {
        // 如果 hpa.Spec.Behavior != nil 则处理是否需要配置的规则
        // 如果配置规则为禁用(可以单独禁用 scale up 或 scale down)，则返回 currentReplicas
        // 如果配合了 hpa.Spec.Behavior.Policies, 则按策略进行伸缩(可以配置一次伸缩的 pod 数量或者百分比，从而可以确保伸缩跨度不会一次性很大)
        desiredReplicas = a.normalizeDesiredReplicasWithBehaviors(hpa, key, currentReplicas, desiredReplicas, minReplicas)
    }
    // 判断是否需要伸缩，最终计算结果可能会当前副本数一致
    rescale = desiredReplicas != currentReplicas
}
...
```

#### 4.1.6. 调整副本数

```go
func (a *HorizontalController) reconcileAutoscaler(hpav1Shared *autoscalingv1.HorizontalPodAutoscaler, key string) error {
    ...

    // 需要伸缩
    if rescale {
        scale.Spec.Replicas = desiredReplicas
        // 更新 scale 对象，最终伸缩操作会由 scale 对应的 controller 去完成
        _, err = a.scaleNamespacer.Scales(hpa.Namespace).Update(context.TODO(), targetGR, scale, metav1.UpdateOptions{})
        if err != nil {
            // 记录日志和 event
            a.eventRecorder.Eventf(hpa, v1.EventTypeWarning, "FailedRescale", "New size: %d; reason: %s; error: %v", desiredReplicas, rescaleReason, err.Error())
            setCondition(hpa, autoscalingv2.AbleToScale, v1.ConditionFalse, "FailedUpdateScale", "the HPA controller was unable to update the target scale: %v", err)
            a.setCurrentReplicasInStatus(hpa, currentReplicas)
            if err := a.updateStatusIfNeeded(hpaStatusOriginal, hpa); err != nil {
                utilruntime.HandleError(err)
            }
            return fmt.Errorf("failed to rescale %s: %v", reference, err)
        }
        setCondition(hpa, autoscalingv2.AbleToScale, v1.ConditionTrue, "SucceededRescale", "the HPA controller was able to update the target scale to %d", desiredReplicas)
        a.eventRecorder.Eventf(hpa, v1.EventTypeNormal, "SuccessfulRescale", "New size: %d; reason: %s", desiredReplicas, rescaleReason)
        a.storeScaleEvent(hpa.Spec.Behavior, key, currentReplicas, desiredReplicas)
        klog.Infof("Successful rescale of %s, old size: %d, new size: %d, reason: %s",
            hpa.Name, currentReplicas, desiredReplicas, rescaleReason)
    } else {
        klog.V(4).Infof("decided not to scale %s to %v (last scale time was %s)", reference, desiredReplicas, hpa.Status.LastScaleTime)
        desiredReplicas = currentReplicas
    }

    // 更新状态
    a.setStatus(hpa, currentReplicas, desiredReplicas, metricStatuses, rescale)
    return a.updateStatusIfNeeded(hpaStatusOriginal, hpa)
}
```

至此，伸缩的大流程是完成了，剩下的就是对细节的了解了。比如如何计算目标副本数的，如何处理伸缩的策略等等。

{{< image src="hpa_controller.png" caption="伸缩流程" width="800" >}}

### 4.2. 计算副本数过程

可通过上面流程看到会有一个计算目标副本数的过程 `a.computeReplicasForMetrics`，看似简单其实内部相当丰富的一个过程，下面一起看一下如何去计算的。

#### 4.2.1. 遍历 `spec.Metrics` 计算得出最大值

```go
// computeReplicasForMetrics computes the desired number of replicas for the metric specifications listed in the HPA,
// returning the maximum  of the computed replica counts, a description of the associated metric, and the statuses of
// all metrics computed.
func (a *HorizontalController) computeReplicasForMetrics(hpa *autoscalingv2.HorizontalPodAutoscaler, scale *autoscalingv1.Scale,
    metricSpecs []autoscalingv2.MetricSpec) (replicas int32, metric string, statuses []autoscalingv2.MetricStatus, timestamp time.Time, err error) {

    /*
    * 省略了部分无关代码
    */
    if scale.Status.Selector == "" {
        errMsg := "selector is required"
        return 0, "", nil, time.Time{}, fmt.Errorf(errMsg)
    }

    selector, err := labels.Parse(scale.Status.Selector)
    if err != nil {
        return 0, "", nil, time.Time{}, fmt.Errorf(errMsg)
    }

    specReplicas := scale.Spec.Replicas
    statusReplicas := scale.Status.Replicas
    // 记录每个 metric 的结果
    statuses = make([]autoscalingv2.MetricStatus, len(metricSpecs))

    invalidMetricsCount := 0
    var invalidMetricError error
    var invalidMetricCondition autoscalingv2.HorizontalPodAutoscalerCondition

    // 遍历计算
    for i, metricSpec := range metricSpecs {
        // 计算单个 metric 的方法
        replicaCountProposal, metricNameProposal, timestampProposal, condition, err := a.computeReplicasForMetric(hpa, metricSpec, specReplicas, statusReplicas, selector, &statuses[i])

        if err != nil {
            if invalidMetricsCount <= 0 {
                invalidMetricCondition = condition
                invalidMetricError = err
            }
            invalidMetricsCount++
        }
        // 取最大
        if err == nil && (replicas == 0 || replicaCountProposal > replicas) {
            timestamp = timestampProposal
            replicas = replicaCountProposal
            metric = metricNameProposal
        }
    }

    // If all metrics are invalid or some are invalid and we would scale down,
    // return an error and set the condition of the hpa based on the first invalid metric.
    // Otherwise set the condition as scaling active as we're going to scale
    if invalidMetricsCount >= len(metricSpecs) || (invalidMetricsCount > 0 && replicas < specReplicas) {
        return 0, "", statuses, time.Time{}, fmt.Errorf("invalid metrics (%v invalid out of %v), first error is: %v", invalidMetricsCount, len(metricSpecs), invalidMetricError)
    }

    return replicas, metric, statuses, timestamp, nil
}
```

#### 4.2.2. 计算单个 metric：根据类型计算 metric

{{< admonition type=inf title="名词解析" open=true >}}
hpa 对象的 `spac.metrics` 中的元素有个 `Type` 字段,记录 metric 数据源的类型，目前支持的以下几种：

| 类型 | 说明 | 支持的计算类型 | 不支持的计算类型 |
| :-------: | :----- | :----- |:----- |
| Object | 由 k8s 本身资源提供的数据，如 ingress 提供命中规则数量 |AverageValue <br> Value| AverageUtilization|
| Pods | 由 pod 提供的除 CPU 内存之外的数据 |AverageValue| AverageUtilization <br> Value|
| Resource | pod 提供的系统资源（CPU 内存） |AverageUtilization <br> AverageValue | Value |
| External | 外部提供的监控指标 |AverageValue <br> Value |AverageUtilization |

- AverageValue：设定平均值，如qps，tps。计算时读取 metric 总和，与预设平均值✖️副本数进行对比，从而判断是否需要伸缩。

- Value：设定固定值，如队列中消息数量，Redis 中 list 长度等。计算时直接拿 metric 和预设值进行对比。

- AverageUtilization： 平均利用率，如 CPU 和内存。先计算 pod的基数的总和（totalMetric 和 totalRequest），最终计算利用率 → totalMetric/totalRequest
{{< /admonition >}}

源码：

```go
// Computes the desired number of replicas for a specific hpa and metric specification,
// returning the metric status and a proposed condition to be set on the HPA object.
func (a *HorizontalController) computeReplicasForMetric(hpa *autoscalingv2.HorizontalPodAutoscaler, spec autoscalingv2.MetricSpec,
    specReplicas, statusReplicas int32, selector labels.Selector, status *autoscalingv2.MetricStatus) (replicaCountProposal int32, metricNameProposal string,
    timestampProposal time.Time, condition autoscalingv2.HorizontalPodAutoscalerCondition, err error) {

    switch spec.Type {
    case autoscalingv2.ObjectMetricSourceType:
        metricSelector, err := metav1.LabelSelectorAsSelector(spec.Object.Metric.Selector)
        if err != nil {
            condition := a.getUnableComputeReplicaCountCondition(hpa, "FailedGetObjectMetric", err)
            return 0, "", time.Time{}, condition, fmt.Errorf("failed to get object metric value: %v", err)
        }
        replicaCountProposal, timestampProposal, metricNameProposal, condition, err = a.computeStatusForObjectMetric(specReplicas, statusReplicas, spec, hpa, selector, status, metricSelector)
        if err != nil {
            return 0, "", time.Time{}, condition, fmt.Errorf("failed to get object metric value: %v", err)
        }
    case autoscalingv2.PodsMetricSourceType:
        metricSelector, err := metav1.LabelSelectorAsSelector(spec.Pods.Metric.Selector)
        if err != nil {
            condition := a.getUnableComputeReplicaCountCondition(hpa, "FailedGetPodsMetric", err)
            return 0, "", time.Time{}, condition, fmt.Errorf("failed to get pods metric value: %v", err)
        }
        replicaCountProposal, timestampProposal, metricNameProposal, condition, err = a.computeStatusForPodsMetric(specReplicas, spec, hpa, selector, status, metricSelector)
        if err != nil {
            return 0, "", time.Time{}, condition, fmt.Errorf("failed to get pods metric value: %v", err)
        }
    case autoscalingv2.ResourceMetricSourceType:
        replicaCountProposal, timestampProposal, metricNameProposal, condition, err = a.computeStatusForResourceMetric(specReplicas, spec, hpa, selector, status)
        if err != nil {
            return 0, "", time.Time{}, condition, err
        }
    case autoscalingv2.ExternalMetricSourceType:
        replicaCountProposal, timestampProposal, metricNameProposal, condition, err = a.computeStatusForExternalMetric(specReplicas, statusReplicas, spec, hpa, selector, status)
        if err != nil {
            return 0, "", time.Time{}, condition, err
        }
    default:
        errMsg := fmt.Sprintf("unknown metric source type %q", string(spec.Type))
        err = fmt.Errorf(errMsg)
        condition := a.getUnableComputeReplicaCountCondition(hpa, "InvalidMetricSourceType", err)
        return 0, "", time.Time{}, condition, err
    }
    return replicaCountProposal, metricNameProposal, timestampProposal, autoscalingv2.HorizontalPodAutoscalerCondition{}, nil
}
```

下面会以 `ExternalMetricSourceType` 为例。

#### 4.2.3. 根据计算类型执行对应的计算逻辑

>下面以 External 的 AverageValue 为例

```go
// GetExternalPerPodMetricReplicas calculates the desired replica count based on a
// target metric value per pod (as a milli-value) for the external metric in the
// given namespace, and the current replica count.
func (c *ReplicaCalculator) GetExternalPerPodMetricReplicas(statusReplicas int32, targetUtilizationPerPod int64, metricName, namespace string, metricSelector *metav1.LabelSelector) (replicaCount int32, utilization int64, timestamp time.Time, err error) {
    // 构造 metric 查询 label
    metricLabelSelector, err := metav1.LabelSelectorAsSelector(metricSelector)
    if err != nil {
        return 0, 0, time.Time{}, err
    }
    // 拉取 metrics
    // https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale/#support-for-metrics-apis
    metrics, timestamp, err := c.metricsClient.GetExternalMetric(metricName, namespace, metricLabelSelector)
    if err != nil {
        return 0, 0, time.Time{}, fmt.Errorf("unable to get external metric %s/%s/%+v: %s", namespace, metricName, metricSelector, err)
    }
    // 计算总和
    utilization = 0
    for _, val := range metrics {
        utilization = utilization + val
    }

    replicaCount = statusReplicas
    // 计算 伸缩比例
    // targetUtilizationPerPod 为配置的单个 pod 的预设值，所以需要乘以副本数
    // 如果当前 metric 查询数据为 100， 预设的单个 pod 的值为 20, 当前有3个副本数
    // 此时伸缩比例为 1.6667
    usageRatio := float64(utilization) / (float64(targetUtilizationPerPod) * float64(replicaCount))
    // c.tolerance 容忍度，默认值为 0.1
    // 如果 1.0 - 伸缩比例 超过容忍度则认为需要伸缩。这里可以理解为查询到的 metric 数据与预设的值浮动小于 10% 时 不需要伸缩
    if math.Abs(1.0-usageRatio) > c.tolerance {
        // update number of replicas if the change is large enough
        // 继续上面的数据计算 新的 replica 数量为 100/20 -> 5
        replicaCount = int32(math.Ceil(float64(utilization) / float64(targetUtilizationPerPod)))
    }
    // 计算当前的平均数据 100/3 -> 33.33 这个值会在 HPA 对象的 日志里打印出来可以看到
    utilization = int64(math.Ceil(float64(utilization) / float64(statusReplicas)))
    return replicaCount, utilization, timestamp, nil
}
```

> 计算结果一路返回到 `reconcileAutoscaler` 方法进行最终伸缩。

## 5. 扩展用法

在实际开发环境只用 `cpu`, `memory` 来作为弹性伸缩依据是远远不够的。大多数情况可能会根据 `qps`, `tps`, `平均延迟时间`, `MQ 中的消息数量`, `Redis 中的数据量` 等与业务息息相关的数据量判断伸缩的依据，这些都属于 HPA 的 External 类型的范畴。但是 External 类型的数据源需要对接 `Adapter` 的方式才能用到 HPA 对象内容(具体请查看: https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale/#support-for-metrics-apis) ，也就是说需要额外开发量的。

这里我推荐一个知名度比较高且支持的数据量比较广泛的 Adapter 的实现 -- [KEDA](https://keda.sh/)。基于事件驱动的autoscaler,且支持从 0 到 1  1 到 0 的伸缩，也就是说业务低峰或者无流量时可以降到 0 个副本数(这个在 HPA 被认为是禁用该功能 所以 KEDA 自己实现的 0 到 1  1 到 0 的伸缩的能力，剩余的情况它叫个 HPA 处理)。

目前 KEDA 支持事件类型如下：

{{< image src="keda.png" caption="KEDA 支持的事件" width="800" >}}

只需要创建 KEDA 的 CRD 资源，就能实现基于事件的弹性伸缩，KEDA 的 controller 会创建对应的 HPA 对象。

下面以 `Prometheus` 为例：

KEDA.ScaledObject:

```yaml
apiVersion: keda.sh/v1alpha1
kind: ScaledObject
metadata:
  name: prom-scaledobject
  namespace: default
spec:
  scaleTargetRef:
    name: klyn-deploy
  triggers:
  - type: prometheus
    metadata:
      serverAddress: http://10.103.255.235:9090 # Prometheus 查询接口
      metricName: http_request_count # 自定义名字
      query: sum(rate(http_request_count{job="klyn-service"}[2m])) # 查询语句 2m 内的平均 qps
      threshold: '50'
  maxReplicaCount: 5
  minReplicaCount: 1
  pollingInterval: 5
```

apply 该 yaml 后，会创建一个 `ScaledObject` 和 `HPA` 对象。

```shell
➜ kubectl get ScaledObject      
NAME                SCALETARGETKIND      SCALETARGETNAME   MIN   MAX   TRIGGERS     AUTHENTICATION   READY   ACTIVE   FALLBACK   AGE
prom-scaledobject   apps/v1.Deployment   klyn-deploy       1     5     prometheus                    True    False    False      9d

## 该 HPA 对象有 KEDA 的 controller 创建的
➜ kubectl get hpa               
NAME                         REFERENCE                TARGETS      MINPODS   MAXPODS   REPLICAS   AGE
keda-hpa-prom-scaledobject   Deployment/klyn-deploy   0/50 (avg)   1         5         1          9d
```

这样一来，可以根据很多事件来控制伸缩的能力，这比单一来 cpu,内存利用率来看更灵活且及时。完全可以根据事件在服务的副本数不够用或者有一堆事件准备处理时，尽可能快速扩容，确保处理能力不会受损。

## 6. 总结

这篇文章主要讲 HPA controller 的源码和如何使用 HPA 相关内容

- `HPA/VPA` 的解释
- 如何使用 `HPA`
- `HPA Controller` 如何处理一次伸缩事件的
- `HPA Controller` 如何计算目标实例数的
- 认识和使用 `KEDA` -- 一个基于事件驱动的 autoscaler

## 7. 链接🔗

- [horizontal-pod-autoscale](https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale/)
- [pvertical-pod-autoscaler](https://github.com/kubernetes/autoscaler/tree/master/vertical-pod-autoscaler)
- [metrics server](https://github.com/kubernetes-sigs/metrics-server)
- [KEDA](https://keda.sh)
