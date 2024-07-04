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

看[知识星球](https://wx.zsxq.com/dweb2/index/group/15552551584552)文章、以及查资料时，看到几篇文章里有的基于现象去跟踪定位内核代码、有的是推荐学习内核方法，挺有收获。看里面的方式很想自己去学习掌握一下，于是有了这篇小结和实验文章。

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

早前因为这句话，有了后面深入学习eBPF的动力。

`ftrace`（或systemtap、ebpf）追踪函数运行序列。

比较好的实践方式：写简单demo（可借助GPT），开启追踪（借助上面工具），得到追踪结果后分析并对照源码印证

来自：[【学习笔记】三小时内速通linux发包流程](https://articles.zsxq.com/id_qc2u23ktni9f.html)

3、gdb调试linux网络源码

比较早之前在B站看到：

* [gdb 调试 Linux 内核网络源码（附视频）](https://wenfh2020.com/2021/05/19/gdb-kernel-networking/)
* [vscode + gdb 远程调试 linux 内核源码（附视频）](https://wenfh2020.com/2021/06/23/vscode-gdb-debug-linux-kernel/)

加上前段时间掘金小册看到：

[实战使用 qemu + gdb 调试 Linux 内核以及网络配置](https://juejin.cn/book/6844733794801418253/section/7358469142175105059)

不同时期的锚点相互叠加产生了足够推动动手的力。（乔布斯斯坦福演讲里说的前后看似不搭边实则隐隐联系在一起，忍不住又又又要去看一遍）

下面学习实践上述文章中涉及的工具和技巧。

## 3. 使用eBPF追踪

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

### 3.1. 扩展：faddr2line用法

上面用到`faddr2line`将堆栈信息的地址转换对应到源码位置，这里学习下这个工具。

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

## 4. 使用perf打印网络堆栈

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

跟踪sdk的消费和释放：

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

## 5. 使用gdb调试内核

需编译内核，然后基于QEMU+gdb调试，后续有需要再实践

## 6. 小结

根据几个看过的文章信息，梳理跟踪内核中网络栈的方式，并学习了解了文章中的工具。

## 7. 参考

1、 [关于解决问题的能力](https://wx.zsxq.com/dweb2/index/columns/15552551584552)

2、 [网络 IO 高级篇：一次有趣的 Docker 网络问题排查](https://heapdump.cn/article/2495315)

3、[【学习笔记】三小时内速通linux发包流程](https://articles.zsxq.com/id_qc2u23ktni9f.html)

4、 [gdb 调试 Linux 内核网络源码（附视频）](https://wenfh2020.com/2021/05/19/gdb-kernel-networking/)

5、 [vscode + gdb 远程调试 linux 内核源码（附视频）](https://wenfh2020.com/2021/06/23/vscode-gdb-debug-linux-kernel/)

6、[实战使用 qemu + gdb 调试 Linux 内核以及网络配置](https://juejin.cn/book/6844733794801418253/section/7358469142175105059)

7、[perf Examples](https://www.brendangregg.com/perf.html)

8、GPT
