---
title: 如何关闭一个TCP连接？
description: 介绍如何利用`tcpkill`和`hping3`关闭一个TCP连接，以及基本原理。
categories: [网络, TCP发送接收过程]
tags: [网络, tcpkill, hping3]
---

介绍如何利用`tcpkill`和`hping3`关闭一个TCP连接，以及基本原理。

## 1. 背景

1、梳理Redis中的epoll流程时（[梳理Redis和Nginx中的epoll机制](https://xiaodongq.github.io/2025/02/28/epoll-redis-nginx/)），看到accept回调中客户端关于keepalive相关的初始配置，想起来之前关于连接建立的实验和梳理：[网络实验 -- TIME_WAIT状态的连接收到SYN是什么表现](https://xiaodongq.github.io/2024/07/13/tcp-timewait-rcv-request/)，回顾了一遍。

实验中发生Seq回绕时，会向已经`Established`的服务端发送一个非法的Seq，而服务端会发送正确的ACK，这个ACK叫 **`Challenge ACK`**。客户端发现ACK并不是自己期望的，于是回复RST报文，服务端收到后就会关闭连接。

具体过程见参考链接：[4.9 已建立连接的TCP，收到SYN会发生什么？](https://www.xiaolincoding.com/network/3_tcp/challenge_ack.html)。

2、另外上周有人问有什么工具可以关闭一个TCP连接，查了下试试tcpkill（位于dsniff包），但环境网络限制和操作系统限制下依赖没解决，GitHub找了个单独实现：[tcpkill](https://github.com/chartbeat/tcpkill)，编译简单用了一下就推过去了。

本篇介绍下关闭连接的基本原理 和 `tcpkill`、`killcx`、`hping3`工具。

## 2. Challenge Ack

Challenge ACK流程示例，客户端宕机场景：

![Challenge ACK流程示例](/images/challenge_syn.png)  
[出处](https://www.xiaolincoding.com/network/3_tcp/challenge_ack.html)

此时服务端是`Established`状态，客户端上线进行三次握手，发送第一次SYN请求，而服务端还是会发送之前正确的ACK（携带了正确序列号和确认号），这个ACK叫 **`Challenge ACK`**。客户端发现ACK并不是自己期望的，于是回复RST报文，服务端收到后就会关闭连接。

## 3. 几种异常时的TCP状态表现

上述要关闭一个TCP连接，直接粗暴的方式：

1、在客户端杀掉进程的话，就会发送 FIN 报文，这个客户端进程与服务端建立的所有 TCP 连接都会被关闭

2、在服务端杀掉进程，此时所有的 TCP 连接都会被关闭

下面说明下几种异常情况下TCP连接的状态。

### 3.1. 拔掉网线几秒，再插回去，原本的 TCP 连接还存在吗？

拔掉网线后，需要分场景来讨论：

**1、拔掉网线后，若有数据传输：**

1）若服务端重传报文的过程中，客户端刚好把网线插回去了

* 拔掉网线并不会改变客户端的TCP连接状态，连接还是处于 `ESTABLISHED` 状态，所以这时客户端是可以正常接收服务端发来的数据报文，然后客户端回复`ACK`响应报文。

2）若重传报文的过程中，客户端一直没有将网线插回去

* 服务端向客户端发送数据得不到响应，触发`超时重传`机制。达到一定阈值后，内核就会判定出该TCP有问题，并通过socket接口告诉应用程序
    * `net.ipv4.tcp_retries1`：默认值一般为3，TCP重传次数达到`tcp_retries1`时，内核会认为网络出现了比较严重的问题，可能会尝试重置TCP连接或者进行其他错误处理，但**通常不会直接关闭连接**
    * **`net.ipv4.tcp_retries2`**：默认值一般为15，TCP重传次数达到`tcp_retries2`时，内核会认为连接已经失效，从而**关闭**该TCP连接。
    * 具体的重传时间间隔会根据 网络状况 和 TCP拥塞控制算法 动态调整，内核会根据`tcp_retries2`设置的值，计算出一个timeout，超过则断开连接
        * 体感：如果 tcp_retries2 =15，那么计算得到的 timeout = 924600 ms，大约为 924.6 秒，`约 15 分钟`

本地CentOS8环境默认参数：

```sh
[CentOS-root@xdlinux ➜ ~ ]$ sysctl -a|grep tcp_retries 
net.ipv4.tcp_retries1 = 3
net.ipv4.tcp_retries2 = 15
```

**2、拔掉网线后，若没有数据传输：**

1）如果没有开启 `TCP keepalive` 机制，在客户端拔掉网线后，并且双方都没有进行数据传输，那么客户端和服务端的 TCP 连接将会一直保持存在。

2）如果开启了 `TCP keepalive` 机制

* 若服务端正常，TCP保活时间重置，等待下一次保活探测
* 若服务端宕机，那么在客户端拔掉网线后，客户端和服务端的TCP连接将会在探测超时后关闭（`2 小时 11 分 15 秒`）。

`TCP keepalive`机制（TCP保活机制），开启需要手动设置`SO_KEEPALIVE`，比如Redis里：

```c
// redis-5.0.3/src/anet.c
int anetKeepAlive(char *err, int fd, int interval)
{
    int val = 1;
    if (setsockopt(fd, SOL_SOCKET, SO_KEEPALIVE, &val, sizeof(val)) == -1)
    {
        anetSetError(err, "setsockopt SO_KEEPALIVE: %s", strerror(errno));
        return ANET_ERR;
    }
    ...
}
```

tcp keepalive相关参数：

```sh
[CentOS-root@xdlinux ➜ ~ ]$ sysctl -a|grep keepalive
# 每次检测间隔 75 秒
net.ipv4.tcp_keepalive_intvl = 75
# 检测 9 次无响应，认为对方不可达
net.ipv4.tcp_keepalive_probes = 9
# 保活时间是 7200 秒（2小时），即 2 小时内如果没有任何连接相关的活动，则会启动保活机制
net.ipv4.tcp_keepalive_time = 7200
```

即TCP`内核态`保活机制 `7200+75*9 = 2小时11分15秒` 才中断连接。此外上层`应用`可以另行实现探测机制进行保活判断。

具体分析请参考：[4.13 拔掉网线后， 原本的 TCP 连接还存在吗？](https://www.xiaolincoding.com/network/3_tcp/tcp_unplug_the_network_cable.html)

### 3.2. TCP 连接，一端断电和进程崩溃有什么区别？

**1、一端断电宕机：**

* 跟`拔掉网线`场景是一样的，无法被对端感知。对于有无数据传输、是否开启TCP keepalive保活机制，表现和上述拔网线一样。
* 所以如果在没有数据传输，并且没有开启 TCP keepalive 机制时，对端的 TCP 连接将会一直处于 `ESTABLISHED` 连接状态。

**2、进程崩溃：**

* 进程崩溃时**内核可以感知**到，即使没有数据传输、没开启TCP keepalive机制
    * 内核会向对端发送`FIN`报文，后续的挥手过程也都是在内核完成，并不需要进程的参与，会**正常进行四次挥手**。
* 对于进程崩溃后立即重启，收到对端之前TCP连接的报文时，进程都会回复`RST`报文以断开连接

具体分析请参考：[4.12 TCP 连接，一端断电和进程崩溃有什么区别？](https://www.xiaolincoding.com/network/3_tcp/tcp_down_and_crash.html)

## 4. 如何关闭一个TCP连接（实验）

利用TCP交互过程中的`RST`机制开发工具，都可以实现连接关闭，比如`tcpkill`/`killcx`/`ngrep`/`scapy`/`hping3`，这里介绍参考链接中的`tcpkill`和`killcx`。

`tcpkill` 和 `killcx` 两个工具都是通过 **伪造`RST`报文** 来关闭指定的 TCP连接，但是它们拿到正确序列号的实现方式是不同的。

* `tcpkill` 是在双方进行 TCP 通信时，拿到对方下一次期望收到的序列号，然后将序列号填充到伪造的 `RST` 报文，并将其发送给对方，达到关闭 TCP 连接的效果。
    * tcpkill 工具属于**被动获取**，双方通信时才能获取正确序列号，这种方式**无法关闭非活跃的 TCP 连接**
* `killcx` 是主动发送一个 `SYN` 报文，对方收到后会回复一个携带了正确序列号和确认号的 `ACK` 报文，这个 ACK 即 `Challenge ACK`，这时就可以拿到对方下一次期望收到的序列号，然后将序列号填充到伪造的 `RST` 报文，并将其发送给对方，达到关闭 TCP 连接的效果。
    * killcx 工具属于**主动获取**，**无论 TCP 连接是否活跃，都可以关闭**
    * 利用 SEQ/ACK 号伪造两个`RST`报文分别发给客户端和服务端，从而关闭双方的连接

`killcx`通过`Challenge ACK`关闭连接 流程示意图：

![killcx通过Challenge ACK关闭连接示意](/images/killcx_process.png)  
[出处](https://www.xiaolincoding.com/network/3_tcp/challenge_ack.html)

### 4.1. tcpkill实验

`tcpkill`来自`dsniff`工具集。原理跟`tcpdump`差不多，都会通过`libpcap`库抓取符合条件的包，选项参数也差不多。

* 官网（这是个人项目）：[dsniff](https://www.monkey.org/~dugsong/dsniff/)
* github上也有其他人的fork：[dsniff](https://github.com/ggreer/dsniff)

CentOS安装：

```sh
yum install epel-release
yum install dsniff
```

实验步骤：

* 1）`python -m http.server`启动服务端（貌似`nc -l`更合适），默认8000
* 2）`nc 127.0.0.1 8000`连接服务端，此时是终端阻塞的
* 3）并且`tcpdump -i any port 8000 -nn`开启监听
* 4）`tcpkill -i any port 8000`指定关闭连接，由于没有数据传输
* 5）`nc`客户端手动输入 "abc" 并回车
* 6）查看`tcpdump`和`tcpkill`能看到RST报文

tcpkill演示--有数据传输前：

![tcpkill演示before](/images/2025-03-02-tcpkill-before.png)

tcpkill演示--有数据传输后：

由于此处`tcpkill`未特意限制 源端 和 目的端，都进行了RST

![tcpkill演示before](/images/2025-03-02-tcpkill-after.png)

### 4.2. killcx实验（失败）

工具网站：[Killcx](https://killcx.sourceforge.net/)

CentOS下安装（参考 [安装 killcx](https://github.com/bingoohuang/blog/issues/215)）：

```
在上述网站下载工具，killcx实际是一个perl脚本
yum install cpan
cpan install Net::RawIP
yum install perl-Net-Pcap
yum install epel-release
yum install libpcap
cpan install NetPacket::Ethernet
```

实验：`nc -l 8000`监听，`nc 127.0.0.1 8000`连接，`netstat`查看连接，使用`killcx`关闭连接

结果：**失败**，没有成功关闭连接，抓包只发了SYN没有应答（尝试`python -m http.server`也失败）

```sh
[CentOS-root@xdlinux ➜ ~ ]$ netstat -anp|grep -w nc
tcp        0      0 192.168.1.150:8000      192.168.1.150:56430     ESTABLISHED 128082/nc
tcp        0      0 192.168.1.150:56430     192.168.1.150:8000      ESTABLISHED 128092/nc 

[CentOS-root@xdlinux ➜ killcx-1.0.3 ]$ ./killcx 192.168.1.150:56430
killcx v1.0.3 - (c)2009-2011 Jerome Bruandet - http://killcx.sourceforge.net/

[PARENT] checking connection with [192.168.1.150:56430]
[PARENT] found connection with [192.168.1.150:8000] (ESTABLISHED)
[PARENT] forking child
[CHILD]  interface not defined, will use [enp4s0]
[CHILD]  setting up filter to sniff ACK on [enp4s0] for 5 seconds
[PARENT] sending spoofed SYN to [192.168.1.150:8000] with bogus SeqNum
[PARENT] no response from child, operation may have failed
[PARENT] => you may try using 'lo' as interface parameter
[PARENT] killing child [128840] and exiting program
```

### 4.3. hping3实验（成功）

上述`killcx`工具使用失败了，不去深究原因了。工具需要安装很多依赖，在平时环境使用也很麻烦，**弃用**。

其实只要基于`Challenge ACK`机制就能实现RST连接的效果。调整为使用`hping3`发送TCP报文，该工具用于生成和发送自定义的网络数据包。

CentOS安装：`yum install hping3`

实验步骤：

* 1）`nc -l 192.168.1.150 8000`
* 2）`nc 192.168.1.150 8000`连接服务端，此时客户端发送信息都会在服务端接收并显示
* 3）并且`tcpdump -i any port 8000 -nn`开启监听
* 4）`netstat -anp|grep 8000`查看连接
* 5）通过`hping3`向关闭非监听端口发起的那条连接，即最终向临时端口发送RST
    * 先发送`SYN`报文：`hping3 192.168.1.150 -a 192.168.1.150 -s 8000 -p 56458 --syn -V -c 1`
        * 选项解释： `hping3 目的ip        -a      源ip   -s 源端口号 -p 目的端口号 发syn报文`
    * 再根据抓包获取应答的`ACK`（此处为13790691），组装`RST`报文并发送
        * `hping3 192.168.1.150 -a 192.168.1.150 -s 8000 -p 56458 --rst --win 0 --setseq 13790691 -c 1`
* 6）查看`nc`和`netstat`结果

hping3操作之前：

![hping3操作之前](/images/2025-03-02-hping3-case-before.png)

hping3操作之后：

![hping3操作之后](/images/2025-03-02-hping3-case-after.png)

可看到客户端发起的那条TCP连接已经关闭了。

## 5. 小结

梳理异常情况下的TCP连接状态；并介绍和使用`tcpkill`、`killcx`和`hping3`，如何关闭一个TCP连接，以及其中的基本原理。

TODO：后续阅读工具的代码，考虑用Cpp/Go/Rust实现小工具。

## 6. 参考

* [网络实验 -- TIME_WAIT状态的连接收到SYN是什么表现](https://xiaodongq.github.io/2024/07/13/tcp-timewait-rcv-request/)
* [4.9 已建立连接的TCP，收到SYN会发生什么？](https://www.xiaolincoding.com/network/3_tcp/challenge_ack.html)
* [4.13 拔掉网线后， 原本的 TCP 连接还存在吗？](https://www.xiaolincoding.com/network/3_tcp/tcp_unplug_the_network_cable.html)
* [4.12 TCP 连接，一端断电和进程崩溃有什么区别？](https://www.xiaolincoding.com/network/3_tcp/tcp_down_and_crash.html)
