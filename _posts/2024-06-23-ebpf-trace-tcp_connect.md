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

* `yum install bcc clang`

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

* `./server`，在服务端 192.168.1.101 上启动`8080`端口
* `./client 192.168.1.101 10`，在客户端 192.168.1.102 上并发请求10次

1、服务端信息

1）`./tcpstates -L 8080` （bcc tools默认安装在/usr/share/bcc/tools/目录）

服务端跟踪本地8080端口结果如下，只有6个ESTABLISHED，且最后变成 CLOSE_WAIT 就不动了。netstat也能看到8080有6个CLOSE_WAIT。

```sh
[root@localhost tools]# ./tcpstates -L 8080
SKADDR           C-PID C-COMM     LADDR           LPORT RADDR           RPORT OLDSTATE    -> NEWSTATE    MS
ffff9c0ee49f9d40 186798 server     0.0.0.0         8080  0.0.0.0         0     CLOSE       -> LISTEN      0.000

ffff9c0552bda700 0     swapper/0  0.0.0.0         8080  0.0.0.0         0     LISTEN      -> SYN_RECV    0.000
ffff9c0552bda700 0     swapper/0  192.168.1.101  8080  192.168.1.102  51968 SYN_RECV    -> ESTABLISHED 0.018
ffff9c0502b21d40 0     swapper/4  0.0.0.0         8080  0.0.0.0         0     LISTEN      -> SYN_RECV    0.000
ffff9c0502b21d40 0     swapper/4  192.168.1.101  8080  192.168.1.102  51958 SYN_RECV    -> ESTABLISHED 0.018
ffff9c0502b209c0 0     swapper/4  0.0.0.0         8080  0.0.0.0         0     LISTEN      -> SYN_RECV    0.000
ffff9c0502b209c0 0     swapper/4  192.168.1.101  8080  192.168.1.102  51976 SYN_RECV    -> ESTABLISHED 0.004
ffff9c0502b22700 0     swapper/4  0.0.0.0         8080  0.0.0.0         0     LISTEN      -> SYN_RECV    0.000
ffff9c0502b22700 0     swapper/4  192.168.1.101  8080  192.168.1.102  51986 SYN_RECV    -> ESTABLISHED 0.003
ffff9c04cbad57c0 0     swapper/8  0.0.0.0         8080  0.0.0.0         0     LISTEN      -> SYN_RECV    0.000
ffff9c04cbad57c0 0     swapper/8  192.168.1.101  8080  192.168.1.102  51964 SYN_RECV    -> ESTABLISHED 0.012
ffff9c0552bda700 0     swapper/0  192.168.1.101  8080  192.168.1.102  51968 ESTABLISHED -> CLOSE_WAIT  0.567
ffff9c05f016eb40 0     swapper/2  0.0.0.0         8080  0.0.0.0         0     LISTEN      -> SYN_RECV    0.000
ffff9c05f016eb40 0     swapper/2  192.168.1.101  8080  192.168.1.102  51988 SYN_RECV    -> ESTABLISHED 0.017
ffff9c05f016eb40 0     swapper/2  192.168.1.101  8080  192.168.1.102  51988 ESTABLISHED -> CLOSE_WAIT  0.566
ffff9c0502b22700 0     swapper/2  192.168.1.101  8080  192.168.1.102  51986 ESTABLISHED -> CLOSE_WAIT  0.610
ffff9c0502b209c0 0     swapper/2  192.168.1.101  8080  192.168.1.102  51976 ESTABLISHED -> CLOSE_WAIT  0.634
ffff9c0502b21d40 0     swapper/4  192.168.1.101  8080  192.168.1.102  51958 ESTABLISHED -> CLOSE_WAIT  0.560
ffff9c04cbad57c0 0     swapper/8  192.168.1.101  8080  192.168.1.102  51964 ESTABLISHED -> CLOSE_WAIT  0.648
```

根据 SKADDR 列过滤看具体某个socket变化，如 ffff9c04cbad57c0

```sh
ffff9c04cbad57c0 0     swapper/8  0.0.0.0         8080  0.0.0.0         0     LISTEN      -> SYN_RECV    0.000
ffff9c04cbad57c0 0     swapper/8  192.168.1.101  8080  192.168.1.102  51964 SYN_RECV    -> ESTABLISHED 0.012
ffff9c04cbad57c0 0     swapper/8  192.168.1.101  8080  192.168.1.102  51964 ESTABLISHED -> CLOSE_WAIT  0.648
```

2）`./tcptracer -p 3897904`，3897904是服务端pid，没抓到内容

3）`./tcpdrop -4`，没抓到内容

这个环境上之前tcpdrop报错了，手动改过，不确定是改的问题还是本来就抓不到（TODO 换其他环境）

```sh
The tcp_drop() function has been inlined in RHEL9 x86_64 kernel and isn't traceable anymore.

This has been finally fixed by the rebase to version 0.25.0
https://bugzilla.redhat.com/show_bug.cgi?id=2033151
```

4）溢出统计情况

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

5）打断server程序，变成CLOSE，netstat看没有8080相关内容了，应该收到了RST（后面又试了一次，抓包看确实是RST）

```sh
ffff9c0ee49f9d40 186798 server     0.0.0.0         8080  0.0.0.0         0     LISTEN      -> CLOSE       823073.810
ffff9c0502b21d40 186798 server     192.168.1.101  8080  192.168.1.102  51958 CLOSE_WAIT  -> CLOSE       718131.499
ffff9c0552bda700 186798 server     192.168.1.101  8080  192.168.1.102  51968 CLOSE_WAIT  -> CLOSE       718131.567
ffff9c04cbad57c0 186798 server     192.168.1.101  8080  192.168.1.102  51964 CLOSE_WAIT  -> CLOSE       718131.490
ffff9c0502b209c0 186798 server     192.168.1.101  8080  192.168.1.102  51976 CLOSE_WAIT  -> CLOSE       718131.500
ffff9c0502b22700 186798 server     192.168.1.101  8080  192.168.1.102  51986 CLOSE_WAIT  -> CLOSE       718131.515
ffff9c05f016eb40 186798 server     192.168.1.101  8080  192.168.1.102  51988 CLOSE_WAIT  -> CLOSE       718131.540
```

第二次尝试时，打断server时的服务端抓包，确实是RST，所以直接变成`CLOSE`了

```sh
[root@localhost ~]# tcpdump -r 8080.cap  -nn
reading from file 8080.cap, link-type EN10MB (Ethernet), snapshot length 262144
dropped privs to tcpdump
12:59:09.487852 IP 192.168.1.101.8080 > 192.168.1.102.48568: Flags [R.], seq 1350646848, ack 1039019527, win 509, options [nop,nop,TS val 3045140028 ecr 1867032119], length 0
12:59:09.487875 IP 192.168.1.101.8080 > 192.168.1.102.48578: Flags [R.], seq 3696534758, ack 1757949962, win 509, options [nop,nop,TS val 3045140028 ecr 1867032119], length 0
12:59:09.487892 IP 192.168.1.101.8080 > 192.168.1.102.48580: Flags [R.], seq 3393769974, ack 3672898952, win 509, options [nop,nop,TS val 3045140028 ecr 1867032120], length 0
12:59:09.487903 IP 192.168.1.101.8080 > 192.168.1.102.48604: Flags [R.], seq 3388981072, ack 1110331342, win 509, options [nop,nop,TS val 3045140028 ecr 1867032120], length 0
12:59:09.487916 IP 192.168.1.101.8080 > 192.168.1.102.48590: Flags [R.], seq 3720239075, ack 2542542395, win 509, options [nop,nop,TS val 3045140028 ecr 1867032120], length 0
12:59:09.487926 IP 192.168.1.101.8080 > 192.168.1.102.48592: Flags [R.], seq 3466164509, ack 4191170730, win 509, options [nop,nop,TS val 3045140028 ecr 1867032120], length 0
```

2、客户端

```sh
# 客户端10次请求分了10个线程并发，每线程只发一次，所以打印有时是乱的
[root@localhost qiuxiaodong]# ./client 192.168.1.101 10
Message sent: helloworldMessage sent: helloworld
Message sent: helloworld
Message sent: helloworld
Message sent: helloworld

Message sent: helloworld
# 等了挺久，最后报错
Connection FailedConnection Failed
Connection Failed

Connection Failed
```

客户端报错退出前可观察到SYN_SENT，退出后就没有8080相关连接了：

```sh
[root@localhost ~]# netstat -anp|grep client
tcp        0      1 192.168.1.102:52006    192.168.1.101:8080     SYN_SENT    18684/./client      
tcp        0      1 192.168.1.102:52020    192.168.1.101:8080     SYN_SENT    18684/./client      
tcp        0      1 192.168.1.102:51996    192.168.1.101:8080     SYN_SENT    18684/./client      
tcp        0      1 192.168.1.102:51998    192.168.1.101:8080     SYN_SENT    18684/./client
```

### 3.2. 实验2：nc正常实验，客户端发起关闭

服务端`nc -l 8090`，客户端curl，curl一次服务端会自动关闭。

说明是客户端主动关闭

```sh
SKADDR           C-PID C-COMM     LADDR           LPORT RADDR           RPORT OLDSTATE    -> NEWSTATE    MS
ffff9c04cb811500 1214733 nc         ::              8090  ::              0     CLOSE       -> LISTEN      0.000

ffff9c05f0168000 1245401 tail       0.0.0.0         8090  0.0.0.0         0     LISTEN      -> SYN_RECV    0.000
ffff9c05f0168000 1245401 tail       192.168.1.101  8090  192.168.1.102  52948 SYN_RECV    -> ESTABLISHED 0.017
ffff9c05f0168000 0     swapper/2  192.168.1.101  8090  192.168.1.102  52948 ESTABLISHED -> CLOSE_WAIT  0.249
ffff9c05f0168000 0     swapper/2  192.168.1.101  8090  192.168.1.102  52948 LAST_ACK    -> CLOSE       0.044
ffff9c05f0168000 1214733 nc         192.168.1.101  8090  192.168.1.102  52948 CLOSE_WAIT  -> LAST_ACK    0.015
ffff9c04cb811500 1214733 nc         ::              8090  ::              0     LISTEN      -> CLOSE       47670.823
```

此时 tcptracer 也可以抓到信息（正常3次握手成功才能抓到）

```sh
[root@localhost tools]# ./tcptracer -p 1214733 -t
Tracing TCP established connections. Ctrl-C to end.
TIME(s)  T  PID    COMM             IP SADDR            DADDR            SPORT  DPORT 

0.000    A  1214733 nc               4  192.168.1.101   192.168.1.102   8090   52948 
0.000    X  1214733 nc               4  192.168.1.101   192.168.1.102   8090   52948
```

### 3.3. 实验3：python起8000正常实验，服务端发起关闭

python起服务，客户端curl请求。

可跟踪到正常的4次挥手，说明是服务端主动发起关闭

```sh
[root@localhost tools]# ./tcpstates -L 8000
SKADDR           C-PID C-COMM     LADDR           LPORT RADDR           RPORT OLDSTATE    -> NEWSTATE    MS
ffff9c04cbad57c0 0     swapper/8  0.0.0.0         8000  0.0.0.0         0     LISTEN      -> SYN_RECV    0.000
ffff9c04cbad57c0 0     swapper/8  192.168.1.101  8000  192.168.1.102  56292 SYN_RECV    -> ESTABLISHED 0.013
ffff9c04cbad57c0 1421971 python     192.168.1.101  8000  192.168.1.102  56292 ESTABLISHED -> FIN_WAIT1   1.615
ffff9c04cbad57c0 1421971 python     192.168.1.101  8000  192.168.1.102  56292 FIN_WAIT1   -> FIN_WAIT1   0.033
ffff9c04cbad57c0 0     swapper/8  192.168.1.101  8000  192.168.1.102  56292 FIN_WAIT1   -> FIN_WAIT2   0.199
ffff9c04cbad57c0 0     swapper/8  192.168.1.101  8000  192.168.1.102  56292 FIN_WAIT2   -> CLOSE       0.015
```

```sh
[root@localhost tools]# ./tcptracer -p 1421971 -t
Tracing TCP established connections. Ctrl-C to end.
TIME(s)  T  PID    COMM             IP SADDR            DADDR            SPORT  DPORT 

0.000    A  1421971 python           4  192.168.1.101   192.168.1.102   8000   56292 
0.002    X  1421971 python           4  192.168.1.101   192.168.1.102   8000   56292
```

## 4. libbpf跟踪

## 5. 小结


## 6. 参考


