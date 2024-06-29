---
layout: post
title: eBPF学习实践系列（六） -- bpftrace学习和使用
categories: eBPF
tags: eBPF bpftrace
---

* content
{:toc}

bpftrace学习和使用



## 1. 背景

前面学习bcc和libbpf时，提到Brendan Gregg等大佬们编写的工具集（几个示意图可参考：[eBPF学习实践系列（一） -- 初识eBPF](https://xiaodongq.github.io/2024/06/06/ebpf_learn/) ），这些工具已经能提供很丰富的功能了。

但是想自己跟踪一些想要的个性化信息时，需要基于Python或者C/C++写逻辑，写完后有时还要调试各类编译问题，于是学习下`bpftrace`的使用，实践中更容易上手。

小结下近期的eBPF学习历程：  
![eBPF学习历程](/images/2024-06-28-ebpf-learn-record.png)

## 2. bpftrace说明

bpftrace是一种针对较近期的Linux内核（4.x系列起）中eBPF的高级跟踪语言。bpftrace利用`LLVM`作为后端，将脚本编译为BPF字节码，并借助`BCC`与Linux BPF系统进行交互，同时也利用了Linux现有的跟踪功能，包括内核动态跟踪（`kprobes`）、用户级动态跟踪（`uprobes`）及`tracepoint`。

bpftrace语言受到了awk、C语言以及先驱跟踪工具如`DTrace`和`SystemTap`的启发，并由[Alastair Robertson](https://github.com/ajor)创建。

项目主页：[bpftrace](https://github.com/bpftrace/bpftrace)

bpftrace内部结构示意图：  
![bpftrace内部结构](/images/bpftrace_internals_2018.png)

bpftrace提供的追踪类型：  
![bpftrace提供的追踪类型](/images/bpftrace_probes_2018.png)

## 3. 基本用法

查看github上bpftrace项目的一行使用教程：[tutorial_one_liners](https://github.com/bpftrace/bpftrace/blob/master/docs/tutorial_one_liners.md)，里面提供了12个简单的使用说明。 (也可以看这篇译文：[bpftrace一行教程](https://eunomia.dev/zh/tutorials/bpftrace-tutorial/))

记录下自己运行环境的bcc和bpftrace、llvm版本（有的环境发现有问题）

```sh
# 使用正常
[root@xdlinux ➜ ~ ]$ rpm -qa|grep bpftr
bpftrace-0.12.1-3.el8.x86_64
[root@xdlinux ➜ ~ ]$ rpm -qa|grep bcc
bcc-0.19.0-4.el8.x86_64
bcc-tools-0.19.0-4.el8.x86_64
python3-bcc-0.19.0-4.el8.x86_64
[root@xdlinux ➜ ~ ]$ rpm -qa|grep llvm
llvm-libs-12.0.1-2.module_el8.5.0+918+ed335b90.x86_64
llvm-12.0.1-2.module_el8.5.0+918+ed335b90.x86_64
```

前面eBPF学习基础后，理解和使用bpftrace就比较丝滑了，很多直接可用的轮子。

### 3.1. 列出所有探针

`bpftrace -l 'tracepoint:syscalls:sys_enter_*'`

支持通配符，如`*`和`?`

```sh
[root@xdlinux ➜ events ]$ bpftrace -l 'tracepoint:skb:*'
tracepoint:skb:consume_skb
tracepoint:skb:kfree_skb
tracepoint:skb:skb_copy_datagram_iovec
```

### 3.2. Hello World

`bpftrace -e 'BEGIN { printf("hello world\n"); }'`

```sh
[root@xdlinux ➜ events ]$ bpftrace -e 'BEGIN { printf("hello world\n"); }'
Attaching 1 probe...
hello world
```

### 3.3. 探测文件打开

`bpftrace -e 'tracepoint:syscalls:sys_enter_openat { printf("%s %s\n", comm, str(args.filename)); }'`

* `common` 是内建变量，表示当前进程名。还有其他内建变量如： pid、tid
* 访问上下文中的成员变量时，低版本使用`args->filename`方式访问成员，用错时会报错提示的
* `str()`把一个指针转换成字符串

```sh
# centos8.5这里，用->访问
[root@xdlinux ➜ events ]$ bpftrace -e 'tracepoint:syscalls:sys_enter_openat { printf("%s %s\n", comm, str(args->filename)); }'
Attaching 1 probe...
irqbalance /proc/interrupts
irqbalance /proc/stat
irqbalance /proc/irq/32/smp_affinity
irqbalance /proc/irq/30/smp_affinity
```

### 3.4. 按进程名统计系统调用次数

`bpftrace -e 'tracepoint:raw_syscalls:sys_enter { @[comm] = count(); }'`

* `@[comm] = count()` 表示定义一个map，形式为`map<comm, count()>`，还可以给map命名
* `count()`是一个map函数

```sh
[root@xdlinux ➜ events ]$ bpftrace -e 'tracepoint:raw_syscalls:sys_enter { @[comm] = count(); }'
Attaching 1 probe...
^C

@[sedispatch]: 1
@[gmain]: 4
@[in:imjournal]: 12
@[sshd]: 17
@[dockerd]: 35
@[NetworkManager]: 44
@[tuned]: 54
@[bpftrace]: 64
@[containerd]: 230

# 给map命名，@test
[root@xdlinux ➜ events ]$ bpftrace -e 'tracepoint:raw_syscalls:sys_enter { @test[comm] = count(); }'
Attaching 1 probe...
^C

@test[sssd]: 1
@test[sedispatch]: 2
@test[sssd_be]: 5
@test[sssd_nss]: 5
@test[gmain]: 6
```

### 3.5. read()返回值分布统计

过滤进程pid，并进行直方图统计，这里跟踪 tracepoint

`bpftrace -e 'tracepoint:syscalls:sys_exit_read /pid == 18644/ { @bytes = hist(args.ret); }'`

```sh
[root@xdlinux ➜ events ]$ bpftrace -e 'tracepoint:syscalls:sys_exit_read /pid == 1481/ { @bytes = hist(args->ret); }'
Attaching 1 probe...
^C

@bytes: 
(..., 0)              70 |@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@|
[0]                   27 |@@@@@@@@@@@@@@@@@@@@                                |
[1]                   15 |@@@@@@@@@@@                                         |
[2, 4)                 3 |@@                                                  |
[4, 8)                 0 |                                                    |
[8, 16)                0 |                                                    |
[16, 32)              26 |@@@@@@@@@@@@@@@@@@@                                 |
[32, 64)               9 |@@@@@@                                              |
[64, 128)             12 |@@@@@@@@                                            |
[128, 256)             9 |@@@@@@                                              |
[256, 512)             4 |@@                                                  |
[512, 1K)              2 |@                                                   |
[1K, 2K)               1 |                                                    |
[2K, 4K)               1 |                                                    |
[4K, 8K)               0 |                                                    |
[8K, 16K)              7 |@@@@@                                               |
```

可以看到 ret 是返回值，对应的是读取的长度

```sh
[root@xdlinux ➜ events ]$ cat syscalls/sys_exit_read/format 
name: sys_exit_read
ID: 671
format:
	field:unsigned short common_type;	offset:0;	size:2;	signed:0;
	field:unsigned char common_flags;	offset:2;	size:1;	signed:0;
	field:unsigned char common_preempt_count;	offset:3;	size:1;	signed:0;
	field:int common_pid;	offset:4;	size:4;	signed:1;

	field:int __syscall_nr;	offset:8;	size:4;	signed:1;
	field:long ret;	offset:16;	size:8;	signed:1;

print fmt: "0x%lx", REC->ret
```

### 3.6. 动态跟踪read()内核态中返回的字节数

`bpftrace -e 'kretprobe:vfs_read { @bytes = lhist(retval, 0, 2000, 200); }'`

跟踪 kretprobe，系统支持的 kretprobe 追踪点列表可以查看 `bpftrace -l 'kretprobe:*'`

```sh
[root@xdlinux ➜ events ]$  bpftrace -e 'kretprobe:vfs_read { @bytes = lhist(retval, 0, 2000, 200); }'
Attaching 1 probe...
^C

@bytes: 
(..., 0)              12 |                                                    |
[0, 200)             906 |@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@|
[200, 400)            75 |@@@@                                                |
[400, 600)            18 |@                                                   |
[600, 800)            11 |                                                    |
[800, 1000)          173 |@@@@@@@@@                                           |
[1000, 1200)          23 |@                                                   |
[1200, 1400)           4 |                                                    |
[1400, 1600)           5 |                                                    |
[1600, 1800)           6 |                                                    |
[1800, 2000)          15 |                                                    |
[2000, ...)          276 |@@@@@@@@@@@@@@@                                     |
```

### 3.7. 各进程read()调用的时间

`bpftrace -e 'kprobe:vfs_read { @start[tid] = nsecs; } kretprobe:vfs_read /@start[tid]/ { @ns[comm] = hist(nsecs - @start[tid]); delete(@start[tid]); }'`

统计不同进程花在`read()`上面的时间，各自按花费时间区间以直方图展示，单位是ns

定义2个map，利用tid作为标识进行关联

```sh
[root@xdlinux ➜ ~ ]$ bpftrace -e 'kprobe:vfs_read { @start[tid] = nsecs; } kretprobe:vfs_read /@start[tid]/ { @ns[comm] = hist(nsecs - @start[tid]); delete(@start[tid]); }'
Attaching 2 probes...

^C

@ns[NetworkManager]: 
[4K, 8K)               2 |@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@|

@ns[containerd]: 
[8K, 16K)              2 |@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@|

@ns[dockerd]: 
[8K, 16K)              1 |@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@|
[16K, 32K)             1 |@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@|

@ns[sshd]: 
[4K, 8K)               2 |@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@|
[8K, 16K)              0 |                                                    |
[16K, 32K)             2 |@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@|

@ns[in:imjournal]: 
[4K, 8K)               7 |@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@|
[8K, 16K)              1 |@@@@@@@                                             |

@ns[irqbalance]: 
[256, 512)             3 |@@@@@@@@@@@@@@@@@@@                                 |
[512, 1K)              4 |@@@@@@@@@@@@@@@@@@@@@@@@@@                          |
[1K, 2K)               2 |@@@@@@@@@@@@@                                       |
[2K, 4K)               0 |                                                    |
[4K, 8K)               1 |@@@@@@                                              |
[8K, 16K)              8 |@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@|
[16K, 32K)             3 |@@@@@@@@@@@@@@@@@@@                                 |
[32K, 64K)             0 |                                                    |
[64K, 128K)            1 |@@@@@@                                              |

@start[6395]: 91660555397772
```

### 3.8. 统计进程级别的事件

`bpftrace -e 'tracepoint:sched:sched* { @[probe] = count(); } interval:s:5 { exit(); }'`

统计`tracepoint:sched:sched*`形式的tracepoint在5s内的触发次数

```sh
[root@xdlinux ➜ ~ ]$ bpftrace -e 'tracepoint:sched:sched* { @[probe] = count(); } interval:s:5 { exit(); }'
Attaching 25 probes...


@[tracepoint:sched:sched_migrate_task]: 1
@[tracepoint:sched:sched_wake_idle_without_ipi]: 24
@[tracepoint:sched:sched_stat_runtime]: 480
@[tracepoint:sched:sched_wakeup]: 547
@[tracepoint:sched:sched_waking]: 556
@[tracepoint:sched:sched_switch]: 1005
```

### 3.9. 跟踪内核函数堆栈

`bpftrace -e 'profile:hz:99 { @[kstack] = count(); }'`

采集On-CPU的内核堆栈及对应的统计次数，采样频率99Hz

`profile:hz:99`：所有cpu都以`99`赫兹的频率采样分析内核栈。为了采集足够的内核信息，这里的`99`够用了，为什么不是正好`100`，这是由于采样频率可能与其他定时事件步调一致，所以`99`赫兹是一个理想的选择

**`kstack` 返回内核调用栈**

另外：**`ustack` 可以分析用户级调用栈**

```sh
[root@xdlinux ➜ ~ ]$ bpftrace -e 'profile:hz:99 { @[kstack] = count(); }'
Attaching 1 probe...
^C

@[
    load_balance+5
    rebalance_domains+700
    __do_softirq+215
    irq_exit+247
    smp_apic_timer_interrupt+116
    apic_timer_interrupt+15
    cpuidle_enter_state+219
    cpuidle_enter+44
    do_idle+564
    cpu_startup_entry+111
    start_secondary+411
    secondary_startup_64_no_verify+194
]: 1
@[
    cpuidle_enter_state+219
    cpuidle_enter+44
    do_idle+564
    cpu_startup_entry+111
    start_kernel+1309
    secondary_startup_64_no_verify+194
]: 221
@[
    cpuidle_enter_state+219
    cpuidle_enter+44
    do_idle+564
    cpu_startup_entry+111
    start_secondary+411
    secondary_startup_64_no_verify+194
]: 6497
```

### 3.10. 调度器跟踪

`bpftrace -e 'tracepoint:sched:sched_switch { @[kstack] = count(); }'`

### 3.11. 块级别I/O跟踪

`bpftrace -e 'tracepoint:block:block_rq_issue { @ = hist(args.bytes); }'`

### 3.12. 内核结构跟踪

使用内核动态跟踪技术跟踪`vfs_read()`函数，该函数的(`struct path *`)作为第一个参数。

path.bt脚本内容：

```c
#ifndef BPFTRACE_HAVE_BTF
// 没有BTF时手动指定必要的内核头文件
#include <linux/path.h>
#include <linux/dcache.h>
#endif

# kprobe跟踪类型
kprobe:vfs_open
{
    printf("open path: %s\n", str(((struct path *)arg0)->dentry->d_name.name));
}
```

执行示例：

```sh
# bpftrace path.bt
Attaching 1 probe...
open path: dev
open path: if_inet6
open path: retrans_time_ms
[...]
```

## 4. bpftrace tools

bpftrace项目的 [tools](https://github.com/bpftrace/bpftrace/tree/master/tools) 目录下有很多直接可用的工具，作为平时使用和开发参考都是值得去看的。

过滤tcp相关的bpftrace脚步，可以用看到之前bcc tools里面的几个熟面孔

```sh
➜  /Users/xd/Documents/workspace/repo/bpftrace/tools git:(master) ls -ltr |grep tcp|grep .bt
-rwxr-xr-x  1 xd  staff  1976  6 29 10:07 tcpaccept.bt
-rwxr-xr-x  1 xd  staff  1869  6 29 10:07 tcpconnect.bt
-rwxr-xr-x  1 xd  staff  2689  6 29 10:07 tcpdrop.bt
-rwxr-xr-x  1 xd  staff  3005  6 29 10:07 tcplife.bt
-rwxr-xr-x  1 xd  staff  2340  6 29 10:07 tcpretrans.bt
-rwxr-xr-x  1 xd  staff   962  6 29 10:07 tcpsynbl.bt
```

简单看一下tcpdrop.bt内容：（对比BCC和libbpf开发，这里省了很多事，当然先不考虑通用移植性）

```sh
#!/usr/bin/env bpftrace
/*
 * tcpdrop.bt   Trace TCP kernel-dropped packets/segments.
 *              For Linux, uses bpftrace and eBPF.
 *
 * USAGE: tcpdrop.bt
 *
 * This is a bpftrace version of the bcc tool of the same name.
 *
 * This provides information such as packet details, socket state, and kernel
 * stack trace for packets/segments that were dropped via kfree_skb.
 * It cannot show tcp flags.
 *
#  当前这个脚本对内核是有要求的。对于老版本内核old下面有一个对应脚本：tools/old/tcpdrop.bt
 * For Linux 5.17+ (see tools/old for script for lower versions).
 *
 * Copyright (c) 2018 Dale Hamel.
 * Licensed under the Apache License, Version 2.0 (the "License")
 *
 * 23-Nov-2018	Dale Hamel	created this.
 * 01-Oct-2022	Rong Tao	use tracepoint:skb:kfree_skb
 */

#ifndef BPFTRACE_HAVE_BTF
#include <linux/socket.h>
#include <net/sock.h>
#else
/*
 * With BTF providing types, socket headers are not needed.
 * We only need to supply the preprocessor defines in this script.
 * AF_INET/AF_INET6 are part of the stable arch-independent Linux ABI
 */
#define AF_INET   2
#define AF_INET6 10
#endif

BEGIN
{
  printf("Tracing tcp drops. Hit Ctrl-C to end.\n");
  printf("%-8s %-8s %-16s %-21s %-21s %-8s\n", "TIME", "PID", "COMM", "SADDR:SPORT", "DADDR:DPORT", "STATE");

  // See https://github.com/torvalds/linux/blob/master/include/net/tcp_states.h
  # 定义map
  @tcp_states[1] = "ESTABLISHED";
  @tcp_states[2] = "SYN_SENT";
  @tcp_states[3] = "SYN_RECV";
  @tcp_states[4] = "FIN_WAIT1";
  @tcp_states[5] = "FIN_WAIT2";
  @tcp_states[6] = "TIME_WAIT";
  @tcp_states[7] = "CLOSE";
  @tcp_states[8] = "CLOSE_WAIT";
  @tcp_states[9] = "LAST_ACK";
  @tcp_states[10] = "LISTEN";
  @tcp_states[11] = "CLOSING";
  @tcp_states[12] = "NEW_SYN_RECV";
}

# 跟踪 skb:kfree_skb 这个tracepoint
tracepoint:skb:kfree_skb
{
  # args 是上下文，根据前面的eBPF学习可知，可利用tracefs或者 bpftrace -lv tracepoint:skb:kfree_skb 查看
  # reason是后面内核版本加的字段
  $reason = args.reason;
  # 变量定义和访问都用`$xxx`形式
  $skb = (struct sk_buff *)args.skbaddr;
  $sk = ((struct sock *) $skb->sk);
  $inet_family = $sk->__sk_common.skc_family;

  if ($reason > SKB_DROP_REASON_NOT_SPECIFIED &&
      ($inet_family == AF_INET || $inet_family == AF_INET6)) {
    if ($inet_family == AF_INET) {
      $daddr = ntop($sk->__sk_common.skc_daddr);
      $saddr = ntop($sk->__sk_common.skc_rcv_saddr);
    } else {
      $daddr = ntop($sk->__sk_common.skc_v6_daddr.in6_u.u6_addr8);
      $saddr = ntop($sk->__sk_common.skc_v6_rcv_saddr.in6_u.u6_addr8);
    }
    $lport = $sk->__sk_common.skc_num;
    $dport = $sk->__sk_common.skc_dport;

    // Destination port is big endian, it must be flipped
    $dport = bswap($dport);

    $state = $sk->__sk_common.skc_state;
    $statestr = @tcp_states[$state];

    time("%H:%M:%S ");
    printf("%-8d %-16s ", pid, comm);
    printf("%39s:%-6d %39s:%-6d %-10s\n", $saddr, $lport, $daddr, $dport, $statestr);
    printf("%s\n", kstack);
  }
}

END
{
  # 清理前面定义的map
  clear(@tcp_states);
}
```

## 5. 小结

了解bpftrace并实践了基本用法，跟BCC、libbpf做了简单对比

## 6. 参考

1、[bpftrace](https://github.com/bpftrace/bpftrace)

2、[tutorial_one_liners](https://github.com/bpftrace/bpftrace/blob/master/docs/tutorial_one_liners.md)

3、[bpftrace一行教程](https://eunomia.dev/zh/tutorials/bpftrace-tutorial/)

4、GPT
