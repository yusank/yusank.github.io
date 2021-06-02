---
title: "Go 文件操作"
date: 2017-05-22T12:20:00+08:00
update: 2017-05-23T12:18:00+08:00
categories: 
- 技术
tags:
- go
---

# GO 文件操作

在任何计算机设备中，文件是都是必须的对象，而在Web编程中,文件的操作一直是Web程序员经常遇到的问题,文件操作在Web应用中是必须的,非常有用的,我们经常遇到生成文件目录,文件(夹)编辑等操作,现在我们来看看 go 对文件是怎么操作的。

## 目录操作

文件操作的大多数函数都是在os包里面，下面列举了几个目录操作的：

- `func Mkdir(name string, perm FileMode) error`

创建名称为name的目录，权限设置是perm，例如0777

- `func MkdirAll(path string, perm FileMode) error`

根据path创建多级子目录，例如 test/test1/test2。

- `func Remove(name string) error`

删除名称为name的目录，当目录下有文件或者其他目录时会出错

- `func RemoveAll(path string) error`

根据path删除多级子目录，如果path是单个名称，那么该目录下的子目录全部删除。

以下是简单的使用：

```go
package main

import (
    "fmt"
    "os"
)

func main() {
	os.Mkdir("test", 0777)
	os.MkdirAll("test/test1/test2", 0777)
	err := os.Remove("test")
	if err != nil {
		fmt.Printf("crash with error %v \n", err)
	}
	os.RemoveAll("test")
}
```

## 文件操作

### 建立与打开文件

新建文件可以通过如下两个方法

- `func Create(name string) (file *File, err Error)`

根据提供的文件名创建新的文件，返回一个文件对象，默认权限是0666的文件，返回的文件对象是可读写的。

- `func NewFile(fd uintptr, name string) *File`

根据文件描述符创建相应的文件，返回一个文件对象

通过如下两个方法来打开文件：

- `func Open(name string) (file *File, err Error)`

该方法打开一个名称为name的文件，但是是只读方式，内部实现其实调用了OpenFile。

- `func OpenFile(name string, flag int, perm uint32) (file *File, err Error)`

打开名称为name的文件，flag是打开的方式，只读、读写等，perm是权限

### 写文件

写文件函数：

- `func (file *File) Write(b []byte) (n int, err Error)`

写入byte类型的信息到文件

- `func (file *File) WriteAt(b []byte, off int64) (n int, err Error)`

在指定位置开始写入byte类型的信息

- `func (file *File) WriteString(s string) (ret int, err Error)`

写入string信息到文件

写文件的示例代码

```go

package main

import (
    "fmt"
    "os"
)

func main() {
	userFile := "yusank.txt"
	fout, err := os.Create(userFile)		
	if err != nil {
		fmt.Println(userFile, err)
		return
	}
	defer fout.Close()
	for i := 0; i < 10; i++ {
		fout.WriteString("Just a test!\r\n")
		fout.Write([]byte("Just a test!\r\n"))
	}
}
```

### 读文件

读文件函数：

- `func (file *File) Read(b []byte) (n int, err Error)`

读取数据到b中

- `func (file *File) ReadAt(b []byte, off int64) (n int, err Error)`

从 off 开始读取数据到 b 中

读文件的示例代码:

```go

package main

import (
	"fmt"
	"os"
)

func main() {
	userFile := "yusank.txt"
	fl, err := os.Open(userFile)
	if err != nil {
		fmt.Println(userFile, err)
		return
	}
	defer fl.Close()
	buf := make([]byte, 1024)
	for {
		n, _ := fl.Read(buf)
		if 0 == n {
			break
		}
		os.Stdout.Write(buf[:n])
	}
}
```

### 删除文件

Go语言里面删除文件和删除文件夹是同一个函数

- `func Remove(name string) Error`

调用该函数就可以删除文件名为name的文件

### 计算文件哈希值

在网络上传输文件完成后，往往都会有一步文件的校验。需要确认传过来的文件是否是损坏的。

#### 小文件

代码：

```go
package main

import (
    "crypto/md5"
    "fmt"
    "io"
    "os"
)

func main() {
    testFile := "/path/to/file"
    file, err := os.Open(testFile)
    if err != nil {
        fmt.Println(err)
        return
    }
    // 以上是为了获的 os.File 对象

    md5h := md5.New()
    io.Copy(md5h, file)
    fmt.Printf("%x", md5h.Sum([]byte(""))) // 打印出来的是 MD5 算法下的哈希结果
}
```

#### 大文件

代码：

```go
package main

import (
    "crypto/md5"
    "fmt"
    "io"
    "math"
    "os"
)

const filechunk = 8192 // 假定 8KB 以上为大文件

func main() {

    file, err := os.Open("utf8.txt")

    if err != nil {
        panic(err.Error())
    }

    defer file.Close()

    // 计算大小
    info, _ := file.Stat()

    filesize := info.Size()

    blocks := uint64(math.Ceil(float64(filesize) / float64(filechunk)))

    hash := md5.New()

    for i := uint64(0); i < blocks; i++ {
        blocksize := int(math.Min(filechunk, float64(filesize-int64(i*filechunk))))
        buf := make([]byte, blocksize)

        file.Read(buf)
        io.WriteString(hash, string(buf)) // append into the hash
    }

    fmt.Printf("%s checksum is %x\n", file.Name(), hash.Sum(nil))

}
```

代码内容是打开本地文件分块读取进行哈希计算，在网络传输中，可以每次传入一包的文件，先用 io.WriteString() 方法添加到哈希并在最后进行 hash.Sum() 操作
