---
title: 容器网络（一） -- 本机网络通信 和 容器网络基础-veth
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
    * [轻松理解 Docker 网络虚拟化基础之 veth 设备](https://kfngxl.cn/index.php/archives/415/)
    * [手工模拟实现 Docker 容器网络！ 配套实验源码](https://kfngxl.cn/index.php/archives/460/)
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

这里也贴下参考链接中提到的，在 边车（`sidecar`）代理程序 和 本地进程 间通信时，通过`eBPF`来绕开内核协议栈的开销（后续再梳理展开）：  
![ebpf-sidecar](/images/network-process-ebpf-sidecar.png)

### 2.2. Unix Domain Socket

`Unix Domain Socket（UDS）`是一种用于同一主机上进程间通信（`IPC`）的机制，它**不依赖网络协议栈**，而是**直接通过内核**实现进程间的数据传递。相比基于 `TCP/UDP`的网络Socket，`UDS`更高效、更安全，是本地进程通信的优选方案之一。

UDS的流程如下，具体详情见参考文章：[本机网络IO之Unix Domain Socket与普通socket的性能对比 实验使用源码](https://kfngxl.cn/index.php/archives/211/)。

建立连接过程：  
![uds-connection](/images/uds-connection.png)

数据收发过程：  
![uds-send-recv](/images/uds-send-recv.png)

说明：
* 不需要经过网络协议栈，无需像TCP那样的三次握手、全连接半连接等过程

#### 2.2.1. 编程方式

和传统`socket`类似，区别主要在 
* 1）使用的socket地址结构为`sockaddr_un`，协议族需要指定`AF_UNIX`
    * `sockaddr_un` 里的`un`表示`UNIX domain sockets`
    * 传统socket地址是`sockaddr_in`结构，`Internet domain sockets`
* 2）需要指定一个系统文件路径用于通信

普通Socket使用方式：
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

Unix Domain Socket使用方式：
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

完整demo示例，可见：[unix_domain_socket](https://github.com/xiaodongQ/prog-playground/tree/main/network/unix_domain_socket/)。

服务端监听后，`netstat`和`ss`查看状态如下：
* 查看下面的 `I-Node`，和 `uds_demo.sock` 文件的`inode`号(`stat`或者`ls -i`查看)并不相同，多次执行用的还是旧文件的引用？但是重启后发现还是不同，代码里尝试用绝对路径也不同（**TODO**）

```sh
# netstat
[root@xdlinux ➜ unix_domain_socket git:(main) ✗ ]$ netstat -anp|grep -E "$(pidof ./server)|UNIX domain|I-Node"
Active UNIX domain sockets (servers and established)
Proto RefCnt Flags       Type       State         I-Node   PID/Program name     Path
unix  2      [ ACC ]     STREAM     LISTENING     47497885 1835025/./server     ./uds_demo.sock
# ss
[root@xdlinux ➜ unix_domain_socket git:(main) ✗ ]$ ss -anp |grep -E "$(pidof ./server)|Send-Q"
Netid State     Recv-Q Send-Q   Local Address:Port          Peer Address:Port    Process
u_str LISTEN    0      5        ./uds_demo.sock 47497885    * 0                  users:(("server",pid=1835025,fd=3))
```

客户端执行（[uds_client.c代码](https://github.com/xiaodongQ/prog-playground/blob/main/network/unix_domain_socket/uds_client.c)）：
```sh
[root@xdlinux ➜ unix_domain_socket git:(main) ✗ ]$ ./client 
Connected to server.
Received from server: Hello from server!
Client closed.
```

服务端执行（[uds_server.c代码](https://github.com/xiaodongQ/prog-playground/blob/main/network/unix_domain_socket/uds_server.c)）：
```sh
[root@xdlinux ➜ unix_domain_socket git:(main) ✗ ]$ ./server 
Server listening on ./uds_demo.sock...
Client connected.
Received from client: Hello from client!
Server closed.
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

### 2.3. 性能对比

`Unix Domain Socket`相比`lo`本地回环少了网络协议栈的交互，小包（e.g. 100字节）传输性能基本是`lo`的**2倍**多（参考链接中的实验场景），当包足够大的时候，网络协议栈上的开销就显得没那么明显了。

具体见：[本机网络IO之Unix Domain Socket与普通socket的性能对比 实验使用源码](https://kfngxl.cn/index.php/archives/211/)。

## 3. 容器网络虚拟化基础 -- veth

> 详情可见参考链接：[轻松理解 Docker 网络虚拟化基础之 veth 设备](https://kfngxl.cn/index.php/archives/415/)

网络虚拟化：用软件来模拟真实网线的连接，实现数据交互。
* 本机网络IO里的 `lo`回环设备 也是一个用软件虚拟出来的设备

### 3.1. 查看当前podman的veth

自己环境里目前安装了K8s和podman，之前的容器都停掉了，启动一下之前的MySQL容器，而后可看到多出来了`4`和`5`对应的虚拟接口。

```sh
[root@xdlinux ➜ ~ ]$ docker ps
Emulate Docker CLI using podman. Create /etc/containers/nodocker to quiet msg.
CONTAINER ID  IMAGE                                   COMMAND               CREATED      STATUS        PORTS                                        NAMES
3477156f2e93  docker.m.daocloud.io/library/mysql:8.0  --character-set-s...  5 weeks ago  Up 2 minutes  0.0.0.0:3306->3306/tcp, 3306/tcp, 33060/tcp  mysql-server

[root@xdlinux ➜ ~ ]$ ip link show
1: lo: <LOOPBACK,UP,LOWER_UP> mtu 65536 qdisc noqueue state UNKNOWN mode DEFAULT group default qlen 1000
    link/loopback 00:00:00:00:00:00 brd 00:00:00:00:00:00
2: enp4s0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc fq_codel state UP mode DEFAULT group default qlen 1000
    link/ether 1c:69:7a:f5:39:32 brd ff:ff:ff:ff:ff:ff
3: wlp3s0: <BROADCAST,MULTICAST> mtu 1500 qdisc noop state DOWN mode DEFAULT group default qlen 1000
    link/ether c8:94:02:4d:2d:01 brd ff:ff:ff:ff:ff:ff
4: podman0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc noqueue state UP mode DEFAULT group default qlen 1000
    link/ether 92:8b:b7:39:c1:c3 brd ff:ff:ff:ff:ff:ff
5: veth0@if2: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc noqueue master podman0 state UP mode DEFAULT group default qlen 1000
    link/ether 1e:90:37:9e:56:88 brd ff:ff:ff:ff:ff:ff link-netns netns-1836f023-0e86-8ff4-1416-bfb03e668d95
```

### 3.2. 实验：手动添加veth

创建veth：`ip link add veth4 type veth peer name veth5`，`ip a`可看到`veth`是成对出现的：
```sh
[root@xdlinux ➜ ~ ]$ ip link add veth4 type veth peer name veth5
[root@xdlinux ➜ ~ ]$ ip a
...
8: veth5@veth4: <BROADCAST,MULTICAST,M-DOWN> mtu 1500 qdisc noop state DOWN group default qlen 1000
    link/ether 9a:2e:ed:06:0c:56 brd ff:ff:ff:ff:ff:ff
9: veth4@veth5: <BROADCAST,MULTICAST,M-DOWN> mtu 1500 qdisc noop state DOWN group default qlen 1000
    link/ether 22:af:86:d7:d3:73 brd ff:ff:ff:ff:ff:ff

# 或ip link show 
[root@xdlinux ➜ ~ ]$ ip link show 
...
8: veth5@veth4: <BROADCAST,MULTICAST,M-DOWN> mtu 1500 qdisc noop state DOWN mode DEFAULT group default qlen 1000
    link/ether 9a:2e:ed:06:0c:56 brd ff:ff:ff:ff:ff:ff
9: veth4@veth5: <BROADCAST,MULTICAST,M-DOWN> mtu 1500 qdisc noop state DOWN mode DEFAULT group default qlen 1000
    link/ether 22:af:86:d7:d3:73 brd ff:ff:ff:ff:ff:ff
```

为设备添加ip并启动：
```sh
# 1、添加ip：
ip addr add 192.168.5.1/24 dev veth4
ip addr add 192.168.5.2/24 dev veth5

# 2、可以看到ip了
[root@xdlinux ➜ ~ ]$ ip a
8: veth5@veth4: <BROADCAST,MULTICAST,M-DOWN> mtu 1500 qdisc noop state DOWN group default qlen 1000
    link/ether 9a:2e:ed:06:0c:56 brd ff:ff:ff:ff:ff:ff
    inet 192.168.5.2/24 scope global veth5
       valid_lft forever preferred_lft forever
9: veth4@veth5: <BROADCAST,MULTICAST,M-DOWN> mtu 1500 qdisc noop state DOWN group default qlen 1000
    link/ether 22:af:86:d7:d3:73 brd ff:ff:ff:ff:ff:ff
    inet 192.168.5.1/24 scope global veth4
       valid_lft forever preferred_lft forever

# 3、启动设备
ip link set veth4 up
ip link set veth5 up

# 4、2个网口设备已启动
8: veth5@veth4: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc noqueue state UP group default qlen 1000
    link/ether 9a:2e:ed:06:0c:56 brd ff:ff:ff:ff:ff:ff
    inet 192.168.5.2/24 scope global veth5
       valid_lft forever preferred_lft forever
    inet6 fe80::982e:edff:fe06:c56/64 scope link 
       valid_lft forever preferred_lft forever
9: veth4@veth5: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc noqueue state UP group default qlen 1000
    link/ether 22:af:86:d7:d3:73 brd ff:ff:ff:ff:ff:ff
    inet 192.168.5.1/24 scope global veth4
       valid_lft forever preferred_lft forever
    inet6 fe80::20af:86ff:fed7:d373/64 scope link 
       valid_lft forever preferred_lft forever

[root@xdlinux ➜ ~ ]$ ping 192.168.5.1
PING 192.168.5.1 (192.168.5.1) 56(84) bytes of data.
64 bytes from 192.168.5.1: icmp_seq=1 ttl=64 time=0.115 ms
64 bytes from 192.168.5.1: icmp_seq=2 ttl=64 time=0.217 ms
```

### 3.3. bpftrace追踪veth接口交互

`veth`的创建、发送/接收等内核源码过程，具体可见[参考链接](https://kfngxl.cn/index.php/archives/415/)进行学习，本篇暂只跟踪下数据发送接口：`veth_xmit`。

追踪内核正反调用栈，还是用`bpftrace`（也可用`perf record -e`+`perf report`） + `funcgraph`。可了解之前的实践用法：[追踪内核网络堆栈的几种方式](https://xiaodongq.github.io/2024/07/03/strace-kernel-network-stack/) 和 [Linux存储IO栈梳理（三） -- eBPF和ftrace跟踪IO写流程](https://xiaodongq.github.io/2024/08/15/linux-write-io-stack/)，还是得结合场景多实践内化，要不时间一长又弱化了。
* `perf-tools`需要从 [GitHub项目主页](https://github.com/brendangregg/perf-tools) 下载使用，可以自行本地归档一份，比如我的归档：[tools/perf-tools](https://github.com/xiaodongQ/prog-playground/tree/main/tools/perf-tools)。

查看对应的符号和追踪点：
```sh
[root@xdlinux ➜ ~ ]$ bpftrace -l|grep veth_xmit
kfunc:veth:veth_xmit
kprobe:veth_xmit
```

如下跟踪`kprobe`，通过`ping 192.168.5.2 -I veth4`来用`veth4`向`veth5`进行发包，可追踪到调用栈：

调用`veth_xmit`之前的调用栈（谁调用到`veth_xmit`）：
```sh
# 通过计数控制抓取的个数
[root@xdlinux ➜ ~ ]$ bpftrace -e 'BEGIN { @count = 0; } kprobe:veth_xmit { if (@count < 2) { printf("comm:%s, stack:%s\n", comm, kstack()); @count++; } else { exit(); } }'

Attaching 2 probes...
comm:ping, stack:
        veth_xmit+1
        dev_hard_start_xmit+136
        __dev_queue_xmit+1214
        arp_solicit+244
        neigh_probe+81
        __neigh_event_send+615
        neigh_resolve_output+305
        ip_finish_output2+401
        ip_push_pending_frames+162
        ping_v4_sendmsg+1086
        __sys_sendto+457
        __x64_sys_sendto+32
        do_syscall_64+95
        entry_SYSCALL_64_after_hwframe+120
```

调用`veth_xmit`之后的调用栈，即`veth_xmit`中的实现流程：
```sh
[root@xdlinux ➜ bin git:(main) ✗ ]$ funcgraph -H veth_xmit
Tracing "veth_xmit"... Ctrl-C to end.
# tracer: function_graph
#
# CPU  DURATION                  FUNCTION CALLS
# |     |   |                     |   |   |   |
 10)               |  veth_xmit [veth]() {
 10)               |    irq_enter_rcu() {
 10)   0.209 us    |      irqtime_account_irq();
 10)   0.676 us    |    }
                        # 中断处理
 10)               |    __sysvec_irq_work() {
 10)               |      __wake_up() {
 10)   0.190 us    |        ...
 10)   7.999 us    |      }
 10)   8.437 us    |    }
 10)               |    irq_exit_rcu() {
 10)   0.180 us    |      irqtime_account_irq();
 10)   0.179 us    |      sched_core_idle_cpu();
 10)   0.866 us    |    }
 10)   0.179 us    |    __rcu_read_lock();
 10)   0.189 us    |    skb_clone_tx_timestamp();
 10)               |    __dev_forward_skb() {
 10)               |      __dev_forward_skb2() {
 10)   0.209 us    |        skb_scrub_packet();
 10)   0.219 us    |        eth_type_trans();
 10)   0.955 us    |      }
 10)   1.293 us    |    }
 10)               |    __netif_rx() {
 10)               |      netif_rx_internal() {
 10)               |        ktime_get_with_offset() {
 10)               |          read_hpet() {
 10)   1.155 us    |            read_hpet.part.0();
 10)   1.483 us    |          }
 10)   1.851 us    |        }
 10)               |        enqueue_to_backlog() {
 10)   0.179 us    |          _raw_spin_lock_irqsave();
 10)   0.190 us    |          __raise_softirq_irqoff();
 10)   0.179 us    |          _raw_spin_unlock_irqrestore();
 10)   1.264 us    |        }
 10)   3.612 us    |      }
 10)   3.971 us    |    }
 10)   0.179 us    |    __rcu_read_unlock();
 10) + 20.358 us   |  }
...
```

## 4. 小结

梳理说明了本机网络通信方式：lo本地回环和`Unix Domain Socket`；介绍了容器网络基础中的`veth`并进行简单跟踪，容器网络基础的其他部分在后续篇幅继续梳理实践。

## 5. 参考

* [127.0.0.1 之本机网络通信过程知多少](https://kfngxl.cn/index.php/archives/195/)
* [本机网络IO之Unix Domain Socket与普通socket的性能对比 实验使用源码](https://kfngxl.cn/index.php/archives/211/)
* [轻松理解 Docker 网络虚拟化基础之 veth 设备](https://kfngxl.cn/index.php/archives/415/)