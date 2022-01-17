# go 语言中的分片 map 的实现


> 本篇分享一个分片式的 map 结构，在一些场景下该结构比原生 `syncMap` 更有优势，本文会对该结构的实现，原理以及时候的场景进行详细的介绍。

<!--more-->

## 1. 背景

`map` 作为一个基础的数据结构，在编程过程中可以说是无处不在，应用场景十分广泛。在大部分场景下用原生的 `map` 就能解决当前的问题。如果是高并发场景可以加入 `sync.RWMutex` 来控制并发读写或者直接使用 `sync.Map` 来减少手动写锁的处理逻辑。如果作为一个应用的基础数据结构，性能可以说是非常的高了，绝大部分场景下是完全足够的。但是总有人在优化性能这块想做到极致（包括我自己），即便是原生的数据结构也会有人想优化。既然想优化 map，那首先得了解 map 在什么情况下性能会受损或者性能不够高呢？

对 map 结构熟悉的同学应该都知道，map 又称之为哈希表，key 是按照哈希值存储的，map 在元素增多/减少的过程在 go 里叫 `grow`,而这个过程中有个非常关键的步骤 `rehash`。即会对 map 内的数据进行重新哈希计算和移动位置，在数据量比较大的时候，map 的写性能会有一定的受损的。

如果我有个对性能要求很高的程序（其实如果对性能要求极高其实可以考虑 C 或者 rust 的，这里就不考虑了），想在 map 上做进一步的优化的，应该如何优化，从什么地方入手呢？

在我之前几篇文章都在讲用 go 语言实现 Redis server 的过程，在实际开发过程中我最开始也是直接用的 `syncMap` 作为底层的哈希表的，但是最后压测的时候，结果不是很满意。尤其是写入操作数据量大的时候，tps 下降比较厉害，所以就开始搜查相关的优化方案。首先遇到了一个开源库[orcaman/concurrent-map](https://github.com/orcaman/concurrent-map),其 README 中的一句话吸引到我了

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
 * Benchmark_concurrence_map_sAdd-12          2619080       440.8 ns/op
 * Benchmark_concurrence_map_sIsMember
 * Benchmark_concurrence_map_sIsMember-12    13764466        77.68 ns/op
 * Benchmark_concurrence_map_sRem
 * Benchmark_concurrence_map_sRem-12         16740207        65.18 ns/op
 * Benchmark_sync_map_sAdd
 * Benchmark_sync_map_sAdd-12                 2101056       765.1 ns/op
 * Benchmark_sync_map_sIsMember
 * Benchmark_sync_map_sIsMember-12           15998791        73.47 ns/op
 * Benchmark_sync_map_sRem
 * Benchmark_sync_map_sRem-12                15768998        76.62 ns/op
 * PASS
 */
```

> 查询元素和删除元素前，提前 insert 50000 条数据进行的压测

对比结果确实让我有些惊讶，我以为这个开源库应该也就大概能达到 `sync.Map` 80-90% 的性能，没想到写入性能比 `sync.Map` 高出 60%，我决定用这个开源库替代`sync.Map`。

但是我在看该库的源码的时候发现让我不是很爽的一个地方，就是读取全量数据的时候会进行一次 buffer，再从 buffer 往外吐出元素，导致全量数据的读取或者遍历变得非常的慢，当然这个作者可能有自己的顾虑，但是对我来说说不可接受。所以我决定对这个库进行一个自定义，下面就把库的实现逻辑和自己自定义的部分一起分享一下。

## 2. 实现

### 2.1. 数据结构

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

### 2.2. 元素定位

从上述结构可以看出，元素分布于多个 `Shard` 内的 map 中，那么如何确定某个元素在哪个分片上呢？答案是： 哈希取模的方式定位元素的分片。

```go
// GetShard returns shard under given key
func (m Map) GetShard(key string) *Shard {
    return m[uint(fnv32(key))%uint(shardCount)]
}

// 哈希算法
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

### 2.3. 增改删查

```go
func (m Map) Get(key string) (interface{}, bool) {
    shard := m.GetShard(key)
    shard.RLock()
    defer shard.RUnlock()

    v, ok := shard.items[key]
    return v, ok
}

func (m Map) Set(key string, value interface{}) {
    shard := m.GetShard(key)
    shard.Lock()
    defer shard.Unlock()
    shard.items[key] = value
}


func (m Map) Delete(key string) {
    shard := m.GetShard(key)
    shard.Lock()
    defer shard.Unlock()
    delete(shard.items, key)
}

// UpsertFunc callback for upsert
// if after found oldValue and want to stop the upsert op, you can return result and true for it
type UpsertFunc func(exist bool, valueInMap, newValue interface{}) (result interface{}, abort bool)

// Upsert - update or insert value and support abort operation after callback
func (m Map) Upsert(key string, value interface{}, f UpsertFunc) (res interface{}, abort bool) {
    shard := m.GetShard(key)
    shard.Lock()
    defer shard.Unlock()
    old, ok := shard.items[key]
    res, abort = f(ok, old, value)
    if abort {
        return
    }
    shard.items[key] = res
    return
}
```

有了基础的方法之后，可以补充一些更方便的方法封装，如 `Exists`, `SetIfNotExists`, `DeleteAndLoad` 等等。

### 2.4. 高级用法

```go

func (m Map) SetIfAbsent(key string, value interface{}) bool {
    shard := m.GetShard(key)
    shard.Lock()
    defer shard.Unlock()
    _, ok := shard.items[key]
    if !ok {
        shard.items[key] = value
        return true
    }

    return false
}

func (m Map) DeleteIfExists(key string) bool {
    shard := m.GetShard(key)
    shard.Lock()
    defer shard.Unlock()
    _, ok := shard.items[key]
    if !ok {
        return false
    }

    delete(shard.items, key)
    return true
}

func (m Map) LoadAndDelete(key string) (v interface{}, loaded bool) {
    shard := m.GetShard(key)
    shard.Lock()
    defer shard.Unlock()
    v, loaded = shard.items[key]
    if !loaded {
        return nil, false
    }

    delete(shard.items, key)
    return v, loaded
}

func (m Map) Delete(key string) {
    shard := m.GetShard(key)
    shard.Lock()
    defer shard.Unlock()
    delete(shard.items, key)
}

func (m Map) Range(f func(key string, value interface{}) bool) {
    for i := range m {
        shard := (m)[i]
        shard.RLock()
        defer shard.RUnlock()
        for s, v := range shard.items {
            if !f(s, v) {
                return
            }
        }
    }
}
```

## 3. 场景 & 压测

### 3.1. 使用场景

> 该结构的特点就是写操作比 `sync.Map` 高大概 60% 左右，所以使用场景的选择的基础的在于以下两点：

- 对性能要求比较高，否则 `sync.Map` 完成足够
- 数据量大。在数据量比较少的情况下，该结构的优势不够明显

综上述，比较合适的使用场景的应该是 `内存数据库`。对性能要求高，且数据量会很大，整体性能不会因为数据量高而会下降。

### 3.2. 压测

压测源码：

```go
func BenchmarkShardMap_Set(b *testing.B) {
    m := New()
    for i := 0; i < b.N; i++ {
        k := strconv.Itoa(i)
        m.Set(k, i)
    }
}

func BenchmarkSyncMap_Set(b *testing.B) {
    m := sync.Map{}
    for i := 0; i < b.N; i++ {
        k := strconv.Itoa(i)
        m.Store(k, i)
    }
}

func BenchmarkShardMap_Get(b *testing.B) {
    m := New()
    for i := 0; i < 3_000_000; i += 3 {
        k := strconv.Itoa(i)
        m.Set(k, i)
    }

    for i := 0; i < b.N; i++ {
        k := strconv.Itoa(i)
        m.Get(k)
    }
}

func BenchmarkSyncMap_Get(b *testing.B) {
    m := sync.Map{}
    for i := 0; i < 3_000_000; i += 3 {
        k := strconv.Itoa(i)
        m.Store(k, i)
    }

    for i := 0; i < b.N; i++ {
        k := strconv.Itoa(i)
        m.Load(k)
    }
}

func BenchmarkShardMap_Del(b *testing.B) {
    m := New()
    for i := 0; i < 3_000_000; i += 3 {
        k := strconv.Itoa(i)
        m.Set(k, i)
    }

    for i := 0; i < b.N; i++ {
        k := strconv.Itoa(i)
        m.Delete(k)
    }
}

func BenchmarkSyncMap_Del(b *testing.B) {
    m := sync.Map{}
    for i := 0; i < 3_000_000; i += 3 {
        k := strconv.Itoa(i)
        m.Store(k, i)
    }

    for i := 0; i < b.N; i++ {
        k := strconv.Itoa(i)
        m.Delete(k)
    }
}
```

> 分别对 `sync.Map`, `ShardMap` 进行大量的读写删操作,下面看看压测结果

{{< admonition type=example title="原始结果" open=false >}}

```shell
goos: darwin
goarch: amd64
pkg: github.com/yusank/godis/lib/shard_map
cpu: Intel(R) Core(TM) i7-9750H CPU @ 2.60GHz
BenchmarkShardMap_Set
BenchmarkShardMap_Set-12     2442687       481.3 ns/op
BenchmarkSyncMap_Set
BenchmarkSyncMap_Set-12      1442368       736.1 ns/op
BenchmarkShardMap_Get
BenchmarkShardMap_Get-12     2702954       385.3 ns/op
BenchmarkSyncMap_Get
BenchmarkSyncMap_Get-12       717051      1409 ns/op
BenchmarkShardMap_Del
BenchmarkShardMap_Del-12     2704998       384.8 ns/op
BenchmarkSyncMap_Del
BenchmarkSyncMap_Del-12       480789      2209 ns/op
PASS
```

{{< /admonition >}}

{{< admonition type=example title="结果对比" open=true >}}

结果如下(单位：`ns/op`)：

| 数据结构 | `Set` | `Get` | `Del` |
| :---- |  -----: | -----: | -----: |
| `ShardMap` | 481.3 | 385.3 | 384.8|
| `sync.Map` | 736.1 | 1409 | 2209 |

不难发现，在数据量大的情况下（百万级别）`sync.Map` 的性能会下降很多，这个与 `sync.Map` 的设计和内部结构有关，感兴趣的朋友可以去阅读一下 `sync.Map` 的源码。

>**注意：这里文章最开始时的压测结果差距很大的原因是 数据量不一样，第一个压测结果是基于 50000 个元素之上进行的，所以查询和删除的性能上看上去很高。而这里的压测时基于 3000000 个元素之上进行的。**

{{< /admonition >}}

## 4. 总结

本篇介绍了一个基于 `map` 的分片式数据结构 -- `ShardMap`。 该结构可以在数据量比较大的使用替代`sync.Map` 从而保持比较高的性能。我在自己的 `godis` 项目内也是用该结构作为基础的哈希表，但是由于`godis` 单进程处理数据，所以我把其中的读写锁去掉 从而获得更高的性能。

本篇主要内容：

- 认识 `ShardMap`
- 了解到 `sync.Map` 也存在性能问题
- 了解到 map 在数据量大的情况下，性能会因为 reshah 机制的存在而有所下降
- 通过分片的方式，降低单个 map 的数据量，从而减少 rehash 带来的性能的降低
- 实现和压测 `ShardMap`

## 5. 链接🔗

- [orcaman/concurrent-map](https://github.com/orcaman/concurrent-map)
- [godis](https://github.com/yusank/godis)
- [godis/shard_map](https://github.com/yusank/godis/blob/master/lib/shard_map/shard_map.go)
