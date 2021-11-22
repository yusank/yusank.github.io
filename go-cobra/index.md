# 如何编写自己的第一个命令行工具


关于如何用 go 语言编写一个命令行工具。这里会基于 `cobra` 开源库进行开发。`cobra` 作为一个非常有名的命令行工具库，被很多开源项目引入使用，很多命令行工具都能看到 `cobra` 的身影。`cobra` 提供一个完整的命令行的工具的所需的功能，包括命令定义、命令扩展、读取参数等。下面我们以开发一个命令行工具的流程一步步学习如何使用 `cobra` 开发一个自己的命令行工具。

## 创建根命令

我们项目暂且就叫 `myCmd`, 我们本地创建一个go项目就叫 `myCmd`。

```shell
$ mkdir myCmd
$ cd myCmd
$ touch main.go
$ go mod init myCmd
```

main.go

```go
package main

import (
	"log"

	"github.com/spf13/cobra"
)

var (
    // 定义主命令
	rootCmd = &cobra.Command{
		Use:   "myCmd",
		Short: "这里是对命令的简短介绍",
		Long: `这里可以放对命令的详细介绍。
可以多行`,
		Example: "myCmd help", // 使用示例
        Version: "v0.0.1", // 定义版本

	}

	dirPath string
)

func init() {
    // 定义参数，即从命令行读取的参数变量
    // 除了 PersistentFlags 外，也可以用 Flags()，区别是 前一个可以在其子命令也可以用，后一个不能。即PersistentFlags是一个全局的flag注册。
	rootCmd.PersistentFlags().StringVarP(&dirPath, "dir", "d", ".", "文件路径")
}

func main() {
	if err := rootCmd.Execute(); err != nil {
		log.Fatal(err)
	}
}
```

这样我们就创建了一个属于的自己的命令，执行看一下效果。

```shell
# 直接执行,会打印 字段Long的值，
➜./myCmd   
这里可以放对命令的详细介绍。
可以多行
# 打印版本
➜./myCmd -v
myCmd version v0.0.1
# 输入未知 flag
➜./myCmd -x
Error: unknown shorthand flag: 'x' in -x
Usage:

Examples:
myCmd help

Flags:
  -d, --dir string   文件路径 (default ".")
  -h, --help         help for myCmd
  -v, --version      version for myCmd

2021/07/04 15:18:59 unknown shorthand flag: 'x' in -x
```

不难发现，版本处理，未知参数处理等情况 cobra已经做了相对完善的处理，我们不需要做太多的错误处理。

目前未知，我们的的命令只是定义了命令，并没有执行任何指令，下面我们添加一个简单的执行函数。`cobra.Command` 有很多参数可以定义执行函数的，我们以最常用的的 `Run`，`RunE` 为例，分别是不返回错误和返回错误的函数定义。

假如我们的主命令执行一个打印 d 参数传值的目录的信息。

```go
// rootCmd
RunE: printDirInfo,

/*
...
*/ 

func printDirInfo(cmd *cobra.Command, args []string) error {
	info, err := os.Stat(dirPath)
	if err != nil {
		return err
	}

	fmt.Printf("name:%s, size:%d modTime:%v \n", info.Name(), info.Size(), info.ModTime())
	return nil
}
```

执行一下命令：

```shell
# 查看一下 main 文件的信息
➜./myCmd -d main.go 
name:main.go, size:759 modTime:2021-07-04 15:26:43.311399368 +0800 CST 

# 查看一个不存在的文件
➜./myCmd -d main.go1
Error: stat main.go1: no such file or directory
Usage:
  myCmd [flags]

Examples:
myCmd help

Flags:
  -d, --dir string   命令执行目录 (default ".")
  -h, --help         help for myCmd
  -v, --version      version for myCmd

2021/07/04 15:30:01 stat main.go1: no such file or directory
# 不仅打印出错误，如何使用命令也会同时打印出来
```

下面我们就添加我们的子命令。

## 添加子命令

我们现在添加一个子命令，这个子命令的功能是统计当前目录下的所有文件信息，我们就起名叫 `stat`。同时，为了方便全局变量的在不同包内读取，创建一个 `variable` 的目录，里面存放全局的一些变量，包内变量就放到各自包内。

```shell
➜ mkdir stat
➜ mkdir variable
➜ touch stat/stat.go
➜ touch variable/variable.go
```

下面是stat文件的内容。

stat.go

``` go
package stat

import (
	"fmt"
	"myCmd/variable"
	"os"
	"path/filepath"

	"github.com/spf13/cobra"
)

var (
	StatCmd = &cobra.Command{
		Use:   "stat",
		Short: "统计目录",
		RunE:  statDir,
	}

	isStatDir bool
)

func init() {
    // 这里使用 Flags 只在我这个命令内解析和读取
	StatCmd.Flags().BoolVarP(&isStatDir, "stat_dir", "s", false, "是否统计目录信息")
}

func statDir(cmd *cobra.Command, args []string) error {
	return filepath.Walk(variable.DirPath, func(path string, info os.FileInfo, err error) error {
		if err != nil {
			return err
		}
		if info.IsDir() && !isStatDir {
			// 不统计
			return nil
		}

		fmt.Printf("path:%s, size:%d, modTime:%v", path, info.Size(), info.ModTime())
		return nil
	})
}
```

然后将该子命令注册的主命令下。

main.go

``` go
package main

import (
	"fmt"
	"log"
	"myCmd/stat"
	"myCmd/variable"
	"os"

	"github.com/spf13/cobra"
)

var (
	rootCmd = &cobra.Command{
		Use:   "myCmd",
		Short: "这里是对命令的简短介绍",
		Long: `这里可以放对命令的详细介绍。
可以多行`,
		Example: "myCmd help", // 使用示例
		Version: variable.Version, // 全局变量常量都移到 variable 目录下
		RunE:    printDirInfo,
	}
)

func init() {
	rootCmd.PersistentFlags().StringVarP(&variable.DirPath, "dir", "d", ".", "文件路径")
    // 注册命令
	rootCmd.AddCommand(stat.StatCmd)
}

func printDirInfo(cmd *cobra.Command, args []string) error {
	info, err := os.Stat(variable.DirPath)
	if err != nil {
		return err
	}

	fmt.Printf("name:%s, size:%d modTime:%v \n", info.Name(), info.Size(), info.ModTime())
	return nil
}

func main() {
	if err := rootCmd.Execute(); err != nil {
		log.Fatal(err)
	}
}
```

再次执行 `help` 查看我们的命令。

```shell
➜./myCmd -h
这里可以放对命令的详细介绍。
可以多行

Usage:
  myCmd [flags]
  myCmd [command]

Examples:
myCmd help

Available Commands:
  help        Help about any command
  stat        统计目录

Flags:
  -d, --dir string   文件路径 (default ".")
  -h, --help         help for myCmd
  -v, --version      version for myCmd

Use "myCmd [command] --help" for more information about a command.

# 查看子命令help
➜./myCmd stat -h
统计目录

Usage:
  myCmd stat [flags]

Flags:
  -h, --help           help for stat
  -s, --stat_dir       是否统计目录信息

Global Flags:
  -d, --dir string   文件路径 (default ".")

# 统计
➜./myCmd stat -d .
path:go.mod, size:61, modTime:2021-07-04 15:03:33.339495852 +0800 CST
path:go.sum, size:56568, modTime:2021-07-04 15:03:33.339185898 +0800 CST
path:main.go, size:929, modTime:2021-07-04 15:55:07.206300444 +0800 CST
path:myCmd, size:4344056, modTime:2021-07-04 16:01:12.930132286 +0800 CST
path:stat/stat.go, size:691, modTime:2021-07-04 16:01:09.353487727 +0800 CST
path:variable/variable.go, size:73, modTime:2021-07-04 15:48:18.345134258 +0800 CST
```

不难发现，这个子命令可以无限嵌套，我们可以拥有二级三级子命令，能满足我们各种各样奇葩的需求，子命令可以复用其上级目录的 flag参数。

## 自主更新

假如我们开发命令，已经发布到 GitHub 上，别人可以简单的 `go get` 命令就能安装使用我们的命令。但是我要是发布一个新版本，希望使用的人能知道我的命令工具有新版了而且要是能方便的更新到最新的版本是不是一个非常人性化的设计呢？

其实实现起来也不难，这里抛出个思路。假如我们命令每次执行的时候，我做一次版本检查（但是**强烈不建议**每次都检查，最好本地做一个上次检查时间的缓存，最多一天检查一次，否则用户体验非常不好），如果有新的版本我就提醒用户，甚至我可以检查的时候拉过来新版本的 feature 展现给用户，，然后提供一个 `update` 的子命令，自我更新，这体验是不是听起来就很不错呀。

至于 `update` 这个子命令实现也很简单，尝试执行一次 `go get -u <myCmdRemoteURL>`  即可，虽然看起来是对 `go get` 的一次封装，但是对于用户来说就很简单方便。

## 小彩蛋

到这里我们一个小命令行工具也有模有样了，但是缺一个灵魂，是什么呢？

当然是

命令的炫酷的logo！！！

先看效果图：

```shell
# 普通版本
  __  __  __     __   _____   __  __   _____  
 |  \/  | \ \   / /  / ____| |  \/  | |  __ \ 
 | \  / |  \ \_/ /  | |      | \  / | | |  | |
 | |\/| |   \   /   | |      | |\/| | | |  | |
 | |  | |    | |    | |____  | |  | | | |__| |
 |_|  |_|    |_|     \_____| |_|  |_| |_____/ 
                                              
                                              
# 斜体
                                                                     
    /|    //| | \\    / /     //   ) )     /|    //| |     //    ) ) 
   //|   // | |  \\  / /     //           //|   // | |    //    / /  
  // |  //  | |   \\/ /     //           // |  //  | |   //    / /   
 //  | //   | |    / /     //           //  | //   | |  //    / /    
//   |//    | |   / /     ((____/ /    //   |//    | | //____/ /     

# 夸张版本
          _____                _____                    _____                    _____                    _____          
         /\    \              |\    \                  /\    \                  /\    \                  /\    \         
        /::\____\             |:\____\                /::\    \                /::\____\                /::\    \        
       /::::|   |             |::|   |               /::::\    \              /::::|   |               /::::\    \       
      /:::::|   |             |::|   |              /::::::\    \            /:::::|   |              /::::::\    \      
     /::::::|   |             |::|   |             /:::/\:::\    \          /::::::|   |             /:::/\:::\    \     
    /:::/|::|   |             |::|   |            /:::/  \:::\    \        /:::/|::|   |            /:::/  \:::\    \    
   /:::/ |::|   |             |::|   |           /:::/    \:::\    \      /:::/ |::|   |           /:::/    \:::\    \   
  /:::/  |::|___|______       |::|___|______    /:::/    / \:::\    \    /:::/  |::|___|______    /:::/    / \:::\    \  
 /:::/   |::::::::\    \      /::::::::\    \  /:::/    /   \:::\    \  /:::/   |::::::::\    \  /:::/    /   \:::\ ___\ 
/:::/    |:::::::::\____\    /::::::::::\____\/:::/____/     \:::\____\/:::/    |:::::::::\____\/:::/____/     \:::|    |
\::/    / ~~~~~/:::/    /   /:::/~~~~/~~      \:::\    \      \::/    /\::/    / ~~~~~/:::/    /\:::\    \     /:::|____|
 \/____/      /:::/    /   /:::/    /          \:::\    \      \/____/  \/____/      /:::/    /  \:::\    \   /:::/    / 
             /:::/    /   /:::/    /            \:::\    \                          /:::/    /    \:::\    \ /:::/    /  
            /:::/    /   /:::/    /              \:::\    \                        /:::/    /      \:::\    /:::/    /   
           /:::/    /    \::/    /                \:::\    \                      /:::/    /        \:::\  /:::/    /    
          /:::/    /      \/____/                  \:::\    \                    /:::/    /          \:::\/:::/    /     
         /:::/    /                                 \:::\    \                  /:::/    /            \::::::/    /      
        /:::/    /                                   \:::\____\                /:::/    /              \::::/    /       
        \::/    /                                     \::/    /                \::/    /                \::/____/        
         \/____/                                       \/____/                  \/____/                  ~~              
                                                                                                                         
```

我随机选了几个作为演示，[点击这里跳转](https://www.colorschemer.com/ascii-art-generator)制作自己工具的logo，然后再主命令注册一个 `PreRun` 的函数，在该函数内打印我们的logo。这样在主逻辑执行前会打印我们的logo，辨识度一下子提高很多。

实际效果：

```shell
➜./myCmd -d main.go 
 __  __  __     __   _____   __  __   _____  
|  \/  | \ \   / /  / ____| |  \/  | |  __ \ 
| \  / |  \ \_/ /  | |      | \  / | | |  | |
| |\/| |   \   /   | |      | |\/| | | |  | |
| |  | |    | |    | |____  | |  | | | |__| |
|_|  |_|    |_|     \_____| |_|  |_| |_____/ 
   
name:main.go, size:1320 modTime:2021-07-04 16:28:51.339520282 +0800 CST 
```

暂且就这么多，感谢 `spf13/cobra` 的作者，提供这么高质量的开源库。

