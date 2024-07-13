---
layout: post
title: 网络实验 -- TIME_WAIT状态的连接收到SYN是什么表现
categories: 网络
tags: TCP 网络
---

* content
{:toc}

TIME_WAIT状态的连接收到SYN是什么表现



## 1. 背景

星球实验：[连接处于 TIME_WAIT 状态，这时收到了 syn 握手包](https://articles.zsxq.com/id_37l6pw1mtb0g.html)，并参考[4.11 在 TIME_WAIT 状态的 TCP 连接，收到 SYN 后会发生什么？](https://www.xiaolincoding.com/network/3_tcp/time_wait_recv_syn.html)

*说明：本博客作为个人学习实践笔记，可供参考但非系统教程，可能存在错误或遗漏，欢迎指正。若需系统学习，建议参考原链接。*

## 2. 问题描述

一个连接如果 Server 主动断开，那么这个连接在Server 上会进入 `TIME_WAIT`

这个时候如果客户端再次用原来的四元组发起连接请求。首先这个连接和已经断开但处于`TIME_WAIT`的连接是重复的，这个时候Server该怎么处理这个握手包呢？

假设服务端监听端口为`8888`，客户端请求端口为`12345`，示意图如下：

![示意图](/images/2024-07-13-time-wait-rcv-syn.png)

## 3. 构造复现场景

### 3.1. 构造方式

1、服务端：192.168.1.150，开不同终端分别进行监听、开启抓包、tcpstates观测

代码：accept连接后就close，[github](https://github.com/xiaodongQ/prog-playground/blob/main/network/tcp_timewait_rcv_syn/server.cpp)

```sh
# 终端1
[root@xdlinux ➜ ~ ]$ tcpdump -i any port 8888 -nn -w server150_8888.cap -v

# 终端2
[root@xdlinux ➜ tools ]$ ./tcpstates -L 8888
```

2、客户端：192.168.1.2，开启抓包，并指定端口请求 `nc 192.168.1.150 8888 -p 12345`，在60s内请求2次

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

2、结论：篇头场景描述的，服务端socket处于TIME_WAIT时，客户端重用12345端口是可以连接的

## 4. 另一种情况

为什么有的文章或书籍里会说上述场景客户端是无法连接的，参考文章里给了说明：

针对这个问题，**关键是要看 SYN 的`序列号和时间戳`是否合法**，因为处于 `TIME_WAIT` 状态的连接收到 SYN 后，会判断 SYN 的`序列号和时间戳`是否合法，然后根据判断结果的不同做不同的处理。

* 合法 SYN：客户端的 SYN 的「序列号」比服务端「期望下一个收到的序列号」要大，并且 SYN 的「时间戳」比服务端「最后收到的报文的时间戳」要大。
* 非法 SYN：客户端的 SYN 的「序列号」比服务端「期望下一个收到的序列号」要小，或者 SYN 的「时间戳」比服务端「最后收到的报文的时间戳」要小。

上面 SYN 合法判断是基于双方都开启了 TCP 时间戳机制（`net.ipv4.tcp_timestamps`）的场景，如果双方都没有开启 TCP 时间戳机制，则 SYN 合法判断如下：

* 合法 SYN：客户端的 SYN 的「序列号」比服务端「期望下一个收到的序列号」要大。
* 非法 SYN：客户端的 SYN 的「序列号」比服务端「期望下一个收到的序列号」要小。

### 4.1. 构造思路

Server 和 Client 都关闭 `net.ipv4.tcp_timestamps`，并构造下次请求的seq比上次的小（需要时间足够长等seq达到最大后重新计数）

服务端timewait时回rst场景，过程解释：

![服务端timewait时回rst场景](/images/2024-07-13-timewait-rst-case.png)

## 5. `TIME_WAIT`影响说明

1、TIME_WAIT 过多对客户端的影响(大多场景)：

端口不够、搜索可用端口导致CPU 飙高、QPS 500 上限等，如果设置好 tw_bucket/reuse 可以解决这些问题

2、TIME_WAIT 过多对Server端的影响(也有Server主动断开的场景)：

客户端 syn需要两次（对应上面SYN非法回RST的场景）、syn 被reset等，主要是导致连接握手异常

## 6. 参考

1、[连接处于 TIME_WAIT 状态，这时收到了 syn 握手包](https://articles.zsxq.com/id_37l6pw1mtb0g.html)

2、[4.11 在 TIME_WAIT 状态的 TCP 连接，收到 SYN 后会发生什么？](https://www.xiaolincoding.com/network/3_tcp/time_wait_recv_syn.html)

3、GPT
