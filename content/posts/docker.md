---
title: "Docker 基础知识和基本操作"
date: 2017-07-17T15:52:00+08:00
updated: 2017-07-17T15:52:01+08:00
categories:
- 技术环境
tags:
- go
- docker
---

关于 容器、Docker 的基础知识、基础操作和常用的命令。

# Docker 基础知识和使用

## 关于Docker

### 容器技术


对于容器，目前并没有一个严格的定义，但是普遍被认可的说法是，它首先必须是一个相对独立的环境，在这一点上有点类似虚拟机，但是没有虚拟机那么彻底。另外，在一个容器环境中，应该最小化其对外界的影响，比如不能在容器中吧host上的资源耗尽，这就是资源的控制。

容器技术之所以受欢迎，一个重要的原因是它已经集成到了 Linux 内核中，已经被当作 Linux 内核原生提供的特征。当然其他平台也有相应的容器技术，但是我们讨论的以及Docker涉及的都是指 Linux 平台上的容器技术。

一般来说，容器技术主要包括Namespace和Cgroup两个内核特征。

- Namespace 命名空间，它主要做的是访问隔离。其原理是对一类资源进行抽象，并将其封装在一起提供给容器使用，对于这类资源，因为每个容器都有自己的抽象，而他们彼此之间是不可见的，所以就做到访问隔离。
- Cgroup是 control group 的简称，又称为控制组，它主要是控制资源控制。其原理是将一组进程放在一个控制组里，通过给这个控制组分配指定的可用资源，达到控制这一组进程可用资源的目的。


容器最核心技术是 Namespace+Cgroup，但是光有这两个抽象的技术概念是无法组成一个完整的容器的。
对于 linux 容器的最小组成，是由一下四个部分构成：
- Cgroup： 资源控制。
- Namespace： 访问隔离。
- rootfs： 系统文件隔离。
- 容器引擎： 生命周期控制。

### 容器的创建原理
代码一
```c
pid = clone(fun, stack, flags, clone_arg);

(flags: CLONE_NEWPID | CLONE_NEWNS |
     CLONE_NEWUSER | CLONE_NEWNET |
     CLONE_NEWIPC | CLONE_NEWUTS |
        ...)

```
- 对于以上代码，通过clone系统调用，并传入各个Namespace对应的clone flag，创建了一个新的子进程，该进程拥有自己的Namespace。从上面的代码可以看出，该进程拥有自己的pid,mount,user,net,ipc,uts namespace 。


代码二：
```sh
echo $pid > /sys/fs/cgroup/cpu/tasks
echo $pid > /sys/fs/cgroup/cpuset/tasks
echo $pid > /sys/fs/cgroup/blkio/tasks
echo $pid > /sys/fs/cgroup/memory/tasks
echo $pid > /sys/fs/cgroup/devices/tasks
echo $pid > /sys/fs/cgroup/freezer/tasks
```
- 对于代码二，将代码一中的pid写入各个Cgroup子系统中，这样该进程就可以受到相应Cgroup子系统的控制。

代码三：
```sh
fun ()
{
    ...
    
    pivot_root("path_of_rootfs/", path);
    ...
    
    exec("/bin/bash");
    ...
}
```
- 对于代码三，该fun函数由上面生成的新进程执行，在fun函数中，通过`pivot_root`系统调用，使进程进入新的`rootfs`，之后通过`exec`系统调用，在新的`Namespace`,`Cgroup`,`rootfs`中执行`"/bin/bash"`程序。

通过以上操作，成功在一个“容器”中运行了一个bash程序。对于Cgroup和Namespace的技术细节，我们下一节详细描述


### Cgroup
#### Cgroup 是什么
Cgroup是control group 的简写，属于 Linux 内核提供的一个特性，用于限制和隔离一组进程对系统资源的使用。这些资源主要包括 CPU， 内存， block I/O（数据块 I/O） 和网络宽带。
Cgroup 从 2.6.24版本进入内核主线，目前各大发行版linux都默认打开了 Cgroup 特性


从实现的角度来看，Cgroup 实现了一个通用的进程分组的框架，而不同资源的具体管理则是由各个 Cgroup 子系统实现的。截止内核4.1版本，Cgroup 中实现的子系统的及其作用如下：
- devices： 设备权限控制
- cpuset： 分配指定的CPU和内存节点
- cpu： 控制 CPU 占用率
- cpuacct： 统计 CPU 使用情况
- memory： 限制内存的使用上限
- freezer： 冻结（暂停）Cgroup 中的进程
- net_cls： 配合tc（traffic controller）限制网络宽带
- net_prio： 设置进程的网络流量优先级
- huge_tlb： 限制HugeTLB（块表缓冲区）的使用
- perf_event： 允许 Perf 工具基于Cgroup分组做性能测试

### Namespace
#### Namespace 是什么
Namespace 是将内核的全局资源做封装，使得每个Namespace都有有一份独立的资源，因此不同的进程各自的 Namespace 内对同一个资源的使用不会互相干扰。
举个例子，执行 sethostname 这个系统调用时，可以改变系统的主机名，这个主机名就是一个内核的全局资源。内核通过实现 UTS Namespace，可以将不同的进程分隔在不同的 UTS Namespace 中，在某个 Namespace 修改主机名时，另一个 Namespace 的主机名还是保持不变。


目前 Linux 内核总共实现了6种 Namespace：
- IPC： 隔离 System V IPC 和 POSIX 消息队列
- Network： 隔离网络资源
- Mount： 隔离文件系统挂载点
- PID： 隔离进程 ID
- UTS： 隔离主机名和域名
- User： 隔离用户 ID 和 组 ID

Namespace 和 Cgroup 的使用是灵活的，同时也有不少需要注意的地方，因此直接操作 Namespace 和 Cgroup 并不是很容易。正是因为这些原因，Docker 通过 Libcontainer 来处理这些底层的事情。这样一来，Docker 只需简单地调用 Libcontainer 的 API ，就能将完整的容器搭建起来。而作为 Docker 的用户，就更不用操心这些事情了。


### 容器造就 Docker
关于容器是否是 Docker 的技术核心技术，业界一直存在着争议。

在理解了容器，理解了容器的核心技术 Cgroup 和 Namespace，理解了容器技术如何巧妙且轻量地实现“容器”本身的资源控制和访问隔离之后，可以看到 Docker 和容器是一种完美的融合和辅助相成的关系，它们不是唯一的搭配，但一定是最完美的结合（目前来说）。与其说是容器造就了 Docker ， 不如说是它们造就了彼此，容器技术让 Docker 得到更多的应用和推广，Docker 也使得容器技术被更多人熟知。

## 基本操作

### 启动容器

#### 新建并启动

所需的命令是 `docker run`

例如：

``` shell
$ docker run ubuntu:14.04 /bin/echo 'hello, worl'
```

容器执行后面的命令直接就会终止 .

下面的命令会启动容器并起一个 bash 终端,允许用户进行交互

``` shell
$ docker run -t -i ubuntu:14.04 /bin/bash
```

其中 `-t`  让 Docker 分配一个伪终端 (pseudo-tty) 并绑定到容器的标准输入上, `-i` 则让容器的标准输入保持打开 .

利用 docker run 来创建容器是, Docker 在后台运行的标准操作包括:

* 检查本地是否存在指定的镜像,不存在就从共有仓库下载
* 利用镜像创建并启动一个容器
* 分配一个文件系统并在只读的镜像层外面挂载一层可读写层
* 在宿主主机配置的网桥接口中桥接一个虚拟接口到容器中去
* 从地址池配置一个 ip 地址给容器
* 执行用户指定的应用程序
* 执行完毕后容器终止

#### 启动已终止容器

可以利用 `docker start` 命令,直接将一个已经终止的容器启动运行 .

可以通过 `docker ps -a` 查看所有的容器和其状态

```shell
CONTAINER ID        IMAGE                   COMMAND                  CREATED             STATUS                     PORTS                    NAMES
aada74689bf7        cockroachdb/cockroach   "/cockroach/cockro..."   3 weeks ago         Exited (137) 3 weeks ago                            roach_master
2e9eb6cf3f66        owncloud                "/entrypoint.sh ap..."   3 weeks ago         Up 3 weeks                 0.0.0.0:80->80/tcp       owncloud
91290c737c73        postgres                "docker-entrypoint..."   3 weeks ago         Up 3 weeks                 5432/tcp                 owncloud-postgres
8f546ec65e61        mysql                   "docker-entrypoint..."   3 weeks ago         Up 3 weeks                 0.0.0.0:3306->3306/tcp   mysql
```

不难发现 name 为 roch_master 的容器已经终止了,想重新启动它,可以执行下面的命令

```shell
$ docker start aada74689bf7
```

参数为容器的 id .

### 后台( background )运行

在很多时候,我们需要让 docker 在后台运行而并不是把执行结果直接输出出来.

这个时候我们可以添加 `-d` 参数来实现

如果使用 `-d` 参数运行容器

``` shell
$ docker run -d mysql:5.7.17
77b2dc01fe0f3f1265df143181e7b9af5e05279a884f4776ee75350ea9d8017a
```

只会输出运行的容器 id, 而输出结果可以用 docker logs 查看 .

```shell
$ docker logs [container ID or NAMES]
```

### 终止容器

可以使用 `docker stop`  来终止正在运行的容器 .

此外,当 Docker 容器中指定的应用终结时, 容器也自动终止 . 例如运行一个容器时,指定了一个终端后,当退出终端的时候,所创建的容器也会立刻终止 .

终止状态的容器, 可以通过 `docker start` 来重新启动 .

此外,`docker restart` 命令会将一个运行态的容器终止,然后重新启动它 .

### 进入容器

在使用 `-d` 参数时, docker 容器会在后台运行. 有些时候需要进入容器,如运行数据库时,需要进入增删改查库里的内容. 进入容器有很多种办法.

#### attach 命令

`docker attach` 是 Docker 自带的命令,用法

但是使用 `attach` 命令有个缺陷,即多个窗口同时用 attach 命令到同一个容器的时候,所有的窗口都是同步显示的,如果其中一个窗口阻塞的时候,其他窗口也无法使用 .

#### nsenter 命令

这个工具需要用如下命令安装

```shell
$ docker run --rm -v /usr/local/bin:/target jpetazzo/nsenter
```

使用方法也比较简单,首先是你要进入的容器的 ID

```shell
$ PID=$(docker inspect --format {{.State.Pid}} <container ID or NAMES>)
```

然后通过这个 PID 进入容器

```shell
$ nsenter --target $PID --mount --uts --ipc --net --pid
```

如果无法通过上述的命令连接到容器,有可能是因为宿主的默认 shell 在容器中并不存在,比如 zsh, 可以使用如下命令显示地使用 bash .

#### exec 命令

```shell
$docker exec -it [container ID or NAMES]
```

`-i` `-t` 前面说过为了标准输入输出保持打开 .

### 导出和导入容器

#### 导出容器

如果要导出本地某个容器,可以使用 `docker export` 命令 .

```shell
$ docker export [container ID or NAMES] > target.tar
```

这样将导出容器快照到本地文件 .

#### 导入容器快照

可以使用 `docker import` 从容器快照文件导入镜像,

```shell
$ cat target.tar | docker import - test/mysql:v1.0
$ sudo docker images
REPOSITORY  TAG  IMAGE ID 		CREATED 			VIRTUAL SIZE
test/ubuntu v1.0 9d37a6082e97 	About a minute ago 	171.3 MB
```

此外,还可以通过指定 URL 或者某个目录来导入

``` shell
$ docker import http://example.com/exampleimage.tgz example/imagerepo
```

*注：用户既可以使用 docker load 来导入镜像存储文件到本地镜像库,也可以使用 docker import 来导入一个容器快照到本地镜像库 .这两者的区别在于容器快照文件将丢弃所有的历史记录和元数据信息（即仅保存容器当时的快照状态）,而镜像存储文件将保存完整记录,体积也要大 .此外,从容器快照文件导入时可以重新指定标签等元数据信息 .

### 删除容器

#### 单独删除

可以使用 `docker rm` 来删除一个处于终止状态的容器 .

```shell
$ docker rm [container ID or NAMES]
```

如果要删除一个运行中的容器,可以添加 `-f` 参数 .Docker 会发送 `SIGKILL` 信号给容器 .

#### 清理所有处于终止状态的容器

用  `docker ps -a`  命令可以查看所有已创建的包括终止状态的容器,如果想批量删除多个容器的话(当然是终止状态的容器) ,可以用这个命令

```shell
$ docker rm $(docker ps -a -q)
```

*注意：这个命令其实会试图删除所有的包括还在运行中的容器,不过就像上面提过的 docker rm 默认并不会删除运行中的容器 .

## 访问仓库

仓库（Repository）是集中存放镜像的地方 .

一个容易混淆的概念是注册服务器（Registry） .实际上注册服务器是管理仓库的具体服务器,每个服务器上可以有多个仓库,而每个仓库下面有多个镜像 .从这方面来说,仓库可以被认为是一个具体的项目或目录 .例如对于仓库地址dl.dockerpool.com/ubuntu 来说, dl.dockerpool.com 是注册服务器地址, ubuntu 是仓库名 .

大部分时候,并不需要严格区分这两者的概念 .

### Docker Hub

目前 Docker 官方维护了一个公共仓库 [Docker Hub](https://hub.docker.com/explore/),   但是开始把阵地移到 [Docker Store](https://store.docker.com/) 这个平台上,其上能找到几乎所有的能想得到的容器, 不可小觑 .

#### 登录

可以通过执行 docker login 命令来输入用户名、密码和邮箱来完成注册和登录 . 注册成功后,本地用户目录的.dockercfg 中将保存用户的认证信息 .

#### 基本操作

用户无需登录即可通过 `docker search` 命令来查找官方仓库中的镜像, 并利用 `docker pull` 命令来将它下载到本地 .

以搜索 mongo 为关键字搜索:

```shell
$ docker search mongo
NAME                           DESCRIPTION                                     STARS     OFFICIAL   AUTOMATED
mongo                          MongoDB document databases provide high av...   3427      [OK]
mongo-express                  Web-based MongoDB admin interface, written...   168       [OK]
mvertes/alpine-mongo           light MongoDB container                         51                   			[OK]
mongoclient/mongoclient        Official docker image for Mongoclient, fea...   29                   			[OK]
torusware/speedus-mongo        Always updated official MongoDB docker ima...   9                    			[OK]
mongooseim/mongooseim-docker   MongooseIM server the latest stable version     9                    			[OK]
```

​搜索结果可以看到很多包含关键字的镜像,其中包括镜像名字、描述、星数（表示该镜像的受欢迎程度）、是否官方创建、是否自动创建 . 官方的镜像说明是官方项目组创建和维护的,automated 资源允许用户验证镜像的来源和内容 .

​根据是否为官方提供, 镜像资源可分为两类 . 一类是累类似 mongo这样的基础镜像 . 这些镜像由 Docker 的用户创建、验证、支持、提供  . 这样的镜像往往是使用单个单词作为名字  . 

另一种类型,比如`mvertes/alpine-mongo` 镜像,它是由 Docker 的用户创建并维护的,往往带有用户名称前缀  . 可以通过前缀 `user_name/` 来指定使用某个用户提供的镜像  .

另外,在查找的时候通过 `-s N` 参数可以指定仅显示星数为 N 以上的镜像 （新版本的 Docker 推荐使用 `--flter=stars=N` 参数） .

下载镜像到本地

```shell
$ sudo docker pull centos
Pulling repository centos
0b443ba03958: Download complete
539c0211cd76: Download complete
511136ea3c5a: Download complete
7064731afe90: Download complete
```

用户也可以登录之后通过 `docker push` 命令来讲镜像推送到 Docker Hub  .

#### 自动创建

​自动创建（automated builds）功能对于需要经常升级镜像内程序来说,十分方便 .有时候,用户创建了镜像安装了某个软件,如果软件发布新版本则需要手动更新镜像 . .而自动创建允许用户通过 Docker Hub 指定跟踪一个目标网站（目前支持 GitHub或 BitBucket）上的项目,一旦项目发生新的提交,则自动执行创建 .

要配置自动创建,包括如下的步骤：

* 创建并登录 Docker Hub,以及目标网站；
* 在目标网站中连接帐户到 Docker Hub；
* 在 Docker Hub 中 配置一个自动创建；
* 选取一个目标网站中的项目（需要含 Dockerfile）和分支；
* 指定 Dockerfile 的位置,并提交创建 .

之后,可以 在Docker Hub 的 自动创建页面 中跟踪每次创建的状态 .

### 私有仓库

有时候使用 Docker Hub 这样的公共仓库由于网络等原因可能不方便,用户可以创建一个本地仓库供私人使用 .

需要用到 `docker-registry` 工具 .

`docker-registry` 是官方提供的工具,可以用于构建私有的镜像仓库  .

#### 安装运行 docker-registry

##### 容器运行

在安装了 Docker 后,可以通过获取官方 registry 镜像来运行  .

```shell
$ docker run -d -p 5000:5000 registry
```

这将使用官方的 registry 镜像来启动本地的私有仓库 .用户可以通过制定参数来配置私有仓库位置,例如配置镜像存储到 Amazon S3 服务  .

```shell
$ sudo docker run \
-e SETTINGS_FLAVOR=s3 \
-e AWS_BUCKET=acme-docker \
-e STORAGE_PATH=/registry \
-e AWS_KEY=AKIAHSHB43HS3J92MXZ \
-e AWS_SECRET=xdDowwlK7TJajV1Y7EoOZrmuPEJlHYcNP2k4j49T
\
-e SEARCH_BACKEND=sqlalchemy \
-p 5000:5000 \
registry
```

此外,还可以指定本地路径（如`/home/user/registry-conf` ）下的配置文件  .

```shell
$ sudo docker run -d -p 5000:5000 -v /home/user/registry-conf:/r
egistry-conf -e DOCKER_REGISTRY_CONFIG=/registry-conf/config.yml
registry
```

 默认情况下,仓库会被创建在容器的 `/var/lib/registry` 下 .可以通过 `-v`  参数来将镜像文件存放在本地的指定路径  . 例如下面的例子将上传的镜像放到 `/opt/data/registy` 目录  .

``` shell
$ sudo docker run -d -p 5000:5000 -v /opt/data/registry:/var/lib
/registry registry
```

#### 本地安装

对于 Ubuntu 或 CentOS 等发行版,可以直接安装  .

* Ubuntu

``` shell
$ sudo apt-get install -y build-essential python-dev libevent-dev python-pip liblzma-dev
$ sudo pip install docker-registry
```

* CentOS

```shell
$ sudo yum install -y python-devel libevent-devel python-pip gcc xz-devel
$ sudo python-pip install docker-registry
```

也可以从 docker-registry 项目下载源码进行安装  .

```shell
$ sudo apt-get install build-essential python-dev libevent-dev python-pip libssl-dev liblzma-dev libffi-dev
$ git clone https://github.com/docker/docker-registry.git
$ cd docker-registry
$ sudo python setup.py install
```

然后修改配置文件,主要修改 dev 模板段的 `storage_path` 到本地的存储仓库的路径  .

```shell
$ cp config/config_sample.yml config/config.yml
```

之后启动 web 服务  .

```shell
$ sudo gunicorn -c contrib/gunicorn.py docker_registry.wsgi:application
```

或者 

```shell
$ sudo gunicorn --access-logfile - --error-logfile - -k gevent -b 0.0.0.0:5000 -w 4 --max-requests 100 docker_registry.wsgi:application
```

此时使用 crul 访问本地的 5000 端口,看到输出 docker-registry 的版本信息说明运行成功  .

*注 ： `config/config_sample.yml` 文件时示例配置文件



#### 在私有仓库上传、下载、搜索镜像

创建好私有仓库之后,就可以使用 `docker tag` 来标记一个镜像,然后推送它到仓库,别的机器上就可以下载了 .如 私有仓库地址为 `1192.168.7.26:5000`

先在本机上查看已有的镜像  .

```shell
$ docker images
REPOSITORY              TAG                 IMAGE ID            CREATED             SIZE
node                    latest              f93ba6280cbd        3 weeks ago         667MB
cockroachdb/cockroach   latest              404f7ee26d38        4 weeks ago         163MB
postgres                latest              ca3a55649cfc        7 weeks ago         269MB
tomcat                  latest              0785a1d16826        7 weeks ago         367MB
owncloud                latest              2327c8d59618        8 weeks ago         572MB
mysql                   latest              e799c7f9ae9c        2 months ago        407MB
```

使用 `docker tag` 将 `tomcat`  这个镜像标记为 `192.168.7.26：5000/test`

```shell
[root@vultr ~]# docker tag tomcat 192.168.7.26:5000/test
[root@vultr ~]# docker images
REPOSITORY               TAG                 IMAGE ID            CREATED             SIZE
node                     latest              f93ba6280cbd        3 weeks ago         667MB
cockroachdb/cockroach    latest              404f7ee26d38        4 weeks ago         163MB
postgres                 latest              ca3a55649cfc        7 weeks ago         269MB
192.168.7.26:5000/test   latest              0785a1d16826        7 weeks ago         367MB
tomcat                   latest              0785a1d16826        7 weeks ago         367MB
owncloud                 latest              2327c8d59618        8 weeks ago         572MB
mysql                    latest              e799c7f9ae9c        2 months ago        407MB
```

用 `docker push`  上传标记的镜像  .

``` shell
$ docker push 192.168.7.26:5000/test
The push refers to a repository [192.168.7.26:5000/test] (len: 1)
Sending image list
Pushing repository 192.168.7.26:5000/test (1 tags)
Image 511136ea3c5a already pushed, skipping
Image 9bad880da3d2 already pushed, skipping
Image 25f11f5fb0cb already pushed, skipping
Image ebc34468f71d already pushed, skipping
Image 2318d26665ef already pushed, skipping
Image ba5877dc9bec already pushed, skipping
Pushing tag for rev [ba5877dc9bec] on {http://192.168.7.26:5000/
v1/repositories/test/tags/latest}
```

用 `curl` 查看仓库中的镜像

```shell
curl http://192.168.7.26:5000/v1/search
{"num_results": 7, "query": "", "results": [{"description": "","name": "library/miaxis_j2ee"}, {"description": "", "name": "library/tomcat"}, {"description": "", "name": "library/ubuntu"}, {"description": "", "name": "library/ubuntu_office"}, {"description": "", "name": "library/desktop_ubu"}, {"description": "", "name": "dockerfile/ubuntu"}, {"description": "", "name": "library/test"}]}
```

这里可以看到 `{"description": "", "name": "library/test"}` ,表面镜像已经上传成功了  .

下载可以用另一台机器去下载这个镜像  .

```shell
$ docker pull 192.168.7.26:5000/test
Pulling repository 192.168.7.26:5000/test
ba5877dc9bec: Download complete
511136ea3c5a: Download complete
9bad880da3d2: Download complete
25f11f5fb0cb: Download complete
ebc34468f71d: Download complete
2318d26665ef: Download complete
$ docker images
REPOSITORY 		TAG 		IMAGE ID
CREATED 		VIRTUAL SIZE
192.168.7.26:5000/test latest ba5877dc9bec 
6 weeks ago 		192.7 MB
```

### 仓库配置文件

Docker 的 registry 利用配置文件提供 了一些仓库的模板（flavor）,用户可以直接使用它们来进行开发或身产环境  .

#### 模板

在 `config_sample.yml` 文件中,可以看到一些现成的模板段：

* `common` ：基础配置
* `local` ：存储数据到本地文件系统
* `s3` ：存储数据到 AWS S3 中
* `dev` ：使用 local 模板的基本配置
* `test` ：单元测试使用
* `prod` ：生产环境配置（基本上跟s3配置类似）
* `gcs` ：存储数据到 Google 的云存储
* `swift` ：存储数据到 OpenStack Swift 服务
* `glance` ：存储数据到 OpenStack Glance 服务,本地文件系统为后备
* `glance-swift `：存储数据到 OpenStack Glance 服务,Swift 为后备
* `elliptics` ：存储数据到 Elliptics key/value 存储

用户可以添加自定义的模板段  .

默认情况下使用的模板是 `dev` ,要是使用某个模板作为默认值,可以添加 `SETTING-FLAVOR` 到环境变量中去,

```shell
export SETTING_FLAVOR=dev
```

另外,配置文件中支持从环境变量中加载,语法格式为

```shell
_env:VARIABLENAME[:DEFAULT]
```

#### 示例配置

```shell
common:
loglevel: info
search_backend: "_env:SEARCH_BACKEND:"
sqlalchemy_index_database:
"_env:SQLALCHEMY_INDEX_DATABASE:sqlite:////tmp/docker-re
gistry.db"
prod:
loglevel: warn
storage: s3
s3_access_key: _env:AWS_S3_ACCESS_KEY
s3_secret_key: _env:AWS_S3_SECRET_KEY
s3_bucket: _env:AWS_S3_BUCKET
boto_bucket: _env:AWS_S3_BUCKET
storage_path: /srv/docker
smtp_host: localhost
from_addr: docker@myself.com
to_addr: my@myself.com
dev:
loglevel: debug
storage: local
storage_path: /home/myself/docker
test:
storage: local
storage_path: /tmp/tmpdockertmp
```

## Docker 数据管理

在容器管理中数据主要有两种方式：

* 数据卷 （Data volumes）
* 数据卷容器 （Data volume containers）

### 数据卷

数据卷是一个可提供一个或多个容器使用的特殊目录,它绕过 UFS, 可以提供很多有用的特征：

* 数据卷可以再荣期间共享和重用
* 对数据卷的修改立马生效
* 对数据及的更新,不会影响镜像
* 数据卷默认会一直存在,即使容器被删除

*注：数据卷的使用,类似于Linux 下对目录或文件进行 mount, 镜像中的被指定为挂载点的目录中的文件会隐藏掉,能显示看的是挂载的数据卷*

#### 创建一个数据卷

​在使用 `docker run ` 命令的时候,使用 `-v` 参数来创建一个数据卷并挂载到容器里 .在一次 run 中可以挂载多个数据卷  .

下面创建一个名为 web 的容器,并加载一个数据卷到容器的 `/webapp` 目录  .

```shell
$ docker run -d -p --name web -v /webapp training/webapp python app.py
```

*注：也可以在 Docker 中使用 `volume` 来添加一个或多个新的卷到有该镜像创建的任意容器  .*

#### 删除数据卷

数据卷是被设计用来持久化数据的,它的生命周期独立于容器,Docker 不会在容器被删除后自动删除数据卷,并且也不存在垃圾回收这样的机制来处理没有任何容器引用的数据卷 .日光需要在删除容器的同时移除数据卷,可以再删除容器的时候使用 `docker rm -v` 这个命令 .

#### 挂载一个主句目录作为数据卷

使用 `-v` 参数也可以指定挂载一个本地主机的目录到容器中去  .

```shell
$ sudo docker run -d -P --name web -v /src/webapp:/opt/webapp training/webapp python app.py
```

​	上面的命令加载主机的 `/src/webapp` 目录到容器的 `/opt/webapp` 目录 .这个功能在进行测试的时候十分方便,比如用户可以放置一些程序到本地目录中,来查看容器是否正常工作 .本地目录的路径必须是绝对路径,如果目录不存在 Docker会自动为你创建它 .

*注：Dockerfile 中不支持这种用法,因为 Dockerfile 是为了移植和分享用的  . 然而,不同的操作系统的路径格式不一样,所以目前还不支持* 

Docker 挂载数据卷的默认权限是读写, 用户也可以通过 `:ro` 指定为只读

```shell
$ sudo docker run -d -P --name web -v /src/webapp:/opt/webapp:ro training/webapp python app.py
```

加了 `:ro` 之后,就挂载为只读了 .



#### 查看数据卷的具体信息

在主机里使用以下命令可以查看指定容器的信息

```shell
$ docker inspect web
...
```

在输出的内容中找到其中和数据卷相关的部分,可以看到所有的数据卷都是创建在主句的 `/var/lib/docker/volumes/` 下面的

```shell
"Volumes": {
"/webapp": "/var/lib/docker/volumes/fac362...80535"
},
"VolumesRW": {
"/webapp": true
}
...
```

*注：从 Docker 1.8.0 起,数据卷配置在 “Mounts” Key 下面, 可以看到所有的数据卷都是创建在主机的 `/mnt/sda1/var/lib/docker/volumes/...` 下面了  .*

```json
"Mounts": [
{
"Name": "b53ebd40054dae599faf7c9666acfe205c3e922
fc3e8bc3f2fd178ed788f1c29",
"Source": "/mnt/sda1/var/lib/docker/volumes/b53e
bd40054dae599faf7c9666acfe205c3e922fc3e8bc3f2fd178ed788f1c29/_data",
"Destination": "/webapp",
"Driver": "local",
"Mode": "",
"RW": true,
"Propagation": ""
}
]
...
```

#### 挂载一个本地主机文件作为数据卷

`-v` 参数也可以从主机挂载单个文件到文件到容器中

```shell
$ sudo docker run --rm -it -v ~/.bash_history:/.bash_history ubuntu /bin/bash
```

这样就可以记录在容器输入过得命令了  .

### 数据卷容器

如果你有一些持续更新的数据需要在容器之间共享,最好创建数据卷容器  .

数据卷容器,其实就是一个正常的容器,专门用来提供数据卷供其他容器挂载的  .

首先,创建一个名为 dbdata 的数据卷容器：

```shell
$ sudo docker run -d -v /dbdata --name dbdata training/postgres echo Data-only container for postgres
```

然后,在其他容器中使用 `--volumes-from` 来挂载 dbdata 容器中的数据卷  .

```shell
$ sudo docker run -d --volumes-form dbdata --name db1 training/postgres
$ sudo docker run -d --volumes-form dbdata --name db2 training/postgres
```

可以使用超过一个的`--volumes-from` 参数来指定从多个容器挂载不同的数据卷  . 也可以从其他已经挂载了数据卷的容器来级联挂载数据卷  .

```shell
$ docker run -d --name db3 --volumes-from db1 training/postgres
```

*注：使用 `--volumes-from`  参数所挂载数据卷的容器自己并不需要保持运行状态* 

如果删除了挂载的容器（包括 dbdata、db1 和 db2 ）,数据卷并不会被自动删除 .如果删除一个数据卷,必须在删除最后一个还挂着它的容器时使用 `docker rm -v` 命令来指定同时删除关联的容器 .这可以让用户在容器之间升级和移到数据卷 .

#### 利用数据卷容器来备份、恢复、迁移数据卷

可以利用数据卷对其中的数据进行备份、恢复和迁移 .

##### 备份

首先使用 `--volumes-from` 标记来创建一个加载 dbdata 数据卷的容器,并从主机挂载当前目录到容器的 /backup 目录 .命令如下：

```shell
$ sudo docker run --volumes-from dbdata -v$(pwd):/backup ubuntu tar cvf /backup/backup.tar /dbdata
```

容器启动后,使用了 `tar` 命令来将 dbdata 卷备份为容器中 /backup/backup.tar 文件,也就是主机当前目录下的名为 backup.tar 的文件  .

##### 恢复

如果要恢复数据到一个容器,首先创建一个带有空数据卷的容器 dbdata2  .

```shell
$ docker run -v /dbdata --name dbdata2 ubuntu /bin/bash
```

然后创建另一个容器,挂载 dbdata2 容器卷中的数据卷,并使用 `untar`  解压备份文件到挂载的容器卷中 .

```shell
$ sudo docker run --volumes-form dbdata2 -v $(pwd):/backup busybox tar xvf
/backup/backup.tar
```

为了查看/验证恢复的数据,可以再启动一个容器挂载同样的容器卷来查看

```shell
$ docker run --volumes-from dbdata2 busybox /bin/ls dbdata
```

##### 迁移数据卷

代写 . . .

# Docker 中的网络

Docker 允许通过外部访问容器或容器互联的方式来提供网络服务  .

## 外部访问容器

容器中可以与运行一些网络应用,要让外部也可以访问这些应用,可以通过 `-P`  或 `-p` 参数来指定端口映射 .

当使用 `-P` 参数时,Docker 会随机映射一个 `49000~49900` 的端口到内部容器开放的网络端口 .

使用 `docker ps` 可以看到,本地主机的49155 被映射到了容器的5000 端口  .

此时访问本机的49155 端口即可访问容器内 web 应用提供的界面 .

```shell
$ sudo docker run -d -P training/webapp python app.py
$ sudo docker ps -l
CONTAINER ID 		IMAGE 					COMMAND 		CREATED
STATUS 			PORTS 					NAMES
bc533791f3f5 		training/webapp:latest 	python app.py 	5 seconds ag
o Up 2 seconds 	0.0.0.0:49155->5000/tcp nostalgic_morse
```

`-P` （小写）则可以指定要映射的端口,并且在一个指定端口上只可以绑定一个容器 .支持的格式有

* `ip:HostPort:containerPort`
* `ip::containerPort`
* `hostPort:containerPort`

### 映射所有接口地址

使用 `hostPort ：containerPort` 格式本地的5000端口映射到容器的5000端口,可以执行

```shell
$ docker run -d -p 5000:5000 training/webapp python app.py
```

此时默认会绑定本地所有接口上的所有接口 .

### 映射到指定地址的指定端口

可以使用 `ip:hostPort:containerPort` 格式指定映射使用一个特定地址,比如 localhost 地址 127.0.0.1

```shell
$ sudo docker run -d -p 127.0.0.1:5000:5000 training/webapp python app.py
```

### 查看映射端口配置

使用 `docker port ` 来查看当前映射的端口配置,也可以查看到绑定的地址

```shell
$ docker port gogs
22/tcp -> 0.0.0.0:10022
3000/tcp -> 0.0.0.0:10080
```

可以看到 `gogs` 有两个容器内的端口 22, 3000 分别映射主机的10022,10080 端口  .

*注： -p 可以多次使用来绑定多个端口,也就是说一条命令可以有多个 -p ,如：上面👆的 gogs 容器就绑定了俩端口*

## 容器互联

容器的连接（linking）系统是除了端口映射外,另一种跟容器中应用交互的方式 .该系统会在源和接受容器之间创建一个通道,接受容器可以看到源容器指定的信息 .

### 自定义容器命名

连接系统依据容器的名称来执行 .因此,首先需要自定义一个好记的容器命名 .

虽然创建容器的时候,系统默认会分配给一个名字 .但是自定义命名容器的话,第一,好记,第二,可以作为有用的参考的 .

使用 `--name` 参数可以为容器自定义命名 .

```shell
$ docker run -d -p 8181:4040 --name own-cloud owncloud
```

使用 `docker ps` 来查看正运行的容器

```shell
CONTAINER ID        IMAGE               COMMAND                  CREATED             STATUS              PORTS                                            NAMES
2c2e766e86fd        owncloud            "/entrypoint.sh ap..."   23 hours ago        Up 23 hours         80/tcp, 0.0.0.0:8181->4040/tcp                   own-cloud
```



使用 `docker inspect` 命令来查看容器名字

```shell
$ docker inspect -f "{{.Name}}" 2c2e766e86fd
/own-cloud
```

*注：容器的名称是唯一的 .如果已经命名了一个叫 own-cloud 的容器,当你再次使用这个名词的时候,需要先把之前的的同名容器删除*

*tips：在执行  `docker run`  的时候可以添加  `—rm`  参数,这样容器在终止后立刻删除 .注意,`—rm` 和  `-d` 参数不能同时使用  .*

### 容器互联

使用 `--link` 参数可以让容器之间安全的进行交互 .

下面是,运行 `Nginx` 容器的时候把 `gogs` 这个容器连接上

```shell
docker run -d --name my_nginx --link gogs:app --link own-cloud:app2 -p 80:80 -v /root/nginx/config:/etc/nginx/conf.d nginx
```

此时,gogs 容器和 my_nginx 容器建立互联关系

`--link` 参数的格式为 `--link name:alias` ,其中 name 是要连接的容器名称, alias 是这个连接的别名  .

可以通过 `docker inspect ` 命令查看 my_nginx 容器信息,就会发现有这么一段信息

``` shell
"Links": [
                "/gogs:/trusting_brown/app",
                "/own-cloud:/trusting_brown/app2"
            ],
```

表面此容器已经连上两个容器, gogs 和 own-cloud,trusting_brown 是系统分配给 Nginx 的名称,连接名称分别是 app 和 app2  .

Docker 在两个互联的容器之间创建了一个安全的隧道,而且不用映射到它们的端口到主机上 .在启动被连接的容器的时候不用添加 -p 或 -P 参数,从而避免暴露端口到外部网络上 .

连接之后,在 Nginx 容器里,就会发生两个变化  .

一是环境变量 .在 Nginx 容器中会出现6个新增的环境变量,这些环境变量的名称分贝时由被连接的服务别名、端口等拼接而成的 .

*由于起得 gogs 容器有两个端口,所以其中 APP_PORT、APP_NAME、APP_ENV_GOGS_CUSTOM 是公用的,其它8个变量每四个的分别对应22, 3000 端口*

```shell
# env | grep APP
APP_PORT_3000_TCP=tcp://172.17.0.2:3000
APP_PORT_22_TCP_PROTO=tcp
APP_ENV_GOGS_CUSTOM=/data/gogs
APP_PORT_3000_TCP_ADDR=172.17.0.2
APP_PORT_3000_TCP_PROTO=tcp
APP_PORT_22_TCP_PORT=22
APP_PORT_3000_TCP_PORT=3000
APP_PORT=tcp://172.17.0.2:22
APP_NAME=/my_nginx/app
APP_PORT_22_TCP=tcp://172.17.0.2:22
APP_PORT_22_TCP_ADDR=172.17.0.2
```

二是 hosts 文件 .在 Nginx 容器的 hosts 文件看到下面的记录 .这就是说,一切访问 连接别名（app）、容器 ID（ac4c0cf35adf）和容器名（gogs）的请求都会被重新导向到实时实际的 app 的 ip 地址上 .

```shell
# cat /etc/hosts | grep app
172.17.0.2	app ac4c0cf35adf gogs
```





## 高级网络配置

当 Docker 启动时,会自动的主机上创建一个 `docker0` 虚拟网桥,实际上是 Linux 的一个 bridge,可以理解为一个软件交换机 .它会挂载到它的网口之间进行转发 .

```shell
$ ip addr | grep docker0
docker0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc noqueue state UP
    link/ether 02:42:23:c6:3f:1c brd ff:ff:ff:ff:ff:ff
    inet 172.17.0.1/16 scope global docker0
       valid_lft forever preferred_lft forever
    inet6 fe80::42:23ff:fec6:3f1c/64 scope link
       valid_lft forever preferred_lft forever
```

同时,Docker 随机分一个本地未占用的私有网段（在 [RFC1919](https://tools.ietf.org/html/rfc1918) 中定义）中的一个地址给 `docker0` 接口 .比如我的主机上的 docker0 ip 为 `172.17.0.1` ,掩码为 `255.255.0.0`  .此后启动的容器内的网口也会自动分配有个一个同一网段（`172.17.0.0/16`）的地址 .

当创建一个 Docker 容器的时候,同时会创建一对 `vath pair` 接口（当数据包发送到一个接口,另一个接口也可以收到相同的数据包） .这对接口一段在容器内,即 `eth0` ；另一端在本地并挂载到 docker0 网桥,名称以 `veth` 开头  .通过这种方式,主机可以跟容器通信,容器之间也可以相互通信 . Docker 就创建了在主机和所有容器之间一个虚拟共享网络 .

![Docker 网络](http://oid1xlj7h.bkt.clouddn.com/network.png)

​											图 i.i docker 网络



接下来部分将介绍在一些场景中,Docker 所有的网络定制配置 .以及通过 Linux 命令来调整、补充、甚至替换 Docker 默认的网络配置 .



### 快速配置



下面是一个跟 Docker 网络相关的命令列表 .

其中有些命令选项只有在 Docker 服务启动的时候才能配置,而且不能马上生效 .

* `-b BRIDGE or --bridge==BRIDGE` --指定容器挂载的网桥
* `--bip=CIDR` — 定制 docker0 的掩码
* `-H SOCKET... or --host=SOCKET…` —Docker 服务端接受命令的通道
* `--icc=true|false` --是否支持容器之间进行通信
* `--ip-forward=true|false` —容器是否能访问外网（详细解析请看下文的容器通信）
* `--iptables=true|false` --是否允许 Docker 添加 iptables 规则
* `--mtu=BYTES` —容器网络中的 MTU

下面的两个命令既可以在服务启动时指定,也可以 Docker 容器启动（docker run ）时候指定 .

在 Docker 服务启动的时候指定则会成为默认值,后面执行`docker run `时可以覆盖设置的默认值 .

* `--dns=IP_ADDRESS…` —使用指定的 DNS 服务器
* `--dns-search=DOMAIN...` 指定 DNS 搜索域

最后这些选项只有在 docker run 执行时使用,因为它是针对容器的特性内容 .

* `-h HOSTNAME or --hostname=HOSTNAME` --配置容器主机名
* `--link=CONRATAINER_NAME:ALIAS` —添加到另一个容器的连接