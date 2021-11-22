---
title: "linux命令"
date: 2016-12-28T13:13:13+08:00
lastmod: 2016-12-28T13:13:13+08:00
categories: ["基础知识"]
tags: ["linux"]
---
welcome to learn terminal command!!!

# linux命令

### 永！远！不！要！执！行！你！不！清！楚！在！干！啥！的！命！令！

## 实用性


```shell
$ ls -l | sed '1d' | sort -n -k5 | awk '{printf "%15s %10s\n", $9,$5}'
```

按文件大小增序打印出当前目录下的文件名及其文件大小(单位字节）



```shell
$ history | awk '{print $2}' | sort | uniq -c | sort -rn | head -10
```

输出你最常用的十条命令



```shell
$ http POST http://localhost:4000/ < /<json文件路径>
```

做测试的时候很有用的一个命令，需要下载http

```shell
$ brew install http
```





```shell
$ lsof -n -P -i TCP -s TCP:LISTEN

COMMAND  PID       USER   FD   TYPE             DEVICE SIZE/OFF NODE NAME
QQ       290 smartestee   33u  IPv4 0x2f3beaa58a62d73b      0t0  TCP 127.0.0.1:4300 (LISTEN)
QQ       290 smartestee   34u  IPv4 0x2f3beaa58c69673b      0t0  TCP 127.0.0.1:4301 (LISTEN)
idea    3257 smartestee  164u  IPv4 0x2f3beaa588d11e43      0t0  TCP 127.0.0.1:6942 (LISTEN)
idea    3257 smartestee  385u  IPv4 0x2f3beaa58c69316b      0t0  TCP 127.0.0.1:63342 (LISTEN)
```

查看端口的使用情况



```shell
$ ps -ef
```

查看进程



```shell
$ kill  xxxx
```

端口冲突时，用此命令，关闭某个端口。用PID替换xxxx



```shell
$ history
```

查看历史命令记录



```shell
$ pwd
```

当前位置



```shell
$ which xx
```

path位置，搭建环境的时候肯定会用得到

### Linux 文件系统命令

修改问价拥有者

```shell
$ chgrp -R 组名 文件 / 目录
$ chown -R 账户名 文件 / 目录
```

修改文件权限

```shell
$ chmod 
```

* 使用数字
  * r：4, w：2, x：1
  * 每种身份的权限的累加的。

```shell
$ chmod 777 test
```

* 使用符号修改

  * u: user, g: group, o: others, a: all

  * 添加权限用+， 除去用-， 设置用=

    ```shell
    $ chmod u=rwx, g=rw, o=r test
    ```

    ```shell
    $ chmod a-x test
    ```

    ```shell
    $ chmod go+r test
    ```

    ​

```shell
$ sudo !!
```

以root权限执行上一条命令（注意上一条命令的内容，以免发生意外）

例如：在Ubuntu 安装软件或插件的时候需要用到这个命令

```shell
$ sudo apt-get install nginx
```



查看和修改：

```shell
$ cat
$ more
$ less
$ head
$ tail

$ vi
$ vim

$ mkdir
$ touch
```



### git

```shell
$ git
```

先给出比较常用的

```shell
$ git add <一个或多个文件名(文件名之间是用空格，也可以是一个点，表示添加全部)>
```



```shell
$ git commit -m "注释"
```

本地提交



```powershell
$ git checkout <分支名或master>
```

切换分支与master



```shell
$ git branch <分支名>
```

新开一个分支



```shell
$ git merge <分支名>
```

主分支与分支的合并



```shell
$ git push origin master
```

提交到github上



```shell
$ fuck
```

纠正命令行输入的错误，比手动改快，实用。

安装：

```shell
$ brew install thefuck
```







## 娱乐



```shell
$ cmatrix
```

```shell
$ telnet towel.blinkenlights.nl
```

telnet是基于Telnet协议的远程登录客户端程序,经常用来远程登录服务器.除此还可以用它来观看星球大战

```shell
$ fortune
```

随机输出名言或者笑话，



还有很多，有兴趣的可以通过这个链接去看：[知乎](https://www.zhihu.com/question/20273259)

个人博客 [yusank](http://aa.yusank.space/2016/12/28/linux%E5%91%BD%E4%BB%A4/)

比较牛逼的一个查找命令的网站：http://www.commandlinefu.com/commands/browse/sort-by-votes

每天都有更新各种命令组合

