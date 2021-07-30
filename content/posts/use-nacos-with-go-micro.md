---
date: 2021-06-23T18:22:00+08:00
title: "Go-Micro 中使用Nacos"
categories:
- microservice
tags:
- go
- go-micro
---

`go-micro` 作为比较流行的微服务框架，其良好的接口设计为后期扩展使用带来了非常好的便利性。本文章主要讲在 `go-micro` 中用 `nacos` 作为服务注册中心和配置中心。

## 注册中心

先看一下 `go-micro` 定义的服务注册接口。

registry.go

```go
// 服务注册接口
type Registry interface {
    // 初始化
    Init(...Option) error
    // 返回可选参数
    Options() Options
    // 服务注册
    Register(*Service, ...RegisterOption) error
    // 服务注销
    Deregister(*Service, ...DeregisterOption) error
    // 查询服务
    GetService(string, ...GetOption) ([]*Service, error)
    // 列出服务
    ListServices(...ListOption) ([]*Service, error)
    // 监听服务
    Watch(...WatchOption) (Watcher, error)
    String() string
}
```

只要基于任意一个服务注册服务实现以上接口，即可在 `go-micro` 中作为注册中心使用。假如我用一个 `customRegistry` 实现接口后，在 `go-micro` 初始化的时候或服务启动时候通过启动参数指定实现接口的接口的 `String() string`方法的返回值接口。

如：

```go
// 假如该结构体已实现 Registry 接口
type customRegistry struct {}

func (c *customRegistry) String() string {
    return "custom"
}

// 代码中指定
func main() {
    micro.NewService(micro.Registry(&customRegistry{}))
}

// 启动参数指定
./myApp -- registry custom

```

如此一看，发现非常方便和好扩展，接下来贴出如何使用nacos 实现该 `Registry` 接口。

直接列出关键代码块：

registry.go

```go

import (
    "errors"
    "fmt"
    "net"
    "strconv"
    "time"

    "github.com/asim/go-micro/v3/cmd"

    "github.com/asim/go-micro/v3/registry"
    "github.com/nacos-group/nacos-sdk-go/v2/clients"
    "github.com/nacos-group/nacos-sdk-go/v2/clients/naming_client"
    "github.com/nacos-group/nacos-sdk-go/v2/common/constant"
    "github.com/nacos-group/nacos-sdk-go/v2/common/logger"
    "github.com/nacos-group/nacos-sdk-go/v2/vo"
)

type nacosRegistry struct {
    // nacos sdk 的client
    client naming_client.INamingClient
    // 可选参数，初始化的时候可以通过 registry.Option 方法指定配置
    opts   registry.Options
}

func init() {
    // 设置为默认配置
    cmd.DefaultRegistries["nacos"] = NewRegistry
}

// NewRegistry NewRegistry
func NewRegistry(opts ...registry.Option) registry.Registry {
    n := &nacosRegistry{
        opts: registry.Options{},
    }
    if err := configure(n, opts...); err != nil {
        panic(err)
    }
    return n
}

// 这个方法总结下来就是干了一件事：配置初始化
func configure(n *nacosRegistry, opts ...registry.Option) error {
    // set opts
    for _, o := range opts {
        o(&n.opts)
    }

    clientConfig := constant.ClientConfig{}
    serverConfigs := make([]constant.ServerConfig, 0)
    contextPath := "/nacos"

    cfg, ok := n.opts.Context.Value(configKey{}).(constant.ClientConfig)
    if ok {
        clientConfig = cfg
    }
    addrs, ok := n.opts.Context.Value(addressKey{}).([]string)
    if !ok {
        addrs = []string{"127.0.0.1:8848"} // 默认连接本地
    }

    for _, addr := range addrs {
        // check we have a port
        host, port, err := net.SplitHostPort(addr)
        if err != nil {
            return err
        }

        p, err := strconv.ParseUint(port, 10, 64)
        if err != nil {
            return err
        }

        serverConfigs = append(serverConfigs, constant.ServerConfig{
            // Scheme:      "go.micro",
            IpAddr:      host,
            Port:        p,
            ContextPath: contextPath,
        })
    }

    if n.opts.Timeout == 0 {
        n.opts.Timeout = time.Second * 1
    }

    clientConfig.TimeoutMs = uint64(n.opts.Timeout.Milliseconds())
    // 创建客户端
    client, err := clients.CreateNamingClient(map[string]interface{}{
        constant.KEY_SERVER_CONFIGS: serverConfigs,
        constant.KEY_CLIENT_CONFIG:  clientConfig,
    })
    if err != nil {
        return err
    }
    n.client = client

    return nil
}


func (n *nacosRegistry) Init(opts ...registry.Option) error {
    _ = configure(n, opts...)
    return nil
}

func (n *nacosRegistry) Options() registry.Options {
    return n.opts
}

func (n *nacosRegistry) Register(s *registry.Service, opts ...registry.RegisterOption) error {
    var options registry.RegisterOptions
    for _, o := range opts {
        o(&options)
    }
    withContext := false
    // 处理参数
    param := vo.RegisterInstanceParam{}
    if options.Context != nil {
        if p, ok := options.Context.Value("register_instance_param").(vo.RegisterInstanceParam); ok {
            param = p
            withContext = ok
        }
    }
    if !withContext {
        host, port, err := getNodeIPPort(s)
        if err != nil {
            return err
        }
        s.Nodes[0].Metadata["version"] = s.Version
        param.Ip = host
        param.Port = uint64(port)
        param.Metadata = s.Nodes[0].Metadata
        param.ServiceName = s.Name
        param.Enable = true
        param.Healthy = true
        param.Weight = 1.0
        param.Ephemeral = true
    }

    // 注册节点
    _, err := n.client.RegisterInstance(param)
    return err
}

func (n *nacosRegistry) Deregister(s *registry.Service, opts ...registry.DeregisterOption) error {
    var options registry.DeregisterOptions
    for _, o := range opts {
        o(&options)
    }
    withContext := false
    param := vo.DeregisterInstanceParam{}
    if options.Context != nil {
        if p, ok := options.Context.Value("deregister_instance_param").(vo.DeregisterInstanceParam); ok {
            param = p
            withContext = ok
        }
    }
    if !withContext {
        host, port, err := getNodeIPPort(s)
        if err != nil {
            return err
        }
        param.Ip = host
        param.Port = uint64(port)
        param.ServiceName = s.Name
    }

    _, err := n.client.DeregisterInstance(param)
    return err
}

func (n *nacosRegistry) GetService(name string, opts ...registry.GetOption) ([]*registry.Service, error) {
    var options registry.GetOptions
    for _, o := range opts {
        o(&options)
    }
    withContext := false
    param := vo.GetServiceParam{}
    if options.Context != nil {
        // 可以通过context传参
        if p, ok := options.Context.Value("select_instances_param").(vo.GetServiceParam); ok {
            param = p
            withContext = ok
        }
    }
    if !withContext {
        param.ServiceName = name
    }
    service, err := n.client.GetService(param)
    if err != nil {
        return nil, err
    }
    services := make([]*registry.Service, 0)
    for _, v := range service.Hosts {
        //log.Printf("%+v\n", v)
        // 跳过不正常的节点
        if !v.Healthy || !v.Enable || v.Weight <= 0 {
            continue
        }

        nodes := make([]*registry.Node, 0)
        nodes = append(nodes, &registry.Node{
            Id:       v.InstanceId,
            Address:  net.JoinHostPort(v.Ip, fmt.Sprintf("%d", v.Port)),
            Metadata: v.Metadata,
        })
        s := registry.Service{
            Name:     v.ServiceName,
            Version:  v.Metadata["version"],
            Metadata: v.Metadata,
            Nodes:    nodes,
        }
        services = append(services, &s)
    }

    return services, nil
}

func (n *nacosRegistry) ListServices(opts ...registry.ListOption) ([]*registry.Service, error) {
    var options registry.ListOptions
    for _, o := range opts {
        o(&options)
    }
    withContext := false
    param := vo.GetAllServiceInfoParam{}
    if options.Context != nil {
        if p, ok := options.Context.Value("get_all_service_info_param").(vo.GetAllServiceInfoParam); ok {
            param = p
            withContext = ok
        }
    }
    if !withContext {
        services, err := n.client.GetAllServicesInfo(param)
        if err != nil {
            return nil, err
        }
        param.PageNo = 1
        param.PageSize = uint32(services.Count)
    }
    services, err := n.client.GetAllServicesInfo(param)
    if err != nil {
        return nil, err
    }
    var registryServices []*registry.Service
    for _, v := range services.Doms {
        registryServices = append(registryServices, &registry.Service{Name: v})
    }
    return registryServices, nil
}

func (n *nacosRegistry) Watch(opts ...registry.WatchOption) (registry.Watcher, error) {
    return newWatcher(n, opts...)
}

func (n *nacosRegistry) String() string {
    return "nacos"
}

func getNodeIPPort(s *registry.Service) (host string, port int, err error) {
    if len(s.Nodes) == 0 {
        return "", 0, errors.New("you must deregister at least one node")
    }
    node := s.Nodes[0]
    host, pt, err := net.SplitHostPort(node.Address)
    if err != nil {
        return "", 0, err
    }
    port, err = strconv.Atoi(pt)
    if err != nil {
        return "", 0, err
    }
    return
}
```

watcher.go 是监听服务的逻辑：

```go

import (
    "fmt"
    "log"
    "net"
    "reflect"
    "sync"

    "github.com/asim/go-micro/v3/logger"
    "github.com/asim/go-micro/v3/registry"
    "github.com/nacos-group/nacos-sdk-go/v2/model"
    "github.com/nacos-group/nacos-sdk-go/v2/vo"
)

type watcher struct {
    n  *nacosRegistry // 注册实现
    wo registry.WatchOptions // 监听option

    next chan *registry.Result // 通过channel传递数据
    exit chan bool // 退出channel

    // 在内存中缓存数据并定时维护
    sync.RWMutex
    services      map[string][]*registry.Service
    cacheServices map[string][]model.Instance
    param         *vo.SubscribeParam
    Doms          []string
}

func newWatcher(nr *nacosRegistry, opts ...registry.WatchOption) (registry.Watcher, error) {
    var wo registry.WatchOptions
    for _, o := range opts {
        o(&wo)
    }
    nw := watcher{
        n:             nr,
        wo:            wo,
        exit:          make(chan bool),
        next:          make(chan *registry.Result, 10),
        services:      make(map[string][]*registry.Service),
        cacheServices: make(map[string][]model.Instance),
        param:         new(vo.SubscribeParam),
        Doms:          make([]string, 0),
    }
    withContext := false
    if wo.Context != nil {
        if p, ok := wo.Context.Value("subscribe_param").(vo.SubscribeParam); ok {
            nw.param = &p
            withContext = ok
            nw.param.SubscribeCallback = nw.callBackHandle
            go nr.client.Subscribe(nw.param)
        }
    }
    if !withContext {
        param := vo.GetAllServiceInfoParam{}
        services, err := nr.client.GetAllServicesInfo(param)
        if err != nil {
            return nil, err
        }
        param.PageNo = 1
        param.PageSize = uint32(services.Count)
        services, err = nr.client.GetAllServicesInfo(param)
        if err != nil {
            return nil, err
        }
        nw.Doms = services.Doms
        for _, v := range nw.Doms {
            param := &vo.SubscribeParam{
                ServiceName:       v,
                SubscribeCallback: nw.callBackHandle,
            }
            go nr.client.Subscribe(param)
        }
    }

    return &nw, nil
}

// callBackHandle 回调函数注册到nacosSDK内，监听的服务有变化时 会被调用
func (nw *watcher) callBackHandle(services []model.Instance, err error) {
    if err != nil {
        logger.Error("nacos watcher call back handle error:%v", err)
        return
    }
    serviceName := services[0].ServiceName

    if nw.cacheServices[serviceName] == nil {

        nw.Lock()
        nw.cacheServices[serviceName] = services
        nw.Unlock()

        for _, v := range services {
            nw.next <- &registry.Result{Action: "create", Service: buildRegistryService(&v)}
            return
        }
    } else {
        for _, subscribeService := range services {
            create := true
            for _, cacheService := range nw.cacheServices[serviceName] {
                if subscribeService.InstanceId == cacheService.InstanceId {
                    if !reflect.DeepEqual(subscribeService, cacheService) {
                        //update instance
                        nw.next <- &registry.Result{Action: "update", Service: buildRegistryService(&subscribeService)}
                        return
                    }
                    create = false
                }
            }
            //new instance
            if create {
                log.Println("create", subscribeService.ServiceName, subscribeService.Port)

                nw.next <- &registry.Result{Action: "create", Service: buildRegistryService(&subscribeService)}

                nw.Lock()
                nw.cacheServices[serviceName] = append(nw.cacheServices[serviceName], subscribeService)
                nw.Unlock()
                return
            }
        }

        for index, cacheService := range nw.cacheServices[serviceName] {
            del := true
            for _, subscribeService := range services {
                if subscribeService.InstanceId == cacheService.InstanceId {
                    del = false
                }
            }
            if del {
                log.Println("del", cacheService.ServiceName, cacheService.Port)
                nw.next <- &registry.Result{Action: "delete", Service: buildRegistryService(&cacheService)}

                nw.Lock()
                nw.cacheServices[serviceName][index] = model.Instance{}
                nw.Unlock()

                return
            }
        }
    }

}

func buildRegistryService(v *model.Instance) (s *registry.Service) {
    nodes := make([]*registry.Node, 0)
    nodes = append(nodes, &registry.Node{
        Id:       v.InstanceId,
        Address:  net.JoinHostPort(v.Ip, fmt.Sprintf("%d", v.Port)),
        Metadata: v.Metadata,
    })
    s = &registry.Service{
        Name:     v.ServiceName,
        Version:  "latest",
        Metadata: v.Metadata,
        Nodes:    nodes,
    }
    return
}

// watcher 实现了 register.Watcher 接口，该方法为阻塞的，只有服务有变化时 next channel里才会有值
func (nw *watcher) Next() (r *registry.Result, err error) {
    select {
    case <-nw.exit:
        return nil, registry.ErrWatcherStopped
    case r, ok := <-nw.next:
        if !ok {
            return nil, registry.ErrWatcherStopped
        }
        return r, nil
    }
}

func (nw *watcher) Stop() {
    select {
    case <-nw.exit:
        return
    default:
        close(nw.exit)
        if len(nw.Doms) > 0 {
            for _, v := range nw.Doms {
                param := &vo.SubscribeParam{
                    ServiceName:       v,
                    SubscribeCallback: nw.callBackHandle,
                }
                _ = nw.n.client.Unsubscribe(param)
            }
        } else {
            _ = nw.n.client.Unsubscribe(nw.param)
        }
    }
}

```

不难发现，其实在接口定义好的情况下，写其实现方法不难，只要按照接口定义和含义，正常逻辑逻辑即可。
这段代码我已经 PR 到 `go-micro` 项目 ，可以在GitHub上直接查看源码。[传送门](https://github.com/asim/go-micro/tree/master/plugins/registry/nacos)。
