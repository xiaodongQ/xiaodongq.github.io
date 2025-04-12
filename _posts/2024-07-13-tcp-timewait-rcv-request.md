---
title: 网络实验 -- TIME_WAIT状态的连接收到SYN是什么表现
categories: 网络
tags: [TCP, 网络]
---

TIME_WAIT状态的连接收到同四元组的SYN是什么表现

## 1. 背景

星球实验：[连接处于 TIME_WAIT 状态，这时收到了 syn 握手包](https://articles.zsxq.com/id_37l6pw1mtb0g.html)，并参考[4.11 在 TIME_WAIT 状态的 TCP 连接，收到 SYN 后会发生什么？](https://www.xiaolincoding.com/network/3_tcp/time_wait_recv_syn.html)

*说明：本博客作为个人学习实践笔记，可供参考但非系统教程，可能存在错误或遗漏，欢迎指正。若需系统学习，建议参考原链接。*

## 2. 问题描述

一个连接如果 Server 主动断开，那么这个连接在Server 上会进入 `TIME_WAIT`，

这个时候如果客户端再次用**原来的四元组**发起连接请求。首先这个连接 和 已经断开但处于`TIME_WAIT`的连接是重复的，这个时候Server该怎么处理这个握手包呢？

假设服务端监听端口为`8888`，客户端请求端口为`12345`，示意图如下：

![示意图](/images/2024-07-13-time-wait-rcv-syn.png)

## 3. 构造场景（场景1）

这里使用CentOS8.5系统，构造常规场景，保持默认TCP参数。内核为4.18.0-348.7.1.el8_5.x86_64.

```sh
# tcp_tw_timeout 在标准内核上没有，ALinux（`Alibaba Cloud Linux`）单独新增
[root@xdlinux ➜ ~ ]$ sysctl -a|grep -E 'ip_local_port_range|tcp_max_tw_buckets|tcp_tw_reuse|tcp_rfc1337|tcp_timestamps|tcp_tw_timeout'
net.ipv4.ip_local_port_range = 32768	60999
net.ipv4.tcp_max_tw_buckets = 131072
net.ipv4.tcp_rfc1337 = 0
net.ipv4.tcp_timestamps = 1
net.ipv4.tcp_tw_reuse = 2
```

**注意：这里`tcp_tw_reuse`是2**，而不是布尔的0或1。包括之前起的ECS也默认2：Alibaba Cloud Linux 3.2104 LTS 64位（内核版本：5.10.134-16.1.al8.x86_64）  

> 在高版本内核中，`net.ipv4.tcp_tw_reuse` 默认值为 2，表示仅为回环地址开启复用，基本可以粗略的认为没开启复用。 [参考](https://imroc.cc/kubernetes/best-practices/performance-optimization/network)

对于网络相关内核参数的说明和取值，可以参考 [kernel.org](https://www.kernel.org/doc/html/latest/networking/ip-sysctl.html) 或者 内核代码里的`Documentation/networking/ip-sysctl.rst`（如下）。

```sh
# linux-5.10.10/Documentation/networking/ip-sysctl.rst
tcp_tw_reuse - INTEGER
    Enable reuse of TIME-WAIT sockets for new connections when it is
    safe from protocol viewpoint.

    - 0 - disable
    - 1 - global enable
    - 2 - enable for loopback traffic only

    It should not be changed without advice/request of technical
    experts.

    Default: 2
```

### 3.1. 构造方式

1、服务端：192.168.1.150，**CentOS8.5**，开不同终端分别进行监听、开启抓包、tcpstates观测

代码：accept连接后就close，[github noread](https://github.com/xiaodongQ/prog-playground/tree/main/network/tcp_timewait_rcv_syn/mac_nc_case_noread/server.cpp)

```sh
# 终端1
[root@xdlinux ➜ ~ ]$ tcpdump -i any port 8888 -nn -w server150_8888.cap -v

# 终端2
[root@xdlinux ➜ tools ]$ ./tcpstates -L 8888
```

2、客户端：192.168.1.2，**MacOS**，开启抓包，并指定端口请求 `nc 192.168.1.150 8888 -p 12345`，在60s内请求2次

*说明：此处客户端机器为MacOS，**自己在Linux上用上述`nc`命令实验会阻塞**，若出现可以考虑换成`curl`并用`--local-port`指定端口*

```sh
➜  /Users/xd/Downloads tcpdump -i en0 port 8888 -nn -w client2_12345.cap -v
```

### 3.2. 实验现象

按时序写一下观察现象。

**服务端：**

* 请求前服务端状态

```sh
[root@xdlinux ➜ ~ ]$ ss -antp|grep 8888
LISTEN 0      5            0.0.0.0:8888      0.0.0.0:*     users:(("server",pid=17006,fd=3))
```

* 请求一次时的服务端状态，第二次（60s内发起）也是这个状态

由于是发起端，最后是TIME_WAIT状态

```sh
[root@xdlinux ➜ ~ ]$ ss -antp|grep 8888
LISTEN    0      5            0.0.0.0:8888      0.0.0.0:*     users:(("server",pid=17006,fd=3))                      
TIME-WAIT 0      0      192.168.1.150:8888  192.168.1.2:12345 
```

两次打印

```sh
[root@xdlinux ➜ tcp_timewait_rcv_syn git:(main) ✗ ]$ ./server
close, client_ip:192.168.1.2, port:12345
close, client_ip:192.168.1.2, port:12345
```

* 最后（2MSL即60s之后）没有TIME_WAIT了

```sh
[root@xdlinux ➜ ~ ]$ ss -antp|grep 8888
LISTEN 0      5            0.0.0.0:8888      0.0.0.0:*     users:(("server",pid=17006,fd=3))
```

* 抓包

```sh
[root@xdlinux ➜ ~ ]$ tcpdump -i any port 8888 -nn -w server150_8888.cap -v
dropped privs to tcpdump
tcpdump: listening on any, link-type LINUX_SLL (Linux cooked v1), capture size 262144 bytes
Got 14
```

* tcpstates结果，可看到均为服务端发起FIN关闭

```sh
[root@xdlinux ➜ tools ]$ ./tcpstates -L 8888
SKADDR           C-PID C-COMM     LADDR           LPORT RADDR           RPORT OLDSTATE    -> NEWSTATE    MS
ffff9f74a152d7c0 0     swapper/9  0.0.0.0         8888  0.0.0.0         0     LISTEN      -> SYN_RECV    0.000
ffff9f74a152d7c0 0     swapper/9  192.168.1.150   8888  192.168.1.2     12345 SYN_RECV    -> ESTABLISHED 0.016
ffff9f74a152d7c0 0     swapper/9  192.168.1.150   8888  192.168.1.2     12345 FIN_WAIT1   -> FIN_WAIT2   1.004
ffff9f74a152d7c0 0     swapper/9  192.168.1.150   8888  192.168.1.2     12345 FIN_WAIT2   -> CLOSE       0.006
ffff9f74a152d7c0 17006 server     192.168.1.150   8888  192.168.1.2     12345 ESTABLISHED -> FIN_WAIT1   0.132
# 这里是第2次
ffff9f74a152d7c0 0     swapper/9  0.0.0.0         8888  0.0.0.0         0     LISTEN      -> SYN_RECV    0.000
ffff9f74a152d7c0 0     swapper/9  192.168.1.150   8888  192.168.1.2     12345 SYN_RECV    -> ESTABLISHED 0.018
ffff9f74a152d7c0 17006 server     192.168.1.150   8888  192.168.1.2     12345 ESTABLISHED -> FIN_WAIT1   0.106
ffff9f74a152d7c0 0     swapper/9  192.168.1.150   8888  192.168.1.2     12345 FIN_WAIT1   -> FIN_WAIT2   2.142
ffff9f74a152d7c0 0     swapper/9  192.168.1.150   8888  192.168.1.2     12345 FIN_WAIT2   -> CLOSE       0.006
```

**客户端：**

```sh
➜  /Users/xd nc 192.168.1.150 8888 -p 12345
➜  /Users/xd nc 192.168.1.150 8888 -p 12345
```

* 抓包，和服务端的包一样

```sh
➜  /Users/xd/Downloads tcpdump -i en0 port 8888 -nn -w client2_12345.cap -v
tcpdump: listening on en0, link-type EN10MB (Ethernet), capture size 262144 bytes
Got 14
```

### 3.3. 抓包和结果分析

1、抓包：可看到两次请求均为服务端发起关闭，且连接正常走了三次握手和四次挥手

![服务端-客户端抓包](/images/2024-07-13-server-fin.png)

2、（局部）结论

此处实验结果：服务端socket处于`TIME_WAIT`时，客户端重用原端口组成相同的四元组是可以连接的；

但不能简单得出所有情况下服务端`TIME_WAIT`都能接收相同四元组的连接，具体见下小节说明。

## 4. 完整结论说明

为什么有的文章或书籍里会说上述场景客户端是无法连接的，参考文章里给了说明，这里先直接贴下结论，下述的说明和流程图均来自[4.11 在 TIME_WAIT 状态的 TCP 连接，收到 SYN 后会发生什么？](https://www.xiaolincoding.com/network/3_tcp/time_wait_recv_syn.html)。

针对这个问题，**关键是要看 SYN 的`序列号和时间戳`是否合法**，因为处于 `TIME_WAIT` 状态的连接收到 SYN 后，会判断 SYN 的`序列号和时间戳`是否合法，然后根据判断结果的不同做不同的处理。

### 4.1. SYN是否合法

`TIME_WAIT`时收到同四元组的SYN是否合法

1、TCP时间戳机制开启情况下（即`net.ipv4.tcp_timestamps=1`，一般默认开启）：

* 合法 SYN：客户端的 SYN 的「序列号」比服务端「期望下一个收到的序列号」要大，**并且** SYN 的「时间戳」比服务端「最后收到的报文的时间戳」要大。
* 非法 SYN：客户端的 SYN 的「序列号」比服务端「期望下一个收到的序列号」要小，或者 SYN 的「时间戳」比服务端「最后收到的报文的时间戳」要小。

2、如果双方都没有开启 TCP 时间戳机制（`net.ipv4.tcp_timestamps=0`），则 SYN 合法判断如下：

* 合法 SYN：客户端的 SYN 的「序列号」比服务端「期望下一个收到的序列号」要大。
* 非法 SYN：客户端的 SYN 的「序列号」比服务端「期望下一个收到的序列号」要小。

上述说的开启`tcp_timestamps`，是需要客户端和服务端都开启。那么对于一端开启一端关闭的情况，表现如何？（**待定 TODO**）

### 4.2. 流程图示

1、如果处于 `TIME_WAIT` 状态的连接收到「**合法的 SYN**」后，就会重用此四元组连接，**跳过 2MSL 而转变为 `SYN_RECV` 状态**，接着就能进行建立连接过程。

收到合法的SYN处理过程（双方都启用了 TCP 时间戳机制，`TSval`是发送报文时的时间戳）：

![收到合法的 SYN](/images/2024-07-13-timewait-valid-syn.png)

2、如果处于 `TIME_WAIT` 状态的连接收到「**非法的 SYN**」后，就会再回复一个第四次挥手的 ACK 报文，客户端收到后，发现并不是自己期望收到确认号（ack num），就回 RST 报文给服务端。

收到合法的SYN处理过程（双方都启用了 TCP 时间戳机制，TSval 是发送报文时的时间戳）：

![收到非法的 SYN](/images/2024-07-13-timewait-invalid-syn.png)

**这里特别注意下：服务端收到非法SYN后回复的是`ACK`（而不是`RST`），`RST`是客户端判断收到的`ACK`号不符合其预期才发起的。**

根据上述说明，构造实验场景的思路：

1. 情形1：两端都设置`net.ipv4.tcp_timestamps=1`，构造下次请求的seq比上次的小、或者构造发送时间戳比前面的小
2. 情形2：两端都设置`net.ipv4.tcp_timestamps=0`，构造下次请求的seq比上次的小

而构造方式需要再考虑。星球给了一个方式：Server 端调大 `net.ipv4.tcp_tw_timeout`（**注意 该参数ALinux特有**，可以起`Alibaba Cloud Linux`的ECS实验） 到600秒，时间长 seq 才有机会回绕

~~这里暂时仅作分析，先不进行实验。~~

## 5. TIME_WAIT 影响说明

1、TIME_WAIT 过多对客户端的影响(大多场景)：

端口不够、搜索可用端口导致CPU 飙高、QPS 500 上限等，如果设置好 tw_bucket/reuse 可以解决这些问题

2、TIME_WAIT 过多对Server端的影响(也有Server主动断开的场景)：

客户端 syn需要两次、syn 被reset等，主要是导致连接握手异常

**但是`TIME_WAIT`状态是必要的**

### 5.1. 为什么要设计 TIME_WAIT 状态？

参考：[tcp_tw_reuse 为什么默认是关闭的？](https://www.xiaolincoding.com/network/3_tcp/tcp_tw_reuse_close.html)，详情请见原链接。

设计 TIME_WAIT 状态，主要有两个原因：

* 防止历史连接中的数据，被后面相同四元组的连接错误的接收；
* 保证「被动关闭连接」的一方，能被正确的关闭；

1、原因一：防止历史连接中的数据，被后面相同四元组的连接错误的接收

先了解下：

* **序列号**，是 TCP 一个头部字段（Seq），标识了 TCP 发送端到 TCP 接收端的数据流的一个字节，因为 TCP 是面向字节流的可靠协议，为了保证消息的顺序性和可靠性，TCP 为每个传输方向上的每个字节都赋予了一个编号，以便于传输成功后确认、丢失后重传以及在接收端保证不会乱序。序列号是一个 32 位的无符号数，因此在到达 4G 之后再循环回到 0（该情况称为 **`回绕`**）。**这意味着无法根据序列号来判断新老数据**。
* **初始序列号（Initial Sequence Number，ISN）**，在 TCP 建立连接的时候，客户端和服务端都会`各自`生成一个初始序列号，它是基于时钟生成的一个随机数，来保证每个连接都拥有不同的初始序列号。初始化序列号可被视为一个 32 位的计数器，该计数器的数值每 4 微秒加 1，循环一次需要 4.55 小时。

`MSL（Maximum Segment Lifetime）`是指 TCP 协议中任何报文在网络上最大的生存时间，任何超过这个时间的数据都将被丢弃。虽然 `RFC 793` 规定 MSL 为 2 分钟，但是在实际实现的时候会有所不同，比如 Linux 默认为 30 秒，那么 2MSL 就是 60 秒。

为了防止历史连接中的数据，被后面相同四元组的连接错误的接收，因此 TCP 设计了 `TIME_WAIT` 状态，状态会持续 `2MSL` 时长，这个时间**足以让两个方向上的数据包都被丢弃，使得原来连接的数据包在网络中都自然消失，再出现的数据包一定都是新建立连接所产生的。**（能"保证"一次完整的发送->应答）

2、原因二：保证「被动关闭连接」的一方，能被正确的关闭

如果主动关闭方最后一次 ACK 报文（第四次挥手）在网络中丢失了，那么按照 TCP 可靠性原则，被动关闭方会重发 FIN 报文。

假设主动关闭方没有 TIME_WAIT 状态，而是在发完最后一次回 ACK 报文就直接进入 CLOSED 状态，如果该 ACK 报文丢失了，对端则重传 FIN 报文，而这时主动关闭方已经进入到关闭状态了，在收到对端重传的 FIN 报文后，就会回 RST 报文。

服务端收到这个 RST 并将其解释为一个错误（Connection reset by peer），这对于一个可靠的协议来说不是一个优雅的终止方式。

为了防止这种情况出现，客户端必须等待足够长的时间，确保服务端能够收到 ACK，如果服务端没有收到 ACK，那么就会触发 TCP 重传机制，服务端会重新发送一个 FIN，这样一去一来刚好两个 MSL 的时间。

再说下几个和`TIME_WAIT`相关的参数：

* `net.ipv4.tcp_tw_reuse`：其作用是让客户端快速复用处于 TIME_WAIT 状态的端口，相当于跳过了 TIME_WAIT 状态。
    * 如果开启该选项的话，客户端（连接发起方） 在调用 connect() 函数时，如果内核选择到的端口，已经被相同四元组的连接占用的时候，就会判断该连接是否处于 TIME_WAIT 状态，如果该连接处于 TIME_WAIT 状态并且 TIME_WAIT 状态持续的时间超过了 `1` 秒，那么就会重用这个连接，然后就可以正常使用该端口了。所以该选项只适用于连接发起方。
    * 新内核中默认值为2，表示仅为回环地址开启复用，基本可以粗略的认为没开启复用
* `net.ipv4.tcp_tw_recycle`：如果开启该选项的话，允许处于 TIME_WAIT 状态的连接被快速回收，该参数在 NAT 的网络下是不安全的！
    * NAT网络存在的问题详情可参考：[SYN 报文什么时候情况下会被丢弃？](https://xiaolincoding.com/network/3_tcp/syn_drop.html)
    * **在 Linux 4.12 版本后，直接取消了tcp_tw_recycle这一参数。**
* `net.ipv4.tcp_timestamps`：tcp_timestamps 选项开启之后， `PAWS（Protect Against Wrapped Sequences）` 机制会自动开启，它的作用是防止 TCP 包中的序列号发生`回绕`。（感觉保护回绕更准确，Seq 4G回绕后借助timestamp判断）
    * 在开启 tcp_timestamps 选项情况下，一台机器发的所有 TCP 包都会带上发送时的时间戳，PAWS 要求连接双方维护最近一次收到的数据包的时间戳（Recent TSval），每收到一个新数据包都会读取数据包中的时间戳值跟 Recent TSval 值做比较，如果发现收到的数据包中时间戳不是递增的，则表示该数据包是过期的，就会直接丢弃这个数据包。

## 6. 构造场景（场景2）

针对上面说的Seq回绕并判断SYN非法的情况，构造场景复现。

### 6.1. 环境说明

环境：起两个阿里云抢占式实例，Alibaba Cloud Linux 3.2104 LTS 64位（内核版本：5.10.134-16.1.al8.x86_64）

相关内核网络参数如下：

```sh
[root@iZ2zeegk1auuwxkov67qfmZ ~]# sysctl -a|grep -E 'ip_local_port_range|tcp_max_tw_buckets|tcp_tw_reuse|tcp_rfc1337|tcp_timestamps|tcp_tw_timeout|tcp_tw_timeout'
net.ipv4.ip_local_port_range = 32768    60999
net.ipv4.tcp_max_tw_buckets = 5000
# 为1时丢掉RST，避免因为 TIME_WAIT 状态收到 RST 报文而跳过 2MSL 的时间；为0则收到RST时提前结束 TIME_WAIT 状态，释放连接
net.ipv4.tcp_rfc1337 = 0
net.ipv4.tcp_timestamps = 1
# 仅回环地址开启TIME_WAIT复用，基本可以粗略的认为没开启复用
net.ipv4.tcp_tw_reuse = 2
# Alinux特有，控制TIME_WAIT的持续时间
net.ipv4.tcp_tw_timeout = 60
net.ipv4.tcp_tw_timeout_inherit = 0
```

做服务端的那台安装需要的工具：`yum install g++ bcc -y`

### 6.2. （失败）构造方式

1、服务端：172.23.133.149

`TIME_WAIT`的持续时间改成10分钟，`sysctl -w net.ipv4.tcp_tw_timeout=600`（Alinux特有）

开不同终端分别进行监听、开启抓包、tcpstates观测

代码：accept连接后就close，[github noread](https://github.com/xiaodongQ/prog-playground/tree/main/network/tcp_timewait_rcv_syn/mac_nc_case_noread/server.cpp)，`g++ server.cpp -o server`。

```sh
# 终端1
[root@iZ2zeegk1auuwxkov67qfmZ ~]# tcpdump -i any port 8888 -nn -w server149_8888.cap -v

# 终端2
[root@iZ2zeegk1auuwxkov67qfmZ ~]# /usr/share/bcc/tools/tcpstates -L 8888
```

2、客户端：172.23.133.150，开启抓包，并指定端口请求 `nc 172.23.133.149 8888 -p 12345`

```sh
[root@iZ2zeegk1auuwxkov67qflZ ~]# tcpdump -i any port 8888 -nn -w client150_12345.cap -v
```

### 6.3. （失败）现象结果

客户端一共发起4次请求。前两次tcp_timestamps默认是开启的，后两次两端都关闭：`sysctl -w net.ipv4.tcp_timestamps=0`

**服务端：**

1、只观察到`FIN-WAIT-2`状态，**没有TIME_WAIT** （为什么？TODO）

```sh
[root@iZ2zeegk1auuwxkov67qfmZ ~]# ss -antp|grep 8888
LISTEN     0      5             0.0.0.0:8888          0.0.0.0:*     users:(("server",pid=5107,fd=3))                        
FIN-WAIT-2 0      0      172.23.133.149:8888   172.23.133.150:12345
```

```sh
[root@iZ2zeegk1auuwxkov67qfmZ ~]# /usr/share/bcc/tools/tcpstates -L 8888
SKADDR           C-PID C-COMM     LADDR           LPORT RADDR           RPORT OLDSTATE    -> NEWSTATE    MS
ffff9a7306de47c0 4630  server     0.0.0.0         8888  0.0.0.0         0     CLOSE       -> LISTEN      0.000
ffff9a7306de47c0 4630  server     0.0.0.0         8888  0.0.0.0         0     LISTEN      -> CLOSE       82994.442
ffff9a7306de5200 5107  server     0.0.0.0         8888  0.0.0.0         0     CLOSE       -> LISTEN      0.000
# 1
ffff9a7306de3d80 0     swapper/0  0.0.0.0         8888  0.0.0.0         0     LISTEN      -> SYN_RECV    0.000
ffff9a7306de3d80 0     swapper/0  172.23.133.149  8888  172.23.133.150  12345 SYN_RECV    -> ESTABLISHED 0.042
ffff9a7306de3d80 5107  server     172.23.133.149  8888  172.23.133.150  12345 ESTABLISHED -> FIN_WAIT1   0.090
ffff9a7306de3d80 0     swapper/0  172.23.133.149  8888  172.23.133.150  12345 FIN_WAIT1   -> FIN_WAIT2   0.704
ffff9a7306de3d80 0     swapper/0  172.23.133.149  8888  172.23.133.150  12345 FIN_WAIT2   -> CLOSE       0.002
# 2
ffff9a7306de3d80 0     swapper/0  0.0.0.0         8888  0.0.0.0         0     LISTEN      -> SYN_RECV    0.000
ffff9a7306de3d80 0     swapper/0  172.23.133.149  8888  172.23.133.150  12345 SYN_RECV    -> ESTABLISHED 0.010
ffff9a7306de3d80 5107  server     172.23.133.149  8888  172.23.133.150  12345 ESTABLISHED -> FIN_WAIT1   0.050
ffff9a7306de3d80 0     swapper/0  172.23.133.149  8888  172.23.133.150  12345 FIN_WAIT1   -> FIN_WAIT2   0.322
ffff9a7306de3d80 0     swapper/0  172.23.133.149  8888  172.23.133.150  12345 FIN_WAIT2   -> CLOSE       0.005
# 3
ffff9a7306de0a40 0     swapper/0  0.0.0.0         8888  0.0.0.0         0     LISTEN      -> SYN_RECV    0.000
ffff9a7306de0a40 0     swapper/0  172.23.133.149  8888  172.23.133.150  12345 SYN_RECV    -> ESTABLISHED 0.011
ffff9a7306de0a40 5107  server     172.23.133.149  8888  172.23.133.150  12345 ESTABLISHED -> FIN_WAIT1   0.077
ffff9a7306de0a40 0     swapper/0  172.23.133.149  8888  172.23.133.150  12345 FIN_WAIT1   -> FIN_WAIT2   0.597
ffff9a7306de0a40 0     swapper/0  172.23.133.149  8888  172.23.133.150  12345 FIN_WAIT2   -> CLOSE       0.003
# 4
ffff9a7306de2900 0     swapper/0  0.0.0.0         8888  0.0.0.0         0     LISTEN      -> SYN_RECV    0.000
ffff9a7306de2900 0     swapper/0  172.23.133.149  8888  172.23.133.150  12345 SYN_RECV    -> ESTABLISHED 0.008
ffff9a7306de2900 5107  server     172.23.133.149  8888  172.23.133.150  12345 ESTABLISHED -> FIN_WAIT1   0.041
ffff9a7306de2900 0     swapper/0  172.23.133.149  8888  172.23.133.150  12345 FIN_WAIT1   -> FIN_WAIT2   1.109
ffff9a7306de2900 0     swapper/0  172.23.133.149  8888  172.23.133.150  12345 FIN_WAIT2   -> CLOSE       0.003
```

2、抓包结果，4次都是服务端发送RST（和上面没有TIME_WAIT有关联），4次请求间隔最长差不多有6分钟

![ECS上抓包情况](/images/2024-07-14-ecs-timewait-syn.png)

可以观察到客户端第2次和第3次时发`SYN`时有Seq回绕，但并不是服务端socket为`TIME_WAIT`时收到的SYN，还是要分析上面为什么没有`TIME_WAIT`。

**客户端：**

1、现象都是请求后阻塞一段时间，最后**输入回车后报错退出**。抓包和服务端是一样的，见上面的图。

```sh
[root@iZ2zeegk1auuwxkov67qflZ ~]# nc 172.23.133.149 8888 -p 12345
Ncat: Broken pipe.
```

### 6.4. （失败）问题分析

上述几个流都由服务端（本处的主动发起关闭方）发起了RST，这里分析下原因。

再看下上述的抓包，服务端发起FIN后收到对端的ACK，变成`FIN_WAIT2`状态，本来正常的挥手应该由对端再发送`FIN`（看上面的流程图示更直观），而后主动发起方才变成`TIME_WAIT`状态。

但是`nc 172.23.133.149 8888 -p 12345`执行时**阻塞**在那，需要多次回车才结束，看过程抓包也是没发送`FIN`的。所以要查下：为什么`nc`在ECS上没发`FIN`呢？

尝试看下：

```sh
[root@iZ2zeegk1auuwxkov67qflZ ~]# strace -yy nc 172.23.133.149 8888 -p 12345
...
socket(AF_INET, SOCK_STREAM, IPPROTO_TCP) = 3<TCP:[60349]>
fcntl(3<TCP:[60349]>, F_GETFL)          = 0x2 (flags O_RDWR)
fcntl(3<TCP:[60349]>, F_SETFL, O_RDWR|O_NONBLOCK) = 0
setsockopt(3<TCP:[60349]>, SOL_SOCKET, SO_REUSEADDR, [1], 4) = 0
bind(3<TCP:[60349]>, {sa_family=AF_INET, sin_port=htons(12345), sin_addr=inet_addr("0.0.0.0")}, 16) = 0
connect(3<TCP:[60349]>, {sa_family=AF_INET, sin_port=htons(8888), sin_addr=inet_addr("172.23.133.149")}, 16) = -1 EINPROGRESS (Operation now in progress)
select(4, [3<TCP:[172.23.133.150:12345->172.23.133.149:8888]>], [3<TCP:[172.23.133.150:12345->172.23.133.149:8888]>], [3<TCP:[172.23.133.150:12345->172.23.133.149:8888]>], {tv_sec=9, tv_usec=999000}) = 1 (out [3], left {tv_sec=9, tv_usec=998876})
getsockopt(3<TCP:[172.23.133.150:12345->172.23.133.149:8888]>, SOL_SOCKET, SO_ERROR, [0], [4]) = 0
# 贴一下声明：int select(int nfds, fd_set *readfds, fd_set *writefds, fd_set *exceptfds, struct timeval *timeout);
# 此处还有8888对应fd read事件的监控
select(4, [0</dev/pts/0<char 136:0>> 3<TCP:[172.23.133.150:12345->172.23.133.149:8888]>], [], [0</dev/pts/0<char 136:0>> 3<TCP:[172.23.133.150:12345->172.23.133.149:8888]>], NULL) = 1 (in [3])
recvfrom(3<TCP:[172.23.133.150:12345->172.23.133.149:8888]>, "", 8192, 0, 0x7ffc073e1710, [128 => 0]) = 0
close(1</dev/pts/0<char 136:0>>)        = 0
# 阻塞 （此处没有8888对应fd read事件监控了）
select(4, [0</dev/pts/0<char 136:0>>], [], [0</dev/pts/0<char 136:0>> 3<TCP:[172.23.133.150:12345->172.23.133.149:8888]>], NULL

# 第1次回车，已经发出了抓包对应的空数据，抓包里可以看出对端发了RST，本端也收到了
) = 1 (in [0])
recvfrom(0</dev/pts/0<char 136:0>>, 0x7ffc073e1790, 8192, 0, 0x7ffc073e1710, [128]) = -1 ENOTSOCK (Socket operation on non-socket)
read(0</dev/pts/0<char 136:0>>, "\n", 8192) = 1
# 8888对应fd write事件的监控
select(4, [], [3<TCP:[172.23.133.150:12345->172.23.133.149:8888]>], [0</dev/pts/0<char 136:0>> 3<TCP:[172.23.133.150:12345->172.23.133.149:8888]>], NULL) = 1 (out [3])
sendto(3<TCP:[172.23.133.150:12345->172.23.133.149:8888]>, "\n", 1, 0, NULL, 0) = 1
# 阻塞，但上面已经RST了（为什么还阻塞着？read、write事件监控都没了）
select(4, [0</dev/pts/0<char 136:0>>], [], [0</dev/pts/0<char 136:0>> 3<TCP:[172.23.133.150:12345->172.23.133.149:8888]>], NULL

# 第2次回车，无法向对端发任何东西
) = 1 (in [0])
recvfrom(0</dev/pts/0<char 136:0>>, 0x7ffc073e1790, 8192, 0, 0x7ffc073e1710, [128]) = -1 ENOTSOCK (Socket operation on non-socket)
read(0</dev/pts/0<char 136:0>>, "\n", 8192) = 1
select(4, [], [3<TCP:[172.23.133.150:12345->172.23.133.149:8888]>], [0</dev/pts/0<char 136:0>> 3<TCP:[172.23.133.150:12345->172.23.133.149:8888]>], NULL) = 1 (out [3])
sendto(3<TCP:[172.23.133.150:12345->172.23.133.149:8888]>, "\n", 1, 0, NULL, 0) = -1 EPIPE (Broken pipe)
--- SIGPIPE {si_signo=SIGPIPE, si_code=SI_USER, si_pid=14093, si_uid=0} ---
write(2</dev/pts/0<char 136:0>>, "Ncat: ", 6Ncat: ) = 6
write(2</dev/pts/0<char 136:0>>, "Broken pipe.\n", 13Broken pipe.
) = 13
exit_group(1)                           = ?
+++ exited with 1 +++
```

查看nc自身的打印信息：

```sh
[root@iZ2ze39uwj39zyd1pdvq3xZ ~]#  nc -vv 172.23.133.149 8888 -p 12345
libnsock nsock_iod_new2(): nsock_iod_new (IOD #1)
libnsock nsock_connect_tcp(): TCP connection requested to 172.23.133.149:8888 (IOD #1) EID 8
libnsock mksock_bind_addr(): Binding to 0.0.0.0:12345 (IOD #1)
libnsock nsock_trace_handler_callback(): Callback: CONNECT SUCCESS for EID 8 [172.23.133.149:8888]
Ncat: Connected to 172.23.133.149:8888.
libnsock nsock_iod_new2(): nsock_iod_new (IOD #2)
libnsock nsock_read(): Read request from IOD #1 [172.23.133.149:8888] (timeout: -1ms) EID 18
libnsock nsock_readbytes(): Read request for 0 bytes from IOD #2 [peer unspecified] EID 26
# 阻塞
libnsock nsock_trace_handler_callback(): Callback: READ EOF for EID 18 [172.23.133.149:8888]

# 回车
libnsock nsock_trace_handler_callback(): Callback: READ SUCCESS for EID 26 [peer unspecified] (1 bytes): .
libnsock nsock_write(): Write request for 1 bytes to IOD #1 EID 35 [172.23.133.149:8888]
libnsock nsock_trace_handler_callback(): Callback: WRITE SUCCESS for EID 35 [172.23.133.149:8888]
# 阻塞
libnsock nsock_readbytes(): Read request for 0 bytes from IOD #2 [peer unspecified] EID 42

# 回车
libnsock nsock_trace_handler_callback(): Callback: READ SUCCESS for EID 42 [peer unspecified] (1 bytes): .
libnsock nsock_write(): Write request for 1 bytes to IOD #1 EID 51 [172.23.133.149:8888]
libnsock nsock_trace_handler_callback(): Callback: WRITE ERROR [Broken pipe (32)] for EID 51 [172.23.133.149:8888]
Ncat: Broken pipe.
```

没直接看出啥问题，试了下服务端先发送部分数据，表现也一样。想回头`strace`和`-v`跟踪下CentOS8.5上的过程用作对比，客户端和服务端都在这台采集，**发现表现跟这里一样，也不发送`FIN`！！！**（之前场景1的客户端机器是MacOS）

场景1的实验里，是由于`nc`在MacOS上执行的，收到服务端`FIN`主动关闭后，后面发送了`FIN`完成挥手，依赖客户端的实现。

涉及`nc`不同系统的实现机制，先不纠结，换一个客户端工具。

### 6.5. （成功）客户端切换为`curl`重新验证

`curl`的`--local-port`选项，可指定本地端口（`--local-port 12345`）或端口范围（`--local-port 4000-4200`）

代码：accept连接后read再close，read下curl请求要不curl会请求失败，[github withread](https://github.com/xiaodongQ/prog-playground/tree/main/network/tcp_timewait_rcv_syn/server.cpp)

*下述IP说明：重新拉了2个ECS，服务端172.23.133.151、客户端172.23.133.152。*

1）尝试1：手动curl调用，隔个十几秒调用并观察实时抓包的Seq（一个窗口`-w`保存抓包、一个实时观察），回绕时**未观察到RST**

2）尝试2：按星球建议的重现技巧，观察到了（差别是请求间隔和次数，为什么？TODO）

* Server 端调大 net.ipv4.tcp_tw_timeout 到600秒（之前设置过）
* Server 和 Client 都关闭 net.ipv4.tcp_timestamps（之前设置过）
* 客户端两次连接间隔150秒左右（**这次不请求那么频繁了，sleep后再请求**）

客户端请求3次，每次间隔150s，如下

```sh
# 脚本内容
[root@iZ2ze39uwj39zyd1pdvq3xZ ~]# cat test.sh 
curl 172.23.133.151:8888 --local-port 12345
sleep 150
curl 172.23.133.151:8888 --local-port 12345
sleep 150
curl 172.23.133.151:8888 --local-port 12345

# 执行
[root@iZ2ze39uwj39zyd1pdvq3xZ ~]# sh test.sh
curl: (52) Empty reply from server
curl: (52) Empty reply from server
curl: (52) Empty reply from server
```

服务端收到请求打印形式如下：

```sh
Client: GET / HTTP/1.1
Host: 172.23.133.151:8888
User-Agent: curl/7.61.1
Accept: */*


close, client_ip:172.23.133.152, port:12345
```

看下抓包：服务端和客户端抓到的包是一样的。

![服务端客户端抓包情况](/images/2024-07-14-timewait-syn-client-rst.png)

[服务端抓包文件](/images/srcfiles/8888_server_172.23.133.151.cap)  
[客户端抓包文件](/images/srcfiles/8888_client_172.23.133.152.cap)

### 6.6. （成功）结果和问题分析

发了3个请求，每个请求间隔150s：

* stream0正常三次握手和四次挥手
* stream1、stream2，服务端对三次握手时的SYN应答 **`TCP ACKed unseen segment`**，客户端于是RST之前的连接；然后客户端发起新的三次握手

下面取stream1的Flow Graph进行分析：

![stream1 Flow Graph](/images/2024-07-14-stream1-flowgraph.png)

分析上述过程，**存在如下疑问。TODO**

#### 6.6.1. 客户端`TCP Port numbers reused`问题

* 1、客户端第2、第3个stream发起的`SYN`握手，为什么也是 **`TCP Port numbers reused`**（上图`mark0`）？ 客户端请求完后`netstat`/`ss`看是已经没有任何`8888`或`12345`的连接的，之前端口用完释放了才对？

分析解答：

这里的`TCP Port numbers reused`提示，是Wireshark的TCP解析器提供的分析功能，可以在Wireshark设置->协议->TCP中，勾选/取消“`Analyze TCP sequence numbers`”来启用或禁用此功能。（还有些其他场景可参考：[TCP Analysis Flags 之 TCP Port numbers reused](https://mp.weixin.qq.com/s/rP65saOCuFFEZQBtJA5H-w)）

针对 SYN 数据包(实际SYN+ACK包也是)，如果已经有一个使用相同 IP+Port 的会话，并且这个 SYN 的序列号与已有会话的 `ISN` 不同时就会设置`TCP Port numbers reused`标记。

所以这个只是Wireshark侧的辅助信息，可展开抓包看下：

![wireshark分析port reused](/images/2024-07-15-wireshark-port-reused.png)

**注意**：这里展示的`port reused`和**内核的端口重用（`REUSEPORT`）特性**不是一回事，端口重用允许同一机器上的多个进程同时创建不同的socket来`bind`和`listen`在相同的端口上，然后在内核层面实现多个用户进程的负载均衡。可通过`setsockopt(fd, SOL_SOCKET, SO_REUSEPORT, ...)`方式开启该特性，进一步了解可见：[深入理解Linux端口重用这一特性](https://mp.weixin.qq.com/s/SYCUMvzktgeGbyAfRdqhmg)。

#### 6.6.2. Seq回绕时应答的ACK 和 `Challenge ACK` 问题

* 2、对于`mark0`处对应的发起SYN后收到的ACK（`mark1`，被标记为 **`TCP ACKed unseen segment`**），和处于`Established`状态收到SYN而收到的 **`Challenge ACK`**是一回事吗？

`Challenge ACK`，相关机制具体参考：[4.9 已建立连接的TCP，收到SYN会发生什么？](https://www.xiaolincoding.com/network/3_tcp/challenge_ack.html)

#### 6.6.3. 服务端`TIME_WAIT`收到`RST`的表现问题

* 3、对于客户端发送的`RST`（上图`mark2`），服务端收到后的表现具体如何？

理论上和`net.ipv4.tcp_rfc1337`有关，为`0`时（默认值，当前环境也是0）则提前结束 TIME_WAIT 状态，释放连接；若为`1`，则会丢掉该 RST 报文。[参考](https://www.xiaolincoding.com/network/3_tcp/time_wait_recv_syn.html#%E5%9C%A8-time-wait-%E7%8A%B6%E6%80%81-%E6%94%B6%E5%88%B0-rst-%E4%BC%9A%E6%96%AD%E5%BC%80%E8%BF%9E%E6%8E%A5%E5%90%97)。

但是看后面`mark4`好像有复用关系？此环境tcp_rfc1337为0，没结束`TIME_WAIT`释放连接吗？

解答：

这个复用同问题1，只是Wireshark发现前面用了相同IP+Port的辅助信息，不用关注了。

至于`tcp_rfc1337`为0，此处应该是释放了之前的`TIME_WAIT`。

#### 6.6.4. 重新发起`SYN`为什么也是`TCP Port numbers reused`

* 4、`mark3`从Seq看是`mark0`的重传，重新发起`SYN`三次握手，这里疑问还是和第1个一样，为什么是`TCP Port numbers reused`？

解答：

这个复用也是同问题1，只是Wireshark发现前面用了相同IP+Port的辅助信息，不用关注了。

#### 6.6.5. 服务端端口重用问题 及 为什么被标记重传

* 5、`mark4`是服务端复用`TIME_WAIT`四元组端口？和前面第3个问题一起待定。另外，这里标记的重传，是谁的重传？

分析：客户端重新发SYN握手时，服务端应答SYN+ACK，其中Seq是重新生成的，对应上面说的`初始序列号`（`mark1`里Seq对应的是老连接）

看起来是正常的三次握手，为什么标记成重传了

```sh
13	20:17:27.322431	172.23.133.151	172.23.133.152	8888	12345	68	TCP	64	0.000029000	[TCP Retransmission] [TCP Port numbers reused] 8888 → 12345 [SYN, ACK] Seq=301265408 Ack=226707748 Win=64240 Len=0 MSS=1460 SACK_PERM WS=128
```

没找到其他Seq=301265408的包，待定

#### 6.6.6. 服务端`FIN`+`ACK`包为什么被标记重传

* 6、`mark5`的重传又是什么鬼？发FIN的同时重传ACK? 印象里ACK不存在重传啊？

~~分析：类似上面端口复用的提示？应该要看下Wireshark的判断规则，本篇暂不深入分析了~~

没注意看，确实是重传了上一个包（Seq都是301265409），这次只是多加了FIN（ACK也有重传？）

```sh
16	20:17:27.322773	172.23.133.151	172.23.133.152	8888	12345	56	TCP	64	0.000011000	8888 → 12345 [ACK] Seq=301265409 Ack=226707831 Win=64256 Len=0
17	20:17:27.322815	172.23.133.151	172.23.133.152	8888	12345	56	TCP	64	0.000042000	[TCP Retransmission] 8888 → 12345 [FIN, ACK] Seq=301265409 Ack=226707831 Win=64256 Len=0
```

#### 6.6.7. 一端开启一端关闭`tcp_timestamps`表现如何

上面描述"`SYN`是否合法"的小节留的TODO：时间回绕判断一般需要客户端和服务端都开启`tcp_timestamps`，那么对于一端开启一端关闭的情况，表现如何？

一般两端都开启（下面代码中有对应判断），本篇暂不深入分析了。

## 7. TCP接收处理源码简要说明

af_inet.c里初始化：`inet_init`->`inet_add_protocol(&tcp_protocol, IPPROTO_TCP)`，里面会注册`tcp_v4_rcv`为TCP层的处理入口函数。下面简要分析`TIME_WAIT`时的处理。

### 7.1. tcp_v4_rcv

```c
// linux-5.10.10/net/ipv4/tcp_ipv4.c
int tcp_v4_rcv(struct sk_buff *skb)
{
    struct net *net = dev_net(skb->dev);
    struct sk_buff *skb_to_free;
    int sdif = inet_sdif(skb);
    int dif = inet_iif(skb);
    const struct iphdr *iph;
    const struct tcphdr *th;
    bool refcounted;
    struct sock *sk;
    ...
    // TCP协议头
    th = (const struct tcphdr *)skb->data;
    // IP协议头
    iph = ip_hdr(skb);
lookup:
    // 根据四元组查找对应的sock
    sk = __inet_lookup_skb(&tcp_hashinfo, skb, __tcp_hdrlen(th), th->source,
                   th->dest, sdif, &refcounted);
process:
    // 如果连接的状态为TIME_WAIT，会跳转到 do_time_wait
    if (sk->sk_state == TCP_TIME_WAIT)
        // 本地为TIME_WAIT状态时，跳到do_time_wait处理
        goto do_time_wait;
    ...
do_time_wait:
    ...
    // 由 tcp_timewait_state_process 函数处理在 TIME_WAIT 状态收到的报文
    switch (tcp_timewait_state_process(inet_twsk(sk), skb, th)) {
    // 如果是TCP_TW_SYN，允许TIM_WAIT状态跃迁到SYN_RECV
    case TCP_TW_SYN: {
        struct sock *sk2 = inet_lookup_listener(dev_net(skb->dev),
                            &tcp_hashinfo, skb,
                            __tcp_hdrlen(th),
                            iph->saddr, th->source,
                            iph->daddr, th->dest,
                            inet_iif(skb),
                            sdif);
        if (sk2) {
            inet_twsk_deschedule_put(inet_twsk(sk));
            sk = sk2;
            tcp_v4_restore_cb(skb);
            refcounted = false;
            goto process;
        }
    }
        /* to ACK */
        fallthrough;
    // 如果是TCP_TW_ACK，返回记忆中的ACK（上一次发送的ACK）
    case TCP_TW_ACK:
        tcp_v4_timewait_ack(sk, skb);
        break;
    // 如果是TCP_TW_RST，直接发送RST包
    case TCP_TW_RST:
        tcp_v4_send_reset(sk, skb);
        inet_twsk_deschedule_put(inet_twsk(sk));
        goto discard_it;
    // 如果是TCP_TW_SUCCESS，则直接丢弃此包，不做任何响应
    case TCP_TW_SUCCESS:;
    }
    ...
}
```

### 7.2. tcp_timewait_state_process

```c
// linux-5.10.10/net/ipv4/tcp_minisocks.c
enum tcp_tw_status
tcp_timewait_state_process(struct inet_timewait_sock *tw, struct sk_buff *skb,
               const struct tcphdr *th)
{
    struct tcp_options_received tmp_opt;
    struct tcp_timewait_sock *tcptw = tcp_twsk((struct sock *)tw);
    //paws_reject 为 false，表示没有发生时间戳回绕
    //paws_reject 为 true，表示发生了时间戳回绕
    bool paws_reject = false;
    tmp_opt.saw_tstamp = 0;
    // TCP头中有选项且旧连接开启了时间戳选项
    // th->doff表示数据偏移量，即 TCP 报头的长度。以 32 位字的形式表示，用于确定数据开始的位置。它的值乘以 4 得到报头长度的字节数。
    // tw_ts_recent_stamp 记录最近一次更新 `tw_ts_recent` 的实际时间（通常是系统时间或 jiffies）
    if (th->doff > (sizeof(*th) >> 2) && tcptw->tw_ts_recent_stamp) {
        tcp_parse_options(twsk_net(tw), skb, &tmp_opt, 0, NULL); // 解析TCP选项放入tmp_opt。其中若协商过时间戳选项或者本地开启了tcp_timestamps，则对时间戳进行记录
        // 启用了 TCP 时间戳选项
        if (tmp_opt.saw_tstamp) {
            // rcv_tsecr：接收方将其上次接收到的数据包中的TSval值填入TSecr并返回给发送方
            if (tmp_opt.rcv_tsecr)
                // tw_ts_offset 是时间戳偏移量，用于防止 TIME-WAIT 重用问题，即在新的连接中避免时间戳冲突
                tmp_opt.rcv_tsecr -= tcptw->tw_ts_offset;
            // ts_recent：存储的是接收到的最新时间戳值。这值是对方在其发送的 TCP 包的时间戳选项（TSval字段）中提供的值。
                // 当一个新的 TCP 包被接收并且其中的时间戳值大于当前的 `ts_recent` 时，这个字段就会被更新，并且 `ts_recent_stamp` 也会相应更新
            // tw_ts_recent：存储最近一次接收到的 TCP 时间戳值。该值用于 PAWS 机制，确保 TIME-WAIT 期间的时间戳一致
            tmp_opt.ts_recent	= tcptw->tw_ts_recent;
            // 上次记录的时间戳
            // 每当 `ts_recent` 更新时，相应地，`ts_recent_stamp` 也会更新为内核当前的时间值。
            tmp_opt.ts_recent_stamp	= tcptw->tw_ts_recent_stamp;
            // 检查收到的报文的时间戳是否发生了时间戳回绕
            paws_reject = tcp_paws_reject(&tmp_opt, th->rst);
        }
    }
    ...
    // RST报文的时间戳没有发生回绕
    if (!paws_reject &&
        (TCP_SKB_CB(skb)->seq == tcptw->tw_rcv_nxt &&
         (TCP_SKB_CB(skb)->seq == TCP_SKB_CB(skb)->end_seq || th->rst))) {
        // 处理rst报文
        if (th->rst) {
            // 不开启 sysctl_tcp_rfc1337 选项，当收到 RST 时会立即回收tw
            if (twsk_net(tw)->ipv4.sysctl_tcp_rfc1337 == 0) {
kill:
                // 删除tw定时器，并释放tw
                inet_twsk_deschedule_put(tw);
                // 如果是TCP_TW_SUCCESS，则直接丢弃此包，不做任何响应
                return TCP_TW_SUCCESS;
            }
        } else {
            // 将 TIMEWAIT 状态的持续时间重新延长
            inet_twsk_reschedule(tw, TCP_TIMEWAIT_LEN);
        }
        ...
        // 如果是TCP_TW_SUCCESS，则直接丢弃此包，不做任何响应
        return TCP_TW_SUCCESS;
    }

    //是SYN包、没有RST、没有ACK、时间戳没有回绕，并且序列号也没有回绕
    if (th->syn && !th->rst && !th->ack && !paws_reject &&
        (after(TCP_SKB_CB(skb)->seq, tcptw->tw_rcv_nxt) ||
         (tmp_opt.saw_tstamp && //新连接开启了时间戳
          (s32)(tcptw->tw_ts_recent - tmp_opt.rcv_tsval) < 0))) { //时间戳没有回绕
        // 初始化序列号
        u32 isn = tcptw->tw_snd_nxt + 65535 + 2;
        if (isn == 0)
            isn++;
        TCP_SKB_CB(skb)->tcp_tw_isn = isn;
        return TCP_TW_SYN; //允许重用TIME_WAIT四元组重新建立连接
    }

    if (paws_reject)
        __NET_INC_STATS(twsk_net(tw), LINUX_MIB_PAWSESTABREJECTED);

    if (!th->rst) {
        // 如果时间戳回绕，或者报文里包含ack，则将 TIMEWAIT 状态的持续时间重新延长
        if (paws_reject || th->ack)
            inet_twsk_reschedule(tw, TCP_TIMEWAIT_LEN);

        return tcp_timewait_check_oow_rate_limit(
            tw, skb, LINUX_MIB_TCPACKSKIPPEDTIMEWAIT);
    }
    inet_twsk_put(tw);
    return TCP_TW_SUCCESS;
}
```

### 7.3. `struct tcp_options_received`

上面`tmp_opt.ts_recent`/`tmp_opt.ts_recent_stamp`等赋值涉及`tcp_options_received`和`tcp_timewait_sock`结构，这里说明下。

* `tcp_options_received` 是 Linux 内核中用于处理接收到的 TCP 选项的重要结构。此结构在 TCP 协议的实现中起着至关重要的作用。TCP 选项是 TCP 首部的一部分，用于提供附加的通信控制功能，例如窗口扩展、时间戳等。
* `tcp_timewait_sock` 是 Linux 内核中用于管理 TIME-WAIT 状态的结构。

TCP**三次握手的过程**中会协商各类选项，包括时间戳选项。如果双方都支持时间戳选项，就会使用时间戳进行后续通信。

下面说明下字段含义，有助于后续梳理代码逻辑。

```c
// linux-5.10.10/include/linux/tcp.h
// 提供了一个集中化的地方来保持所有已接收 TCP 选项的状态。处理函数会根据这些选项来调整 TCP 连接的行为。
// 通过解析 TCP 包中的选项字段，然后填充这个结构，TCP 协议可以动态调整其操作。
struct tcp_options_received {
/*	PAWS/RTTM data	*/
    // `ts_recent_stamp` 是一个时间戳，
    // 记录的是最近一次更新 `ts_recent` 的内核时间。这是一个内核时间的标记，通常以系统时间或者定时器滴答值（jiffies）表示，用于衡量时间流逝的。
    // 主要用于计算 TCP 连接中的 RTT（Round-Trip Time），以及进行 PAWS（Protect Against Wrapped Sequence numbers）保护机制中的时间验证。
    // 每当 `ts_recent` 更新时，相应地，`ts_recent_stamp` 也会更新为内核当前的时间值。这样能够帮助内核知道 `ts_recent` 是什么时候最后更新的，从而进行时间相关的验证和计算。
    int	ts_recent_stamp;/* Time we stored ts_recent (for aging) */
    // 存储的是接收到的最新时间戳值。这值是对方在其发送的 TCP 包的时间戳选项（TSval字段）中提供的值。
    // PAWS 通过检查接收的时间戳值是否小于 `ts_recent` 来防止因 TCP 序列号回绕（序列号重新开始）引起的包混乱
    // 当一个新的 TCP 包被接收并且其中的时间戳值大于当前的 `ts_recent` 时，这个字段就会被更新，并且 `ts_recent_stamp` 也会相应更新
    u32	ts_recent;	/* Time stamp to echo next		*/
    // 时间戳值（Timestamp Value, TSval）：发送方获取本地时钟的当前值填入TSval
    u32	rcv_tsval;	/* Time stamp value             	*/
    // 回送时间戳回显值（Timestamp Echo Reply field, TSecr）：接收方将其上次接收到的数据包中的TSval值填入TSecr并返回给发送方
    u32	rcv_tsecr;	/* Time stamp echo reply        	*/
    // `saw_tstamp` 是一个标志位，表示该连接是否启用了 TCP 时间戳选项。
    // 当一个 TCP 包被接收并且其中包含时间戳选项时，这个标志位就会被设置为1。根据这个标志位，内核可以决定是否需要解析和使用其他时间戳相关的字段。
    // 如果 `saw_tstamp` 是1，表示时间戳功能已经确认，可以信赖这些时间戳数据来进行 RTT 计算和 PAWS 保护
    u16 	saw_tstamp : 1,	/* Saw TIMESTAMP on last packet		*/
    // 一个标志，表示时间戳选项是否已协商通过
        tstamp_ok : 1,	/* TIMESTAMP seen on SYN packet		*/
        dsack : 1,	/* D-SACK is scheduled			*/
        // 一个标志，表示窗口扩大选项是否已协商通过
        wscale_ok : 1,	/* Wscale seen on SYN packet		*/
        // 一个标志，表示选择性确认（Selective ACK）的支持情况。它值为3是为了确保多次协商的结果一致。
        sack_ok : 3,	/* SACK seen on SYN packet		*/
        smc_ok : 1,	/* SMC seen on SYN packet		*/
        // 存储发送方向的窗口扩大因子（scale factor）
        snd_wscale : 4,	/* Window scaling received from sender	*/
        // 存储接收方向的窗口扩大因子（scale factor）
        rcv_wscale : 4;	/* Window scaling to send to receiver	*/
    u8	saw_unknown:1,	/* Received unknown option		*/
        unused:7;
    // 用于统计选项 SACK（Selective Acknowledgment）的数量
    u8	num_sacks;	/* Number of SACK blocks		*/
    // 用户设置的最大报文段大小（MSS, Maximum Segment Size）
    u16	user_mss;	/* mss requested by user in ioctl	*/
    // 代表协商过后使用的最大报文段大小（MSS, Maximum Segment Size）
    u16	mss_clamp;	/* Maximal mss, negotiated at connection setup */
};

// linux-5.10.10/include/linux/tcp.h
struct tcp_timewait_sock {
    // 基类，包含通用的 TIME-WAIT 状态信息，如源、目标地址等。
    struct inet_timewait_sock tw_sk;
    // 下一个期待接收的序列号。辅助确保重传数据包可以被正确识别和处理。
#define tw_rcv_nxt tw_sk.__tw_common.skc_tw_rcv_nxt
    // 下一个要发送的序列号。在 TIME-WAIT 状态期间，这个字段通常不会改变，但仍然需要保留它以应对潜在的重传和处理。
#define tw_snd_nxt tw_sk.__tw_common.skc_tw_snd_nxt
    // 接收窗口大小
    u32			  tw_rcv_wnd;
    // 时间戳偏移量，用于防止 TIME-WAIT 重用问题，即在新的连接中避免时间戳冲突。
    u32			  tw_ts_offset;
    // 存储最近一次接收到的 TCP 时间戳值。该值用于 PAWS 机制，确保 TIME-WAIT 期间的时间戳一致。
    u32			  tw_ts_recent;

    /* The time we sent the last out-of-window ACK: */
    u32			  tw_last_oow_ack_time;

    // 记录最近一次更新 `tw_ts_recent` 的实际时间（通常是系统时间或 jiffies）。这对于时间相关的验证非常重要。
    int			  tw_ts_recent_stamp;
    u32			  tw_tx_delay;
#ifdef CONFIG_TCP_MD5SIG
    struct tcp_md5sig_key	  *tw_md5_key;
#endif
};
```

三次握手时会协商TCP选项，下面是开启和关闭`net.ipv4.tcp_timestamps`时握手的抓包对比：

![tcp头选项-timestamp对比](/images/2024-07-16-tcp-option-timestamp.png)

## 8. 小结

对`TIME_WAIT`状态的连接收到同四元组的SYN的表现做了实验分析。踩了一些坑，还有好几个问题待定分析。

## 9. 参考

1、[连接处于 TIME_WAIT 状态，这时收到了 syn 握手包](https://articles.zsxq.com/id_37l6pw1mtb0g.html)

2、[4.11 在 TIME_WAIT 状态的 TCP 连接，收到 SYN 后会发生什么？](https://www.xiaolincoding.com/network/3_tcp/time_wait_recv_syn.html)

3、[K8S最佳实践-网络性能调优](https://imroc.cc/kubernetes/best-practices/performance-optimization/network)

4、[tcp_tw_reuse 为什么默认是关闭的？](https://www.xiaolincoding.com/network/3_tcp/tcp_tw_reuse_close.html)

5、[4.9 已建立连接的TCP，收到SYN会发生什么？](https://www.xiaolincoding.com/network/3_tcp/challenge_ack.html)

6、[SYN 报文什么时候情况下会被丢弃？](https://xiaolincoding.com/network/3_tcp/syn_drop.html)

7、[深入理解Linux端口重用这一特性](https://mp.weixin.qq.com/s/SYCUMvzktgeGbyAfRdqhmg)

8、[TCP Analysis Flags 之 TCP Port numbers reused](https://mp.weixin.qq.com/s/rP65saOCuFFEZQBtJA5H-w)

9、GPT
