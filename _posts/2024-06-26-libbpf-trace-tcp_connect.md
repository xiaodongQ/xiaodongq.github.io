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

继续上一篇

## 2. libbpf跟踪

基于libbpf-bootstrap框架，先参考bcc项目中的 `tcpdrop.py`和`tcplife.bpf.c`进行移植，跟踪tracepoint：`skb:kfree_skb`，后面再扩展

这里摘抄部分内容，移植过程中可以更直观感受到BCC和libbpf（支持CO-RE）的数据结构区别，完整代码放在[这里](https://github.com/xiaodongQ/prog-playground/tree/main/network/ebpf)。

先说下结果：编译成功，运行报错（还准备扩展，第一步就夭折了。。）

1、test_tcptrace.bpf.c

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

2、test_tcptrace.c

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

3、拷贝到 libbpf-bootstrap/examples/c 下面，修改Makefile并编译

向Makefile里新增test_tcptrace：

`APPS = test_tcptrace minimal minimal_legacy ...`

只编译这次的test_tcptrace即可：`make test_tcptrace`，编译得到二进制文件：`test_tcptrace`

4、开始运行（理论上这个二进制文件可以拷贝分发到其他内核版本的机器运行了）

但是报错了：(TODO 待定位)

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

## 3. bpftrace跟踪

先降级使用bpftrace吧。。




## 4. 小结


## 5. 参考

1、[BCC 到 libbpf 的转换指南【译】](https://www.ebpf.top/post/bcc-to-libbpf-guid/)

2、BCC项目
