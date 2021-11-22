# 部署单机 k8s 集群


本文介绍本地或服务器上搭建单节点的 k8s 集群和 webUI 以及启用ingress，可以用作开发和测试环境。


## 准备工作

所需工具：

-   docker
-   minkube
-   kubectl

如何安装 docker 就不再这里撰述。

### 安装 minikube

[官方文档](https://v1-18.docs.kubernetes.io/zh/docs/tasks/tools/install-minikube/)

**Mac**

```shell
$ brew install minkube
```

**linux**

```shell
$ curl -Lo minikube https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64 \
  && chmod +x minikube
```

将 Minikube 可执行文件添加至 PATH：

```shell
sudo mkdir -p /usr/local/bin/
sudo install minikube /usr/local/bin/
```

也可以在 [GitHub](https://github.com/kubernetes/minikube) 上下载系统对应的二级制文件



### 安装 kubectl

[官方文档](https://v1-18.docs.kubernetes.io/zh/docs/tasks/tools/install-kubectl/#install-kubectl-on-linux)

**Mac**

```shell
$ brew install kubernetes-cli
```

**Linux**

```shell
$ sudo apt-get update && sudo apt-get install -y apt-transport-https
$ curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add -
$ echo "deb https://apt.kubernetes.io/ kubernetes-xenial main" | sudo tee -a /etc/apt/sources.list.d/kubernetes.list
$ sudo apt-get update
$ sudo apt-get install -y kubectl
```

## 启动&检查

**启动**

```shell
$ minikube start --vm-driver=docker
```

**检查**

```shell
$ minikube status
minikube
type: Control Plane
host: Running
kubelet: Running
apiserver: Running
kubeconfig: Configured
```

至此集群已经部署成功，可以通过 `kubectl` 命令查看状态

```shell
$ kubectl cluster-info
Kubernetes control plane is running at https://xxx.xxx.xx.xx:8443
CoreDNS is running at https://xxx.xxx.xx.xx:8443/api/v1/namespaces/kube-system/services/kube-dns:dns/proxy
```


## 停止&清理

**停止**

```shell
$ minkube stop
```

**清理**

```shell
$ minikube delete
```



## webUI

安装 k8s 管理 dashboard。

```shell
$ minikube dashboard --url
🤔  Verifying dashboard health ...
🚀  Launching proxy ...
🤔  Verifying proxy health ...
http://127.0.0.1:35983/api/v1/namespaces/kubernetes-dashboard/services/http:kubernetes-dashboard:/proxy/
```

`minikube` 会安装 dashboard 并返回可访问的 url,  如果是本地则直接访问即可。

如果是服务器上，则需要执行以下命令：

```shell
$ kubectl proxy --address='0.0.0.0' --disable-filter=true
W0907 17:47:12.246841  591818 proxy.go:162] Request filter disabled, your proxy is vulnerable to XSRF attacks, please be cautious
Starting to serve on [::]:8001
```

并通过`http://serverIP:8001/api/v1/namespaces/kubernetes-dashboard/services/http:kubernetes-dashboard:/proxy/`访问 dashboard 。

## Ingress

启动 ingress 也是需要通过 `minikube` 命令执行。

```shell
$ minikube addons enable ingress
```

`minikube` 会开启 ingress 并安装 `ingress-nginx`, 我们只需要写 `ingress` 规则即可。然后通过 `kubectl` 命令查看可访问的虚拟 ip。

```shell
$ kubectl get ingress
NAME            CLASS    HOSTS   ADDRESS        PORTS   AGE
goapp-ingress   <none>   *       192.168.49.2   80      2d
$ curl 192.168.49.2/ping
"pong"
```

可以访问的通的。



>   相关连接:
>
>   -   https://v1-18.docs.kubernetes.io/zh/docs/tasks/tools/install-minikube/
>
>   -   https://kubernetes.io/zh/docs/tasks/access-application-cluster/ingress-minikube/
>
>   -   https://stackoverflow.com/questions/47173463/how-to-access-local-kubernetes-minikube-dashboard-remotely

