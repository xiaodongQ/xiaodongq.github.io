---
layout: post
title: TCP半连接全连接（三） -- eBPF跟踪全连接队列溢出
categories: 网络
tags: 网络
---

* content
{:toc}

通过eBPF跟踪TCP全连接队列溢出现象并进行分析。



## 1. 背景

在“[TCP半连接全连接（一） -- 全连接队列相关过程](https://xiaodongq.github.io/2024/05/18/tcp_connect/)”这篇文章中，进行了全连接队列溢出的实验，并且遗留了几个问题。

1. 半连接队列溢出情况分析，服务端接收具体处理逻辑
2. 内核drop包的时机，以及跟抓包的关系。哪些情况可能会抓不到drop的包？
3. systemtap/ebpf跟踪TCP状态变化，跟踪上述drop事件
4. 上述全连接实验case1中，2MSL内没观察到客户端连接`FIN_WAIT2`状态，为什么？

[TCP半连接全连接（二） -- 半连接队列代码逻辑](https://xiaodongq.github.io/2024/05/30/tcp_syn_queue/) 中基本梳理涉及到问题1、2。

本篇通过eBPF跟踪TCP状态变化和溢出情况，经过"eBPF学习实践系列"，终于可以投入实际验证了。

## 2. 环境准备

1、仍使用第一篇中的客户端、服务端程序，代码和编译脚步归档在 [github处](https://github.com/xiaodongQ/prog-playground/tree/main/network/tcp_connect)

2、起2个阿里云抢占式ECS：Alibaba Cloud Linux 3.2104 LTS 64位（内核版本：5.10.134-16.1.al8.x86_64）

安装好bcc：

* `yum install bcc clang` （安装后版本 bcc-0.25.0-5.0.1.2.al8.x86_64）

下载libbpf-bootstrap并安装其编译依赖：

* `git clone https://github.com/libbpf/libbpf-bootstrap.git`、`git submodule update --init --recursive`
* `yum install zlib-devel elfutils-libelf-devel`

3、基于5.10内核代码跟踪流程

## 3. bcc tools 跟踪

从之前"[eBPF学习实践系列（二） -- bcc tools网络工具集](https://xiaodongq.github.io/2024/06/10/bcc-tools-network/)"学习记录的bcc tools工具集中，选取如下工具：

* `tcpstates`，跟踪TCP状态变化，每次连接改变其状态时，tcpstates都会显示一个新行
* `tcptracer`，追踪**已建立连接**的TCP socket，每个connect/accept/close事件都会记录打印
* `tcpdrop`，追踪被内核丢弃的TCP数据包

### 3.1. 实验1：服务端listen不accept

用上述github中的server和client程序：

* `./server`，在服务端 172.16.58.146 上启动`8080`端口
* `./client 172.16.58.146 10`，在客户端 172.16.58.147 上并发请求10次

1、服务端信息

1）`/usr/share/bcc/tools/tcpstates -L 8080` （bcc tools默认安装在/usr/share/bcc/tools/目录）

服务端跟踪本地8080端口结果如下，只有6个ESTABLISHED，且最后变成 CLOSE_WAIT 就不动了。netstat也能看到8080有6个CLOSE_WAIT。

```sh
# tcpstates
[root@iZbp12vk49h9xtc8lx3o3uZ tools]# ./tcpstates -L 8080
SKADDR           C-PID C-COMM     LADDR           LPORT RADDR           RPORT OLDSTATE    -> NEWSTATE    MS
ffff9594075870c0 5348  server     0.0.0.0         8080  0.0.0.0         0     CLOSE       -> LISTEN      0.000

ffff959407583340 11    ksoftirqd/ 0.0.0.0         8080  0.0.0.0         0     LISTEN      -> SYN_RECV    0.000
ffff959407583340 11    ksoftirqd/ 172.16.58.146   8080  172.16.58.147   43752 SYN_RECV    -> ESTABLISHED 0.011
ffff959407581480 5315  tcpstates  0.0.0.0         8080  0.0.0.0         0     LISTEN      -> SYN_RECV    0.000
ffff959407581480 5315  tcpstates  172.16.58.146   8080  172.16.58.147   43762 SYN_RECV    -> ESTABLISHED 0.002
ffff959407582900 5315  tcpstates  0.0.0.0         8080  0.0.0.0         0     LISTEN      -> SYN_RECV    0.000
ffff959407582900 5315  tcpstates  172.16.58.146   8080  172.16.58.147   43758 SYN_RECV    -> ESTABLISHED 0.001
ffff95940742bd80 5315  tcpstates  0.0.0.0         8080  0.0.0.0         0     LISTEN      -> SYN_RECV    0.000
ffff95940742bd80 5315  tcpstates  172.16.58.146   8080  172.16.58.147   43774 SYN_RECV    -> ESTABLISHED 0.001
ffff959407581480 5315  tcpstates  172.16.58.146   8080  172.16.58.147   43762 ESTABLISHED -> CLOSE_WAIT  0.175
ffff95940742a900 5315  tcpstates  0.0.0.0         8080  0.0.0.0         0     LISTEN      -> SYN_RECV    0.000
ffff95940742a900 5315  tcpstates  172.16.58.146   8080  172.16.58.147   43794 SYN_RECV    -> ESTABLISHED 0.002
ffff95940742c7c0 5315  tcpstates  0.0.0.0         8080  0.0.0.0         0     LISTEN      -> SYN_RECV    0.000
ffff95940742c7c0 5315  tcpstates  172.16.58.146   8080  172.16.58.147   43768 SYN_RECV    -> ESTABLISHED 0.001
ffff959407582900 5315  tcpstates  172.16.58.146   8080  172.16.58.147   43758 ESTABLISHED -> CLOSE_WAIT  0.244
ffff95940742bd80 5315  tcpstates  172.16.58.146   8080  172.16.58.147   43774 ESTABLISHED -> CLOSE_WAIT  0.238
ffff95940742a900 5315  tcpstates  172.16.58.146   8080  172.16.58.147   43794 ESTABLISHED -> CLOSE_WAIT  0.191
ffff95940742c7c0 5315  tcpstates  172.16.58.146   8080  172.16.58.147   43768 ESTABLISHED -> CLOSE_WAIT  0.188
ffff959407583340 0     swapper/0  172.16.58.146   8080  172.16.58.147   43752 ESTABLISHED -> CLOSE_WAIT  0.720

# netstat
[root@iZbp12vk49h9xtc8lx3o3uZ ~]# netstat -anp|grep 8080
tcp        6      0 0.0.0.0:8080            0.0.0.0:*               LISTEN      5348/./server       
tcp       11      0 172.16.58.146:8080      172.16.58.147:43752     CLOSE_WAIT  -                   
tcp       11      0 172.16.58.146:8080      172.16.58.147:43774     CLOSE_WAIT  -                   
tcp       11      0 172.16.58.146:8080      172.16.58.147:43758     CLOSE_WAIT  -                   
tcp       11      0 172.16.58.146:8080      172.16.58.147:43768     CLOSE_WAIT  -                   
tcp       11      0 172.16.58.146:8080      172.16.58.147:43762     CLOSE_WAIT  -                   
tcp       11      0 172.16.58.146:8080      172.16.58.147:43794     CLOSE_WAIT  -
```

根据 SKADDR 列过滤看具体某个socket变化，如 ffff95940742a900

```sh
ffff95940742a900 5315  tcpstates  0.0.0.0         8080  0.0.0.0         0     LISTEN      -> SYN_RECV    0.000
ffff95940742a900 5315  tcpstates  172.16.58.146   8080  172.16.58.147   43794 SYN_RECV    -> ESTABLISHED 0.002
ffff95940742a900 5315  tcpstates  172.16.58.146   8080  172.16.58.147   43794 ESTABLISHED -> CLOSE_WAIT  0.191
```

2）`/usr/share/bcc/tools/tcptracer -p $(pidof server)`，没抓到内容（追踪3次握手成功的连接）

3）`/usr/share/bcc/tools/tcpdrop -4`，没抓到8080相关的内容

**TODO tcpdrop的应用场景没理解到位？待跟eBPF主动监测对比** 

4）溢出统计情况

客户端请求完溢出数量就不变了

```sh
[root@iZbp12vk49h9xtc8lx3o3uZ ~]# netstat -s|grep -i listen
    17 times the listen queue of a socket overflowed
    17 SYNs to LISTEN sockets dropped
```

顺便记录下之前在一个物理机环境（非本次的ECS实验）观察的溢出统计，ECS里面应该是优化了一些TCP内核参数：

```sh
# 请求前：
[root@localhost ~]# netstat -s|grep -i listen
    85 times the listen queue of a socket overflowed
    85 SYNs to LISTEN sockets dropped

# 多次检查溢出统计，每次加4次溢出，可知其为4个客户端重发SYN请求
[root@localhost ~]# netstat -s|grep -i listen
    101 times the listen queue of a socket overflowed
    101 SYNs to LISTEN sockets dropped
[root@localhost ~]# netstat -s|grep -i listen
    105 times the listen queue of a socket overflowed
    105 SYNs to LISTEN sockets dropped
[root@localhost ~]# netstat -s|grep -i listen
    109 times the listen queue of a socket overflowed
    109 SYNs to LISTEN sockets dropped
# 后面就不动了
[root@localhost ~]# netstat -s|grep -i listen
    113 times the listen queue of a socket overflowed
    113 SYNs to LISTEN sockets dropped
```

5）最后打断server程序（先开8080抓包），连接都变成了CLOSE，netstat看没有8080相关内容了，抓包看收到了RST

```sh
ffff9594075870c0 5348  server     0.0.0.0         8080  0.0.0.0         0     LISTEN      -> CLOSE       1841483.232
ffff959407583340 5348  server     172.16.58.146   8080  172.16.58.147   43752 CLOSE_WAIT  -> CLOSE       960007.376
ffff959407581480 5348  server     172.16.58.146   8080  172.16.58.147   43762 CLOSE_WAIT  -> CLOSE       960007.894
ffff959407582900 5348  server     172.16.58.146   8080  172.16.58.147   43758 CLOSE_WAIT  -> CLOSE       960007.829
ffff95940742bd80 5348  server     172.16.58.146   8080  172.16.58.147   43774 CLOSE_WAIT  -> CLOSE       960007.794
ffff95940742a900 5348  server     172.16.58.146   8080  172.16.58.147   43794 CLOSE_WAIT  -> CLOSE       960007.729
ffff95940742c7c0 5348  server     172.16.58.146   8080  172.16.58.147   43768 CLOSE_WAIT  -> CLOSE       960007.734
```

打断server时的服务端抓包，确实是RST，所以直接由`CLOSE_WAIT`变成`CLOSE`了

```sh
[root@iZbp12vk49h9xtc8lx3o3uZ ~]# tcpdump -i any port 8080 -nn
dropped privs to tcpdump
tcpdump: verbose output suppressed, use -v or -vv for full protocol decode
listening on any, link-type LINUX_SLL (Linux cooked v1), capture size 262144 bytes
07:12:27.783229 IP 172.16.58.146.8080 > 172.16.58.147.43752: Flags [R.], seq 3446801307, ack 2969925217, win 509, options [nop,nop,TS val 1950798553 ecr 3917065523], length 0
07:12:27.783247 IP 172.16.58.146.8080 > 172.16.58.147.43762: Flags [R.], seq 1119926990, ack 3287899058, win 509, options [nop,nop,TS val 1950798553 ecr 3917065522], length 0
07:12:27.783255 IP 172.16.58.146.8080 > 172.16.58.147.43758: Flags [R.], seq 2435603, ack 2250084921, win 509, options [nop,nop,TS val 1950798553 ecr 3917065522], length 0
07:12:27.783276 IP 172.16.58.146.8080 > 172.16.58.147.43774: Flags [R.], seq 3869551769, ack 469295059, win 509, options [nop,nop,TS val 1950798553 ecr 3917065522], length 0
07:12:27.783283 IP 172.16.58.146.8080 > 172.16.58.147.43794: Flags [R.], seq 1295553639, ack 3174173105, win 502, options [nop,nop,TS val 1950798553 ecr 3917065522], length 0
07:12:27.783293 IP 172.16.58.146.8080 > 172.16.58.147.43768: Flags [R.], seq 1362122314, ack 2250654632, win 502, options [nop,nop,TS val 1950798553 ecr 3917065522], length 0
```

2、客户端，也开启bcc tools跟踪，并发起请求

```sh
# 客户端10次请求分了10个线程并发，每线程只发一次
[root@iZbp12vk49h9xtc8lx3o3tZ ~]# ./client 172.16.58.146 10
Message sent: helloworld
Message sent: helloworld
Message sent: helloworld
Message sent: helloworld
Message sent: helloworld
Message sent: helloworld
Message sent: helloworld
Message sent: helloworld
Message sent: helloworld
Message sent: helloworld
```

1）客户端可短期观察到FIN_WAIT2，过段时间就没有8080相关信息了

```sh
[root@iZbp12vk49h9xtc8lx3o3tZ ~]# netstat -anp|grep 8080
tcp        0      0 172.16.58.147:43768     172.16.58.146:8080      FIN_WAIT2   -                   
tcp        0      0 172.16.58.147:43752     172.16.58.146:8080      FIN_WAIT2   -                   
tcp        0      0 172.16.58.147:43774     172.16.58.146:8080      FIN_WAIT2   -                   
tcp        0      0 172.16.58.147:43762     172.16.58.146:8080      FIN_WAIT2   -                   
tcp        0      0 172.16.58.147:43794     172.16.58.146:8080      FIN_WAIT2   -                   
tcp        0      0 172.16.58.147:43758     172.16.58.146:8080      FIN_WAIT2   -
[root@iZbp12vk49h9xtc8lx3o3tZ ~]# netstat -anp|grep 8080
[root@iZbp12vk49h9xtc8lx3o3tZ ~]#

# 之前的物理机环境（非本次ECS实验）里，客户端报错退出前还可观察到SYN_SENT，退出后就没有8080相关连接了
# [root@localhost ~]# netstat -anp|grep client
# tcp        0      1 172.16.58.147:52006    172.16.58.146:8080     SYN_SENT    18684/./client      
# tcp        0      1 172.16.58.147:52020    172.16.58.146:8080     SYN_SENT    18684/./client      
# tcp        0      1 172.16.58.147:51996    172.16.58.146:8080     SYN_SENT    18684/./client      
# tcp        0      1 172.16.58.147:51998    172.16.58.146:8080     SYN_SENT    18684/./client
```

2）tcpstates跟踪远端8080端口

```sh
[root@iZbp12vk49h9xtc8lx3o3tZ ~]# /usr/share/bcc/tools/tcpstates -D 8080
SKADDR           C-PID C-COMM     LADDR           LPORT RADDR           RPORT OLDSTATE    -> NEWSTATE    MS
ffff90cd83ae0a40 6099  client     172.16.58.147   0     172.16.58.146   8080  CLOSE       -> SYN_SENT    0.000
ffff90cd87cf5c40 6099  client     172.16.58.147   0     172.16.58.146   8080  CLOSE       -> SYN_SENT    0.000
ffff90cd87cf1ec0 6099  client     172.16.58.147   0     172.16.58.146   8080  CLOSE       -> SYN_SENT    0.000
ffff90cd87cf3d80 6099  client     172.16.58.147   0     172.16.58.146   8080  CLOSE       -> SYN_SENT    0.000
ffff90cd87cf2900 6099  client     172.16.58.147   0     172.16.58.146   8080  CLOSE       -> SYN_SENT    0.000
ffff90cdd53cb340 6099  client     172.16.58.147   0     172.16.58.146   8080  CLOSE       -> SYN_SENT    0.000
ffff90cdd53c8a40 6099  client     172.16.58.147   0     172.16.58.146   8080  CLOSE       -> SYN_SENT    0.000
ffff90cdd53ca900 6099  client     172.16.58.147   0     172.16.58.146   8080  CLOSE       -> SYN_SENT    0.000
ffff90cdd53c8000 6099  client     172.16.58.147   0     172.16.58.146   8080  CLOSE       -> SYN_SENT    0.000
ffff90cdd53c9480 6099  client     172.16.58.147   0     172.16.58.146   8080  CLOSE       -> SYN_SENT    0.000
ffff90cd83ae0a40 0     swapper/0  172.16.58.147   43752 172.16.58.146   8080  SYN_SENT    -> ESTABLISHED 0.516
ffff90cd87cf1ec0 5967  tcptracer  172.16.58.147   43762 172.16.58.146   8080  SYN_SENT    -> ESTABLISHED 0.312
ffff90cd87cf5c40 5967  tcptracer  172.16.58.147   43758 172.16.58.146   8080  SYN_SENT    -> ESTABLISHED 0.344
ffff90cd87cf2900 5967  tcptracer  172.16.58.147   43774 172.16.58.146   8080  SYN_SENT    -> ESTABLISHED 0.390
ffff90cd87cf1ec0 6099  client     172.16.58.147   43762 172.16.58.146   8080  ESTABLISHED -> FIN_WAIT1   0.206
ffff90cdd53c8a40 6099  client     172.16.58.147   43794 172.16.58.146   8080  SYN_SENT    -> ESTABLISHED 0.513
ffff90cd87cf3d80 6099  client     172.16.58.147   43768 172.16.58.146   8080  SYN_SENT    -> ESTABLISHED 0.569
ffff90cdd53cb340 6099  client     172.16.58.147   43782 172.16.58.146   8080  SYN_SENT    -> ESTABLISHED 0.544
ffff90cdd53ca900 6099  client     172.16.58.147   43796 172.16.58.146   8080  SYN_SENT    -> ESTABLISHED 0.554
ffff90cdd53c9480 6099  client     172.16.58.147   43800 172.16.58.146   8080  SYN_SENT    -> ESTABLISHED 0.530
ffff90cd87cf5c40 6099  client     172.16.58.147   43758 172.16.58.146   8080  ESTABLISHED -> FIN_WAIT1   0.330
ffff90cd87cf2900 6099  client     172.16.58.147   43774 172.16.58.146   8080  ESTABLISHED -> FIN_WAIT1   0.279
ffff90cdd53c8a40 6099  client     172.16.58.147   43794 172.16.58.146   8080  ESTABLISHED -> FIN_WAIT1   0.139
ffff90cd87cf3d80 6099  client     172.16.58.147   43768 172.16.58.146   8080  ESTABLISHED -> FIN_WAIT1   0.150
ffff90cdd53cb340 6099  client     172.16.58.147   43782 172.16.58.146   8080  ESTABLISHED -> FIN_WAIT1   0.161
ffff90cdd53ca900 6099  client     172.16.58.147   43796 172.16.58.146   8080  ESTABLISHED -> FIN_WAIT1   0.136
ffff90cdd53c8000 6099  client     172.16.58.147   43798 172.16.58.146   8080  ESTABLISHED -> FIN_WAIT1   0.754
ffff90cdd53ca900 5967  tcptracer  172.16.58.147   43796 172.16.58.146   8080  FIN_WAIT1   -> CLOSE       0.237
ffff90cdd53c8000 5967  tcptracer  172.16.58.147   43798 172.16.58.146   8080  FIN_WAIT1   -> CLOSE       0.195
ffff90cd83ae0a40 6099  client     172.16.58.147   43752 172.16.58.146   8080  ESTABLISHED -> FIN_WAIT1   0.860
ffff90cdd53c9480 6099  client     172.16.58.147   43800 172.16.58.146   8080  ESTABLISHED -> FIN_WAIT1   0.617
ffff90cdd53c9480 5837  tcpdrop    172.16.58.147   43800 172.16.58.146   8080  FIN_WAIT1   -> CLOSE       0.212
ffff90cdd53c8a40 0     swapper/0  172.16.58.147   43794 172.16.58.146   8080  FIN_WAIT1   -> FIN_WAIT2   40.370
ffff90cdd53c8a40 0     swapper/0  172.16.58.147   43794 172.16.58.146   8080  FIN_WAIT2   -> CLOSE       0.004
ffff90cd87cf3d80 0     swapper/0  172.16.58.147   43768 172.16.58.146   8080  FIN_WAIT1   -> FIN_WAIT2   40.395
ffff90cd87cf3d80 0     swapper/0  172.16.58.147   43768 172.16.58.146   8080  FIN_WAIT2   -> CLOSE       0.001
ffff90cd87cf1ec0 0     swapper/0  172.16.58.147   43762 172.16.58.146   8080  FIN_WAIT1   -> FIN_WAIT2   40.609
ffff90cd87cf1ec0 0     swapper/0  172.16.58.147   43762 172.16.58.146   8080  FIN_WAIT2   -> CLOSE       0.001
ffff90cd87cf5c40 0     swapper/0  172.16.58.147   43758 172.16.58.146   8080  FIN_WAIT1   -> FIN_WAIT2   40.499
ffff90cd87cf5c40 0     swapper/0  172.16.58.147   43758 172.16.58.146   8080  FIN_WAIT2   -> CLOSE       0.001
ffff90cd87cf2900 0     swapper/0  172.16.58.147   43774 172.16.58.146   8080  FIN_WAIT1   -> FIN_WAIT2   40.462
ffff90cd87cf2900 0     swapper/0  172.16.58.147   43774 172.16.58.146   8080  FIN_WAIT2   -> CLOSE       0.001
ffff90cd83ae0a40 5837  tcpdrop    172.16.58.147   43752 172.16.58.146   8080  FIN_WAIT1   -> FIN_WAIT2   41.005
ffff90cd83ae0a40 5837  tcpdrop    172.16.58.147   43752 172.16.58.146   8080  FIN_WAIT2   -> CLOSE       0.003
ffff90cdd53cb340 0     swapper/0  172.16.58.147   43782 172.16.58.146   8080  FIN_WAIT1   -> CLOSE       12916.193
```

我们找其中一个SKADDR跟踪，如 ffff90cdd53c8a40，可看到客户端连接正常建立，并正常发起关闭

```sh
ffff90cdd53c8a40 6099  client     172.16.58.147   0     172.16.58.146   8080  CLOSE       -> SYN_SENT    0.000
ffff90cdd53c8a40 6099  client     172.16.58.147   43794 172.16.58.146   8080  SYN_SENT    -> ESTABLISHED 0.513
ffff90cdd53c8a40 6099  client     172.16.58.147   43794 172.16.58.146   8080  ESTABLISHED -> FIN_WAIT1   0.139
ffff90cdd53c8a40 0     swapper/0  172.16.58.147   43794 172.16.58.146   8080  FIN_WAIT1   -> FIN_WAIT2   40.370
ffff90cdd53c8a40 0     swapper/0  172.16.58.147   43794 172.16.58.146   8080  FIN_WAIT2   -> CLOSE       0.004
```

3）tcptracer 能跟踪到发起连接->关闭连接

```sh
[root@iZbp12vk49h9xtc8lx3o3tZ ~]# /usr/share/bcc/tools/tcptracer
Tracing TCP established connections. Ctrl-C to end.
T  PID    COMM             IP SADDR            DADDR            SPORT  DPORT 
C  6099   client           4  172.16.58.147    172.16.58.146    43752  8080  
C  6099   client           4  172.16.58.147    172.16.58.146    43762  8080  
C  6099   client           4  172.16.58.147    172.16.58.146    43758  8080  
C  6099   client           4  172.16.58.147    172.16.58.146    43774  8080  
X  6099   client           4  172.16.58.147    172.16.58.146    43762  8080  
C  6099   client           4  172.16.58.147    172.16.58.146    43794  8080  
C  6099   client           4  172.16.58.147    172.16.58.146    43768  8080  
C  6099   client           4  172.16.58.147    172.16.58.146    43782  8080  
C  6099   client           4  172.16.58.147    172.16.58.146    43796  8080  
C  6099   client           4  172.16.58.147    172.16.58.146    43800  8080  
X  6099   client           4  172.16.58.147    172.16.58.146    43758  8080  
X  6099   client           4  172.16.58.147    172.16.58.146    43774  8080  
X  6099   client           4  172.16.58.147    172.16.58.146    43794  8080  
X  6099   client           4  172.16.58.147    172.16.58.146    43768  8080  
X  6099   client           4  172.16.58.147    172.16.58.146    43782  8080  
X  6099   client           4  172.16.58.147    172.16.58.146    43796  8080  
X  6099   client           4  172.16.58.147    172.16.58.146    43798  8080  
X  6099   client           4  172.16.58.147    172.16.58.146    43752  8080  
X  6099   client           4  172.16.58.147    172.16.58.146    43800  8080  
```

4）tcpdrop

```sh
06:56:30 0       4  172.16.58.146:8080   > 172.16.58.147:43782  FIN_WAIT1 (SYN|ACK)
        b'tcp_drop+0x1'
        b'tcp_validate_incoming+0xe7'
        b'tcp_rcv_state_process+0x19b'
        b'tcp_v4_do_rcv+0xbc'
        b'tcp_v4_rcv+0xd02'
        b'ip_protocol_deliver_rcu+0x2b'
        b'ip_local_deliver_finish+0x44'
        b'__netif_receive_skb_core+0x50b'
        b'__netif_receive_skb_list_core+0x12f'
        b'__netif_receive_skb_list+0xed'
        b'netif_receive_skb_list_internal+0xec'
        b'napi_complete_done+0x6f'
        b'virtnet_poll+0x121'
        b'napi_poll+0x95'
        b'net_rx_action+0x9a'
        b'__softirqentry_text_start+0xc4'
        b'asm_call_sysvec_on_stack+0x12'
        b'do_softirq_own_stack+0x37'
        b'irq_exit_rcu+0xc4'
        b'common_interrupt+0x77'
        b'asm_common_interrupt+0x1e'
        b'default_idle+0x13'
        b'default_enter_idle+0x2f'
        b'cpuidle_enter_state+0x8b'
        b'cpuidle_enter+0x29'
        b'cpuidle_idle_call+0x108'
        b'do_idle+0x77'
        b'cpu_startup_entry+0x19'
        b'start_kernel+0x432'
        b'secondary_startup_64_no_verify+0xc6'

06:56:40 0       4  172.16.58.146:8080   > 172.16.58.147:43782  CLOSE (RST)
        b'tcp_drop+0x1'
        b'tcp_validate_incoming+0xe7'
        b'tcp_rcv_state_process+0x19b'
        b'tcp_v4_do_rcv+0xbc'
        b'tcp_v4_rcv+0xd02'
        b'ip_protocol_deliver_rcu+0x2b'
        b'ip_local_deliver_finish+0x44'
        b'__netif_receive_skb_core+0x50b'
        b'__netif_receive_skb_list_core+0x12f'
        b'__netif_receive_skb_list+0xed'
        b'netif_receive_skb_list_internal+0xec'
        b'napi_complete_done+0x6f'
        b'virtnet_poll+0x121'
        b'napi_poll+0x95'
        b'net_rx_action+0x9a'
        b'__softirqentry_text_start+0xc4'
        b'asm_call_sysvec_on_stack+0x12'
        b'do_softirq_own_stack+0x37'
        b'irq_exit_rcu+0xc4'
        b'common_interrupt+0x77'
        b'asm_common_interrupt+0x1e'
        b'default_idle+0x13'
        b'default_enter_idle+0x2f'
        b'cpuidle_enter_state+0x8b'
        b'cpuidle_enter+0x29'
        b'cpuidle_idle_call+0x108'
        b'do_idle+0x77'
        b'cpu_startup_entry+0x19'
        b'start_kernel+0x432'
        b'secondary_startup_64_no_verify+0xc6'
```

### 3.2. 实验2：nc正常实验，客户端发起关闭

服务端`nc -l 8090`，客户端curl，curl一次服务端会自动关闭。

监测到服务端收到客户端主动发起的FIN关闭

```sh
SKADDR           C-PID C-COMM     LADDR           LPORT RADDR           RPORT OLDSTATE    -> NEWSTATE    MS
ffff9c04cb811500 1214733 nc         ::              8090  ::              0     CLOSE       -> LISTEN      0.000

ffff9c05f0168000 1245401 tail       0.0.0.0         8090  0.0.0.0         0     LISTEN      -> SYN_RECV    0.000
ffff9c05f0168000 1245401 tail       172.16.58.146   8090  172.16.58.147  52948  SYN_RECV    -> ESTABLISHED 0.017
ffff9c05f0168000 0     swapper/2    172.16.58.146   8090  172.16.58.147  52948  ESTABLISHED -> CLOSE_WAIT  0.249
ffff9c05f0168000 0     swapper/2    172.16.58.146   8090  172.16.58.147  52948  LAST_ACK    -> CLOSE       0.044
ffff9c05f0168000 1214733 nc         172.16.58.146   8090  172.16.58.147  52948  CLOSE_WAIT  -> LAST_ACK    0.015
ffff9c04cb811500 1214733 nc         ::              8090  ::              0     LISTEN      -> CLOSE       47670.823
```

此时 tcptracer 也可以抓到信息（正常3次握手成功才能抓到）

```sh
[root@localhost tools]# /usr/share/bcc/tools/tcptracer -p 1214733 -t
Tracing TCP established connections. Ctrl-C to end.
TIME(s)  T  PID    COMM             IP SADDR            DADDR            SPORT  DPORT 

0.000    A  1214733 nc               4  172.16.58.146   172.16.58.147   8090   52948 
0.000    X  1214733 nc               4  172.16.58.146   172.16.58.147   8090   52948
```

### 3.3. 实验3：正常实验，服务端发起关闭

python起服务，客户端curl请求。

监测到服务端主动发起FIN关闭

```sh
[root@localhost tools]# /usr/share/bcc/tools/tcpstates -L 8000
SKADDR           C-PID C-COMM     LADDR           LPORT RADDR           RPORT OLDSTATE    -> NEWSTATE    MS
ffff9c04cbad57c0 0     swapper/8  0.0.0.0         8000  0.0.0.0         0     LISTEN      -> SYN_RECV    0.000
ffff9c04cbad57c0 0     swapper/8  172.16.58.146   8000  172.16.58.147   56292 SYN_RECV    -> ESTABLISHED 0.013
ffff9c04cbad57c0 1421971 python   172.16.58.146   8000  172.16.58.147   56292 ESTABLISHED -> FIN_WAIT1   1.615
ffff9c04cbad57c0 1421971 python   172.16.58.146   8000  172.16.58.147   56292 FIN_WAIT1   -> FIN_WAIT1   0.033
ffff9c04cbad57c0 0     swapper/8  172.16.58.146   8000  172.16.58.147   56292 FIN_WAIT1   -> FIN_WAIT2   0.199
ffff9c04cbad57c0 0     swapper/8  172.16.58.146   8000  172.16.58.147   56292 FIN_WAIT2   -> CLOSE       0.015
```

```sh
[root@localhost tools]# /usr/share/bcc/tools/tcptracer -p 1421971 -t
Tracing TCP established connections. Ctrl-C to end.
TIME(s)  T  PID    COMM             IP SADDR            DADDR            SPORT  DPORT 

0.000    A  1421971 python           4  172.16.58.146   172.16.58.147   8000   56292 
0.002    X  1421971 python           4  172.16.58.146   172.16.58.147   8000   56292
```

## 4. libbpf跟踪

## 5. 小结


## 6. 参考


