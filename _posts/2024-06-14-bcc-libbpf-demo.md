---
layout: post
title: eBPF学习实践系列（三） -- bcc tools网络工具集
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

各种性能工具是为了能应用到实际中提升定位问题的效率，而工具已经有这么多了，我们该选用哪些呢？对于Linux下初步的性能问题定位，先说下大佬们总结的最佳实践。

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
# man bcc-tcptop
NAME
       tcptop - Summarize TCP send/recv throughput by host. Top for TCP.

SYNOPSIS
       tcptop [-h] [-C] [-S] [-p PID] [--cgroupmap MAPPATH]
                 [--mntnsmap MAPPATH] [interval] [count]

DESCRIPTION
       This is top for TCP sessions.

       This summarizes TCP send/receive Kbytes by host, and prints a summary that refreshes, along other system-wide metrics.

       This uses dynamic tracing of kernel TCP send/receive functions, and will need to be updated to match kernel changes.
```

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

对网络负载的特征和流量计算很有帮助，可以识别当前有哪些连接、连接上有多少数据传输

```sh
# man bcc-tcplife
DESCRIPTION
       This tool traces TCP sessions that open and close while tracing, and prints a line of output to summarize each one. This includes the IP addresses,
       ports, duration, and throughput for the session. This is useful for workload characterisation and flow accounting: identifying what connections are
       happening, with the bytes transferred.

       This  tool  works using the sock:inet_sock_set_state tracepoint if it exists, added to Linux 4.16, and switches to using kernel dynamic tracing for
       older kernels. Only TCP state changes are traced, so it is expected that the overhead of this tool is much lower than typical send/receive tracing.
```

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

`man bcc-tcptracer`部分内容：

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

跟踪主动发起(通过`connect()`)连接的TCP，所有尝试`connect`的连接都会跟踪，即使是最终失败的。注意：`accept()`是被动连接，不在此追踪范围(可通过`tcpaccept`追踪)。

`man bcc-tcpconnect`部分内容：

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

示例：linux机器(192.168.1.150)上`python -m http.server`起`8000`端口服务。ssh到linux机器，并`curl 192.168.1.150:8000`

```sh
[root@anonymous ➜ /usr/share/bcc/tools ]$ ./tcpaccept
PID     COMM         IP RADDR            RPORT LADDR            LPORT
1227    sshd         4  192.168.1.2      63276 192.168.1.150    22   
5110    python       4  192.168.1.150    57004 192.168.1.150    8000
```

### 3.7. `tcpconnlat`：跟踪TCP主动连接的延迟

TCP连接延迟是建立连接所需的时间：从发出`SYN`到向对端发应答包(即三次握手时收到`SYN+ACK`后的`ACK`应答)的时间。

针对的是内核TCP/IP处理和网络往返时间，而不是应用程序运行时。

所有连接尝试都会追踪，即使最后是失败的(应答`RST`)

```sh
# man bcc-tcpconnlat
NAME
       tcpconnlat - Trace TCP active connection latency. Uses Linux eBPF/bcc.

SYNOPSIS
       tcpconnlat [-h] [-t] [-p PID] [-L] [-v] [min_ms]

DESCRIPTION
       This  tool  traces  active  TCP connections (eg, via a connect() syscall), and shows the latency (time) for the connection as measured locally: the
       time from SYN sent to the response packet.  This is a useful performance metric that typically spans kernel TCP/IP processing and the network round
       trip time (not application runtime).

       All connection attempts are traced, even if they ultimately fail (RST packet in response).

       This  tool  works  by  use of kernel dynamic tracing of TCP/IP functions, and will need updating to match any changes to these functions. This tool
       should be updated in the future to use static tracepoints, once they are available.
```

```sh
# -h
examples:
    ./tcpconnlat           # trace all TCP connect()s
    ./tcpconnlat 1         # trace connection latency slower than 1 ms
    ./tcpconnlat 0.1       # trace connection latency slower than 100 us
    ./tcpconnlat -t        # include timestamps
    ./tcpconnlat -p 181    # only trace PID 181
    ./tcpconnlat -L        # include LPORT while printing outputs
```

示例：`python -m http.server`起`8000`端口服务，(本机)`curl ip:8000`请求；

并发起一个不存在端口的请求，`curl ip:12345`

```sh
# -L 同时展示本端端口，默认不会展示
# 追踪的是主动发起连接的记录
[root@anonymous ➜ /usr/share/bcc/tools ]$ ./tcpconnlat -L
PID    COMM         IP SADDR            LPORT  DADDR            DPORT LAT(ms)
12326  curl         4  192.168.1.150    57406  192.168.1.150    8000  0.09
12331  curl         4  192.168.1.150    51656  192.168.1.150    12345 0.08
```

### 3.8. `tcpretrans`：重传的TCP连接跟踪

动态追踪内核中的 `tcp_retransmit_skb()` 和 `tcp_send_loss_probe()`函数 (可能更新以匹配不同内核版本)

```sh
# man bcc-tcpretrans
DESCRIPTION
       This  traces  TCP retransmits, showing address, port, and TCP state information, and sometimes the PID (although usually not, since retransmits are
       usually sent by the kernel on timeouts). To keep overhead very low, only the TCP retransmit functions are traced. This does not trace every  packet
       (like  tcpdump(8)  or  a  packet sniffer). Optionally, it can count retransmits over a user signalled interval to spot potentially dropping network
       paths the flows are traversing.

       This uses dynamic tracing of the kernel tcp_retransmit_skb() and tcp_send_loss_probe() functions, and will need  to  be  updated  to  match  kernel
       changes to these functions.
```

可以查看内核符号中是否匹配：

```sh
[root@anonymous ➜ /home ]$ grep -wE "tcp_retransmit_skb|tcp_send_loss_probe" /proc/kallsyms
ffffffff99075720 T tcp_send_loss_probe
ffffffff99075910 T tcp_retransmit_skb
```

用法：

```sh
[root@anonymous ➜ /usr/share/bcc/tools ]$ ./tcpretrans -h
usage: tcpretrans [-h] [-l] [-c]

Trace TCP retransmits

optional arguments:
  -h, --help       show this help message and exit
  -l, --lossprobe  include tail loss probe attempts
  -c, --count      count occurred retransmits per flow

examples:
    ./tcpretrans           # trace TCP retransmits
    # TLP：tail loss probe，TCP发送端用于处理尾包丢失场景的算法
    # 目的是使用快速重传取代RTO（重传超时）超时重传来处理尾包丢失，以减少因尾包丢失带来的延迟，提高TCP性能。
    ./tcpretrans -l        # include TLP attempts
```

示例：通过构造丢包场景来进行实验

#### 3.8.1. tc模拟

1、先安装`tc`：`yum install iproute-tc`，并构造丢包(实验环境网卡为`enp4s0`)

查看qdisc设置：`tc qdisc show dev enp4s0`

2、添加队列规则：`tc qdisc add dev enp4s0 root netem loss 10%`

报错了："Error: Specified qdisc not found."

查看没有`sch_netem`模块，`modprobe`加载，报错

```sh
[root@anonymous ➜ /root ]$ lsmod | grep netem
[root@anonymous ➜ /root ]$ modprobe sch_netem
modprobe: FATAL: Module sch_netem not found in directory /lib/modules/4.18.0-348.el8.x86_64
[root@anonymous ➜ /root ]$
```

安装`kernel-modules-extra`(提示`/boot`空间不够了)，而后再`modprobe sch_netem`

解决方式：[RTNETLINK answers: No such file or directory¶](https://tcconfig.readthedocs.io/en/latest/pages/troubleshooting.html)

~~netem模块没加载，可能要修改内核，暂放弃。~~ 也可用下节的iptables模拟丢包。

`/boot`空间不够的问题，尝试扩容失败了，重装后`tc`使用正常。(踩坑过程：[记一次失败的/boot分区扩容](https://xiaodongq.github.io/2024/06/12/record-failed-expend-space/))

#### 3.8.2. iptables模拟

1. Linux服务端：`iptables -A INPUT -m statistic --mode random --probability 0.2 -j DROP`
2. Linux服务端：`python -m http.server`起`8000`端口服务，并开启`./tcpretrans`
3. (本机)`wget 192.168.1.150:8000/tmpstrace`请求 (tmpstrace是一个2M左右的文件)
4. `iptables -F`恢复环境(原来就没有防火墙规则，最好单条规则删除)

出现了重传，结果如下：

```sh
[root@anonymous ➜ /usr/share/bcc/tools ]$ ./tcpretrans
Tracing retransmits ... Hit Ctrl-C to end
TIME     PID    IP LADDR:LPORT          T> RADDR:RPORT          STATE
16:48:23 0      4  192.168.1.150:57870  R> 192.168.1.150:8000   ESTABLISHED
16:48:23 5110   4  192.168.1.150:8000   R> 192.168.1.150:57870  ESTABLISHED
16:48:23 0      4  192.168.1.150:8000   R> 192.168.1.150:57870  FIN_WAIT1
16:48:23 0      4  192.168.1.150:8000   R> 192.168.1.150:57870  FIN_WAIT1
16:48:23 0      4  192.168.1.150:8000   R> 192.168.1.150:57870  FIN_WAIT1
16:48:23 0      4  192.168.1.150:8000   R> 192.168.1.150:57870  FIN_WAIT1
16:48:23 0      4  192.168.1.150:8000   R> 192.168.1.150:57870  FIN_WAIT1
16:48:23 0      4  192.168.1.150:8000   R> 192.168.1.150:57870  FIN_WAIT1
16:48:23 0      4  192.168.1.150:8000   R> 192.168.1.150:57870  FIN_WAIT1
16:48:24 0      4  192.168.1.150:8000   R> 192.168.1.150:57870  FIN_WAIT1
16:48:24 0      4  192.168.1.150:8000   R> 192.168.1.150:57870  FIN_WAIT1
16:48:24 0      4  192.168.1.150:8000   R> 192.168.1.150:57870  FIN_WAIT1
16:48:24 0      4  192.168.1.150:8000   R> 192.168.1.150:57870  FIN_WAIT1
16:48:24 0      4  192.168.1.150:8000   R> 192.168.1.150:57870  FIN_WAIT1
16:48:24 0      4  192.168.1.150:57870  R> 192.168.1.150:8000   LAST_ACK
```

每次TCP重传数据包时，`tcpretrans`会打印一行记录，包含源地址和目的地址，以及当时该 TCP 连接所处的内核状态。TCP 重传会导致延迟和吞吐量方面的问题。

重传通常是网络健康状况不佳的标志，这个工具对它们的调查很有用。与使用tcpdump不同，该工具的开销非常低，因为它只跟踪重传函数。

`T`列：内核可能发送了一个TLP，但在某些情况下它可能最终没有被发送。

* `L>`: 表示数据包是从本地地址(LADDR)发送到远程地址(RADDR)的。
* `R>`: 表示数据包是从远程地址(RADDR)发送到本地地址(LADDR)的。

通过前面`tcptracer`的追踪，可以看到`curl`时是服务端先关闭连接(8000)，`wget`可以再跟踪下

```sh
[root@anonymous ➜ /usr/share/bcc/tools ]$ ./tcptracer  -v        
Tracing TCP established connections. Ctrl-C to end.
TYPE         PID    COMM             IP SADDR            DADDR            SPORT  DPORT  NETNS   
connect      9418   curl             4  192.168.1.150    192.168.1.150    56426  8000   4026531992
accept       5110   python           4  192.168.1.150    192.168.1.150    8000   56426  4026531992
close        5110   python           4  192.168.1.150    192.168.1.150    8000   56426  4026531992
close        9418   curl             4  192.168.1.150    192.168.1.150    56426  8000   4026531992
```

### 3.9. `tcpsubnet`：统计发送到特定子网的TCP流量

`tcpsubnet`工具汇总并合计了本地主机发往子网的 IPv4 TCP 流量，并按固定间隔显示输出。该工具使用 eBPF 功能来收集并总结数据，以减少开销。

```sh
examples:
    ./tcpsubnet                 # Trace TCP sent to the default subnets:
                                # 127.0.0.1/32,10.0.0.0/8,172.16.0.0/12,
                                # 192.168.0.0/16,0.0.0.0/0
    ./tcpsubnet -f K            # Trace TCP sent to the default subnets
                                # aggregated in KBytes.
    ./tcpsubnet 10.80.0.0/24    # Trace TCP sent to 10.80.0.0/24 only
    ./tcpsubnet -J              # Format the output in JSON.
```

示例：

```sh
[root@desktop-mme7h3a ➜ /usr/share/bcc/tools ]$ ./tcpsubnet  
Tracing... Output every 1 secs. Hit Ctrl-C to end
[06/13/24 14:33:36]
192.168.0.0/16           224
[06/13/24 14:33:37]
192.168.0.0/16           200
[06/13/24 14:33:38]
192.168.0.0/16           200
[06/13/24 14:33:39]
192.168.0.0/16           224
```

### 3.10. `tcpdrop`：被内核丢弃的TCP数据包跟踪

每次内核丢弃 TCP 数据包和段时，`tcpdrop` 都会显示连接的详情，包括导致软件包丢弃的内核堆栈追踪。

示例：
`python -m http.server`起`8000`端口服务，用`ab`工具(`yum install httpd-tools`)压测

`ab -n 100 -c 6 http://192.168.1.150:8000/`，6并发请求100次，注意url后面的`/`不能少

监测结果：

```sh
[root@desktop-mme7h3a ➜ /usr/share/bcc/tools ]$ ./tcpdrop                                
TIME     PID    IP SADDR:SPORT          > DADDR:DPORT          STATE (FLAGS)
15:11:36 9433   4  192.168.1.150:8000   > 192.168.1.150:33166  CLOSE (ACK)
	b'tcp_drop+0x1'
	b'tcp_rcv_state_process+0xb2'
	b'tcp_v4_do_rcv+0xb4'
	b'__release_sock+0x7c'
	b'__tcp_close+0x180'
	b'tcp_close+0x1f'
	b'inet_release+0x42'
	b'__sock_release+0x3d'
	b'sock_close+0x11'
	b'__fput+0xbe'
	b'task_work_run+0x8a'
	b'exit_to_usermode_loop+0xeb'
	b'do_syscall_64+0x198'
	b'entry_SYSCALL_64_after_hwframe+0x65'

15:11:36 9433   4  192.168.1.150:8000   > 192.168.1.150:33168  CLOSE (ACK)
	b'tcp_drop+0x1'
	b'tcp_rcv_state_process+0xb2'
	b'tcp_v4_do_rcv+0xb4'
	b'__release_sock+0x7c'
	b'__tcp_close+0x180'
	b'tcp_close+0x1f'
	b'inet_release+0x42'
	b'__sock_release+0x3d'
	b'sock_close+0x11'
	b'__fput+0xbe'
	b'task_work_run+0x8a'
	b'exit_to_usermode_loop+0xeb'
	b'do_syscall_64+0x198'
	b'entry_SYSCALL_64_after_hwframe+0x65'
```

`STATE (FLAGS)`：TCP 连接的状态和相关的 TCP 标志：

* `CLOSE_WAIT (FIN|ACK)`
    * `CLOSE_WAIT` 表示本地应用程序已经接收了关闭连接的 FIN 包，但还没有发送它自己的 FIN 包来关闭连接。
    * `FIN|ACK`标志 表示这个数据包是一个带有 FIN 和 ACK 标志的 TCP 段。这通常是在关闭连接的过程中发送的。
* `CLOSE (ACK)`
    * `CLOSE`状态 表示连接正在关闭，但还没有完全关闭。
    * `ACK`标志 表示这个数据包是一个TCP确认包，用于确认之前接收到的数据包。

### 3.11. `tcpstates`：显示TCP状态更改信息

跟踪TCP状态变化，并打印每个状态的持续时间。

每次连接改变其状态时，`tcpstates`都会显示一个新行，其中包含更新的连接详情。

```sh
usage: tcpstates [-h] [-T] [-t] [-w] [-s] [-L LOCALPORT] [-D REMOTEPORT] [-Y]

Trace TCP session state changes and durations

examples:
    ./tcpstates           # trace all TCP state changes
    ./tcpstates -t        # include timestamp column
    ./tcpstates -T        # include time column (HH:MM:SS)
    ./tcpstates -w        # wider columns (fit IPv6)
    ./tcpstates -stT      # csv output, with times & timestamps
    ./tcpstates -Y        # log events to the systemd journal
    ./tcpstates -L 80     # only trace local port 80
    ./tcpstates -L 80,81  # only trace local ports 80 and 81
    ./tcpstates -D 80     # only trace remote port 80
```

示例：`python -m http.server`起`8000`端口服务，(本机)`curl ip:8000`请求，跟踪8000端口

```sh
[root@desktop-mme7h3a ➜ /usr/share/bcc/tools ]$ ./tcpstates -L 8000
SKADDR           C-PID C-COMM     LADDR           LPORT RADDR           RPORT OLDSTATE    -> NEWSTATE    MS
ffff9e64e0769380 8531  curl       0.0.0.0         8000  0.0.0.0         0     LISTEN      -> SYN_RECV    0.000
ffff9e64e0769380 8531  curl       192.168.1.150   8000  192.168.1.150   32894 SYN_RECV    -> ESTABLISHED 0.004
ffff9e64e0769380 8463  python3    192.168.1.150   8000  192.168.1.150   32894 ESTABLISHED -> FIN_WAIT1   1.303
ffff9e64e0769380 8463  python3    192.168.1.150   8000  192.168.1.150   32894 FIN_WAIT1   -> FIN_WAIT1   0.008
ffff9e64e0769380 8531  curl       192.168.1.150   8000  192.168.1.150   32894 FIN_WAIT1   -> CLOSING     0.010
ffff9e64e0769380 8531  curl       192.168.1.150   8000  192.168.1.150   32894 CLOSING     -> CLOSE       0.012
```

### 3.12. `tcprtt`

`tcprtt`可以监控TCP连接的往返时间，从而评估网络质量，帮助用户找出可能的问题所在。可以打印直方图形式的时间分布。

```sh
usage: tcprtt [-h] [-i INTERVAL] [-d DURATION] [-T] [-m] [-p LPORT] [-P RPORT]
              [-a LADDR] [-A RADDR] [-b] [-B] [-D]

Summarize TCP RTT as a histogram

examples:
    ./tcprtt            # summarize TCP RTT
    ./tcprtt -i 1 -d 10 # print 1 second summaries, 10 times
    ./tcprtt -m -T      # summarize in millisecond, and timestamps
    ./tcprtt -p         # filter for local port
       -p LPORT, --lport LPORT
    ./tcprtt -P         # filter for remote port
       -P RPORT, --rport RPORT
    ./tcprtt -a         # filter for local address
       -a LADDR, --laddr LADDR
    ./tcprtt -A         # filter for remote address
       -A RADDR, --raddr RADDR
    ./tcprtt -b         # show sockets histogram by local address
       -b, --byladdr
    ./tcprtt -B         # show sockets histogram by remote address
       -B, --byraddr
    ./tcprtt -D         # show debug bpf text
       -D, --debug
```

示例1：总体RTT分布

```sh
[root@desktop-mme7h3a ➜ /usr/share/bcc/tools ]$ ./tcprtt -i 1 -d 10 -m
Tracing TCP RTT... Hit Ctrl-C to end.

     msecs               : count     distribution
         0 -> 1          : 1        |****************************************|

     msecs               : count     distribution
         0 -> 1          : 0        |                                        |
         2 -> 3          : 0        |                                        |
         4 -> 7          : 1        |****************************************|
         8 -> 15         : 0        |                                        |
        16 -> 31         : 1        |****************************************|
```

示例2：按远端IP展示

```sh
[root@desktop-mme7h3a ➜ /usr/share/bcc/tools ]$ ./tcprtt -i 3 -m --lport 8000 --byraddr
Tracing TCP RTT... Hit Ctrl-C to end.

Remote Address:  = b'192.168.1.150'
     msecs               : count     distribution
         0 -> 1          : 3        |****************************************|

Remote Address:  = b'192.168.1.150'
     msecs               : count     distribution
         0 -> 1          : 300      |****************************************|

Remote Address:  = b'192.168.1.150'
     msecs               : count     distribution
         0 -> 1          : 3        |****************************************|

Remote Address:  = b'192.168.1.150'
     msecs               : count     distribution
         0 -> 1          : 3        |****************************************|
```

## 4. 小结

学习bcc tools工具集中网络相关的部分工具，并在环境中实践工具效果。

## 5. 参考

1、[【BPF入门系列-1】eBPF 技术简介](https://www.ebpf.top/post/ebpf_intro/)

2、[TCP 连接排故:使用 BPF BCC工具包进行网络跟踪](https://mp.weixin.qq.com/s/HMbAkc2g9vBZRZ_1AnL1Tw)

3、[使用 BPF 编译器集合进行网络追踪](https://docs.redhat.com/zh_hans/documentation/red_hat_enterprise_linux/9/html-single/configuring_and_managing_networking/index#network-tracing-using-the-bpf-compiler-collection_configuring-and-managing-networking)