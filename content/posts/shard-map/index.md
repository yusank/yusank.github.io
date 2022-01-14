---
title: "go 语言中的分片 map 的实现"
date: 2022-01-13T10:50:00+08:00
lastmod: 2022-01-13T11:50:00+08:00
categories: ["代码技巧"]
tags: ["go", "map", "数据结构"]
draft: true
---

> 本篇分享一个分片式的 map 结构，在一些场景下该结构比原生 `syncMap` 更有优势，本文会对该结构的实现，原理以及时候的场景进行详细的介绍。

<!--more-->

## 背景

`map` 作为一个基础的数据结构，在编程过程中可以说是无处不在，应用场景十分广泛。在大部分场景下用原生的 `map` 就能解决当前的问题。如果是高并发场景可以加入 `sync.RWMutex` 来控制并发读写或者直接使用 `sync.Map` 来减少手动写锁的处理逻辑。如果作为一个应用的基础数据结构，性能可以说是非常的高了，绝大部分场景下是完全足够的。但是总有人在优化性能这块想做到极致（包括我自己），即便是原生的数据结构也会有人想优化。既然想优化 map，那首先得了解 map 在什么情况下性能会受损或者性能不够高呢？

对 map 结构熟悉的同学应该都知道，map 又称之为哈希表，key 是按照哈希值存储的，map 在元素增多/减少的过程在 go 里叫 `grow`,而这个过程中有个非常关键的步骤 `rehash`。即会对 map 内的数据进行重新哈希计算和移动位置，在数据量比较大的时候，map 的写性能会有一定的受损的。

如果我有个对性能要求很高的程序（其实如果对性能要求极高其实可以考虑 C 或者 rust 的，这里就不考虑了），想在 map 上做进一步的优化的，应该如何优化，从什么地方入手呢？

在我之前几篇文章都在将用 go 语言实现 Redis server 的过程，在实际开发过程中我最开始也是直接用的 `syncMap` 作为底层的哈希表的，但是最后压测的时候，结果不是很满意。尤其是写入操作数据量大的时候，tps 下降比较厉害，所以就开始搜查相关的优化方案。首先遇到了一个开源库[orcaman/concurrent-map](https://github.com/orcaman/concurrent-map),其 README 中的一句话吸引到我了

{{< admonition type=quote title="orcaman/concurrent-map.README" open=true >}}
Prior to Go 1.9, there was no concurrent map implementation in the stdlib. In Go 1.9, `sync.Map` was introduced. The new `sync.Map` has a few key differences from this map. The stdlib `sync.Map` is designed for append-only scenarios. **So if you want to use the map for something more like in-memory db, you might benefit from using our version**
{{< /admonition >}}

这不就是在说我吗？所以马上clone 下来进行 benchmark 测试，与 `syncMap` 进行对比。仅对基础读写能力进行一个压测对比，结果如下：

```shell
/*
 * goos: darwin
 * goarch: amd64
 * pkg: github.com/yusank/godis/datastruct
 * cpu: Intel(R) Core(TM) i7-9750H CPU @ 2.60GHz
 * Benchmark_concurrence_map_sAdd
 * Benchmark_concurrence_map_sAdd-12         	 2619080	       440.8 ns/op
 * Benchmark_concurrence_map_sIsMember
 * Benchmark_concurrence_map_sIsMember-12    	13764466	        77.68 ns/op
 * Benchmark_concurrence_map_sRem
 * Benchmark_concurrence_map_sRem-12         	16740207	        65.18 ns/op
 * Benchmark_sync_map_sAdd
 * Benchmark_sync_map_sAdd-12                	 2101056	       765.1 ns/op
 * Benchmark_sync_map_sIsMember
 * Benchmark_sync_map_sIsMember-12           	15998791	        73.47 ns/op
 * Benchmark_sync_map_sRem
 * Benchmark_sync_map_sRem-12                	15768998	        76.62 ns/op
 * PASS
 */
```

对比结果确实让我有些惊讶，我以为这个开源库应该也就大概能达到 `sync.Map` 80-90% 的性能，没想到写入性能比 `sync.Map` 高出 60%，我决定用这个开源库替代`sync.Map`。

但是我在看该库的源码的时候发现让我不是很爽的一个地方，就是读取全量数据的时候会进行一次 buffer，再从 buffer 往外吐出元素，导致全量数据的读取或者遍历变得非常的慢，当然这个作者可能有自己的顾虑，但是对我来说说不可接受。所以我决定对这个库进行一个自定义，下面就把库的实现逻辑和自己自定义的部分一起分享一下。

## 实现

### 数据结构

我们先从数据结构的定义入手看看这个库为什么能做到这么高的性能。

```go
var SHARD_COUNT = 32

// A "thread" safe map of type string:Anything.
// To avoid lock bottlenecks this map is dived to several (SHARD_COUNT) map shards.
type ConcurrentMap []*ConcurrentMapShared

// A "thread" safe string to anything map.
type ConcurrentMapShared struct {
    items        map[string]interface{}
    sync.RWMutex // Read Write mutex, guards access to internal map.
}

// Creates a new concurrent map.
func New() ConcurrentMap {
    m := make(ConcurrentMap, SHARD_COUNT)
    for i := 0; i < SHARD_COUNT; i++ {
        m[i] = &ConcurrentMapShared{items: make(map[string]interface{})}
    }
    return m
}
```

`ConcurrentMap` 是一个 32 个分片的 map 结构，每个分片内是一个 map-lock 的组合。这个 `SHARD_COUNT` 可能是为了方便后期可以通过编译过程注入的方式扩展分片大小而定义的变量。我目前没有这个需求，而且其他变量名觉得有点啰嗦，所以稍微改了一下：

```go
const shardCount = 32

// Map -
// 直接定义32 长度的数组
type Map [shardCount]*Shard

// Shard of Map
// 分片
type Shard struct {
    sync.RWMutex
    items map[string]interface{}
}

func New() Map {
    m := Map{}
    for i := 0; i < shardCount; i++ {
        m[i] = &Shard{items: make(map[string]interface{})}
    }

    return m
}
```

### 元素定位

从上述结构可以看出，元素分布于多个 `Shard` 内的 map 中，那么如何确定某个元素在哪个分片上呢？答案是： 哈希取模的方式定位元素的分片。

```go
// GetShard returns shard under given key
func (m Map) GetShard(key string) *Shard {
    return m[uint(fnv32(key))%uint(shardCount)]
}

func fnv32(key string) uint32 {
    hash := uint32(2166136261)
    const prime32 = uint32(16777619)
    keyLength := len(key)
    for i := 0; i < keyLength; i++ {
        hash *= prime32
        hash ^= uint32(key[i])
    }
    return hash
}

```



## 场景 & 压测

## 总结
