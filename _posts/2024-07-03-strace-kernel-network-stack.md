---
layout: post
title: 追踪内核网络堆栈的几种方式
categories: 网络
tags: TCP 内核
---

* content
{:toc}

介绍学习几种追踪内核网络堆栈的方式



## 1. 背景

看[知识星球](https://wx.zsxq.com/dweb2/index/group/15552551584552)文章、以及查资料时，看到几篇文章里有的基于现象去跟踪定位内核代码、有的推荐比较好的学习内核网络方法，挺有收获。看里面的方式很想自己去学习掌握一下，于是有了这篇小结和实验文章。

*说明：本博客作为个人学习实践笔记，可供参考但非系统教程，可能存在错误或遗漏，欢迎指正。若需系统学习，建议参考原链接。*

## 2. 几个输入源

1、根据现象一步步定位问题，工具技巧

值得学习的：解决问题的能力，以及涉及到的工具及技巧，包括`systemtap`、`faddr2line`、`iptables`debug日志

来自这两篇的输入：

* [关于解决问题的能力](https://wx.zsxq.com/dweb2/index/columns/15552551584552)
* [网络 IO 高级篇：一次有趣的 Docker 网络问题排查](https://heapdump.cn/article/2495315)

**现象：**

> 前段时间公司的安卓打包服务出现问题，现象是在上传 360 服务器进行加固的时候，非常大概率会卡在上传阶段，长时间重试最后失败。
> 
> 抓包看宿主机发送了一个 RST 包给远程的 360 加固服务器，再后面就是不停重试发送数据，上传卡住也就对应这个不断重试发送数据的阶段

**定位过程：**

1. 通过`systemtap`跟踪这两个函数：`tcp_v4_send_reset@net/ipv4/tcp_ipv4.c`和`tcp_send_active_reset@net/ipv4/tcp_output.c`
2. 通过`faddr2line`把堆栈中的信息还原为源码对应的行数：`faddr2line /usr/lib/debug/lib/modules/`uname -r`/vmlinux tcp_v4_rcv+0x536/0x9c0`
3. 找到位置后，通过Docker桥接模式涉及到的NAT，其基于`Netfilter`内核框架，去查看netfilter的代码，发现netfilter会将out of window 的包标记为 INVALID 状态
4. 可以通过iptables把invalid的包打印出来：`iptables -A INPUT -m conntrack --ctstate INVALID -m limit --limit 1/sec   -j LOG --log-prefix "invalid: " --log-level 7`，并可在`dmesg`中查看到
5. 得到上述结果后，分析：如果是 INVALID 状态的包，netfilter 不会对其做 IP 和端口的 NAT 转换，这样协议栈再去根据 ip + 端口去找这个包的连接时，就会找不到，这个时候就会回复一个 RST。这就跟抓包里对应起来了
6. 而后快速验证上面推测：使用`iptables` 把 invalid 包 drop 掉，不让它产生 RST
7. （通过源码知道）更加优雅的改法是修改 把内核选项 net.netfilter.nf_conntrack_tcp_be_liberal 设置为 1

2、“读源码不如读执行”

早前因为这句话，有了深入学习eBPF/perf等追踪技术的动力和更好的源码学习思路。

`ftrace`（或systemtap、ebpf）追踪函数运行序列。

比较好的实践方式：写简单demo（可借助GPT），开启追踪（借助上面工具），得到追踪结果后分析并对照源码印证

来自：[【学习笔记】三小时内速通linux发包流程](https://articles.zsxq.com/id_qc2u23ktni9f.html)

3、gdb调试linux网络源码

比较早之前在B站看到：

* [gdb 调试 Linux 内核网络源码（附视频）](https://wenfh2020.com/2021/05/19/gdb-kernel-networking/)
* [vscode + gdb 远程调试 linux 内核源码（附视频）](https://wenfh2020.com/2021/06/23/vscode-gdb-debug-linux-kernel/)

加上前段时间掘金小册看到：

* [实战使用 qemu + gdb 调试 Linux 内核以及网络配置](https://juejin.cn/book/6844733794801418253/section/7358469142175105059)

4、耗子叔的[《左耳听风》](https://time.geekbang.org/column/article/14389)专栏，里面说的去获取第一手知识、高效学习、逆人性等颇有体会，不定期重读受益良多。

不同时期的锚点相互叠加产生了足够推动动手的力。（乔布斯斯坦福演讲里说的前后看似不搭边实则隐隐联系在一起，忍不住又又又要去看一遍）

下面学习实践上述文章中涉及的工具和技巧。

## 3. 使用eBPF追踪网络堆栈

上面的链接文章里用了systemtap追踪两个网络相关跟踪点`tcp_v4_send_reset`和`tcp_send_active_reset`，怎么用eBPF跟踪呢？

这里还是用`bpftrace`，用法可参考之前的学习笔记：[eBPF学习实践系列（六） -- bpftrace学习和使用](https://xiaodongq.github.io/2024/06/28/ebpf-bpftrace-learn/)

1、先查看系统是否支持（CentOS 8.5），可看到是有这两个符号的：

```sh
[root@xdlinux ➜ ~ ]$ bpftrace -l|grep -E "tcp_v4_send_reset|tcp_send_active_reset"
kfunc:tcp_send_active_reset
kfunc:tcp_v4_send_reset
kprobe:tcp_send_active_reset
kprobe:tcp_v4_send_reset

[root@xdlinux ➜ ~ ]$ uname -r
4.18.0-348.7.1.el8_5.x86_64
```

2、由于是`kprobe`类型，无法通过tracefs查看结构信息，到对应内核版本的代码中查看函数声明

```c
// linux-4.18/net/ipv4/tcp_ipv4.c
static void tcp_v4_send_reset(const struct sock *sk, struct sk_buff *skb)
{
    ...
}

// linux-4.18/include/net/tcp.h
void tcp_send_active_reset(struct sock *sk, gfp_t priority);
```

按需查看第一个参数（arg0）的结构（若需要访问里面的内容）

```c
// linux-4.18/include/net/sock.h
struct sock {
    ...
}
```

3、bpftrace一行命令，简单跟踪是哪个进程触发了这两个kprobe

直接向服务器一个不存在的端口请求curl，可跟踪到下述reset事件

```sh
[root@xdlinux ➜ bpftrace_tcp_reset git:(main) ✗ ]$ bpftrace -e 'kprobe:tcp_v4_send_reset, kprobe:tcp_send_active_reset { printf("comm:%s, call stack:%s\n", comm, kstack()); }'
Attaching 2 probes...

comm:swapper/9, call stack:
        tcp_v4_send_reset+1
        tcp_v4_rcv+2051
        ip_protocol_deliver_rcu+44
        ip_local_deliver_finish+77
        ip_local_deliver+224
        ip_rcv+635
        __netif_receive_skb_core+2963
        netif_receive_skb_internal+61
        napi_gro_receive+186
        rtl8169_poll+667
        __napi_poll+45
        net_rx_action+595
        __softirqentry_text_start+215
        irq_exit+247
        do_IRQ+127
        ret_from_intr+0
        cpuidle_enter_state+219
        cpuidle_enter+44
        do_idle+564
        cpu_startup_entry+111
        start_secondary+411
        secondary_startup_64_no_verify+194
```

更进一步还可根据`struct sock`获取信息，比如下面获取源ip和源端口

可自己找结构体字段，也可直接参考下bpftrace项目里面的[tools](https://github.com/bpftrace/bpftrace/tree/master/tools)，里面的网络相关`.bt`脚本基本都涉及常用的字段。

还是用[之前](https://github.com/xiaodongQ/prog-playground/tree/main/network/tcp_connect)全连接队列的demo程序：`./server`监听8080，客户端仅用`curl 192.168.1.150:8080`，由于客户端不发数据，会阻塞住，打断`./server`程序即会向客户端发送RST，监测结果如下：

```sh
[root@xdlinux ➜ bpftrace_tcp_reset git:(main) ✗ ]$ bpftrace -e 'kprobe:tcp_v4_send_reset, kprobe:tcp_send_active_reset { printf("comm:%s, foreign:%s:%d, call stack:%s\n", comm, ntop( ((struct sock*)arg0)->__sk_common.skc_daddr ),  ((struct sock*)arg0)->__sk_common.skc_dport, kstack()); }'
Attaching 2 probes...
comm:server, foreign:192.168.1.2:46067, call stack:
        tcp_send_active_reset+1
        tcp_disconnect+1211
        inet_child_forget+48
        inet_csk_listen_stop+168
        __tcp_close+944
        tcp_close+31
        inet_release+66
        __sock_release+61
        sock_close+17
        __fput+190
        task_work_run+138
        do_exit+915
        do_group_exit+58
        get_signal+344
        do_signal+54
        exit_to_usermode_loop+137
        do_syscall_64+408
        entry_SYSCALL_64_after_hwframe+101
```

对于复杂结构和逻辑，还是写个`.bt`脚本方便一些。

其他网络相关跟踪点（部分，比如还有收到包时的tracepoint:net:netif_receive_skb），按需使用

```sh
[root@xdlinux ➜ dbdoctor ]$ bpftrace -l |grep -E 'tcp:|sock:inet|skb:' 
# 这几个先不管
# tracepoint:mptcp:ack_update_msk
# tracepoint:mptcp:get_mapping_status
# tracepoint:mptcp:mptcp_subflow_get_send
# tracepoint:mptcp:subflow_check_data_avail
tracepoint:skb:consume_skb
tracepoint:skb:kfree_skb
tracepoint:skb:skb_copy_datagram_iovec
tracepoint:sock:inet_sock_set_state
tracepoint:tcp:tcp_destroy_sock
tracepoint:tcp:tcp_probe
tracepoint:tcp:tcp_rcv_space_adjust
tracepoint:tcp:tcp_receive_reset
tracepoint:tcp:tcp_retransmit_skb
tracepoint:tcp:tcp_retransmit_synack
tracepoint:tcp:tcp_send_reset
```

### 3.1. 扩展：faddr2line用法

上面用到`faddr2line`将堆栈信息的地址转换对应到源码位置，这里学习了解下这个工具。

1、检索`faddr2line`，发现它是内核中脚本的一部分，find能找到该文件，不过该路径没加在PATH里（即直接执行`faddr2line`是找不到的）。

```sh
[root@xdlinux ➜ tcp_connect git:(main) ✗ ]$ find / -name faddr2line
/usr/src/kernels/4.18.0-348.7.1.el8_5.x86_64/scripts/faddr2line
```

2、查看脚本内容（**Shell脚本**），可以发现它和`addr2line`（**二进制文件**）的关系

脚本`faddr2line`，用来转换堆栈转储中的函数偏移，里面会组合使用`addr2line`、`readelf`、`nm`、`size`

相对于`addr2line`，`faddr2line`支持转换查看`function+offset`形式

这里的size有点陌生，man一下，可看到其用于查看object文件的各个section大小的

```sh
[root@xdlinux ➜ tcp_connect git:(main) ✗ ]$ size ./server
   text	   data	    bss	    dec	    hex	filename
   3012	    708	    280	   4000	    fa0	./server
```

3、先简单使用`addr2line`

`./server`启动程序，gcore生成个core文件，用`addr2line`分析地址对应的函数位置

```sh
# ./server的进程号
[root@xdlinux ➜ workspace ]$ ps -fe|grep server
root        4430    2729  0 15:13 pts/1    00:00:00 ./server

# 生成core
[root@xdlinux ➜ workspace ]$ gcore 4430
0x00007f04b521dd68 in nanosleep () from /lib64/libc.so.6
Saved corefile core.4430
[Inferior 1 (process 4430) detached]
```

gdb加载core查看堆栈

```sh
[root@xdlinux ➜ workspace ]$ gdb -c core.4430 prog-playground/network/tcp_connect/server 
GNU gdb (GDB) Red Hat Enterprise Linux 8.2-16.el8
...
Reading symbols from prog-playground/network/tcp_connect/server...done.
[New LWP 4430]
Core was generated by `./server'.
#0  0x00007f04b521dd68 in nanosleep () from /lib64/libc.so.6
Missing separate debuginfos, use: yum debuginfo-install glibc-2.28-164.el8.x86_64 libgcc-8.5.0-3.el8.x86_64 libstdc++-8.5.0-3.el8.x86_64
(gdb) bt
#0  0x00007f04b521dd68 in nanosleep () from /lib64/libc.so.6
#1  0x00007f04b521dc9e in sleep () from /lib64/libc.so.6
#2  0x0000000000400b64 in main () at server.cpp:43
(gdb) q
```

`addr2line`查看上面地址对应的函数位置：

```sh
# 可以看到用户代码的具体位置
[root@xdlinux ➜ workspace ]$ addr2line -e prog-playground/network/tcp_connect/server 0x0000000000400b64
/home/workspace/prog-playground/network/tcp_connect/server.cpp:43

# libc库里的符号找不到确切位置
[root@xdlinux ➜ workspace ]$ addr2line -e prog-playground/network/tcp_connect/server 0x00007f04b521dc9e
??:0
```

关于上面gdb的报错："Missing separate debuginfos, use: yum debuginfo-install glibc-2.28-164.el8.x86_64 libgcc-8.5.0-3.el8.x86_64 libstdc++-8.5.0-3.el8.x86_64"

yum安装找不到相关debuginfo包：

```sh
[root@xdlinux ➜ workspace ]$ yum debuginfo-install glibc-2.28-164.el8.x86_64 libgcc-8.5.0-3.el8.x86_64 libstdc++-8.5.0-3.el8.x86_64
Last metadata expiration check: 3:51:32 ago on Wed 03 Jul 2024 07:14:14 PM CST.
Could not find debuginfo package for the following installed packages: glibc-2.28-164.el8.x86_64, libgcc-8.5.0-3.el8.x86_64, libstdc++-8.5.0-3.el8.x86_64
Could not find debugsource package for the following installed packages: glibc-2.28-164.el8.x86_64, libgcc-8.5.0-3.el8.x86_64, libstdc++-8.5.0-3.el8.x86_64
Dependencies resolved.
Nothing to do.
Complete!
```

查了下需要启用Debuginfo yum源，看之前陪的阿里云的源里没有Debuginfo，先手动下一下。

到centos8官方（已停止维护更新）的debuginfo里下rpm：http://debuginfo.centos.org/8/x86_64/Packages/

glibc-debuginfo-2.28-164.el8.x86_64.rpm、libgcc-debuginfo-8.5.0-3.el8.x86_64.rpm、libstdc++-debuginfo-8.5.0-3.el8.x86_64.rpm

另外下载（安装上述包时会提示依赖）：gcc-debuginfo-8.5.0-3.el8.x86_64.rpm、glibc-debuginfo-common-2.28-164.el8.x86_64.rpm

`rpm -ivh *.rpm`安装上述包后，再加载core文件可以直接看到内核函数的具体位置了

```sh
(gdb) bt
#0  0x00007f670e9f7d68 in __GI___nanosleep (
    requested_time=requested_time@entry=0x7ffc536adea0, 
    remaining=remaining@entry=0x7ffc536adea0) at ../sysdeps/unix/sysv/linux/nanosleep.c:28
#1  0x00007f670e9f7c9e in __sleep (seconds=0) at ../sysdeps/posix/sleep.c:55
#2  0x0000000000400b64 in main () at server.cpp:43
(gdb) 
```

### 3.2. 扩展：iptables debug

这里也参考上面学习下iptables调试日志，之前[网络实验-设置机器的MTU和MSS](https://xiaodongq.github.io/2023/04/09/network-mtu-mss/)里用`iptables`设置MSS时就想跟踪的，当时留了TODO项。

上面打印iptables DEBUG日志的命令：

`iptables -A INPUT -m conntrack --ctstate INVALID -m limit --limit 1/sec   -j LOG --log-prefix "invalid: " --log-level 7`

看一下加这个规则前后`iptables -L`结果的变化：

```sh
[root@xdlinux ➜ ~ ]$ iptables -nL > tmp
[root@xdlinux ➜ ~ ]$ iptables -A INPUT -m conntrack --ctstate INVALID -m limit --limit 1/sec   -j LOG --log-prefix "invalid: " --log-level 7
[root@xdlinux ➜ ~ ]$ iptables -nL > tmp2
[root@xdlinux ➜ ~ ]$ iptables -D INPUT -m conntrack --ctstate INVALID -m limit --limit 1/sec   -j LOG --log-prefix "invalid: " --log-level 7
[root@xdlinux ➜ ~ ]$ diff tmp tmp2
11a12
> LOG        all  --  0.0.0.0/0            0.0.0.0/0            ctstate INVALID limit: avg 1/sec burst 5 LOG flags 0 level 7 prefix "invalid: "
```

虽然`lsmod|grep nf_log_ipv4`看不到nf_log_ipv4这个模块（此处CentOS8例看不到，发现CentOS7机器可看到），但是若移除这个模块`modprobe -r nf_log_ipv4`，会影响上面的命令，添加iptables规则时就会直接报错：

```sh
# 移除nf_log_ipv4模块添加规则时报错
[root@xdlinux ➜ ~ ]$ iptables -A INPUT -m conntrack --ctstate INVALID -m limit --limit 1/sec   -j LOG --log-prefix "invalid: " --log-level 7
iptables v1.8.4 (nf_tables):  RULE_APPEND failed (No such file or directory): rule in chain INPUT

# 过滤模块啥都没有
[root@xdlinux ➜ ~ ]$ lsmod |grep -iE "nf_log_ipv4|ipt_LOG|ip6t_LOG|nfnetlink_log"
[root@xdlinux ➜ ~ ]$ 
```

`modprobe -r nf_log_ipv4`移除模块后，参数默认重置为：

```sh
[root@xdlinux ➜ ~ ]$ sysctl -a|grep net.netfilter.|grep log    
net.netfilter.nf_conntrack_log_invalid = 0
net.netfilter.nf_log.0 = NONE
net.netfilter.nf_log.1 = NONE
net.netfilter.nf_log.10 = NONE
net.netfilter.nf_log.11 = NONE
net.netfilter.nf_log.12 = NONE
net.netfilter.nf_log.2 = NONE
net.netfilter.nf_log.3 = NONE
net.netfilter.nf_log.4 = NONE
net.netfilter.nf_log.5 = NONE
net.netfilter.nf_log.6 = NONE
net.netfilter.nf_log.7 = NONE
net.netfilter.nf_log.8 = NONE
net.netfilter.nf_log.9 = NONE
net.netfilter.nf_log_all_netns = 0
```

`modprobe nf_log_ipv4`后，参数自动调整为了：

```sh
[root@xdlinux ➜ ~ ]$ sysctl -a|grep net.netfilter.|grep log
net.netfilter.nf_conntrack_log_invalid = 0
net.netfilter.nf_log.0 = NONE
net.netfilter.nf_log.1 = NONE
net.netfilter.nf_log.10 = nf_log_ipv6
net.netfilter.nf_log.11 = NONE
net.netfilter.nf_log.12 = NONE
net.netfilter.nf_log.2 = nf_log_ipv4
net.netfilter.nf_log.3 = nf_log_arp
net.netfilter.nf_log.4 = NONE
net.netfilter.nf_log.5 = nf_log_netdev
net.netfilter.nf_log.6 = NONE
net.netfilter.nf_log.7 = nf_log_bridge
net.netfilter.nf_log.8 = NONE
net.netfilter.nf_log.9 = NONE
net.netfilter.nf_log_all_netns = 0
```

下面记录在CentOS8.5上的几次尝试，都没成功追踪到iptables的日志

#### 3.2.1. CentOS 8.5上的尝试 及 其他系统对比

CentOS8.5的内核：4.18.0-348.7.1.el8_5.x86_64

1、尝试1：模仿上面改成`ESTABLISHED`状态，没追踪到日志

`iptables -A INPUT -m conntrack --ctstate ESTABLISHED -m limit --limit 1/sec -j LOG --log-prefix "conn_established_related: " --log-level 7`

**而找了个openEuler机器环境，追踪成功了！（之前加上这次，都是被CentOS8坑了，机制应该有变化）：**

```sh
# openEuler机器上
[root@localhost ~]# iptables -A INPUT -m conntrack --ctstate ESTABLISHED -m limit --limit 1/sec -j LOG --log-prefix "conn_established_related: " --log-level 7

# 查看dmesg里有iptables日志了
[root@localhost ~]# dmesg -T|tail
[Fri Jul  5 03:09:55 2024] conn_established_related: IN=br0 OUT= MAC=xxx SRC=xxx DST=xxx LEN=136 TOS=0x00 PREC=0x00 TTL=123 ID=47007 DF PROTO=TCP SPT=52005 DPT=22 WINDOW=8210 RES=0x00 ACK PSH URGP=0 
[Fri Jul  5 03:09:56 2024] conn_established_related: IN=br0 OUT= MAC=xxx SRC=xxx DST=xxx LEN=136 TOS=0x00 PREC=0x00 TTL=123 ID=47017 DF PROTO=TCP SPT=52005 DPT=22 WINDOW=8208 RES=0x00 ACK PSH URGP=0 

# 删除规则，还原
iptables -D INPUT -m conntrack --ctstate ESTABLISHED -m limit --limit 1/sec -j LOG --log-prefix "conn_established_related: " --log-level 7
```

openEuler上加载的模块和参数如下，lsmod可看到nf_log_ipv4

```sh
# lsmod
[root@localhost ～]# lsmod |grep -E "nf_log_ipv4|ipt_LOG|ip6t_LOG|nfnetlink_log"
nf_log_ipv4            16384  0
nf_log_common          16384  1 nf_log_ipv4

# 系统参数
[root@localhost ～]# sysctl -a|grep netfilter|grep log
net.netfilter.nf_conntrack_log_invalid = 0
net.netfilter.nf_log.0 = NONE
net.netfilter.nf_log.1 = NONE
net.netfilter.nf_log.10 = NONE
net.netfilter.nf_log.11 = NONE
net.netfilter.nf_log.12 = NONE
net.netfilter.nf_log.2 = nf_log_ipv4
net.netfilter.nf_log.3 = NONE
net.netfilter.nf_log.4 = NONE
net.netfilter.nf_log.5 = NONE
net.netfilter.nf_log.6 = NONE
net.netfilter.nf_log.7 = NONE
net.netfilter.nf_log.8 = NONE
net.netfilter.nf_log.9 = NONE
net.netfilter.nf_log_all_netns = 0
```

2、尝试2：通过raw表跟踪，也没成功（CentOS8上）

试下通过raw表跟踪，因为raw表在所有iptables规则中优先级是最高的，raw表有两条链，prerouting和output，分别作为输入和输出的第一必经点。  

```sh
iptables -t raw -A PREROUTING -p icmp -j TRACE
iptables -t raw -A OUTPUT -p icmp -j TRACE
```

添加raw规则前后，`iptables -nL`对比没有任何变化

CentOS7中，依赖的iptables日志模块是`nf_log_ipv4`（CentOS6则是ipt_LOG）  
参考：[CentOS通过raw表实现iptables日志输出和调试](http://www.chinasem.cn/article/958790)

3、尝试3：设置net.netfilter.nf_log_all_netns=1，也没成功

注意到上面 net.netfilter.nf_log_all_netns=0，修改为1。结果dmesg还是没追踪到日志，而CentOS7上该值也为0但是有日志

```sh
sysctl -w net.netfilter.nf_log_all_netns=1
```

为了明确CentOS8的问题，起几个其他系统实锤对比。

#### 3.2.2. 对比测试：Alibaba Cloud Linux 3.2104 LTS 64位

起一个阿里云抢占式ECS：Alibaba Cloud Linux 3.2104 LTS 64位（内核版本：5.10.134-16.1.al8.x86_64）

**注意设置规则前后，模块和系统参数的变化情况。**

1）刚创建的ECS：

```sh
# 开始没有过滤到模块
[root@iZ2zeb922hid1kv9lv9ufuZ ~]# lsmod |grep -E "nf_log_ipv4|ipt_LOG|ip6t_LOG|nfnetlink_log"
[root@iZ2zeb922hid1kv9lv9ufuZ ~]# 

# 系统参数如下，都是默认空的：
[root@iZ2zeb922hid1kv9lv9ufuZ ~]# sysctl -a|grep netfilter|grep log
net.netfilter.nf_log.0 = NONE
net.netfilter.nf_log.1 = NONE
net.netfilter.nf_log.10 = NONE
net.netfilter.nf_log.11 = NONE
net.netfilter.nf_log.12 = NONE
net.netfilter.nf_log.2 = NONE
net.netfilter.nf_log.3 = NONE
net.netfilter.nf_log.4 = NONE
net.netfilter.nf_log.5 = NONE
net.netfilter.nf_log.6 = NONE
net.netfilter.nf_log.7 = NONE
net.netfilter.nf_log.8 = NONE
net.netfilter.nf_log.9 = NONE
net.netfilter.nf_log_all_netns = 0

# iptables规则没有日志相关记录
[root@iZ2zeb922hid1kv9lv9ufuZ ~]# iptables -nL|grep -i log
[root@iZ2zeb922hid1kv9lv9ufuZ ~]# 
```

2）添加日志追踪规则：

```sh
[root@iZ2zeb922hid1kv9lv9ufuZ ~]# iptables -A INPUT -m conntrack --ctstate ESTABLISHED -m limit --limit 1/sec -j LOG --log-prefix "conn_established_related: " --log-level 7

[root@iZ2zeb922hid1kv9lv9ufuZ ~]# iptables -nL|grep -i log
LOG        all  --  0.0.0.0/0            0.0.0.0/0            ctstate ESTABLISHED limit: avg 1/sec burst 5 LOG flags 0 level 7 prefix "conn_established_related: "
```

可追踪到iptables日志：

```sh
[root@iZ2zeb922hid1kv9lv9ufuZ ~]# dmesg |tail
[  111.529820] AliSecGuard : 0cf05ee8d063d9f37208e027efd361240bc0dc88
[  412.424779] conn_established_related: IN=eth0 OUT= MAC=00:16:3e:3d:77:98:ee:ff:ff:ff:ff:ff:08:00 SRC=100.104.192.129 DST=172.23.133.147 LEN=40 TOS=0x00 PREC=0x20 TTL=57 ID=61323 DF PROTO=TCP SPT=43167 DPT=22 WINDOW=0 RES=0x00 RST URGP=0 
[  412.426768] conn_established_related: IN=eth0 OUT= MAC=00:16:3e:3d:77:98:ee:ff:ff:ff:ff:ff:08:00 SRC=100.104.192.129 DST=172.23.133.147 LEN=52 TOS=0x00 PREC=0x00 TTL=57 ID=7112 DF PROTO=TCP SPT=39071 DPT=22 WINDOW=409 RES=0x00 ACK URGP=0 
[  412.543725] conn_established_related: IN=eth0 OUT= MAC=00:16:3e:3d:77:98:ee:ff:ff:ff:ff:ff:08:00 SRC=100.100.30.26 DST=172.23.133.147 LEN=40 TOS=0x00 PREC=0x00 TTL=52 ID=3530 DF PROTO=TCP SPT=80 DPT=51562 WINDOW=1807 RES=0x00 ACK URGP=0 
```

模块和系统参数自动变化了：

```sh
# 自动加载了nf_log_ipv4
[root@iZ2zeb922hid1kv9lv9ufuZ ~]# lsmod |grep -E "nf_log_ipv4|ipt_LOG|ip6t_LOG|nfnetlink_log"
nf_log_ipv4            16384  0
nf_log_common          16384  1 nf_log_ipv4
```

```sh
# 自动设置了 net.netfilter.nf_log.2=nf_log_ipv4
[root@iZ2zeb922hid1kv9lv9ufuZ ~]# sysctl -a|grep netfilter|grep log
net.netfilter.nf_conntrack_log_invalid = 0
net.netfilter.nf_log.0 = NONE
net.netfilter.nf_log.1 = NONE
net.netfilter.nf_log.10 = NONE
net.netfilter.nf_log.11 = NONE
net.netfilter.nf_log.12 = NONE
net.netfilter.nf_log.2 = nf_log_ipv4
net.netfilter.nf_log.3 = NONE
net.netfilter.nf_log.4 = NONE
net.netfilter.nf_log.5 = NONE
net.netfilter.nf_log.6 = NONE
net.netfilter.nf_log.7 = NONE
net.netfilter.nf_log.8 = NONE
net.netfilter.nf_log.9 = NONE
net.netfilter.nf_log_all_netns = 0
```

3）删除规则，还原

```sh
[root@iZ2zeb922hid1kv9lv9ufuZ ~]# iptables -D INPUT -m conntrack --ctstate ESTABLISHED -m limit --limit 1/sec -j LOG --log-prefix "conn_established_related: " --log-level 7
```

加载模块和系统参数不变，不会自动清理

```sh
# 加载模块和上面一样
[root@iZ2zeb922hid1kv9lv9ufuZ ~]# lsmod |grep -E "nf_log_ipv4|ipt_LOG|ip6t_LOG|nfnetlink_log"
nf_log_ipv4            16384  0
nf_log_common          16384  1 nf_log_ipv4

# 系统参数和上面一样
[root@iZ2zeb922hid1kv9lv9ufuZ ~]# sysctl -a|grep netfilter|grep log
net.netfilter.nf_conntrack_log_invalid = 0
net.netfilter.nf_log.0 = NONE
net.netfilter.nf_log.1 = NONE
net.netfilter.nf_log.10 = NONE
net.netfilter.nf_log.11 = NONE
net.netfilter.nf_log.12 = NONE
net.netfilter.nf_log.2 = nf_log_ipv4
net.netfilter.nf_log.3 = NONE
net.netfilter.nf_log.4 = NONE
net.netfilter.nf_log.5 = NONE
net.netfilter.nf_log.6 = NONE
net.netfilter.nf_log.7 = NONE
net.netfilter.nf_log.8 = NONE
net.netfilter.nf_log.9 = NONE
net.netfilter.nf_log_all_netns = 0
```

4）手动移除模块 `modprobe -r nf_log_ipv4`

可看到系统参数自动还原了

```sh
[root@iZ2zeb922hid1kv9lv9ufuZ ~]# lsmod |grep -E "nf_log_ipv4|ipt_LOG|ip6t_LOG|nfnetlink_log"
[root@iZ2zeb922hid1kv9lv9ufuZ ~]# sysctl -a|grep netfilter|grep log
net.netfilter.nf_conntrack_log_invalid = 0
net.netfilter.nf_log.0 = NONE
net.netfilter.nf_log.1 = NONE
net.netfilter.nf_log.10 = NONE
net.netfilter.nf_log.11 = NONE
net.netfilter.nf_log.12 = NONE
net.netfilter.nf_log.2 = NONE
net.netfilter.nf_log.3 = NONE
net.netfilter.nf_log.4 = NONE
net.netfilter.nf_log.5 = NONE
net.netfilter.nf_log.6 = NONE
net.netfilter.nf_log.7 = NONE
net.netfilter.nf_log.8 = NONE
net.netfilter.nf_log.9 = NONE
net.netfilter.nf_log_all_netns = 0
```

5）测试raw规则

**结果：没成功。**

按照上面的方式：[CentOS通过raw表实现iptables日志输出和调试](http://www.chinasem.cn/article/958790)

```sh
iptables -t raw -A PREROUTING -p icmp -j TRACE
iptables -t raw -A OUTPUT -p icmp -j TRACE
```

通过ping -c 1 172.23.133.147验证

`nf_log_ipv4`模块也有、nf_log_all_netns=1也试过，/var/log/messages 和 dmesg里都没有iptables日志！

#### 3.2.3. 对比测试：CentOS7.9

再起一个CentOS7.9 ECS

```sh
[root@iZbp1by1hq7wgbzm5nrdu2Z ~]# cat /etc/system-release
CentOS Linux release 7.9.2009 (Core)
[root@iZbp1by1hq7wgbzm5nrdu2Z ~]# uname -r
3.10.0-1160.119.1.el7.x86_64
```

重复上述步骤，结果和结论和 Alibaba Cloud Linux 3.2104 LTS 64位 完全一样。

(后续跟踪学习netfilter代码 TODO)

## 4. 使用perf跟踪网络堆栈

[之前](https://xiaodongq.github.io/2024/06/20/ebpf-practice-case/)也看过TCP相关的tracepoint，没有多少个：

```sh
[root@xdlinux ➜ ~ ]$ perf list 'tcp:*' 'sock:inet*' 'skb:*'

List of pre-defined events (to be used in -e):

  tcp:tcp_destroy_sock                               [Tracepoint event]
  tcp:tcp_probe                                      [Tracepoint event]
  tcp:tcp_rcv_space_adjust                           [Tracepoint event]
  tcp:tcp_receive_reset                              [Tracepoint event]
  tcp:tcp_retransmit_skb                             [Tracepoint event]
  tcp:tcp_retransmit_synack                          [Tracepoint event]
  tcp:tcp_send_reset                                 [Tracepoint event]

  sock:inet_sock_set_state                           [Tracepoint event]

  skb:consume_skb                                    [Tracepoint event]
  skb:kfree_skb                                      [Tracepoint event]
  skb:skb_copy_datagram_iovec                        [Tracepoint event]
```

跟踪skb的消费和释放：

```sh
[root@xdlinux ➜ ~ ]$ perf record -e 'skb:consume_skb' -e 'skb:kfree_skb' -g -a 
^C[ perf record: Woken up 1 times to write data ]
[ perf record: Captured and wrote 0.266 MB perf.data (15 samples) ]

```

查看结果：采集到很多内容，这里截取部分，已经可以根据调用栈辅助代码跟踪了

```sh
[root@xdlinux ➜ ~ ]$ perf report --stdio
# To display the perf.data header info, please use --header/--header-only options.
#
#
# Total Lost Samples: 0
#
# Samples: 5  of event 'skb:consume_skb'
# Event count (approx.): 5
#
# Children      Self  Command  Shared Object      Symbol                            
# ........  ........  .......  .................  ..................................
#
   100.00%     0.00%  swapper  [kernel.kallsyms]  [k] secondary_startup_64_no_verify
            |
            ---secondary_startup_64_no_verify
               start_secondary
               cpu_startup_entry
               do_idle
               cpuidle_enter
               cpuidle_enter_state
               ret_from_intr
               do_IRQ
               irq_exit
               __softirqentry_text_start
               net_rx_action
               __napi_poll
               rtl8169_poll
               |          
               |--80.00%--napi_consume_skb
               |          napi_consume_skb
               |          
                --20.00%--napi_gro_receive
                          netif_receive_skb_internal
                          __netif_receive_skb_core
                          ip_rcv
                          ip_local_deliver
                          ip_local_deliver_finish
                          ip_protocol_deliver_rcu
                          tcp_v4_rcv
                          tcp_v4_do_rcv
                          tcp_rcv_state_process
                          consume_skb
                          consume_skb
...
# Samples: 1  of event 'skb:kfree_skb'
# Event count (approx.): 1
#
# Children      Self  Command  Shared Object      Symbol                            
# ........  ........  .......  .................  ..................................
#
   100.00%   100.00%  swapper  [kernel.kallsyms]  [k] kfree_skb
            |
            ---secondary_startup_64_no_verify
               start_secondary
               cpu_startup_entry
               do_idle
               cpuidle_enter
               cpuidle_enter_state
               ret_from_intr
               do_IRQ
               irq_exit
               __softirqentry_text_start
               net_rx_action
               __napi_poll
               rtl8169_poll
               napi_gro_receive
               netif_receive_skb_internal
               __netif_receive_skb_core
               kfree_skb
               kfree_skb
...
```

另外，brendangregg大佬的这篇：[perf Examples](https://www.brendangregg.com/perf.html)，有很多实用的perf命令，需要单独开一篇博客学习记录下。

## 5. 使用gdb调试跟踪网络堆栈

需编译内核，然后基于QEMU+gdb调试，后续有需要再实践。

## 6. 小结

根据几个看过的文章信息及近期的学习实践，梳理跟踪内核中网络栈的几种方式，并学习了解了文章中的工具。

对比了几个不同系统里面iptables设置跟踪日志的表现，CentOS8里实验失败的原因这里先遗留了，作为TODO项后续定位。

## 7. 参考

1、 [关于解决问题的能力](https://wx.zsxq.com/dweb2/index/columns/15552551584552)

2、 [网络 IO 高级篇：一次有趣的 Docker 网络问题排查](https://heapdump.cn/article/2495315)

3、[【学习笔记】三小时内速通linux发包流程](https://articles.zsxq.com/id_qc2u23ktni9f.html)

4、 [gdb 调试 Linux 内核网络源码（附视频）](https://wenfh2020.com/2021/05/19/gdb-kernel-networking/)

5、 [vscode + gdb 远程调试 linux 内核源码（附视频）](https://wenfh2020.com/2021/06/23/vscode-gdb-debug-linux-kernel/)

6、[实战使用 qemu + gdb 调试 Linux 内核以及网络配置](https://juejin.cn/book/6844733794801418253/section/7358469142175105059)

7、[perf Examples](https://www.brendangregg.com/perf.html)

8、[CentOS通过raw表实现iptables日志输出和调试](http://www.chinasem.cn/article/958790)

9、GPT
