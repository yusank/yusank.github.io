---
title: "Unix 网络编程"
date: 2017-04-22T16:52:00+08:00
updated: 2017-04-22T16:52:01+08:00
categories: 
- 技术
tags: 
- Unix
- 网络编程
---
# Unix 网络编程

​																		**卷II - 进程间通信**

IPC是进程间通信（interprocess communication）的简称。传统上该术语描述的是运行在某个操作系统之上的不同进程间各种消息传递（*message passing*）的方式。

进程间的通信一般是一下四种形式：



- 消息传递（管道、FIFO和消息队列）；
- 同步（互斥量、条件变量、读写锁、文件和记录锁、信号量）；
- 共享内存（匿名的和具名的）；
- 远程过程调用（Solaris 门和 Sun RPC）。



# 消息队列

**消息传递：**

- 管道和FIFO；
- Posix 消息队列；
- System V消息队列。


## 管道和FIFO

管道是最初的Unix IPC 形式。由于管道没有名字，所以它只能用于有亲缘关系的进程间的通信。

**实现机制：**

管道是由内核管理的一个缓冲区，相当于我们放入内存中的一个纸条。管道的一端连接一个进程的输出。这个进程会向管道中放入信息。管道的另一端连接一个进程的输入，这个进程取出被放入管道的信息。一个缓冲区不需要很大，它**被设计成为环形的数据结构**，以便管道可以被循环利用。当管道中没有信息的话，从管道中读取的进程会等待，直到另一端的进程放入信息。当管道被放满信息的时候，尝试放入信息的进程会等待，直到另一端的进程取出信息。当两个进程都终结的时候，管道也自动消失。

```c
#include <unistd.h>

int pipe (int fd[2])             //返回：若成功返回0，若出错返回-1
```

该函数返回两个文件描述符：fd[0] 和 fd[1]。前者打开来读，后者打开来写。

管道尽管是单个进程创建，但是管道的典型用途是为两个不同的进程（一个父进程，一个子进程）提供进程间的通信手段。

![Screen Shot 2017-02-22 at 11.49.01 AM](http://oid1xlj7h.bkt.clouddn.com/Screen%20Shot%202017-02-22%20at%2011.49.01%20AM.png)

​	  									   数据流 >>>>>>

首先是，由一个进程（它将成为父进程）创建一个 pipe 后调用 fork 派生一个自身的副本，接着关闭着个 pipe 的读成端，子进程关闭同一个 pipe 的写入端。这就是进程间提供了一个单向数据流，如下图。

![Screen Shot 2017-02-22 at 11.56.11 AM](http://oid1xlj7h.bkt.clouddn.com/Screen%20Shot%202017-02-22%20at%2011.56.11%20AM.png)

```c
int main(void)
{
    int n;
    int fd[2];
    pid_t pid;
    char line[MAXLINE];
   
    if(pipe(fd) === 0){                 // 先建立管道得到一对文件描述符
        exit(0);
    }

    if((pid = fork()) == 0)            // 父进程把文件描述符复制给子进程
        exit(1);
    else if(pid > 0){                // 父进程写 
        close(fd[0]);                // 关闭读描述符
        write(fd[1], "\nhello world\n", 14);
    }
    else{                            // 子进程读
        close(fd[1]);                // 关闭写端
        n = read(fd[0], line, MAXLINE);
        write(STDOUT_FILENO, line, n);
    }

    exit(0);
}
```



*technically，自从可以在进程间传递描述符后，管道也能用于无亲缘关系的进程间，而现实中管道通常用于具有共同祖先的进程间。*

**FIFO：命名管道(named PIPE)**

管道尽管对很多操作来说是很有用的，但是它的根本局限性在于没有名字，从而只能由亲缘关系的进程（父子进程）使用。为了解决这一问题，Linux提供了FIFO方式连接进程。有了FIFO之后这一缺点得以改正。FIFO有时也称之为有名管道（named pipe）。FIFO除了有管道的功能外，它还允许无亲缘关系的进程的通信。pipe 和 FIFO 都是使用通常的 read 和 write 函数访问的。

FIFO (First in, First out)为一种特殊的文件类型，它在文件系统中有对应的路径。当一个进程以读(r)的方式打开该文件，而另一个进程以写(w)的方式打开该文件，那么内核就会在这两个进程之间建立管道，所以FIFO实际上也由内核管理，不与硬盘打交道。之所以叫FIFO，是因为管道本质上是一个先进先出的队列数据结构，最早放入的数据被最先读出来，从而保证信息交流的顺序。FIFO只是借用了文件系统(file system,命名管道是一种特殊类型的文件，因为Linux中所有事物都是文件，它在文件系统中以文件名的形式存在。)来为管道命名。写模式的进程向FIFO文件中写入，而读模式的进程从FIFO文件中读出。当删除FIFO文件时，管道连接也随之消失。**FIFO的好处在于我们可以通过文件的路径来识别管道，从而让没有亲缘关系的进程之间建立连接**

```c
#include <sys/types.h>
#include <sys/stat.h>

int mkfifo (const char *pathname, mode_t mode);    // 返回： 成功返回0，出错返回 -1
```

其中 *pathname* 是一个普通的 Unix 路径名，它是该 FIFO 的名字。

mkfifo 函数中参数 *mode* 指定 FIFO 的读写权限。

mkfifo 函数是要么创建一个新的 FIFO ，要么返回一个 EEXIST 错误（如果该 FIFO 已存在），如果不希望创建一个新的 FIFO 那就用 open 函数就可以。

FIFO 不能打开既写又读。

如果一个 FIFO 只读不写，只写不读都会形成阻塞。

下边是一个简单地例子：

```c
#include <stdio.h>  
#include <stdlib.h>  
#include <sys/types.h>  
#include <sys/stat.h>  
      
# define FIFO1  "/tmp/my_fifo"
int main()  
{  
    int res = mkfifo("/tmp/my_fifo", 0777);  
    if (res == 0)  
    {  
        printf("FIFO created/n");  
    }  
  // 打开FIFO
  //writefd = Open(FIFO1, O_WRONLY | O_NONBLOCK, 0)	
  //readfd = Open(FIFO1, O_RDONLY, 0)
     exit(EXIT_SUCCESS);  
}
```

*open* 第二个参数中的选项O_NONBLOCK，选项O_NONBLOCK表示非阻塞，加上这个选项后，表示open调用是非阻塞的，如果没有这个选项，则表示open调用是阻塞的。

* 对于以只读方式（O_RDONLY）打开的FIFO文件，如果open调用是阻塞的（即第二个参数为O_RDONLY），除非有一个进程以写方式打开同一个FIFO，否则它不会返回；如果open调用是非阻塞的的（即第二个参数为O_RDONLY|O_NONBLOCK），则即使没有其他进程以写方式打开同一个FIFO文件，open调用将成功并立即返回。
* 对于以只写方式（O_WRONLY）打开的FIFO文件，如果open调用是阻塞的（即第二个参数为O_WRONLY），open调用将被阻塞，直到有一个进程以只读方式打开同一个FIFO文件为止；如果open调用是非阻塞的（即第二个参数为O_WRONLY|O_NONBLOCK），open总会立即返回，但如果没有其他进程以只读方式打开同一个FIFO文件，open调用将返回-1，并且FIFO也不会被打开。



关于管道或 FIFO 的读写的若干规则：

* 如果请求读出的数据量多于管道或 FIFO 中当前的可用数据量，那么只会返回这些可用的数据。
* 如果请求你写入的数据的字节数小于或等于 PIPE_BUF (可原子地写入往一个管道或 FIFO 的最大数据量， Posix 要求至少为512)，那么 write 操作保证是原子的。这意味着，如果两个进程差不多同时往同一个管道或 FIFO 写，那么不管是先写入来自第一个进程的所有数据再写第二个，还是顺序颠倒过来。系统都不会相互混杂来自两个进程的数据。然而如果数据的字节数大于 PIPE_BUF ，那么 write 操作不能保证是原子的。
* 不止以上这些。。。



**小结**： FIFO 与管道类似，但是它用 mkfifo 创建，之后需要open 打开。打开管道必须小心，因为许多规则（read 只写管道、write 只读管道、从空的管道或FIFO read 等的情况的返回结果。）制约着 open 的阻塞与否。

## Posix IPC

Posix--可移植性操作系统接口（Protable operating system interface）

有关Unix标准化的大多数活动是由 Posix 和 Open Group 做的。

Posix 不是单一的标准，是一系列的标准。

以下三种类型的IPC合成为“Posix IPC”

* Posix 消息队列
* Posix 信号量
* Posix 共享内存区


## Posix 消息队列

消息队列可认为是个消息链表。有足够写权限的进程可往队列放置信息，有足够读权限的进程可从队列读取信息。每一个信息都是一条记录，它是由发送者赋予一个优先级。在某个进程往一个队列写入消息之前，并不需要另一个进程在该队列上等待消息的到达。这根管道和 FIFO 是相反的。

一个进程可以往某些队列写入一些信息，然后终止，再让另外一个进程在以后的某个时刻读取这些信息。



Posix 消息队列和下面讲的System V 消息队列有许多的相似性。以下是主要的差别：

* 对 Posix 消息队列的读总是返回最高优先级的最早消息，对 System V 消息队列的读则可以返回任意指定优先级的消息；
* 当往一个空队列放置一个信息时，Posix 消息队列允许产生一个信号或启动一个线程，System V消息队列则是不提供类似的机制。

队列中的每一个消息都有如下属性：

* 一个无符号整数优先级（Posix）或 一个长整数类型（system V）；
* 消息的数据部分长度（可以为0）；
* 数据本身（如果长度大于0）。

一个消息队列的可能布局。

![unix 网络](http://oid1xlj7h.bkt.clouddn.com/unix%20%E7%BD%91%E7%BB%9C.png)



我们所设想的是一个链表，该链表的有中含有当前队列的两个属性：队列中允许的最大开销数以及每一个消息的最大大小。



**mq_open ,mq_close 和 mq_unlink 函数 **：

mq_open 函数创建一个新的消息队列或打开一个已存在的消息队列。

```c
# include <mqueue.h>
mqd_t mq_open (const char *name, int oflag, ...
              /* mode_t mode, struct mq_attr *attr  */);
							//返回： 成功返回消息对列描述符，出错返回-1
```

其中 *name* 有自己的一套命名规则，因为 Posix IPC 使用“Posix IPC 名字”进行标识。为方便于移植起见，Posix IPC 名字必须以斜杠符开头并且不能再包含任何斜杠符。

*oflag* 是O_RDONLY、O_WRONLY 或 	O_RDWR 之一， 可能按位或上O_CREATE(若不存在则创建)、O_EXCL(与O_CREATE一起，若已存在返回EEXIST 错误)或 O_NONBLOCK（非阻塞标识符）。

当实际操作创建一个新的消息队列时（指定O_CREATE标志，且请求的队列不存在），*mode* 和 *attr* 参数是需要的。mode上面介绍过。attr参数用于给新队列指定某些属性。

mq_open 返回值称为**消息队列描述符（message queue descriptor）**，这个值用作其他消息队列函数的第一参数。



已打开的消息队列是由 mq_close 关闭的。

```c
#include <mqueue.h>

int mq_close(mqd_t mqdes)                       //返回： 成功返回0，出错返回-1
```

关闭之后调用进程不再使用该描述符，但其消息队列并不从系统中删除。一个进程终止时，它打开着的消息队列都关闭，就像调用mq_close 一样。



要从系统中删除消息队列则用mq_unlink 函数，其第一参数为 mq_open 的第一参数 *name*。

```c
# include <mqueue.h>

int mq_unlink(const char *name)                    //返回： 成功返回0，出错返回-1
```

**mq_getattr 和 mq_setattr 函数**

消息队列有四个属性，这两个函数是获取和修改这些属性。

```c
mq_flags		//队列阻塞标志位
mq_maxmsg		//队列最大允许消息数
mq_msgsize		//队列消息最大字节数
mq_curmsgs		//队列当前消息条数
```

```c
#include <mqueue.h>

int mq_getattr(mqd_t mqdes,struct mq_attr *attr);
int mq_setattr(mqd_t mqdes,const struct mq_attr *attr, struct mq_attr *oattr);  //返回：均成功返回0，出错返回-1
```

**mq_send 和 mq_receive 函数**

​	这两个函数分别往一个队列放置一个信息和从一个队列取走一个消息。每一个消息都有优先级，它是一个小于MQ_PRIO_MAX 的无符号整数。Posix要求这个上限至少为32.

​	mq_receive 总是返回所指定队列中优先级最高的的最早消息，而且该优先级能随该消息的内容及其长度一同返回。

```c
#include <mqueue.h>

int mq_send(mqd_t mqdes, const char *ptr, size_t len, unsigned int prio);      //返回： 成功返回0，出错返回-1
ssize_t mq_reccevie(mqd_t mqdes, char *ptr, size_t len, unsigned int *priop);     //返回： 成功返回消息中的字节数，出错返回-1
```

mq_receive 的 *len* 参数的值不能小于能加到所指定队列中的最大大小（该队列 mq_attr 结构的 mq_msgsize ）。要是 *len* 小于该值， mq_receive立即返回 EMSGSIZE 错误。

mq_send 的 *prio* 参数是待发信息的优先级，其值必须小于 MQ_PRIO_MAX 。如果 mq_receive 的 *priop* 参数是一个非空指针，所返回消息的优先级就通过该指针存放。如果应用不必使用优先级不同的消息，那就给mq_send 指针值为0的优先级，给 mq_receive 指定一个空指针作为其最后一个参数。

往某个队列中增加一个消息

```c
#include <mqueue.h>

int
main(int argc, char **argv)
{
  mqd_t		mqd;		//描述符
  void		*ptr;		//指向缓冲区的指针
  size_t	len;		//长度
  uint_t	prio;		//优先度
  
  if (argc != 4)
    err_quit("usage: mqsend <name> <#bytes> <priority>");
  len = atoi(argv[2]);
  prio = atoi(argv[3]);
  
  mqd = Mq_open(argv[1], O_WRONLY);	// 创建一个消息队列
  
  ptr = Calloc(len, sizeof(char));// 所用的缓冲区用colloc分配，该函数会把该缓冲区初始化为0
  Mq_send(mqd, ptr, len, prio);
  
  exit(0);
}
```

待发消息的大小和优先级必须作为命令行参数指定。

从某队列读出下一个信息

```c
#include "unpipc.h"

int
main(int argc, char **argv)
{
  int 		c,flags;
  mqd_t		maq;
  ssize_t	n;
  uint_t	prio;
  void		*buff;
  struct	mq_attr	attr;
  
  flags = O_RDONLY;
  while ( (c = Getopt(argc, argv, "n")) != -1) {
    switch (c) {
      case 'n':
        flags |= O_NONBLOCK;
        break;
    }
  }
  if (optind != argc - 1)
    err_quit("usage: mqreceive [-n] <name>");
  
  mqd =Mq_open(argv[optind], flags);
  Mq_getattr(mqd, &attr);
  
  buff = Malloc(attr.mq_msgsize);
  
  n = Mq_receive(mqd, buff, attr.mq_msgsize, &prio);
  printf("read %ld bytes, priority = %u\n", (long) n, prio);
  
  exit(0);
}
```

命令行选项 -n 指定非阻塞属性，这样如果所指定的队列中没有消息， 则返回一个错误。

调用 mq_getattr 打开队列并取得属性。需要确定最大消息大小，因为必须为调用的 mq_receive 分配一个这样大小的缓冲区。最后输出所读出消息的大小及其属性。

```shell
solaris %mqcreate /test1							创建并获取属性
solaris %mqgetattr /test1
max

solaris % mqsend /test1 100 9999					以无效的优先级发送
mq_send error: Invalid argument

solaris % mqsend /test1 100 6						100字节，优先级6 
solaris % mqsend /test1 50 18 						50字节，优先级18
solaris % mqsend /test1 33 18 						33字节，优先级18

solaris % mqreceive /test1
read 50 bytes, priority = 18						返回优先级最高的最早消息
solaris % mqreceive /test1
read 33 bytes, priority = 18
solaris % mqreceive /test1
read 100 bytes, priority = 6
solaris % mqreceive /test1							指定非阻塞属性，队列为空
mq_recevie error: Resource temporarily unavalibale
```



消息队列限制：

* mq_mqxmsg			队列的最大消息数
* mq_msgsize                  给定消息的最大字节数
* MQ_OPEN_MAX            一个进程能够同时拥有的打开着消息队列的组大数目（Posix要求至少为8）
* MQ_PRIO_MAX             任意消息的最大优先级值加1（Posix要求至少为32）

**mq_notify 函数**

Posix 消息队列允许异步事件通知（ *asynchronous event notifiction*），以告知何时有一个消息放置到了某个空消息队列中。



## System V 消息队列

以下三种类型的IPC称为 System V IPC：

* System V 消息队列；
* System V 信号量；
* System V 共享内存区。

这个称为作为这三个IPC机制的通称是因为它们源自 System V Unix 。这三种IPC最先出现在AT&T System v UNIX上面，并遵循XSI标准，有时候也被称为XSI IPC。

System V 消息队列使用*消息队列标识符（message queue identifier）* 标识。有足够权限的任何进程可往队列放置信息，有足够权限的任何进程可从队列读取信息。跟 Posix 一样，在某个进程往一个队列写入消息之前，不求另外某个进程正在等待该队列上一个消息的到达。

对于系统的每个消息队列，内核维护一个定义在 `<sys/msg.h>`  头文件中的信息结构.

```c
struct msqid_ds {
    struct ipc_perm 	msg_perm   //operation permission structure
    struct msg			*msg_frist //ptr to frist message on queue
    struct msg			*msg_last  //ptr to last message on queue
    msglen_t			msg_cbytes //current #bytes on queue
    msgqnum_t       	msg_qnum   //number of messages currently on queue
    msglen_t        	msg_qbytes //maximum number of bytes allowed on queue
    pid_t           	msg_lspid  //process ID of last msgsnd()
    pid_t           	msg_lrpid  //process ID of last msgrcv()
    time_t          	msg_stime  //time of last msgsnd()
    time_t          	msg_rtime  //time of last msgrcv()
    time_t          	msg_ctime  //time of last change
}
```

*Unix 98 不要求有 msg_frist、msg_last 和 msg_cbytes 成员。然而普通的源自 [System V](http://pubs.opengroup.org/onlinepubs/7908799/xsh/sysmsg.h.html) 的实现中可以找到这三个成员。就算提供了这两个指针，那么它们指向的是内核内存空间，对于应用来说基本没有作用的。*

![unix 网络 (1)](http://oid1xlj7h.bkt.clouddn.com/unix%20%E7%BD%91%E7%BB%9C%20%281%29.png)

我们可以将内核中某个特定的消息队列画为一个消息链表，如图。

**msgget 函数**

msgget 函数用于创建一个新的消息队列或访问一个已存在的消息队列。

```c
#include <sys/msg.h>
int msgget (key_t key, int oflag)	
  											//返回： 成功返回非负标识符，出错返回-1
```

返回值是一个整数标识符，其他三个msg函数就用它来指代该队列。

oflag是读写权限的组合。（稍微复杂。。。）

当创建一个新的消息队列的时，msqid_ds 结构的如下成员被初始化。

* msg_perm 结构的 uid 和 cuid 成员被设置成当前进程的有效用户ID，gid 和 cgid 成员被设置成当前的进程的有效组ID。

* oflag 中的读写权限位存放在msg_perm.mode 中。

* msg_qnum、msg_lspid，msg_lrpid、msg_stime 和 msg_rtime 被设置为0.

* msg_ctime 被设置为当前时间。

* msg_qbytes 被设置成系统限制值。

  ```c
  struct ipc_perm
  {
  key_t        		key;            /*调用shmget()时给出的关键字*/
  uid_t           	uid;            /*共享内存所有者的有效用户ID */
  gid_t          		gid;            /* 共享内存所有者所属组的有效组ID*/ 
  uid_t          		cuid;           /* 共享内存创建 者的有效用户ID*/
  gid_t         		cgid;           /* 共享内存创建者所属组的有效组ID*/
  mode_t			   	mode;    		/* Permissions + SHM_DEST和SHM_LOCKED标志*/
  ulong_t		    	seq;          	/* 序列号*/
  };
  ```

  ​

**msgsnd 函数**

使用 msgget 函数打开一个消息队列后，使用 msgsnd 函数往其上放置一个消息。

```c
# include <sys/msg.h>
int msgsnd(int msqid, const void *ptr,size_t length, int flag);
```

其中msqid 是由msgget 函数返回的标识符。ptr 是一个结构指针，该结构具有如下的模板：

```c
struct msgbuf {
 	long 	mtype;			// message type ,must be > 0
 	char	mtext[1]		// message data
};
```

*消息类型必须大于0，因为对于 msgrcv 函数来说，非正的消息类型用作特殊的指示器。*

*mtext虽然起名是 text ，但是消息类型并不局限于文本。任何形式的数据都是允许的。内核根本不解释消					  息数据的内容。ptr 所指向的是一个含有消息类型的长整数，消息本身则紧跟着它之后。*



msgsnd 的 *length* 参数以字节为单位指定待发送消息的长度。是用户自定义的，可以是0.

*flag* 参数既可以是0，也可以是IPC_NOWAIT 。IPC_NOWAIT 标志使得 msgsnd 调用非阻塞：如果没有存放新消息的可用空间，该函数马上返回。这个条件可能发生的情况包括：

* 在指定的队列中已有太多的字节（对应 该队列的msqid_ds 结构中的msg_qbytes 值）；
* 在系统范围存在太多的消息。

如果两个条件一个存在，而且IPC_NOWAIT标志已指定，msgsnd 就返回一个EAGAIN 错误。如果两个条件一个存在，标志未指定，那么调用线程就被投入睡眠，直到：

* 具备存放新消息的空间；
* 由 msqgid 标识的消息队列从系统中删除（这个情况下回返回一个EIDRM 错误）；
* 调用线程被某个捕获的信息所中断。