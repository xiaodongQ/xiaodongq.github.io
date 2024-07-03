---
layout: post
title: TCP半连接全连接（四） -- eBPF跟踪全连接队列溢出（下）
categories: 网络
tags: 网络
---

* content
{:toc}

通过eBPF跟踪TCP全连接队列溢出现象并进行分析，基于libbpf和bpftrace。



## 1. 说明

继续上一篇 [TCP半连接全连接（三） -- eBPF跟踪全连接队列溢出（上）](https://xiaodongq.github.io/2024/06/23/bcctools-trace-tcp_connect/)

*说明：本博客作为个人学习实践笔记，可供参考但非系统教程，可能存在错误或遗漏，欢迎指正。若需系统学习，建议参考原链接。*

## 2. libbpf跟踪

基于libbpf-bootstrap框架，先参考bcc项目中的 `tcpdrop.py`和`tcplife.bpf.c`进行移植，跟踪tracepoint：`skb:kfree_skb`，后面再扩展

这里摘抄部分代码内容，移植过程中可以更直观感受到BCC和libbpf（支持CO-RE）的数据结构区别，完整代码放在[这里](https://github.com/xiaodongQ/prog-playground/tree/main/network/ebpf/libbpf_tcptrace)。

先说下结果：编译成功，运行报错（还准备扩展的，第一步就夭折了。。）

### 2.1. test_tcptrace.bpf.c

```c
// libbpf方式，不需要包含内核头文件，只要包含一个vmlinux.h和几个libbpf帮助头文件
// #include <linux/bpf.h>
// #include <linux/skbuff.h>

#include "vmlinux.h"
#include <bpf/bpf_helpers.h>
#include <bpf/bpf_core_read.h>
#include <bpf/bpf_tracing.h>

// 定义一个 struct ipv4_data_t结构，用作记录性能事件
#include "test_tcptrace.h"

// 原来BCC中的方式转换为libbpf方式的事件ring buffer，key可以传一个指针
// BPF_PERF_OUTPUT(ipv4_events);
struct {
    __uint(type, BPF_MAP_TYPE_PERF_EVENT_ARRAY);
    __uint(key_size, sizeof(__u32));
    __uint(value_size, sizeof(__u32));
} ipv4_events SEC(".maps");

...

SEC("tracepoint/skb/kfree_skb")
int handle_tp(struct trace_event_raw_kfree_skb *args)
{
 struct sk_buff *skb = (struct sk_buff*)BPF_CORE_READ(args, skbaddr);
 struct sock *sk = skb->sk;

    if (sk == NULL)
        return 0;

    __u32 pid = bpf_get_current_pid_tgid() >> 32;

    // pull in details from the packet headers and the sock struct
    __u16 family = sk->__sk_common.skc_family;
    char state = sk->__sk_common.skc_state;
    __u16 sport = 0, dport = 0;
    struct tcphdr *tcp = skb_to_tcphdr(skb);
    struct iphdr *ip = skb_to_iphdr(skb);
    __u8 tcpflags = ((__u8 *)tcp)[13];
    sport = tcp->source;
    dport = tcp->dest;

    // 只管 IPV4，暂不考虑IPV6
    if (family == AF_INET) {
        struct ipv4_data_t data4 = {};
        data4.pid = pid;
        data4.ip = 4;
        data4.saddr = ip->saddr;
        data4.daddr = ip->daddr;
        data4.dport = dport;
        data4.sport = sport;
        data4.state = state;
        data4.tcpflags = tcpflags;
        // 这里的 调用栈 是BCC里实现的宏，对应BPF_MAP_TYPE_STACK，实现调用栈功能有点复杂，暂不用
        // data4.stack_id = stack_traces.get_stackid(args, 0);
        // 换成libbpf方式操作性能事件
        // ipv4_events.perf_submit(args, &data4, sizeof(data4));
        bpf_perf_event_output(args, &ipv4_events, BPF_F_CURRENT_CPU, &data4, sizeof(data4));
    }

    return 0;
}
```

test_tcptrace.h：

```c
#define AF_INET    2
#define AF_INET6   10
 
// 作为丢包事件结构
struct ipv4_data_t {
    __u32 pid;
    __u64 ip; 
    __u32 saddr;
    __u32 daddr;
    __u16 sport;
    __u16 dport;
    __u8 state;
    __u8 tcpflags;
    __u32 stack_id;
};
```

### 2.2. test_tcptrace.c

```c
int main(int argc, char **argv) {
    struct test_tcptrace_bpf *skel;
    struct perf_buffer *pb = NULL;
    int err;

    /* Set up libbpf errors and debug info callback */
    libbpf_set_print(libbpf_print_fn);

    /* Open BPF application */
    skel = test_tcptrace_bpf__open();
    ...

    /* Load & verify BPF programs */
    err = test_tcptrace_bpf__load(skel);
    ...

    /* Attach tracepoint handler */
    err = test_tcptrace_bpf__attach(skel);
    ...

    // 从内核态的性能事件ring buffer里获取信息，handle_event回调用来进行数据处理
    pb = perf_buffer__new(bpf_map__fd(skel->maps.ipv4_events), PERF_BUFFER_PAGES,
                          handle_event, handle_lost_events, NULL, NULL);
    ...
    printf("%-8s %-7s %-2s %-20s > %-20s %s (%s)", "TIME", "PID", "IP",
           "SADDR:SPORT", "DADDR:DPORT", "STATE", "FLAGS");

    for (;;) {
        /* trigger our BPF program */
        err = perf_buffer__poll(pb, PERF_POLL_TIMEOUT_MS);
        ...
    }
    ...
}
```

### 2.3. 拷贝到libbpf-bootstrap中编译

拷贝3个文件到 libbpf-bootstrap/examples/c，向Makefile里新增test_tcptrace：

`APPS = test_tcptrace minimal minimal_legacy ...`

只编译这次的test_tcptrace即可：`make test_tcptrace`，编译得到二进制文件：`test_tcptrace`

### 2.4. 开始运行

理论上这个二进制文件可以拷贝分发到其他内核版本的机器运行了。

先本地运行，emmm 报错了：(TODO 待定位)

```sh
[root@xdlinux ➜ c git:(master) ✗ ]$ ./test_tcptrace 
libbpf: loading object 'test_tcptrace_bpf' from buffer
libbpf: elf: section(2) .symtab, size 168, link 1, flags 0, type=2
libbpf: elf: section(3) tracepoint/skb/kfree_skb, size 416, link 0, flags 6, type=1
libbpf: sec 'tracepoint/skb/kfree_skb': found program 'handle_tp' at insn offset 0 (0 bytes), code size 52 insns (416 bytes)
libbpf: elf: section(4) license, size 13, link 0, flags 3, type=1
libbpf: license of test_tcptrace_bpf is Dual BSD/GPL
libbpf: elf: section(5) .maps, size 24, link 0, flags 3, type=1
libbpf: elf: section(6) .reltracepoint/skb/kfree_skb, size 16, link 2, flags 0, type=9
libbpf: elf: section(7) .BTF, size 17944, link 0, flags 0, type=1
libbpf: elf: section(8) .BTF.ext, size 812, link 0, flags 0, type=1
libbpf: looking for externs among 7 symbols...
libbpf: collected 0 externs total
libbpf: map 'ipv4_events': at sec_idx 5, offset 0.
libbpf: map 'ipv4_events': found type = 4.
libbpf: map 'ipv4_events': found key_size = 4.
libbpf: map 'ipv4_events': found value_size = 4.
libbpf: sec '.reltracepoint/skb/kfree_skb': collecting relocation for section(3) 'tracepoint/skb/kfree_skb'
libbpf: sec '.reltracepoint/skb/kfree_skb': relo #0: insn #44 against 'ipv4_events'
libbpf: prog 'handle_tp': found map 0 (ipv4_events, sec 5, off 0) for insn #44
libbpf: object 'test_tcptrace_b': failed (-22) to create BPF token from '/sys/fs/bpf', skipping optional step...
libbpf: loaded kernel BTF from ''
libbpf: sec 'tracepoint/skb/kfree_skb': found 12 CO-RE relocations
libbpf: CO-RE relocating [8] struct trace_event_raw_kfree_skb: found target candidate [79041] struct trace_event_raw_kfree_skb in [vmlinux]
libbpf: prog 'handle_tp': relo #0: <byte_off> [8] struct trace_event_raw_kfree_skb.skbaddr (0:1 @ offset 8)
libbpf: prog 'handle_tp': relo #0: matching candidate #0 <byte_off> [79041] struct trace_event_raw_kfree_skb.skbaddr (0:1 @ offset 8)
libbpf: prog 'handle_tp': relo #0: patched insn #1 (ALU/ALU64) imm 8 -> 8
libbpf: CO-RE relocating [18] struct sk_buff: found target candidate [3530] struct sk_buff in [vmlinux]
libbpf: prog 'handle_tp': relo #1: <byte_off> [18] struct sk_buff.sk (0:1:0 @ offset 24)
libbpf: prog 'handle_tp': relo #1: matching candidate #0 <byte_off> [3530] struct sk_buff.sk (0:1:0 @ offset 24)
libbpf: prog 'handle_tp': relo #1: patched insn #9 (LDX/ST/STX) off 24 -> 24
libbpf: CO-RE relocating [71] struct sock: found target candidate [3327] struct sock in [vmlinux]
libbpf: prog 'handle_tp': relo #2: <byte_off> [71] struct sock.__sk_common.skc_family (0:0:3 @ offset 16)
libbpf: prog 'handle_tp': relo #2: matching candidate #0 <byte_off> [3327] struct sock.__sk_common.skc_family (0:0:3 @ offset 16)
libbpf: prog 'handle_tp': relo #2: patched insn #12 (LDX/ST/STX) off 16 -> 16
libbpf: prog 'handle_tp': relo #3: <byte_off> [71] struct sock.__sk_common.skc_state (0:0:4 @ offset 18)
libbpf: prog 'handle_tp': relo #3: matching candidate #0 <byte_off> [3327] struct sock.__sk_common.skc_state (0:0:4 @ offset 18)
libbpf: prog 'handle_tp': relo #3: patched insn #13 (LDX/ST/STX) off 18 -> 18
libbpf: prog 'handle_tp': relo #4: <byte_off> [18] struct sk_buff.transport_header (0:20:0:45 @ offset 182)
libbpf: prog 'handle_tp': relo #4: matching candidate #0 <byte_off> [3530] struct sk_buff.transport_header (0:68 @ offset 194)
libbpf: prog 'handle_tp': relo #4: patched insn #14 (LDX/ST/STX) off 182 -> 194
libbpf: prog 'handle_tp': relo #5: <byte_off> [18] struct sk_buff.head (0:23 @ offset 200)
libbpf: prog 'handle_tp': relo #5: matching candidate #0 <byte_off> [3530] struct sk_buff.head (0:77 @ offset 224)
libbpf: prog 'handle_tp': relo #5: patched insn #15 (LDX/ST/STX) off 200 -> 224
libbpf: CO-RE relocating [207] struct tcphdr: found target candidate [39823] struct tcphdr in [vmlinux]
libbpf: prog 'handle_tp': relo #6: <byte_off> [207] struct tcphdr.dest (0:1 @ offset 2)
libbpf: prog 'handle_tp': relo #6: matching candidate #0 <byte_off> [39823] struct tcphdr.dest (0:1 @ offset 2)
libbpf: prog 'handle_tp': relo #6: patched insn #18 (LDX/ST/STX) off 2 -> 2
libbpf: prog 'handle_tp': relo #7: <byte_off> [207] struct tcphdr.source (0:0 @ offset 0)
libbpf: prog 'handle_tp': relo #7: matching candidate #0 <byte_off> [39823] struct tcphdr.source (0:0 @ offset 0)
libbpf: prog 'handle_tp': relo #7: patched insn #19 (LDX/ST/STX) off 0 -> 0
libbpf: prog 'handle_tp': relo #8: <byte_off> [18] struct sk_buff.head (0:23 @ offset 200)
libbpf: prog 'handle_tp': relo #8: matching candidate #0 <byte_off> [3530] struct sk_buff.head (0:77 @ offset 224)
libbpf: prog 'handle_tp': relo #8: patched insn #20 (LDX/ST/STX) off 200 -> 224
libbpf: prog 'handle_tp': relo #9: <byte_off> [18] struct sk_buff.network_header (0:20:0:46 @ offset 184)
libbpf: prog 'handle_tp': relo #9: matching candidate #0 <byte_off> [3530] struct sk_buff.network_header (0:69 @ offset 196)
libbpf: prog 'handle_tp': relo #9: patched insn #21 (LDX/ST/STX) off 184 -> 196
libbpf: CO-RE relocating [209] struct iphdr: found target candidate [39845] struct iphdr in [vmlinux]
libbpf: prog 'handle_tp': relo #10: <byte_off> [209] struct iphdr.saddr (0:9:0:0 @ offset 12)
libbpf: prog 'handle_tp': relo #10: matching candidate #0 <byte_off> [39845] struct iphdr.saddr (0:9 @ offset 12)
libbpf: prog 'handle_tp': relo #10: patched insn #33 (LDX/ST/STX) off 12 -> 12
libbpf: prog 'handle_tp': relo #11: <byte_off> [209] struct iphdr.daddr (0:9:0:1 @ offset 16)
libbpf: prog 'handle_tp': relo #11: matching candidate #0 <byte_off> [39845] struct iphdr.daddr (0:10 @ offset 16)
libbpf: prog 'handle_tp': relo #11: patched insn #35 (LDX/ST/STX) off 16 -> 16
libbpf: map 'ipv4_events': setting size to 32
libbpf: map 'ipv4_events': created successfully, fd=3
libbpf: prog 'handle_tp': BPF program load failed: Permission denied
libbpf: prog 'handle_tp': -- BEGIN PROG LOAD LOG --
Unrecognized arg#0 type PTR
; int handle_tp(struct trace_event_raw_kfree_skb *args)
0: (bf) r6 = r1
1: (b7) r1 = 8
2: (bf) r3 = r6
3: (0f) r3 += r1
last_idx 3 first_idx 0
regs=2 stack=0 before 2: (bf) r3 = r6
regs=2 stack=0 before 1: (b7) r1 = 8
4: (bf) r1 = r10
; 
5: (07) r1 += -40
; struct sk_buff *skb = (struct sk_buff*)BPF_CORE_READ(args, skbaddr);
6: (b7) r2 = 8
7: (85) call bpf_probe_read_kernel#113
last_idx 7 first_idx 0
regs=4 stack=0 before 6: (b7) r2 = 8
; struct sk_buff *skb = (struct sk_buff*)BPF_CORE_READ(args, skbaddr);
8: (79) r7 = *(u64 *)(r10 -40)
; struct sock *sk = skb->sk;
9: (79) r8 = *(u64 *)(r7 +24)
R7 invalid mem access 'inv'
processed 10 insns (limit 1000000) max_states_per_insn 0 total_states 0 peak_states 0 mark_read 0
-- END PROG LOAD LOG --
libbpf: prog 'handle_tp': failed to load: -13
libbpf: failed to load object 'test_tcptrace_bpf'
libbpf: failed to load BPF skeleton 'test_tcptrace_bpf': -13
Failed to load and verify BPF skeleton
```

### 2.5. 失败心得

虽然运行失败了，迁移过程还是有收获的。

原来的tcpdrop里还有调用栈打印，使用是BCC里实现的`BPF_STACK_TRACE(stack_traces, 1024);`机制，其中用到了`BPF_MAP_TYPE_STACK`的eBPF程序类型。

基于libbpf-bootstrap看示例里没有这个轮子，自己实现的话有点复杂。看来还是有必要用用BCC，毕竟轮子和参考示例会多不少。

## 3. bpftrace跟踪

先降低难度使用[bpftrace](https://github.com/bpftrace/bpftrace)吧。。

这里记录了bpftrace学习使用：[eBPF学习实践系列（六） -- bpftrace学习和使用](https://xiaodongq.github.io/2024/06/28/ebpf-bpftrace-learn/)

### 3.1. 尝试tcpdrop.bt跟踪

直接先试试bpftrace项目tools里的 tcpdrop.bt 跟踪全连接队列溢出

若是yum安装的bpftrace，tools默认安装在：`/usr/share/bpftrace/tools`

执行`./tcpdrop.bt`报错了：

```sh
[root@xdlinux ➜ tools ]$ pwd
/usr/share/bpftrace/tools
[root@xdlinux ➜ tools ]$ ./tcpdrop.bt
definitions.h:3:10: fatal error: 'net/sock.h' file not found
```

[之前](https://xiaodongq.github.io/2024/06/12/record-failed-expend-space/)重装系统时内核小版本不对应，应该是内核头文件没有

查看安装匹配的：kernel-headers

```sh
# 查看安装的kernel-headers
[root@xdlinux ➜ tools ]$ rpm -qa|grep kernel-head
kernel-headers-4.18.0-348.el8.x86_64
# 和当前内核并不匹配（小版本不同）
[root@xdlinux ➜ tools ]$ uname -r
4.18.0-348.7.1.el8_5.x86_64

# 查找安装匹配的kernel-headers
[root@xdlinux ➜ tools ]$ yum list kernel-headers
Last metadata expiration check: 4:30:45 ago on Sat 29 Jun 2024 07:58:12 AM CST.
Installed Packages
kernel-headers.x86_64             4.18.0-348.el8          @anaconda
Available Packages
kernel-headers.x86_64             4.18.0-348.7.1.el8_5    base

# 安装成功
[root@xdlinux ➜ tools ]$ yum install kernel-headers.x86_64 
Last metadata expiration check: 0:05:25 ago on Sat 29 Jun 2024 12:29:12 PM CST.
Package kernel-headers-4.18.0-348.el8.x86_64 is already installed.
Dependencies resolved.
=====================================================================================
 Package           Architecture     Version                  Repository Size
=====================================================================================
Upgrading:
 kernel-headers    x86_64           4.18.0-348.7.1.el8_5     base       8.3 M

Transaction Summary
=====================================================================================
Upgrade  1 Package

Total download size: 8.3 M
Is this ok [y/N]: y
Downloading Packages:
kernel-headers-4.18.0-348.7.1.el8_5.x86_64.rpm       2.3 MB/s | 8.3 MB     00:03
-------------------------------------------------------------------------------
Total                                                2.3 MB/s | 8.3 MB     00:03
Running transaction check
Transaction check succeeded.
Running transaction test
Transaction test succeeded.
Running transaction
  Preparing        :                                               1/1 
  Upgrading        : kernel-headers-4.18.0-348.7.1.el8_5.x86_64    1/2 
  Cleanup          : kernel-headers-4.18.0-348.el8.x86_64          2/2 
  Verifying        : kernel-headers-4.18.0-348.7.1.el8_5.x86_64    1/2 
  Verifying        : kernel-headers-4.18.0-348.el8.x86_64          2/2 

Upgraded:
  kernel-headers-4.18.0-348.7.1.el8_5.x86_64 

Complete!
[root@xdlinux ➜ tools ]$ 
```

重试还是报错，kernel-devel也装一下：`yum install kernel-devel`

再次重试，可以了。**不过没抓到内容。**

查看当前版本的tcpdrop.bt里面跟踪的是`kprobe:tcp_drop`（bpftrace-0.12.1-3.el8.x86_64）

```sh
[root@xdlinux ➜ tools git:(master) ]$ rpm -qa|grep bpftrace
bpftrace-0.12.1-3.el8.x86_64
[root@xdlinux ➜ tools git:(master) ]$ bpftrace -l "kprobe:tcp_drop"
kprobe:tcp_drop
```

### 3.2. 对比bcc tools结果分析

结果对比：

* 上小节`tcpdrop.bt`没抓到服务端全连接队列满时的drop包；
* 在[TCP半连接全连接（三） -- eBPF跟踪全连接队列溢出（上）](https://xiaodongq.github.io/2024/06/23/bcctools-trace-tcp_connect/)里用bcc的`tcpdrop`也没抓到服务端drop包，当时遗留了一个TODO项：“TODO tcpdrop的应用场景没理解到位？待跟eBPF主动监测对比”

之前以为是工具理解不到位，到这里基本可以排除了。工具对应的下述两个追踪点确实就是没有触发到：

* kprobe:tcp_drop
* tracepoint/skb/kfree_skb

继续来看一下内核中服务端收到SYN时的处理代码（`tcp_v4_conn_request` -> `tcp_conn_request`）

```cpp
// linux-5.10.10/net/ipv4/tcp_input.c
// 处理第一次SYN请求
int tcp_conn_request(struct request_sock_ops *rsk_ops,
             const struct tcp_request_sock_ops *af_ops,
             struct sock *sk, struct sk_buff *skb)
{
    ...
    // tcp_syncookies：1表示当半连接队列满时才开启；2表示无条件开启功能，此处可看到就算半连接队列满了也不drop
    // inet_csk_reqsk_queue_is_full：判断半连接队列是否满(相对于4.4之前的内核，之后内核中半连接队列最大长度也和全连接队列一样)
    if ((net->ipv4.sysctl_tcp_syncookies == 2 ||
         inet_csk_reqsk_queue_is_full(sk)) && !isn) {
        want_cookie = tcp_syn_flood_action(sk, rsk_ops->slab_name);
        if (!want_cookie)
            goto drop;
    }
    ...
    // 检查当前 sock 的全连接队列是否满
    if (sk_acceptq_is_full(sk)) {
        NET_INC_STATS(sock_net(sk), LINUX_MIB_LISTENOVERFLOWS);
        goto drop;
    }
    // 创建一个request_sock，socket状态为：TCP_NEW_SYN_RECV;
    // 里面包含一个引用计数，涉及sock的管理，4.4做的内存优化，暂忽略
    // 这里第3个参数，如果没开启cookie则传入true，一般是开的，所以传false
    req = inet_reqsk_alloc(rsk_ops, sk, !want_cookie);
    if (!req)
        goto drop;
    ...
    if (!want_cookie && !isn) {
        // 没开启syncookies时，若 `max_syn_backlog - 半连接长度` < max_syn_backlog>>2，则丢弃请求包
        if (!net->ipv4.sysctl_tcp_syncookies &&
            (net->ipv4.sysctl_max_syn_backlog - inet_csk_reqsk_queue_len(sk) <
             (net->ipv4.sysctl_max_syn_backlog >> 2)) &&
            !tcp_peer_is_proven(req, dst)) {
            ...
            goto drop_and_release;
        }
        ...
    }
    ...
    return 0;

drop_and_release:
    dst_release(dst);
drop_and_free:
    __reqsk_free(req);
drop:
    // 丢弃包
    tcp_listendrop(sk);
    return 0;
}
```

全连接、半连接溢出时都会到`tcp_listendrop`里面，查看其逻辑，确实是不涉及上述两个追踪点的。

```c
// linux-5.10.10/include/net/tcp.h
static inline void tcp_listendrop(const struct sock *sk)
{
    atomic_inc(&((struct sock *)sk)->sk_drops);
    __NET_INC_STATS(sock_net(sk), LINUX_MIB_LISTENDROPS);
}
```

### 3.3. bpftrace跟踪其他追踪点

**那可以直接追踪`tcp_listendrop`吗？**

查看并没有这个直接的追踪点，只有显式导出的内核函数才可以被eBPF进行动态跟踪：

```sh
[root@xdlinux ➜ tools ]$ bpftrace -l | grep tcp_listendrop
[root@xdlinux ➜ tools ]$ 
# 系统符号里也没有
[root@xdlinux ➜ tools ]$ grep tcp_listendrop /proc/kallsyms
[root@xdlinux ➜ tools ]$ 
```

那只能间接跟踪下了，通过分析代码里的tcp_listendrop上下文后设计跟踪脚本。  
调用链是：`tcp_v4_conn_request` -> `tcp_conn_request` -> `tcp_listendrop`，那我们查下前面的追踪点：

```sh
[root@xdlinux ➜ tools ]$ bpftrace -l | grep -E "tcp_v4_conn_request|tcp_conn_request"
kfunc:tcp_conn_request
kfunc:tcp_v4_conn_request
kprobe:tcp_conn_request
kprobe:tcp_v4_conn_request
```

可以看到前两者都有，那先跟踪下 `kprobe:tcp_conn_request`。

再翻看下上述`tcp_conn_request`函数的内核代码，其发生全连接队列溢出的位置如下：

```c
    // 检查当前 sock 的全连接队列是否满
    if (sk_acceptq_is_full(sk)) {
        NET_INC_STATS(sock_net(sk), LINUX_MIB_LISTENOVERFLOWS);
        goto drop;
    }
```

由于自己的实验环境有时是本地PC（4.18内核），有时是阿里云ECS（5.10内核），这里把两个版本的`sk_acceptq_is_full`和`tcp_conn_request`都贴一下。对比后差别并不大，不影响流程分析。

```c
// linux-4.18/include/net/sock.h
static inline bool sk_acceptq_is_full(const struct sock *sk)
{
    return sk->sk_ack_backlog > sk->sk_max_ack_backlog;
}

// linux-5.10.10/include/net/sock.h
static inline bool sk_acceptq_is_full(const struct sock *sk)
{
    return READ_ONCE(sk->sk_ack_backlog) > READ_ONCE(sk->sk_max_ack_backlog);
}
```

```c
// linux-4.18/net/ipv4/tcp_input.c
int tcp_conn_request(struct request_sock_ops *rsk_ops,
             const struct tcp_request_sock_ops *af_ops,
             struct sock *sk, struct sk_buff *skb);

// linux-5.10.10/net/ipv4/tcp_input.c
int tcp_conn_request(struct request_sock_ops *rsk_ops,
             const struct tcp_request_sock_ops *af_ops,
             struct sock *sk, struct sk_buff *skb)
```

把`struct sock`结构中的`sk->sk_ack_backlog`和`sk->sk_max_ack_backlog`进行对比，即可满足调用`tcp_listendrop`的条件。编写bpftrace脚本tcp_queue.bt（[这里](https://github.com/xiaodongQ/prog-playground/blob/main/network/ebpf/bpftrace_tcp_queue/tcp_queue.bt)有归档），内容如下：

```sh
#!/usr/bin/env bpftrace

/*
函数声明如下：
int tcp_conn_request(struct request_sock_ops *rsk_ops,
             const struct tcp_request_sock_ops *af_ops,
             struct sock *sk, struct sk_buff *skb)
*/

kprobe:tcp_conn_request
{
    // 注意：arg0表示函数的第1个参数
    $sk = (struct sock*)arg2;
    $inet_csk=(struct inet_connection_sock *)$sk;

    // 当前半连接队列长度，~~废弃：qlen这里貌似没办法获取到数量~~
    // qlen定义为`atomic_t	qlen;`，而atomic_t是一个结构体，需要再qlen.counter获取
    $syn_queue_num = $inet_csk->icsk_accept_queue.qlen.counter;
    // 半连接队列最大长度，4.4+的内核和全连接最大限制一样
    $syn_queue_max = $sk->sk_max_ack_backlog;
    // 当前全连接队列长度
    $accept_queue_num = $sk->sk_ack_backlog;
    // 全连接队列最大长度
    $accept_queue_max = $sk->sk_max_ack_backlog;

    printf( "syn_queue_num:%d, syn_queue_max:%d\n accept_queue_num:%d, accept_queue_max:%d\n", 
        $syn_queue_num, $syn_queue_max,
        $accept_queue_num, $accept_queue_max );
    
    if( $accept_queue_num > $accept_queue_max ){
        printf("call stack:%s\n", kstack);
    }
}
```

实验方式：

* `./server`起服务端并开启抓包（tcpdump -i any port 8080 -nn -w 8080.cap -v）
* 客户端手动测试，单次一个请求：`./client 192.168.1.150 1`

现象和结果分析：

* 客户端，请求6次提示成功；第7次失败，且阻塞一段时间（TCP重试，见后面服务端的抓包分析）

```sh
➜  tcp_connect git:(main) ✗ ./client 192.168.1.150 1
Message sent: helloworld
➜  tcp_connect git:(main) ✗ ./client 192.168.1.150 1
Message sent: helloworld
➜  tcp_connect git:(main) ✗ ./client 192.168.1.150 1
Message sent: helloworld
➜  tcp_connect git:(main) ✗ ./client 192.168.1.150 1
Message sent: helloworld
➜  tcp_connect git:(main) ✗ ./client 192.168.1.150 1
Message sent: helloworld
➜  tcp_connect git:(main) ✗ ./client 192.168.1.150 1
Message sent: helloworld
➜  tcp_connect git:(main) ✗ ./client 192.168.1.150 1
Connection Failed
```

* 服务端bpftrace结果如下，抓包文件在[这里](https://github.com/xiaodongQ/xiaodongq.github.io/tree/master/images/srcfiles/8080_server150-20240630.cap)

```sh
[root@xdlinux ➜ bpftrace_tcp_queue git:(main) ✗ ]$ ./tcp_queue.bt   
Attaching 1 probe...

syn_queue_num:0, syn_queue_max:5
 accept_queue_num:0, accept_queue_max:5
syn_queue_num:0, syn_queue_max:5
 accept_queue_num:1, accept_queue_max:5
syn_queue_num:0, syn_queue_max:5
 accept_queue_num:2, accept_queue_max:5
syn_queue_num:0, syn_queue_max:5
 accept_queue_num:3, accept_queue_max:5
syn_queue_num:0, syn_queue_max:5
 accept_queue_num:4, accept_queue_max:5
syn_queue_num:0, syn_queue_max:5
 accept_queue_num:5, accept_queue_max:5
# 这是第7次，客户端开始阻塞一段时间了，有13次`call stack:`打印，重传了12次
syn_queue_num:0, syn_queue_max:5
 accept_queue_num:6, accept_queue_max:5
call stack:
        tcp_conn_request+1
        tcp_rcv_state_process+532
        tcp_v4_do_rcv+180
        tcp_v4_rcv+3089
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

syn_queue_num:0, syn_queue_max:5
 accept_queue_num:6, accept_queue_max:5
call stack:
...
（略，`call stack:`一共打印了13次）
```

分析：

* 上面可看到全连接队列的数字依次从0增加到6，实际0-5这6次客户端请求才是正常的，即最大数量5+1（内核中从0开始计数）
* 第7次时就开始阻塞了，而上面`call stack`打印了13次，所以这里进行了12次SYN重传，结合抓包看也是相符的（至于为什么是12次，这里客户端是mac笔记本，就先不去纠结了 ）。这也解答了第一篇中的一个TODO项：drop的包是可以在tcpdump中抓到的（当前场景）
* 上述结果里半连接队列的长度一直是0，是由于开始半连接->全连接是正常的，半连接队列记录一直被实时取走；而全连接队列超出限制后，不允许新的半连接建立，半连接队列中也就没有记录了
* **所以这里我们通过bpftrace抓取到了全连接队列溢出的情况。**

```sh
# 服务端全连接队列情况
[root@xdlinux ➜ workspace ]$ ss -antp|grep -E "8080|Local" 
State  Recv-Q Send-Q Local Address:Port Peer Address:Port Process                                                 
LISTEN 6      5            0.0.0.0:8080      0.0.0.0:*     users:(("server",pid=27846,fd=3)) 

[root@xdlinux ➜ workspace ]$ netstat -anp|grep -E "8080|Local"
Proto Recv-Q Send-Q Local Address           Foreign Address         State       PID/Program name    
tcp        6      0 0.0.0.0:8080            0.0.0.0:*               LISTEN      27846/./server 
```

抓包：

![抓包结果](/images/2024-06-30-SYN-retrans.png)

这里也记录一下服务端的系统参数（CentOS8.5系统，4.18.0内核）：

```sh
[root@xdlinux ➜ workspace ]$ sysctl -a|grep -E "syn_backlog|somaxconn|syn_retries|synack_retries|syncookies|abort_on_overflow|net.ipv4.tcp_fin_timeout|tw_buckets|tw_reuse|tw_recycle|tcp_orphan_retries"
net.core.somaxconn = 128
net.ipv4.tcp_abort_on_overflow = 0
net.ipv4.tcp_fin_timeout = 60
net.ipv4.tcp_max_syn_backlog = 1024
net.ipv4.tcp_max_tw_buckets = 131072
net.ipv4.tcp_orphan_retries = 0
net.ipv4.tcp_syn_retries = 6
net.ipv4.tcp_synack_retries = 5
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_tw_reuse = 2
```

## 4. 小结

用libbpf和bpftrace跟踪TCP全连接溢出，最后用bpftrace成功抓到了。

## 5. 附：系列总结

到这里，TCP全连接、半连接学习实践先告一段落，做个小总结。

从开始的全连接、半连接队列不太清晰的概念，到深入代码和实践过程，建立起了相对扎实一点的体感，以后不犯怵了。

第一篇学习和实验过程中的疑问点和发现的问题，作为TODO项去啃。过程中发现ss/netstat在不同环境的表现差异，去跟踪源码确认；为了跟踪TCP相关过程开始学习实践eBPF，输出了eBPF学习实践系列笔记；在实验使用bcc tools构造丢包时，/boot空间不够，扩容搞崩了一次环境，也作为笔记记录了一下过程。

整个过程下来，常会出现之前输出的内容后面发现理解有偏差、或者表述不大好、或者低级错误，来回修改的过程也是模拟给人讲述的过程。体会是费曼学习法真是个有用的技巧，理论+实践是学习成长的捷径。

过程笔记顺序稍作了调整，包含：

* [TCP半连接全连接（一） -- 全连接队列相关过程](https://xiaodongq.github.io/2024/05/18/tcp_connect/)
* [TCP半连接全连接（二） -- 半连接队列代码逻辑](https://xiaodongq.github.io/2024/05/30/tcp_syn_queue/)
* [TCP半连接全连接（三） -- eBPF跟踪全连接队列溢出（上）](https://xiaodongq.github.io/2024/06/23/bcctools-trace-tcp_connect/)
* [TCP半连接全连接（四） -- eBPF跟踪全连接队列溢出（下）](https://xiaodongq.github.io/2024/06/26/libbpf-trace-tcp_connect/)

* [分析某环境中ss结果中Send-Q为0的原因](https://xiaodongq.github.io/2024/05/20/ss-sendq-0/)
* [分析netstat中的Send-Q和Recv-Q](https://xiaodongq.github.io/2024/05/27/netstat-code/)

* [eBPF学习实践系列（一） -- 初识eBPF](https://xiaodongq.github.io/2024/06/06/ebpf_learn/)
* [eBPF学习实践系列（二） -- bcc tools网络工具集](https://xiaodongq.github.io/2024/06/10/bcc-tools-network/)
* [eBPF学习实践系列（三） -- 基于libbpf开发实践](https://xiaodongq.github.io/2024/06/15/libbpf-future/)
* [eBPF学习实践系列（四） -- eBPF的各种追踪类型](https://xiaodongq.github.io/2024/06/19/ebpf-trace-type/)
* [eBPF学习实践系列（五） -- 分析tcplife.bpf.c程序](https://xiaodongq.github.io/2024/06/20/ebpf-practice-case/)
* [eBPF学习实践系列（六） -- bpftrace学习和使用](https://xiaodongq.github.io/2024/06/28/ebpf-bpftrace-learn/)
* [记一次失败的/boot分区扩容](https://xiaodongq.github.io/2024/06/12/record-failed-expend-space/)

## 6. 参考

1、[BCC 到 libbpf 的转换指南【译】](https://www.ebpf.top/post/bcc-to-libbpf-guid/)

2、[深入浅出eBPF｜你要了解的7个核心问题](https://juejin.cn/post/7110139083971624997)

3、[bpftrace](https://github.com/bpftrace/bpftrace)

4、[BCC项目](https://github.com/iovisor/bcc)
