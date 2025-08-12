---
title: 容器网络（一） -- 本机网络通信和容器网络基础
description: 梳理学习容器网络
categories: [云原生, 容器网络]
tags: [云原生, 容器网络]
---


## 1. 引言

[Kubernetes学习实践](https://xiaodongq.github.io/categories/kubernetes/) 前几篇中了解了基本的K8s操作，终于可以开始梳理容器网络了，这也是之前的核心出发点之一，本篇来梳理下容器网络相关基础，并澄清说明一下本机网络的基本流程。

本篇主要参考：[开发内功修炼](https://kfngxl.cn/index.php) 中网络篇的一些文章，后续再在本基础上扩展学习。
* 本机网络通信：本地回环 和 `Unix Domain Socket`
    * [127.0.0.1 之本机网络通信过程知多少](https://kfngxl.cn/index.php/archives/195/)
    * [本机网络IO之Unix Domain Socket与普通socket的性能对比 实验使用源码](https://kfngxl.cn/index.php/archives/211/)
* 容器网络
    * [手工模拟实现 Docker 容器网络！ 配套实验源码](https://kfngxl.cn/index.php/archives/460/)
    * [轻松理解 Docker 网络虚拟化基础之 veth 设备](https://kfngxl.cn/index.php/archives/415/)
    * 命名空间
        * [彻底弄懂 Linux 网络命名空间 配套实验源码](https://kfngxl.cn/index.php/archives/443/)
    * 数据交换和路由
        * [聊聊 Linux 上软件实现的“交换机” - Bridge！ 配套实验源码](https://kfngxl.cn/index.php/archives/430/)
        * [天天讲路由，那 Linux 路由到底咋实现的！？](https://kfngxl.cn/index.php/archives/488/)

## 2. 本机网络通信方式说明

[Kubernetes学习实践（一） -- 总体说明和基本使用](https://xiaodongq.github.io/2025/07/13/kubernetes-overview/) 中搭建环境时提到需要为容器CLI工具`crictl`新增配置文件（“修复上述警告和crictl命令执行不了的问题”所在小节），其中指定了`Unix Domain Socket（UDS）`的通信地址：`unix:///var/run/containerd/containerd.sock`，这里就是指定`UDS`进行`bind`时需要用到的文件路径。

此处来介绍下`Unix Domain Socket`的本机通信方式，并说明其和`127.0.0.1`回环（`loopback`）网络通信的差异，以及和跨主机网络通信的差异。

贴一下`crictl`配置文件相关内容：
```sh
cat <<EOF | sudo tee /etc/crictl.yaml
runtime-endpoint: unix:///var/run/containerd/containerd.sock
image-endpoint: unix:///var/run/containerd/containerd.sock
timeout: 10
debug: false
EOF
```

### 2.1. 跨主机通信 和 loopback回环网络通信

此处只做总体流程简要说明，进一步细节和代码级流程梳理，可见：[127.0.0.1 之本机网络通信过程知多少](https://kfngxl.cn/index.php/archives/195/)。

1、先来看下最常规情况下的网络通信：2台机器之间进行基本的TCP `socket`交互。流程如下：

![network-process-cross-host](/images/network-process-cross-host.png)

发送方数据经过内核网络协议栈处理，通过**邻居子系统**发送到驱动程序，而后通过**网卡硬件**发出。接收方则也通过**网卡硬件**接收。

之前宿主机网络相关的梳理和实验稍微多一点，可见：[TCP发送接收过程](https://xiaodongq.github.io/categories/tcp%E5%8F%91%E9%80%81%E6%8E%A5%E6%94%B6%E8%BF%87%E7%A8%8B/) 和 [TCP半连接全连接](https://xiaodongq.github.io/categories/tcp%E5%8D%8A%E8%BF%9E%E6%8E%A5%E5%85%A8%E8%BF%9E%E6%8E%A5/)。

2、loopback回环网络通信流程

![network-process-loopback](/images/network-process-loopback.png)

可看到：
* `127.0.0.1`本机回环网络通信时，**<mark>数据不需要经过网卡</mark>**，因此即使拔掉网卡，也不影响本机上通过loopback通信
* 本机回环网络数据流向：还是 **<mark>需要经过跨机通信一样（除了网卡硬件）的各流程处理</mark>**，只是数据不需要经过网卡的`RingBuffer`队列，而是通过**软中断**直接把`skb`传给接收协议栈（本机回环的驱动程序也是一个纯软件的虚拟程序）。

**问题**：访问本机Server时，使用`127.0.0.1​`能比使用本机ip（例如`192.168.x.x`）更快吗？
* 结论：两种使用方法在性能上没有啥差别
* 所有`local`路由表项内核都会标识为`RTN_LOCAL`，查找路由表时（`__ip_route_output_key`），都会路由选择`loopback`虚拟设备

比如我的环境中的`local`路由表：
```sh
[root@xdlinux ➜ ~ ]$ ip route list table local
...
local 127.0.0.0/8 dev lo proto kernel scope host src 127.0.0.1 
local 127.0.0.1 dev lo proto kernel scope host src 127.0.0.1 
broadcast 127.255.255.255 dev lo proto kernel scope link src 127.0.0.1 
# 虽然显示enp4s0，实际上所有的`RTN_LOCAL`项，路由还是会选择loopback 虚拟设备
local 192.168.1.150 dev enp4s0 proto kernel scope host src 192.168.1.150 
broadcast 192.168.1.255 dev enp4s0 proto kernel scope link src 192.168.1.150 
```

这里也贴下参考链接中提到的，在 边车（`sidecar`）代理程序 和 本地进程 间通信时，通过`eBPF`来绕开内核协议栈的开销：  
![ebpf-sidecar](/images/network-process-ebpf-sidecar.png)

### 2.2. Unix Domain Socket

`Unix Domain Socket（UDS）`是一种用于同一主机上进程间通信（`IPC`）的机制，它**不依赖网络协议栈**，而是**直接通过内核**实现进程间的数据传递。相比基于 `TCP/UDP`的网络Socket，`UDS`更高效、更安全，是本地进程通信的优选方案之一。

#### 2.2.1. 编程方式

和传统`socket`类似，区别主要在 1）协议族需要指定`AF_UNIX`

```cpp
 // 创建socket  
int server_fd = socket(AF_INET, SOCK_STREAM, 0)  
struct sockaddr_in address;
address.sin_family = AF_INET;  
address.sin_addr.s_addr = INADDR_ANY;  
address.sin_port = htons(PORT); 
bind(server_fd, (struct sockaddr *)&address, sizeof(address))
listen(server_fd, BACKLOG)
```

```cpp
struct sockaddr_un server_addr;
// 创建 unix domain socket
int fd = socket(AF_UNIX, SOCK_STREAM, 0);
// 绑定监听
char *socket_path = "./server.sock";
strcpy(serun.sun_path, socket_path); 
bind(fd, serun, ...);
listen(fd, 128);
```

#### 2.2.2. unlink 和 rm 对比

上面`UDS`的示例中，使用`unlink`进行文件删除，这里对其做下说明。
* 在 Unix/Linux 系统中，`unlink`是一个用于删除文件（或特殊文件，如 Unix Domain Socket 创建的 .sock 文件）的系统调用（或同名命令）。它的核心作用是**移除文件系统中的目录项（directory entry），并减少文件的链接计数（link count）**。
    * 当文件的链接计数变为 `0` 且没有进程打开该文件时，文件所占用的磁盘空间会被**内核回收**。
* `rm`本质上调用`unlink`实现文件删除，但支持更多功能（如递归删除目录 -r、强制删除 -f 等）
    * `unlink`一次只能删除一个文件，且不能删除目录；`rm`可批量删除文件或目录。

文件的`inode`链接计数，之前在 [从1万空文件占用空间大小看Linux文件系统结构](https://xiaodongq.github.io/2023/06/30/linux-directory-struct/) 中也做过简单实验，这里再看下，刚touch的文件（未创建soft/hard链接）：`Links: 1`
```sh
[root@xdlinux ➜ unix_domain_socket git:(main) ✗ ]$ touch 111
[root@xdlinux ➜ unix_domain_socket git:(main) ✗ ]$ stat 111 
  File: 111
  Size: 0               Blocks: 0          IO Block: 4096   regular empty file
Device: fd06h/64774d    Inode: 25168712    Links: 1
Access: (0644/-rw-r--r--)  Uid: (    0/    root)   Gid: (    0/    root)
Access: 2025-08-11 07:20:05.473274762 +0800
Modify: 2025-08-11 07:20:05.473274762 +0800
Change: 2025-08-11 07:20:05.473274762 +0800
 Birth: 2025-08-11 07:20:05.473274762 +0800
```

1）`unlink`命令，调用到`unlink`接口（`int unlink(const char *pathname);`）：

```sh
[root@xdlinux ➜ unix_domain_socket git:(main) ✗ ]$ touch 111           
[root@xdlinux ➜ unix_domain_socket git:(main) ✗ ]$ strace -yy unlink 111
execve("/usr/bin/unlink", ["unlink", "111"], 0x7ffc142d35d0 /* 52 vars */) = 0
...
# 调用到 unlink接口
unlink("111")                           = 0
close(1</dev/pts/0<char 136:0>>)        = 0
close(2</dev/pts/0<char 136:0>>)        = 0
exit_group(0)                           = ?
+++ exited with 0 +++
```

2）`rm`命令，调用到`unlinkat`接口（`int unlinkat(int dirfd, const char *pathname, int flags);`）：
* 调用`unlinkat`接口的操作表现，和`unlink`或`rmdir`接口是一样的，但功能更强。
* 是`unlink`的扩展，支持通过**相对路径+目录描述符**处理路径，更适合在多线程环境或需要动态切换目录的场景中使用。

```sh
[root@xdlinux ➜ unix_domain_socket git:(main) ✗ ]$ touch 111       
[root@xdlinux ➜ unix_domain_socket git:(main) ✗ ]$ strace -yy rm -f 111
execve("/usr/bin/rm", ["rm", "-f", "111"], 0x7ffef209eb68 /* 52 vars */) = 0
...
newfstatat(AT_FDCWD</home/workspace/prog-playground/network/unix_domain_socket>, "111", {st_mode=S_IFREG|0644, st_size=0, ...}, AT_SYMLINK_NOFOLLOW) = 0
# 调用到 unlinkat接口
unlinkat(AT_FDCWD</home/workspace/prog-playground/network/unix_domain_socket>, "111", 0) = 0
lseek(0</dev/pts/0<char 136:0>>, 0, SEEK_CUR) = -1 ESPIPE (Illegal seek)
close(0</dev/pts/0<char 136:0>>)        = 0
close(1</dev/pts/0<char 136:0>>)        = 0
close(2</dev/pts/0<char 136:0>>)        = 0
exit_group(0)                           = ?
+++ exited with 0 +++
```

## 3. 小结


## 4. 参考
