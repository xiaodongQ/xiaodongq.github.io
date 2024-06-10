---
layout: post
title: eBPF学习实践系列（二） -- bcc tools网络工具集
categories: eBPF
tags: Linux eBPF
---

* content
{:toc}

bcc tools工具集中网络部分说明和使用。



## 1. 背景

上篇([eBPF学习实践系列（一） -- 初识eBPF](https://xiaodongq.github.io/2024/06/06/ebpf_learn/#22-ebpf%E5%86%85%E6%A0%B8%E7%89%88%E6%9C%AC%E6%94%AF%E6%8C%81%E8%AF%B4%E6%98%8E))中提到性能分析大师`Brendan Gregg`等编写了**诸多的 BCC 或 BPFTrace 的工具集**可以拿来直接使用，可以满足很多我们日常问题分析和排查，本篇先学习下网络相关的几个工具。

![bcc tools 2019](/images/bcc-tools-2019.png)  

## 2. Linux性能分析60s

工具是为了能应用到实际中提升定位问题的效率，而工具已经有这么多了，我们该选用哪些呢？对于Linux下初步的性能问题定位，先说下大佬们总结的最佳实践。

### 2.1. 60s系列Linux命令版本

60s内，用下述的10个命令全面了解系统资源的使用情况

```sh
uptime
dmesg | tail
vmstat 1
mpstat -P ALL 1
pidstat 1
iostat -xz 1
free -m
sar -n DEV 1
sar -n TCP,ETCP 1
top
```

具体可参考：[Linux Performance Analysis in 60,000 Milliseconds](https://netflixtechblog.com/linux-performance-analysis-in-60-000-milliseconds-accc10403c55)

1. `uptime` 快速查看平均负载
2. `dmesg | tail` 查看最近10个系统日志，是否有可能导致性能问题的错误(如OOM、TCP丢包)
    * 不要忽略这个步骤，`dmesg`总是值得检查的！
3. `vmstat 1` 系统状态(CPU使用率，内存使用，虚拟内存交换情况,IO读写情况等)
4. `mpstat -P ALL 1` 显示每个CPU的占用情况
5. `pidstat 1` 进程的CPU占用率
6. `iostat -xz 1` 磁盘IO情况
7. `free -m` 系统内存使用情况
8. `sar -n DEV 1` 网络设备吞吐率
9. `sar -n TCP,ETCP 1` 查看TCP连接状态
10. `top` 相对全面的各系统负载情况

### 2.2. 60s系列`BPF`版本

![bcc tools 60s](/images/ebpf_60s-bcctools2017.png)  
[参考](https://www.ebpf.top/post/ebpf_intro/)

## 3. bcc tools网络相关工具集

通过开头的`bcc`工具集示意图，网络相关工具如下：

* `sofdsnoop`
* `tcptop`
* `tcplife`
* `tcptracer`
* `tcpconnect`
* `tcpaccept`
* `tcpconnlat`
* `tcpretrans`
* `tcpsubnet`
* `tcpdrop`
* `tcpstates`
* 此外还有 `tcprtt`、`tcpsynbl`、`solisten`、`netqtop`等，以及中断统计的`softirqs`

下面看一下各自的功能和基本用法。

可以通过`-h` 或者 `man`查看说明，如 `./tcptop -h`、`man bcc-tcptop`/`man tcptop`。

### 3.1. `sofdsnoop`：跟踪通过socket传递的文件描述符

```sh
[root@anonymous ➜ /usr/share/bcc/tools ]$ ./sofdsnoop -h
usage: sofdsnoop [-h] [-T] [-p PID] [-t TID] [-n NAME] [-d DURATION]

Trace file descriptors passed via socket

examples:
    ./sofdsnoop           # trace passed file descriptors
    ./sofdsnoop -T        # include timestamps
    ./sofdsnoop -p 181    # only trace PID 181
    ./sofdsnoop -t 123    # only trace TID 123
    ./sofdsnoop -d 10     # trace for 10 seconds only
    ./sofdsnoop -n main   # only print process names containing "main"
```

执行结果示例如下：

```sh
[root@anonymous ➜ /usr/share/bcc/tools ]$ ./sofdsnoop 
ACTION TID    COMM             SOCKET                    FD    NAME
SEND   1199   systemd-logind   12:socket:[20935]         25    N/A
SEND   1122   dbus-daemon      6:N/A                     21    N/A
SEND   6701   sshd             12:socket:[65823]         10    /dev/ptmx
SEND   6701   sshd             12:socket:[65823]         13    N/A
```

另外用`python -m http.server`起服务，`curl ip:8000`请求，但是没抓到fd，为什么？(**TODO**)

### 3.2. `tcptop`：统计TCP发送/接收的吞吐量

```sh
[root@anonymous ➜ /usr/share/bcc/tools ]$ ./tcptop -h
usage: tcptop [-h] [-C] [-S] [-p PID] [--cgroupmap CGROUPMAP]
              [--mntnsmap MNTNSMAP]
              [interval] [count]

Summarize TCP send/recv throughput by host

positional arguments:
  interval              output interval, in seconds (default 1)
  count                 number of outputs

examples:
    ./tcptop           # trace TCP send/recv by host
    ./tcptop -C        # don't clear the screen
    ./tcptop -p 181    # only trace PID 181
    ./tcptop --cgroupmap mappath  # only trace cgroups in this BPF map
    ./tcptop --mntnsmap mappath   # only trace mount namespaces in the map
```

示例：`python -m http.server`起`8000`端口服务，(本机)`curl ip:8000`请求

```sh
[root@anonymous ➜ /usr/share/bcc/tools ]$ ./tcptop -C 5
Tracing... Output every 5 secs. Hit Ctrl-C to end

14:11:52 loadavg: 0.13 0.05 0.01 2/319 7868

PID    COMM         LADDR                 RADDR                  RX_KB  TX_KB
4891   sshd         192.168.1.150:22      192.168.1.2:61572          0      0

14:11:57 loadavg: 0.12 0.04 0.01 2/319 7873

PID    COMM         LADDR                 RADDR                  RX_KB  TX_KB
6704   sshd         192.168.1.150:22      192.168.1.2:62262          0      2
7869   7869         192.168.1.150:55890   192.168.1.150:8000         2      0
5110   python       192.168.1.150:8000    192.168.1.150:55890        0      2
4891   sshd         192.168.1.150:22      192.168.1.2:61572          0      0
6393   sshd         192.168.1.150:22      192.168.1.2:61936          0      0
5059   sshd         192.168.1.150:22      192.168.1.2:61727          0      0
```

### 3.3. `tcplife`：TCP会话跟踪

```sh
[root@anonymous ➜ /usr/share/bcc/tools ]$ ./tcplife -h
usage: tcplife [-h] [-T] [-t] [-w] [-s] [-p PID] [-L LOCALPORT]
               [-D REMOTEPORT]

Trace the lifespan of TCP sessions and summarize

examples:
    ./tcplife           # trace all TCP connect()s
    ./tcplife -T        # include time column (HH:MM:SS)
    ./tcplife -w        # wider columns (fit IPv6)
    ./tcplife -stT      # csv output, with times & timestamps
    ./tcplife -p 181    # only trace PID 181
    ./tcplife -L 80     # only trace local port 80
    ./tcplife -L 80,81  # only trace local ports 80 and 81
    ./tcplife -D 80     # only trace remote port 80
```

示例：`python -m http.server`起`8000`端口服务，(本机)`curl ip:8000`请求

```sh
[root@anonymous ➜ /usr/share/bcc/tools ]$ ./tcplife -T                 
TIME     PID   COMM       LADDR           LPORT RADDR           RPORT TX_KB RX_KB MS
14:33:27 8981  curl       192.168.1.150   8000  192.168.1.150   56164     2     0 0.68
14:33:27 8981  curl       192.168.1.150   56164 192.168.1.150   8000      0     2 0.70
```

另外试了下`-L 8000`和`-D 8000`，单独都能抓到；`||`条件没办法，`-L 8000 -D 8000`是`&&`的关系，没法抓到上述包

### 3.4. `tcptracer`：已建立的TCP连接跟踪

`man bcc-tcptracer`：

```sh
NAME
       tcptracer - Trace TCP established connections. Uses Linux eBPF/bcc.

SYNOPSIS
       tcptracer [-h] [-v] [-p PID] [-N NETNS] [--cgroupmap MAPPATH] [--mntnsmap MAPPATH]

DESCRIPTION
       This  tool  traces established TCP connections that open and close while tracing, and prints a line of output per connect, accept and close events.
       This includes the type of event, PID, IP addresses and ports.
```

示例：`python -m http.server`起`8000`端口服务，(本机)`curl ip:8000`请求

```sh
[root@anonymous ➜ /usr/share/bcc/tools ]$ ./tcptracer   
Tracing TCP established connections. Ctrl-C to end.
T  PID    COMM             IP SADDR            DADDR            SPORT  DPORT 
C  9102   curl             4  192.168.1.150    192.168.1.150    56260  8000  
A  5110   python           4  192.168.1.150    192.168.1.150    8000   56260 
X  5110   python           4  192.168.1.150    192.168.1.150    8000   56260 
X  9102   curl             4  192.168.1.150    192.168.1.150    56260  8000

# 5110是8000端口服务的pid
[root@anonymous ➜ /usr/share/bcc/tools ]$ ./tcptracer -t -p 5110
Tracing TCP established connections. Ctrl-C to end.
TIME(s)  T  PID    COMM             IP SADDR            DADDR            SPORT  DPORT 
0.000    A  5110   python           4  192.168.1.150    192.168.1.150    8000   56270 
0.001    X  5110   python           4  192.168.1.150    192.168.1.150    8000   56270
```

关于事件类型的解释：

* `C` 表示连接(Connect)：这通常表示一个 TCP 连接请求已经发送或接收。
* `A` 表示接受(Accept)：这通常表示服务器已经接受了一个来自客户端的连接请求，并创建了一个新的连接
* `X` 表示关闭(Close)：这表示 TCP 连接已经关闭，可能是由于正常关闭(如通过 FIN/ACK 握手)或由于某种错误导致的异常关闭。

可以用`-v`展示事件的名称(`-v    Print full lines, with long event type names and network namespace numbers.`)

```sh
[root@anonymous ➜ /usr/share/bcc/tools ]$ ./tcptracer  -v        
Tracing TCP established connections. Ctrl-C to end.
TYPE         PID    COMM             IP SADDR            DADDR            SPORT  DPORT  NETNS   
connect      9418   curl             4  192.168.1.150    192.168.1.150    56426  8000   4026531992
accept       5110   python           4  192.168.1.150    192.168.1.150    8000   56426  4026531992
close        5110   python           4  192.168.1.150    192.168.1.150    8000   56426  4026531992
close        9418   curl             4  192.168.1.150    192.168.1.150    56426  8000   4026531992
```

### 3.5. `tcpconnect`：主动的TCP连接跟踪

`man bcc-tcpconnect`部分内容：

跟踪主动发起(通过`connect()`)连接的TCP，所有尝试`connect`的连接都会跟踪，即使是最终失败的。注意：`accept()`是被动连接，不在此追踪范围(可通过`tcpaccept`追踪)。

```sh
NAME
       tcpconnect - Trace TCP active connections (connect()). Uses Linux eBPF/bcc.

SYNOPSIS
       tcpconnect [-h] [-c] [-t] [-p PID] [-P PORT] [-L] [-u UID] [-U] [--cgroupmap MAPPATH] [--mntnsmap MAPPATH] [-d]

DESCRIPTION
       This  tool  traces  active  TCP  connections  (eg, via a connect() syscall; accept() are passive connections). This can be useful for general trou-
       bleshooting to see what connections are initiated by the local server.

       All connection attempts are traced, even if they ultimately fail.

       This works by tracing the kernel tcp_v4_connect() and tcp_v6_connect() functions using dynamic tracing, and will need updating to match any changes
       to these functions.
```

一些用法(`-h`)：

```sh
examples:
    ./tcpconnect           # trace all TCP connect()s
    ./tcpconnect -t        # include timestamps
    ./tcpconnect -d        # include DNS queries associated with connects
    ./tcpconnect -p 181    # only trace PID 181
    ./tcpconnect -P 80     # only trace port 80
    # 可以同时跟踪几个端口
    ./tcpconnect -P 80,81  # only trace port 80 and 81
    ./tcpconnect -U        # include UID
    ./tcpconnect -u 1000   # only trace UID 1000
    ./tcpconnect -c        # count connects per src ip and dest ip/port
    ./tcpconnect -L        # include LPORT while printing outputs
    ./tcpconnect --cgroupmap mappath  # only trace cgroups in this BPF map
    ./tcpconnect --mntnsmap mappath   # only trace mount namespaces in the map
```

示例：`python -m http.server`起`8000`端口服务，(本机)`curl ip:8000`请求；

并发起一个不存在端口的请求，`curl ip:12345`，可以看到都追踪到了

```sh
[root@anonymous ➜ /usr/share/bcc/tools ]$ ./tcpconnect
Tracing connect ... Hit Ctrl-C to end
PID    COMM         IP SADDR            DADDR            DPORT 
10189  curl         4  192.168.1.150    192.168.1.150    12345  
10194  curl         4  192.168.1.150    192.168.1.150    8000
```

另外一个案例待定位(**TODO**)：主机1(MAC电脑，192.168.1.2) ssh到 主机2(Linux PC机，即上面的192.168.1.150)，`python -m http.server`起服务都是在Linux操作的，但是从MAC上`curl 192.168.1.150:8000`不通。

* MAC上ping 192.168.1.150 正常
* curl时，能抓到客户端发送了`SYN`，同时服务端能收到`SYN`，不过没后续应答了
* ~~Linux机器上`tcpconnect`没抓到 connect 请求(有`SYN`为什么不算connect？)~~ 混淆了，服务端就是抓不到主动connect(上面抓到只是因为在同一台机器发起的连接)
* Linux机器上，自己curl(`curl 192.168.1.150:8000`)时http应答都是正常的

### 3.6. `tcpaccept`：被动的TCP连接跟踪

```sh
NAME
       tcpaccept - Trace TCP passive connections (accept()). Uses Linux eBPF/bcc.

SYNOPSIS
       tcpaccept [-h] [-T] [-t] [-p PID] [-P PORTS] [--cgroupmap MAPPATH] [--mntnsmap MAPPATH]

DESCRIPTION
       This  tool  traces  passive  TCP  connections (eg, via an accept() syscall; connect() are active connections). This can be useful for general trou-
       bleshooting to see what new connections the local server is accepting.

       This uses dynamic tracing of the kernel inet_csk_accept() socket function (from tcp_prot.accept), and will need to  be  modified  to  match  kernel
       changes.

       This tool only traces successful TCP accept()s. Connection attempts to closed ports will not be shown (those can be traced via other functions).
```

## 4. 小结

学习bcc tools工具集中网络相关的部分工具，并在环境中实践工具效果。

## 5. 参考

1、[【BPF入门系列-1】eBPF 技术简介](https://www.ebpf.top/post/ebpf_intro/)

2、[TCP 连接排故:使用 BPF BCC工具包进行网络跟踪](https://mp.weixin.qq.com/s/HMbAkc2g9vBZRZ_1AnL1Tw)

3、[使用 BPF 编译器集合进行网络追踪](https://docs.redhat.com/zh_hans/documentation/red_hat_enterprise_linux/9/html-single/configuring_and_managing_networking/index#network-tracing-using-the-bpf-compiler-collection_configuring-and-managing-networking)