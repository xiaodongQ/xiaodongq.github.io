---
layout: _post
title: TCP半连接全连接（三） -- eBPF跟踪全连接队列溢出（上）
categories: 网络
tags: 网络
---

* content
{:toc}

通过eBPF跟踪TCP全连接队列溢出现象并进行分析，先基于bcc tools。



## 1. 背景

在“[TCP半连接全连接（一） -- 全连接队列相关过程](https://xiaodongq.github.io/2024/05/18/tcp_connect/)”这篇文章中，进行了全连接队列溢出的实验，并且遗留了几个问题。

1. 半连接队列溢出情况分析，服务端接收具体处理逻辑
2. 内核drop包的时机，以及跟抓包的关系。哪些情况可能会抓不到drop的包？
3. systemtap/ebpf跟踪TCP状态变化，跟踪上述drop事件
4. 上述全连接实验case1中，2MSL内没观察到客户端连接`FIN_WAIT2`状态，为什么？

[TCP半连接全连接（二） -- 半连接队列代码逻辑](https://xiaodongq.github.io/2024/05/30/tcp_syn_queue/) 中基本梳理涉及到问题1、2。

本篇通过eBPF跟踪TCP状态变化和溢出情况，经过"eBPF学习实践系列"，终于可以投入实际验证了。

*说明：本博客作为个人学习实践笔记，可供参考但非系统教程，可能存在错误或遗漏，欢迎指正。若需系统学习，建议参考原链接。*

## 2. 环境准备

1、仍使用第一篇中的客户端、服务端程序，代码和编译脚本归档在 [github处](https://github.com/xiaodongQ/prog-playground/tree/main/network/)

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

用上述github中tcp_connect目录的server和client程序：

* `./server`，在服务端 172.16.58.146 上启动`8080`端口
* `./client 172.16.58.146 10`，在客户端 172.16.58.147 上并发请求10次（10线程，每线程请求1次）

1、服务端信息

1）`/usr/share/bcc/tools/tcpstates -L 8080`

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

服务端这里只跟踪到6个stream，另外4个请求的SYN此处未跟踪到，分析是全连接队列满drop掉了

根据 SKADDR 列过滤看具体某个socket变化，如 ffff95940742a900

```sh
ffff95940742a900 5315  tcpstates  0.0.0.0         8080  0.0.0.0         0     LISTEN      -> SYN_RECV    0.000
ffff95940742a900 5315  tcpstates  172.16.58.146   8080  172.16.58.147   43794 SYN_RECV    -> ESTABLISHED 0.002
ffff95940742a900 5315  tcpstates  172.16.58.146   8080  172.16.58.147   43794 ESTABLISHED -> CLOSE_WAIT  0.191
```

2）`/usr/share/bcc/tools/tcptracer -p $(pidof server)`，没抓到内容（追踪3次握手成功的连接，服务端没accept）

3）`/usr/share/bcc/tools/tcpdrop -4`，没抓到8080相关的内容

全连接队列溢出时的drop在这里抓不到吗？（TODO）

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

打断server时的服务端抓包如下，确实是RST，所以直接由`CLOSE_WAIT`变成`CLOSE`了

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

2、客户端，也同步开启bcc tools跟踪，并发起请求

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

# 之前的物理机环境（非本次ECS实验）里，客户端最后几个请求可能会阻塞，最后报错退出前还可观察到SYN_SENT，退出后就没有8080相关连接了
# [root@localhost ~]# netstat -anp|grep client
# tcp        0      1 172.16.58.147:52006    172.16.58.146:8080     SYN_SENT    18684/./client      
# tcp        0      1 172.16.58.147:52020    172.16.58.146:8080     SYN_SENT    18684/./client      
# tcp        0      1 172.16.58.147:51996    172.16.58.146:8080     SYN_SENT    18684/./client      
# tcp        0      1 172.16.58.147:51998    172.16.58.146:8080     SYN_SENT    18684/./client
```

之前相同ECS上的TCP相关内核参数：

```sh
[root@iZ2zejee6e4h8ysmmjwj1nZ ~]# sysctl -a|grep -E "syn_backlog|somaxconn|syn_retries|synack_retries|syncookies|abort_on_overflow|net.ipv4.tcp_fin_timeout|tw_buckets|tw_reuse|tw_recycle"
net.core.somaxconn = 4096
net.ipv4.tcp_abort_on_overflow = 0
net.ipv4.tcp_fin_timeout = 60
net.ipv4.tcp_max_syn_backlog = 128
net.ipv4.tcp_max_tw_buckets = 5000
net.ipv4.tcp_syn_retries = 6
net.ipv4.tcp_synack_retries = 2
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_tw_reuse = 2
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

上面包含10个stream，作为对比，上面服务端tcpstates只有6个stream。服务端开启了tcp_syncookies，所以对于客户端而言三次握手走到了ESTABLISHED

我们根据`SKADDR`过滤，可跟踪到各自的流转。细心看有**3种情形**：

**情形1**：可看到客户端发起SYN连接 -> 建立连接 -> 主动发起FIN关闭 -> 收到对端ACK（因为变成了FIN_WAIT2） -> 最后成功CLOSE。

且这种情形有 `6` 个stream（技巧：检索FIN_WAIT2并查看NEWSTATE列）。  
**和系列第一篇抓包中的case1对应**

```sh
ffff90cdd53c8a40 6099  client     172.16.58.147   0     172.16.58.146   8080  CLOSE       -> SYN_SENT    0.000
ffff90cdd53c8a40 6099  client     172.16.58.147   43794 172.16.58.146   8080  SYN_SENT    -> ESTABLISHED 0.513
ffff90cdd53c8a40 6099  client     172.16.58.147   43794 172.16.58.146   8080  ESTABLISHED -> FIN_WAIT1   0.139
ffff90cdd53c8a40 0     swapper/0  172.16.58.147   43794 172.16.58.146   8080  FIN_WAIT1   -> FIN_WAIT2   40.370
ffff90cdd53c8a40 0     swapper/0  172.16.58.147   43794 172.16.58.146   8080  FIN_WAIT2   -> CLOSE       0.004
```

**情形2**：客户端发起SYN连接 -> 建立连接 -> 发起FIN关闭 -> 直接 CLOSE（没有走完四次挥手，应该收到了对端的RST）

这种情形有 `1` 个stream（检索FIN_WAIT1   -> CLOSE）  
**注意看其处于FIN_WAIT1状态长达近13s（12916ms），和系列第一篇抓包中的case2对应**，可知从FIN_WAIT1到CLOSE之间是重传过程，重传间隔每次翻倍(0.2/0.4/0.8/1.6/3.2/6.4)

```sh
ffff90cdd53cb340 6099  client     172.16.58.147   43782 172.16.58.146   8080  SYN_SENT    -> ESTABLISHED 0.544
ffff90cdd53cb340 6099  client     172.16.58.147   43782 172.16.58.146   8080  SYN_SENT    -> ESTABLISHED 0.544
ffff90cdd53cb340 6099  client     172.16.58.147   43782 172.16.58.146   8080  ESTABLISHED -> FIN_WAIT1   0.161
ffff90cdd53cb340 0     swapper/0  172.16.58.147   43782 172.16.58.146   8080  FIN_WAIT1   -> CLOSE       12916.193
```

**情形3**：客户端发起SYN连接 -> 建立连接 -> 发起FIN关闭 -> 直接 CLOSE（没有走完四次挥手，应该收到了对端的RST）

且这种情形有 `4` 个stream（检索FIN_WAIT1   -> CLOSE）  
**注意看FIN_WAIT1状态持续只有0.2ms，和系列第一篇抓包中的case3对应。**

```sh
ffff90cdd53ca900 6099  client     172.16.58.147   0     172.16.58.146   8080  CLOSE       -> SYN_SENT    0.000
ffff90cdd53ca900 6099  client     172.16.58.147   43796 172.16.58.146   8080  SYN_SENT    -> ESTABLISHED 0.554
ffff90cdd53ca900 6099  client     172.16.58.147   43796 172.16.58.146   8080  ESTABLISHED -> FIN_WAIT1   0.136
ffff90cdd53ca900 5967  tcptracer  172.16.58.147   43796 172.16.58.146   8080  FIN_WAIT1   -> CLOSE       0.237
```

3）tcptracer 能跟踪到客户端发起连接->关闭连接

9次连接，10次关闭？

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

过滤端口，如 43762：

```sh
C  6099   client           4  172.16.58.147    172.16.58.146    43762  8080  
X  6099   client           4  172.16.58.147    172.16.58.146    43762  8080  
```

4）tcpdrop，监测到服务端发送的几种包，本地丢弃了

```sh
# 本地已是CLOSE状态，收到对端ACK，丢弃（通过43794端口看是对应case1）
06:56:27 0       4  172.16.58.146:8080   > 172.16.58.147:43794  CLOSE (ACK)
        b'tcp_drop+0x1'
        b'tcp_rcv_state_process+0x97'
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
# 本地已经发起了FIN变成了FIN_WAIT1，后续收到对端SYN|ACK，丢弃
# 这里的SYN|ACK是重传包，通过 43782 端口可以匹配上面tcpstates的结果，对应case2
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
# 收到对端RST，丢弃，对应case2
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

### 3.2. 实验2：nc对比实验，客户端发起关闭

服务端`nc -l 8090`（默认accept一个连接，-k可继续accept其他连接），客户端curl

收到客户端主动发起的FIN关闭

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

### 3.3. 实验3：对比实验，服务端发起关闭

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

这里的 `FIN_WAIT1   -> FIN_WAIT1`，是什么场景？（TODO）

```sh
[root@localhost tools]# /usr/share/bcc/tools/tcptracer -p 1421971 -t
Tracing TCP established connections. Ctrl-C to end.
TIME(s)  T  PID    COMM             IP SADDR            DADDR            SPORT  DPORT 

0.000    A  1421971 python           4  172.16.58.146   172.16.58.147   8000   56292 
0.002    X  1421971 python           4  172.16.58.146   172.16.58.147   8000   56292
```

#### 3.3.1. TIME_WAIT 跟踪疑惑

上述python起服务正常场景的`tcpstates`结果中，没有`TIME_WAIT`状态，于是单独进行了跟踪实验。

环境：服务端-192.168.1.101，客户端-192.168.1.102，服务端起python http服务。

netstat看，服务端短时间内是有TIME_WAIT的，不会体现在tcpstates里

```sh
[root@localhost tools]# netstat -anp|grep 8000
tcp        0      0 0.0.0.0:8000            0.0.0.0:*               LISTEN      256554/python       
tcp        0      0 192.168.1.101:8000     192.168.1.102:36646    TIME_WAIT   -    
```

这个时间，之间没注意去统计，感觉并没有等到2MSL（当前linux的MSL一般为30s，2MSL即60s）

于是带着几个怀疑去实验对比（下述实验是假设TIME_WAIT没有等到2MSL就消失的前提下做的）

#### 3.3.2. 怀疑点1：`SO_LINGER`选项

是因为python简单服务端设置了`SO_LINGER`？

该选项设置socket让其在关闭时避免进入TIME_WAIT或者设置该状态持续的超时时间

到`/usr/lib64/python3.9`全局搜，python里并没有设置该选项，所以排除

#### 3.3.3. 怀疑点2：`SO_REUSEADDR`选项

跟踪了`python -m http.server`示例的基本代码，看到里面设置了`SO_REUSEADDR`

这个一般是为了复用已有`TIME_WAIT`状态的socket，而不是让`TIME_WAIT`回收，**难道自己理解有偏差？**

下面进行实际实验对比：

代码位置：/usr/lib64/python3.9/http/server.py

```python
# /usr/lib64/python3.9/http/server.py
class HTTPServer(socketserver.TCPServer):

    allow_reuse_address = 1    # Seems to make sense in testing environment

    def server_bind(self):
        """Override server_bind to store the server name."""
        socketserver.TCPServer.server_bind(self)
        host, port = self.server_address[:2]
        self.server_name = socket.getfqdn(host)
        self.server_port = port
```

上面对应的是 socketserver.TCPServer，于是到该文件找TCPServer(父类)

```python
# /usr/lib64/python3.9/socketserver.py
# 上面子类方法重写(override)了 `server_bind`，且把 allow_reuse_address 赋值为true
class TCPServer(BaseServer):
    ...
    request_queue_size = 5
    allow_reuse_address = False
    ...
    def __init__(self, server_address, RequestHandlerClass, bind_and_activate=True):
        """Constructor.  May be extended, do not override."""
        BaseServer.__init__(self, server_address, RequestHandlerClass)
        self.socket = socket.socket(self.address_family,
                                    self.socket_type)
        if bind_and_activate:
            try:
                # 调用下面的函数，可能用的是子类重写的函数
                self.server_bind()
                self.server_activate()
            except:
                self.server_close()
                raise

    def server_bind(self):
        """Called by constructor to bind the socket.

        May be overridden.

        """
        if self.allow_reuse_address:
            self.socket.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self.socket.bind(self.server_address)
        self.server_address = self.socket.getsockname()

    def server_activate(self):
        """Called by constructor to activate the server.

        May be overridden.

        """
        self.socket.listen(self.request_queue_size)
```

1）跟踪是否跟`SO_REUSEADDR`有关，备份/usr/lib64/python3.9/http/server.py并改成`allow_reuse_address=0`

人工试了几次，确实就是`60s`（即2MSL）后TIME_WAIT消失，基本都是如下过程

```sh
# 开始有TIME_WAIT
[root@localhost http]# netstat -anp|grep 8000
tcp        0      0 0.0.0.0:8000            0.0.0.0:*               LISTEN      3347507/python      
tcp        0      0 192.168.1.101:8000     192.168.1.102:53484    TIME_WAIT   -
# 人工确认几次
[root@localhost http]# date; netstat -anp|grep 8000
Tue Jun 25 05:43:46 CST 2024
tcp        0      0 0.0.0.0:8000            0.0.0.0:*               LISTEN      3347507/python      
tcp        0      0 192.168.1.101:8000     192.168.1.102:53484    TIME_WAIT   -
...
[root@localhost http]# date; netstat -anp|grep 8000
Tue Jun 25 05:44:31 CST 2024
tcp        0      0 0.0.0.0:8000            0.0.0.0:*               LISTEN      3347507/python      
tcp        0      0 192.168.1.101:8000     192.168.1.102:53484    TIME_WAIT   -
# 最后没有了，60s左右
[root@localhost http]# date; netstat -anp|grep 8000
Tue Jun 25 05:44:43 CST 2024
tcp        0      0 0.0.0.0:8000            0.0.0.0:*               LISTEN      3347507/python
```

2）还原对比：也是维持了60s

所以`TIME_WAIT`持续时间跟`SO_REUSEADDR`没关系

#### 3.3.4. 怀疑点3：tcp_fin_timeout参数影响

`net.ipv4.tcp_fin_timeout`参数，理论上是控制`FIN_WAIT2`的超时时间（对端发起被动FIN前的持续状态）

正常应该不影响`TIME_WAIT`持续时间，**难道自己理解又有偏差？**（好像不是"又"，上一个没偏差）

1）该参数默认是`net.ipv4.tcp_fin_timeout = 60`，跟2MSL区分不开

2）修改为10s，再次进行验证

`sysctl -w net.ipv4.tcp_fin_timeout=10`

未重启进程，`TIME_WAIT`持续还是60s

3）重启进程，持续还是60s

结论：`TIME_WAIT`持续时间确实和`net.ipv4.tcp_fin_timeout`没关系

**总结：到这里，可以说`TIME_WAIT`持续状态就是2MSL，和上面的这些参数都无关。**

（`tcp_tw_recycle`更是不建议开，还是建议保持优雅关闭，且Linux 4.12版本后直接取消了这一参数，[参考](https://time.geekbang.org/column/article/238388)。上面5.10内核环境中`sysctl -a`确实没看到该参数了）

#### 3.3.5. tcp_fin_timeout 生效场景验证

上面提到`net.ipv4.tcp_fin_timeout`和`TIME_WAIT`无关，但是我想看下跟它有关的状态（即`FIN_WAIT2`）控制情况。

先看下挥手过程，在文本描述示意过程时，想起来正好前几天试了个有意思的工具：[PlantUML](https://plantuml.com/zh/)，可以用类似markdown文本来画图，可以画时序图和其他UML图。觉得可以试下描述这个过程

这是过程描述：

```plaintext
@startuml tcpconnect
participant client as A
participant server as B

A ->(20) B: FIN
note left: 主动端发起关闭
hnote over A: FIN_WAIT1
hnote over B: CLOSE_WAIT
A (20)<- B: ACK
hnote over A: FIN_WAIT2

A (20)<- B: FIN
note right: 被动端发起关闭
hnote over B: LAST_ACK

hnote over A: TIME_WAIT

A ->(20) B: ACK
hnote over B: CLOSE

note over A: 2MSL(60s)

hnote over A: CLOSE
@enduml
```

生成的图长这样：  
![plantuml生成图](/images/2024-06-26-tcp-fin-plantuml.png)

调起来有点费劲且丑，劝退了。。还是草图省事。

这里再放下第一篇的TCP握手和断开流程：

![TCP握手断开过程](/images/tcp-connect-close.png)

上图可直观看出，只要前面3次握手正常，且最后被动关闭方不下发`close()`发送FIN，则主动发起方理论上就是处于`FIN_WAIT2`并等待超时。

~~这里尝试用`scapy`进行模拟（因为有锤子，想试试效果。当然对端代码里直接不close能更快复现）。先不折腾了，关注重点。~~

在笔记本和linux PC间进行实验。笔记本作为服务端，linux PC作为客户端

服务端新增accept处理，但不close，完整代码见：[server.cpp](https://github.com/xiaodongQ/prog-playground/blob/main/network/tcp_connect_fin_wait2/server.cpp)

```c
// server.cpp
while (true) {  
    struct sockaddr_in client_address; // 用于存储客户端地址信息
    socklen_t client_len = sizeof(client_address);

    // 使用accept函数接受连接请求
    if ((new_socket = accept(server_fd, (struct sockaddr *)&client_address, &client_len)) < 0) {
        perror("accept");
        continue; // 如果接受失败，继续下一次循环尝试
    }

    char client_ip[INET_ADDRSTRLEN]; // 用于存储客户端IP的字符串形式
    inet_ntop(AF_INET, &(client_address.sin_addr), client_ip, INET_ADDRSTRLEN);

    std::cout << "Connection accepted from " << client_ip << ":" << ntohs(client_address.sin_port) << std::endl;

    // 读取数据逻辑
    char buffer[1024] = {0}; // 缓冲区用于存放接收的数据
    int valread;

    while ((valread = recv(new_socket, buffer, 1024, 0)) > 0) { // 循环读取直到没有更多数据
        std::cout << "Client: " << buffer << std::endl; // 打印接收到的数据
        memset(buffer, 0, 1024); // 清空缓冲区以便下一次读取
    }

    if (valread == 0) {
        std::cout << "Client disconnected" << std::endl; // 客户端正常关闭连接
    } else if (valread == -1) {
        perror("recv failed"); // 读取错误处理
    }

    // 不做关闭
}  
```

1、客户端发起1个请求

**现象及结果分析：**

```sh
[root@xdlinux ➜ tcp_connect_fin_wait2 git:(main) ✗ ]$ ./client 192.168.1.2 1
Message sent: helloworld
```

netstat观察，FIN_WAIT2确实持续了60s

```sh
# 客户端请求完，查看有FIN_WAIT2
[root@xdlinux ➜ ~ ]$ date; netstat -anp|grep 8080
Wed Jun 26 23:26:25 CST 2024
tcp        0      0 192.168.1.150:58482     192.168.1.2:8080        FIN_WAIT2   -  
# 人工定期查看
[root@xdlinux ➜ ~ ]$ date; netstat -anp|grep 8080
Wed Jun 26 23:26:27 CST 2024
tcp        0      0 192.168.1.150:58482     192.168.1.2:8080        FIN_WAIT2   -
...
[root@xdlinux ➜ ~ ]$ date; netstat -anp|grep 8080
Wed Jun 26 23:27:24 CST 2024
tcp        0      0 192.168.1.150:58482     192.168.1.2:8080        FIN_WAIT2   -  
# 最后没有了，基本是60s
[root@xdlinux ➜ ~ ]$ date; netstat -anp|grep 8080
Wed Jun 26 23:27:25 CST 2024
```

tcpstates观察到的状态变化，FIN_WAIT2只有很短的时间，后面的60s没统计到这里，暂不深究了

```sh
[root@xdlinux ➜ tools ]$ ./tcpstates -t -D 8080
TIME(s)   SKADDR           C-PID C-COMM     LADDR           LPORT RADDR           RPORT OLDSTATE    -> NEWSTATE    MS
0.000000  ffff96cb39d6a700 6657  client     192.168.1.150   0     192.168.1.2     8080  CLOSE       -> SYN_SENT    0.000
0.007642  ffff96cb39d6a700 0     swapper/9  192.168.1.150   58482 192.168.1.2     8080  SYN_SENT    -> ESTABLISHED 7.632
0.007804  ffff96cb39d6a700 6657  client     192.168.1.150   58482 192.168.1.2     8080  ESTABLISHED -> FIN_WAIT1   0.152
0.011840  ffff96cb39d6a700 0     swapper/9  192.168.1.150   58482 192.168.1.2     8080  FIN_WAIT1   -> FIN_WAIT2   4.031
0.011850  ffff96cb39d6a700 0     swapper/9  192.168.1.150   58482 192.168.1.2     8080  FIN_WAIT2   -> CLOSE       0.003
```

这是linux机器的相关内核参数，可看到tcp_fin_timeout默认是60s：

```sh
[root@xdlinux ➜ ~ ]$ sysctl -a|grep -E "syn_backlog|somaxconn|syn_retries|synack_retries|syncookies|abort_on_overflow|net.ipv4.tcp_fin_timeout|tw_buckets|tw_reuse|tw_recycle"
net.core.somaxconn = 128
net.ipv4.tcp_abort_on_overflow = 0
net.ipv4.tcp_fin_timeout = 60
net.ipv4.tcp_max_syn_backlog = 1024
net.ipv4.tcp_max_tw_buckets = 131072
net.ipv4.tcp_syn_retries = 6
net.ipv4.tcp_synack_retries = 5
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_tw_reuse = 2
```

2、调整`sysctl -w net.ipv4.tcp_fin_timeout=10`，再请求观察

可看到FIN_WAIT2只持续了10s，参数生效，到此结束tcp_fin_timeout观察实验

```sh
# client请求后，另一个终端开始手动统计（也可简单写个统计脚本方便点）
[root@xdlinux ➜ ~ ]$ date; netstat -anp|grep 8080
Wed Jun 26 23:35:31 CST 2024
tcp        0      0 192.168.1.150:58484     192.168.1.2:8080        FIN_WAIT2   -                   
[root@xdlinux ➜ ~ ]$ date; netstat -anp|grep 8080
Wed Jun 26 23:35:32 CST 2024
tcp        0      0 192.168.1.150:58484     192.168.1.2:8080        FIN_WAIT2   -                   
...
[root@xdlinux ➜ ~ ]$ date; netstat -anp|grep 8080
Wed Jun 26 23:35:38 CST 2024
tcp        0      0 192.168.1.150:58484     192.168.1.2:8080        FIN_WAIT2   -                   
[root@xdlinux ➜ ~ ]$ date; netstat -anp|grep 8080
Wed Jun 26 23:35:39 CST 2024
tcp        0      0 192.168.1.150:58484     192.168.1.2:8080        FIN_WAIT2   -                   
# 最后没有FIN_WAIT2了，距开始差不多是10s
[root@xdlinux ➜ ~ ]$ date; netstat -anp|grep 8080
Wed Jun 26 23:35:39 CST 2024
```

这里解答一下之前遗留的TODO项："**上述全连接实验case1中，2MSL内没观察到客户端连接FIN_WAIT2状态，为什么？**"

* 应该也是犯了这次类似的错误，隔了一段时间（当时不觉得久）才去统计

## 4. 小结

本篇先使用bcc tools跟踪网络交互过程，并跟踪了几个内核参数的生效情况。

本来准备继续libbpf跟踪，但篇幅有点长，拆分成不同篇

## 5. 参考

1、BCC项目
