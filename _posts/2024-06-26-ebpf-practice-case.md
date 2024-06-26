---
layout: post
title: eBPF学习实践系列（五） -- 分析一个libbpf程序
categories: eBPF
tags: eBPF libbpf
---

* content
{:toc}

跟踪分析bcc项目ibbpf-tools中的 `ltcplife.bpf.c` 程序



## 1. 背景

前面的eBPF学习实践系列主要是跟着别人的文章学习，积累了比较理论的知识。

[TCP半连接全连接（三） -- eBPF跟踪全连接队列溢出](https://xiaodongq.github.io/2024/06/23/ebpf-trace-tcp_connect/) 这篇中，自己要写eBPF程序了，带着实践的目的去参考已有工具代码，发现视角完全变了。

之前的理论知识很多都串起来了，再次体会到如这篇文章：[举三反一--从理论知识到实际问题的推导](https://plantegg.github.io/2020/11/02/%E4%B8%BE%E4%B8%89%E5%8F%8D%E4%B8%80--%E4%BB%8E%E7%90%86%E8%AE%BA%E7%9F%A5%E8%AF%86%E5%88%B0%E5%AE%9E%E9%99%85%E9%97%AE%E9%A2%98%E7%9A%84%E6%8E%A8%E5%AF%BC/) 里说的**工程效率**和**知识效率**，理论+实践才是学习的捷径。

这篇主要记录自己为了写eBPF跟踪TCP队列溢出程序，而进行的检索和扩展学习过程。

## 2. TCP相关tracepoint

查看有哪些可用的TCP跟踪点，检索到Brendan Gregg大佬的这篇文章：[tcp-tracepoints](https://www.brendangregg.com/blog/2018-03-22/tcp-tracepoints.html)

不多，比想象中的少得多，可以通过如下方式查看：

1、方式1：通过 /sys/kernel/debug/tracing/available_events 文件查看

可看到直接相关的就8个

```sh
[root@localhost tracing]# grep -E "tcp:|sock:inet" /sys/kernel/debug/tracing/available_events
# 4.16新增
tcp:tcp_probe
tcp:tcp_retransmit_synack
tcp:tcp_rcv_space_adjust
tcp:tcp_destroy_sock
tcp:tcp_receive_reset
tcp:tcp_send_reset
tcp:tcp_retransmit_skb
# 4.16新增，可用于TCP分析的socket跟踪点
# 4.15中新增过tcp:tcp_set_state，不过4.16加的下述tracepoint是其超集，所以就把tcp:tcp_set_state去掉了
sock:inet_sock_set_state
```

2、方式2：`perf list 'tcp:*' 'sock:inet*'`

```sh
[root@localhost tracing]# perf list 'tcp:*' 'sock:inet*'

List of pre-defined events (to be used in -e):

  tcp:tcp_destroy_sock                               [Tracepoint event]
  tcp:tcp_probe                                      [Tracepoint event]
  tcp:tcp_rcv_space_adjust                           [Tracepoint event]
  tcp:tcp_receive_reset                              [Tracepoint event]
  tcp:tcp_retransmit_skb                             [Tracepoint event]
  tcp:tcp_retransmit_synack                          [Tracepoint event]
  tcp:tcp_send_reset                                 [Tracepoint event]

  sock:inet_sock_set_state                           [Tracepoint event]
```

3、方式3：通过bcc tools里的`tplist`查看

```sh
[root@localhost tracing]# /usr/share/bcc/tools/tplist | grep -E "tcp:|sock:inet" 
sock:inet_sock_set_state
tcp:tcp_retransmit_skb
tcp:tcp_send_reset
tcp:tcp_receive_reset
tcp:tcp_destroy_sock
tcp:tcp_rcv_space_adjust
tcp:tcp_retransmit_synack
tcp:tcp_probe
```

## 3. SEC(name)对应的eBPF类型

bcc/libbpf-tools/中有很多不同的`SEC(xxx)`类型，这个和 [eBPF学习实践系列（四） -- eBPF的各种追踪类型](https://xiaodongq.github.io/2024/06/19/ebpf-trace-type/) 里介绍的30来种`enum bpf_prog_type`枚举值是怎么对应起来的？

比如下面几个：

* `SEC("tracepoint/sock/inet_sock_set_state")`
    * bcc/libbpf-tools/tcplife.bpf.c
* `SEC("kprobe/tcp_v4_connect")`、`SEC("kretprobe/tcp_v4_connect")`
    * bcc/libbpf-tools/tcptracer.bpf.c
* `SEC("fentry/tcp_v4_connect")`
    * bcc/libbpf-tools/tcpconnlat.bpf.c

对应关系可**通过libbpf库中的`libbpf.c`中的bpf程序类型定义查看**

这是内核中libbpf.c：

```c
// linux-5.10.10\tools\lib\bpf\libbpf.c
static const struct bpf_sec_def section_defs[] = {
    BPF_PROG_SEC("socket",          BPF_PROG_TYPE_SOCKET_FILTER),
    BPF_PROG_SEC("sk_reuseport",        BPF_PROG_TYPE_SK_REUSEPORT),
    // SEC_DEF 这个宏会自动拼接BPF_PROG_TYPE_前缀：.prog_type = BPF_PROG_TYPE_##ptype
    SEC_DEF("kprobe/", KPROBE,
        .attach_fn = attach_kprobe),
    BPF_PROG_SEC("uprobe/",         BPF_PROG_TYPE_KPROBE),
    SEC_DEF("kretprobe/", KPROBE,
        .attach_fn = attach_kprobe),
    BPF_PROG_SEC("uretprobe/",      BPF_PROG_TYPE_KPROBE),
    BPF_PROG_SEC("classifier",      BPF_PROG_TYPE_SCHED_CLS),
    BPF_PROG_SEC("action",          BPF_PROG_TYPE_SCHED_ACT),
    SEC_DEF("tracepoint/", TRACEPOINT,
        .attach_fn = attach_tp),
    SEC_DEF("tp/", TRACEPOINT,
        .attach_fn = attach_tp),
    ...
}
```

对应可知归属eBPF程序类型分别为：

* `SEC("tracepoint/sock/inet_sock_set_state")`
    * BPF_PROG_TYPE_TRACEPOINT
* `SEC("kprobe/tcp_v4_connect")`、`SEC("kretprobe/tcp_v4_connect")`
    * BPF_PROG_TYPE_KPROBE
* `SEC("fentry/tcp_v4_connect")`
    * BPF_PROG_TYPE_TRACING

这是ibbpf-bootstrap项目中的libbpf.c，展开宏后逻辑一样的：

```c
// libbpf-bootstrap-master\bpftool\libbpf\src\libbpf.c
static const struct bpf_sec_def section_defs[] = {
    // SEC_DEF 这个宏会自动拼接BPF_PROG_TYPE_前缀：.prog_type = BPF_PROG_TYPE_##ptype
    SEC_DEF("socket",       SOCKET_FILTER, 0, SEC_NONE),
    SEC_DEF("sk_reuseport/migrate", SK_REUSEPORT, BPF_SK_REUSEPORT_SELECT_OR_MIGRATE, SEC_ATTACHABLE),
    SEC_DEF("sk_reuseport",     SK_REUSEPORT, BPF_SK_REUSEPORT_SELECT, SEC_ATTACHABLE),
    SEC_DEF("kprobe+",      KPROBE, 0, SEC_NONE, attach_kprobe),
    SEC_DEF("uprobe+",      KPROBE, 0, SEC_NONE, attach_uprobe),
    ...
    SEC_DEF("perf_event",       PERF_EVENT, 0, SEC_NONE),
    ...
    SEC_DEF("sk_skb",       SK_SKB, 0, SEC_NONE),
    ...
    SEC_DEF("cgroup/setsockopt",    CGROUP_SOCKOPT, BPF_CGROUP_SETSOCKOPT, SEC_ATTACHABLE),
    SEC_DEF("cgroup/dev",       CGROUP_DEVICE, BPF_CGROUP_DEVICE, SEC_ATTACHABLE_OPT),
    SEC_DEF("struct_ops+",      STRUCT_OPS, 0, SEC_NONE),
    SEC_DEF("struct_ops.s+",    STRUCT_OPS, 0, SEC_SLEEPABLE),
    SEC_DEF("sk_lookup",        SK_LOOKUP, BPF_SK_LOOKUP, SEC_ATTACHABLE),
    SEC_DEF("netfilter",        NETFILTER, BPF_NETFILTER, SEC_NONE),
};
```

## 4. 具体分析 tcplife.bpf.c

[tcp-tracepoints](https://www.brendangregg.com/blog/2018-03-22/tcp-tracepoints.html) 中举例提及了`tcplife`在BCC和libbpf前后的对比。

这里重点跟踪一下：

* [bcc/libbpf-tools/tcplife.bpf.c](https://github.com/iovisor/bcc/blob/master/libbpf-tools/tcplife.bpf.c)
* 对比 [bcc/tools/tcplife.py](https://github.com/iovisor/bcc/blob/master/tools/tcplife.py)

并结合这篇文章译文：[BCC 到 libbpf 的转换指南【译】](https://www.ebpf.top/post/bcc-to-libbpf-guid/)，后续碰到libbpf程序应该都可以顺利拆解了。

### 4.1. 追踪点sock:inet_sock_set_state的参数

查看参数格式：（`tcptracer`工具也是用的这个追踪点）

可以看到这里还很友好地把TCP状态的枚举名称也对应起来了。

（关于`TCP_NEW_SYN_RECV`状态，我们在[TCP半连接全连接（二） -- 半连接队列代码逻辑](https://xiaodongq.github.io/2024/05/30/tcp_syn_queue/)中还分析过netstat里是追踪不到的）

```sh
[root@xdlinux ➜ ~ ]$ cat /sys/kernel/debug/tracing/events/sock/inet_sock_set_state/format 
name: inet_sock_set_state
ID: 1250
format:
    field:unsigned short common_type;	offset:0;	size:2;	signed:0;
    field:unsigned char common_flags;	offset:2;	size:1;	signed:0;
    field:unsigned char common_preempt_count;	offset:3;	size:1;	signed:0;
    field:int common_pid;	offset:4;	size:4;	signed:1;

    field:const void * skaddr;	offset:8;	size:8;	signed:0;
    field:int oldstate;	offset:16;	size:4;	signed:1;
    field:int newstate;	offset:20;	size:4;	signed:1;
    field:__u16 sport;	offset:24;	size:2;	signed:0;
    field:__u16 dport;	offset:26;	size:2;	signed:0;
    field:__u16 family;	offset:28;	size:2;	signed:0;
    field:__u8 protocol;	offset:30;	size:1;	signed:0;
    field:__u8 saddr[4];	offset:31;	size:4;	signed:0;
    field:__u8 daddr[4];	offset:35;	size:4;	signed:0;
    field:__u8 saddr_v6[16];	offset:39;	size:16;	signed:0;
    field:__u8 daddr_v6[16];	offset:55;	size:16;	signed:0;

print fmt: "family=%s protocol=%s sport=%hu dport=%hu saddr=%pI4 daddr=%pI4 saddrv6=%pI6c daddrv6=%pI6c oldstate=%s newstate=%s", 
    __print_symbolic(REC->family, { 2, "AF_INET" }, { 10, "AF_INET6" }), 
    __print_symbolic(REC->protocol, { 6, "IPPROTO_TCP" }, { 33, "IPPROTO_DCCP" }, { 132, "IPPROTO_SCTP" }, { 262, "IPPROTO_MPTCP" }), 
    REC->sport, REC->dport, REC->saddr, REC->daddr, REC->saddr_v6, REC->daddr_v6, 
    __print_symbolic(REC->oldstate, { 1, "TCP_ESTABLISHED" }, { 2, "TCP_SYN_SENT" }, { 3, "TCP_SYN_RECV" }, { 4, "TCP_FIN_WAIT1" }, { 5, "TCP_FIN_WAIT2" }, { 6, "TCP_TIME_WAIT" }, { 7, "TCP_CLOSE" }, { 8, "TCP_CLOSE_WAIT" }, { 9, "TCP_LAST_ACK" }, { 10, "TCP_LISTEN" }, { 11, "TCP_CLOSING" }, { 12, "TCP_NEW_SYN_RECV" }), 
    __print_symbolic(REC->newstate, { 1, "TCP_ESTABLISHED" }, { 2, "TCP_SYN_SENT" }, { 3, "TCP_SYN_RECV" }, { 4, "TCP_FIN_WAIT1" }, { 5, "TCP_FIN_WAIT2" }, { 6, "TCP_TIME_WAIT" }, { 7, "TCP_CLOSE" }, { 8, "TCP_CLOSE_WAIT" }, { 9, "TCP_LAST_ACK" }, { 10, "TCP_LISTEN" }, { 11, "TCP_CLOSING" }, { 12, "TCP_NEW_SYN_RECV" })
[root@xdlinux ➜ ~ ]$
```

### 4.2. 如何eBPF helper函数说明

系统libbpf的include下的bpf.h里可以看到各helper函数功能介绍

（linux-5.10.10\include\uapi\linux\bpf.h或者bcc-master\src\cc\libbpf\include\uapi\linux\bpf.h）

### 4.3. 代码分析

代码整体贴过来：

```c
// bcc/libbpf-tools/tcplife.bpf.c

// SPDX-License-Identifier: GPL-2.0
/* Copyright (c) 2022 Hengqi Chen */
#include <vmlinux.h>
#include <bpf/bpf_core_read.h>
#include <bpf/bpf_helpers.h>
#include <bpf/bpf_tracing.h>
#include "tcplife.h"

#define MAX_ENTRIES	10240
#define AF_INET		2
#define AF_INET6	10

const volatile bool filter_sport = false;
const volatile bool filter_dport = false;
const volatile __u16 target_sports[MAX_PORTS] = {};
const volatile __u16 target_dports[MAX_PORTS] = {};
const volatile pid_t target_pid = 0;
const volatile __u16 target_family = 0;

// 这里是libbpf里面使用BPF map的方式
/*
    BCC 中 Map 的默认大小是10240 。使用 libbpf，你必须明确指定大小
    作为对比，按参考译文的规则，BCC里面的方式是这样：
        BPF_HASH(birth, struct sock *, __u64);
    看 tcplife.py里的bcc代码段确实如此：
        BPF_HASH(birth, struct sock *, u64);
*/
struct {
    __uint(type, BPF_MAP_TYPE_HASH);
    __uint(max_entries, MAX_ENTRIES);
    __type(key, struct sock *);
    __type(value, __u64);
} birth SEC(".maps");

struct {
    __uint(type, BPF_MAP_TYPE_HASH);
    __uint(max_entries, MAX_ENTRIES);
    __type(key, struct sock *);
    __type(value, struct ident);
} idents SEC(".maps");

/*
    这里也做一下BCC和libbpf的对比，BPF_MAP_TYPE_PERF_EVENT_ARRAY 对应 BPF_PERF_OUTPUT
        reference_guide.md 里，可以看到 BPF_PERF_OUTPUT 的解释说明
            创建一个BPF表来通过 perf环形缓冲区 将自定义事件数据推送到用户空间。这是将每事件数据推送到用户空间的首选方法。
            Perf环形缓冲区是Linux内核中的一个高性能事件收集机制，它可以收集各种硬件和软件性能事件，并将它们存储在一个高效的环形缓冲区中。
            然后，用户空间的应用程序可以通过读取这个环形缓冲区来获取事件数据，进行进一步的分析和处理。
        另外，kernel-versions.md 里可以查看各BPF类型是哪个内核版本引入的，比如 BPF_PROG_TYPE_KPROBE 就是 4.1 引入
    BCC中的方式如下：
        BPF_PERF_OUTPUT(events)
*/
struct {
    __uint(type, BPF_MAP_TYPE_PERF_EVENT_ARRAY);
    __uint(key_size, sizeof(__u32));
    __uint(value_size, sizeof(__u32));
} events SEC(".maps");

SEC("tracepoint/sock/inet_sock_set_state")
int inet_sock_set_state(struct trace_event_raw_inet_sock_set_state *args)
{
    __u64 ts, *start, delta_us, rx_b, tx_b;
    struct ident ident = {}, *identp;
    __u16 sport, dport, family;
    struct event event = {};
    struct tcp_sock *tp;
    struct sock *sk;
    bool found;
    __u32 pid;
    int i;

    // 通过上面cat查看`sock:inet_sock_set_state`这个tracepoint的format，就更容易看懂下面的逻辑了（tcp状态枚举值还做了名称的对应）
    // bcc到libbpf的转变：原来的 tsk->parent->pid 方式，替换为 BPF_CORE_READ(tsk, parent, pid) 方式
        // BCC 会默默地重写你的 BPF 代码，并将诸如 tsk->parent->pid 之类的字段访问转换为一系列 bpf_probe_read() 调用
    //  各转变方式可以看这篇译文：https://www.ebpf.top/post/bcc-to-libbpf-guid/
        // BPF_CORE_READ 宏也可在 BCC 模式下工作
    if (BPF_CORE_READ(args, protocol) != IPPROTO_TCP)
        return 0;

    family = BPF_CORE_READ(args, family);
    if (target_family && family != target_family)
        return 0;

    sport = BPF_CORE_READ(args, sport);
    if (filter_sport) {
        found = false;
        for (i = 0; i < MAX_PORTS; i++) {
            if (!target_sports[i])
                return 0;
            if (sport != target_sports[i])
                continue;
            found = true;
            break;
        }
        if (!found)
            return 0;
    }

    dport = BPF_CORE_READ(args, dport);
    if (filter_dport) {
        found = false;
        for (i = 0; i < MAX_PORTS; i++) {
            if (!target_dports[i])
                return 0;
            if (dport != target_dports[i])
                continue;
            found = true;
            break;
        }
        if (!found)
            return 0;
    }

    // format里是一个void*
    sk = (struct sock *)BPF_CORE_READ(args, skaddr);
    if (BPF_CORE_READ(args, newstate) < TCP_FIN_WAIT1) {
        // helper函数，获取系统启动到现在的时间
        // 系统libbpf的include下的bpf.h里可以看到各helper函数功能介绍
        // （linux-5.10.10\include\uapi\linux\bpf.h或者bcc-master\src\cc\libbpf\include\uapi\linux\bpf.h）
        ts = bpf_ktime_get_ns();
        /*
            helper函数，可以bpftool feature |less里面查找各程序类型支持的helper函数，比如下面tracepoint类型:
            eBPF helpers supported for program type tracepoint:
            - bpf_map_lookup_elem
            - bpf_map_update_elem
            - bpf_map_delete_elem
        */
        // 声明和参数说明到bpf.h里看：long bpf_map_update_elem(struct bpf_map *map, const void *key, const void *value, u64 flags)
            // 功能是向 map 里面添加或者更新元素(key,value)
            // map：指向要更新的eBPF映射的指针。这个映射必须已经通过bpf()系统调用或其他方式在**内核中**创建。
            // key：指向要更新的元素的键的指针。键的类型和大小取决于映射的定义。
            // value：指向新值的指针。这个值将替换映射中与给定键关联的旧值。值的类型和大小同样取决于映射的定义。
        // ~~这里是个错误示例，通过代码跳转到了：int bpf_map_update_elem(int fd, const void *key, const void *value, __u64 flags)~~
        // birth是上面定义的BPF map，相当于bcc里面的BPF_HASH(birth, struct sock *, u64); 这个是创建在内核中的
        bpf_map_update_elem(&birth, &sk, &ts, BPF_ANY);
    }

    if (BPF_CORE_READ(args, newstate) == TCP_SYN_SENT || BPF_CORE_READ(args, newstate) == TCP_LAST_ACK) {
        pid = bpf_get_current_pid_tgid() >> 32;
        if (target_pid && pid != target_pid)
            return 0;
        ident.pid = pid;
        // 声明：long bpf_get_current_comm(void *buf, u32 size_of_buf)
        // 拷贝 comm 属性到 buf，具体是啥待定，format前面几个字段？
        bpf_get_current_comm(ident.comm, sizeof(ident.comm));
        // map<struct sock *, struct indent>，这个map也是创建在内核中的
        bpf_map_update_elem(&idents, &sk, &ident, BPF_ANY);
    }

    if (BPF_CORE_READ(args, newstate) != TCP_CLOSE)
        return 0;

    // void *bpf_map_lookup_elem(struct bpf_map *map, const void *key)
    // 根据 key 查找 map，返回是key映射value的地址，这是一个内核态的指针
    start = bpf_map_lookup_elem(&birth, &sk);
    if (!start) {
        bpf_map_delete_elem(&idents, &sk);
        return 0;
    }
    ts = bpf_ktime_get_ns();
    delta_us = (ts - *start) / 1000;

    identp = bpf_map_lookup_elem(&idents, &sk);
    pid = identp ? identp->pid : bpf_get_current_pid_tgid() >> 32;
    if (target_pid && pid != target_pid)
        goto cleanup;

    tp = (struct tcp_sock *)sk;
    rx_b = BPF_CORE_READ(tp, bytes_received);
    tx_b = BPF_CORE_READ(tp, bytes_acked);

    // 从内核态读取出来的内容，组合成一个 struct event （tcplife.h里自己定义了一个struct event）
    event.ts_us = ts / 1000;
    event.span_us = delta_us;
    event.rx_b = rx_b;
    event.tx_b = tx_b;
    event.pid = pid;
    event.sport = sport;
    event.dport = dport;
    event.family = family;
    if (!identp)
        bpf_get_current_comm(event.comm, sizeof(event.comm));
    else
        // long bpf_probe_read_kernel(void *dst, u32 size, const void *unsafe_ptr)
        // 安全地尝试从内核空间地址 unsafe_ptr 读取size大小的数据到dst
        bpf_probe_read_kernel(event.comm, sizeof(event.comm), (void *)identp->comm);
    if (family == AF_INET) {
        bpf_probe_read_kernel(&event.saddr, sizeof(args->saddr), BPF_CORE_READ(args, saddr));
        bpf_probe_read_kernel(&event.daddr, sizeof(args->daddr), BPF_CORE_READ(args, daddr));
    } else {	/*  AF_INET6 */
        bpf_probe_read_kernel(&event.saddr, sizeof(args->saddr_v6), BPF_CORE_READ(args, saddr_v6));
        bpf_probe_read_kernel(&event.daddr, sizeof(args->daddr_v6), BPF_CORE_READ(args, daddr_v6));
    }
    // 声明：long bpf_perf_event_output(void *ctx, struct bpf_map *map, u64 flags, void *data, u64 size)
        // 向性能事件缓冲区发送数据。性能事件缓冲区是内核中的环形缓冲区，可以被各种类型的事件触发，如硬件计数器或软件事件（如函数的进入和退出）
        // 要求把上下文一起传入，此处即args
        // tcplife.h里自己定义了一个struct event，此处是将 &event 发送给 events（前面创建的性能事件环形缓冲区）
            // BPF_F_CURRENT_CPU用来指定数据应该输出到当前 CPU 的本地性能事件缓冲区。在多核系统中，每个 CPU 可能都有自己的性能事件缓冲区
            // 使用 BPF_F_CURRENT_CPU 标志可以确保数据被发送到处理 eBPF 程序的当前 CPU 的缓冲区，这样可以避免跨 CPU 的数据传输，从而提高效率并减少竞争条件。
    bpf_perf_event_output(args, &events, BPF_F_CURRENT_CPU, &event, sizeof(event));

cleanup:
    // 声明：long bpf_map_delete_elem(struct bpf_map *map, const void *key)
    // 从 map 里清理 key对应的元素
    bpf_map_delete_elem(&birth, &sk);
    bpf_map_delete_elem(&idents, &sk);
    /*
        所以整体逻辑是
        1) 在内核态创建自定义全局数据结构：map或array，并创建性能事件ring buffer
        2) 通过ebpf(BPF_CORE_READ或bcc)从上下文中读取内容放在上述内核态结构中。这里可以做一些想要的判断处理逻辑，比如根据(key,value)写入
        3) 从上述内核态自定义结构中，提取信息组合后，投递到性能事件ring buffer里
        4）最后想要的是性能事件数组，可以清理单次的(key,value)
    */
    return 0;
}

char LICENSE[] SEC("license") = "GPL";
```

## 5. 参考

1、[tcp-tracepoints](https://www.brendangregg.com/blog/2018-03-22/tcp-tracepoints.html)

2、[BPF 进阶笔记（一）：BPF 程序（BPF Prog）类型详解：使用场景、函数签名、执行位置及程序示例](https://arthurchiao.art/blog/bpf-advanced-notes-1-zh)

3、[BCC 到 libbpf 的转换指南【译】](https://www.ebpf.top/post/bcc-to-libbpf-guid/)

4、GPT
