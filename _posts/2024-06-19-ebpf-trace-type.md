---
layout: post
title: eBPF学习实践系列（四） -- eBPF的各种追踪类型
categories: eBPF
tags: eBPF libbpf
---

* content
{:toc}

eBPF追踪类型学习整理



## 1. 背景

前面涉及了helloworld级别程序的开发流程，本文梳理学习梳理各种追踪机制及使用方式。

先通过BCC和libbpf-bootstrap中的示例学习。

几种追踪机制：

* Tracepoints（Kernel Tracepoints），内核预定义跟踪点，跟踪特定事件或操作，是静态定义的
* Kprobes（Kernel Probes），内核探针，运行时动态挂接到内核代码
* Uprobes（User Probes），用户探针，运行时动态挂接到用户空间应用程序
* USDT（User Statically Defined Tracing），用户预定义跟踪点

此外还有不少其他类型，如：

* Socket Filter
    * 允许在网络层面对数据包进行过滤和分析。通过编写eBPF程序并附加到网络套接字上，可以实时捕获和分析网络流量，实现如流量分类、性能监控等任务
* Syscall Tracing
    * 追踪系统调用的执行情况

## 2. eBPF程序类型

> eBPF 程序通常包含用户态和内核态两部分：用户态程序通过 BPF 系统调用，完成 eBPF 程序的加载、事件挂载以及映射创建和更新，而内核态中的 eBPF 程序则需要通过 BPF 辅助函数完成所需的任务。

并不是所有的辅助函数都可以在 eBPF 程序中随意使用，不同类型的 eBPF 程序所支持的辅助函数是不同的。

在libbpf的`include/uapi/linux/bpf.h`中，查看`bpf_prog_type`即可看到类型。

5.10.10内核（LIBBPF_0.2.0）中的类型定义如下，其中有30种，高版本可能更多。

```sh
# linux-5.10.10/tools/include/uapi/linux/bpf.h
enum bpf_prog_type {
	BPF_PROG_TYPE_UNSPEC,
	BPF_PROG_TYPE_SOCKET_FILTER,
	BPF_PROG_TYPE_KPROBE,
	BPF_PROG_TYPE_SCHED_CLS,
	BPF_PROG_TYPE_SCHED_ACT,
	BPF_PROG_TYPE_TRACEPOINT,
	BPF_PROG_TYPE_XDP,
	BPF_PROG_TYPE_PERF_EVENT,
	BPF_PROG_TYPE_CGROUP_SKB,
	BPF_PROG_TYPE_CGROUP_SOCK,
	BPF_PROG_TYPE_LWT_IN,
	BPF_PROG_TYPE_LWT_OUT,
	BPF_PROG_TYPE_LWT_XMIT,
	BPF_PROG_TYPE_SOCK_OPS,
	BPF_PROG_TYPE_SK_SKB,
	BPF_PROG_TYPE_CGROUP_DEVICE,
	BPF_PROG_TYPE_SK_MSG,
	BPF_PROG_TYPE_RAW_TRACEPOINT,
	BPF_PROG_TYPE_CGROUP_SOCK_ADDR,
	BPF_PROG_TYPE_LWT_SEG6LOCAL,
	BPF_PROG_TYPE_LIRC_MODE2,
	BPF_PROG_TYPE_SK_REUSEPORT,
	BPF_PROG_TYPE_FLOW_DISSECTOR,
	BPF_PROG_TYPE_CGROUP_SYSCTL,
	BPF_PROG_TYPE_RAW_TRACEPOINT_WRITABLE,
	BPF_PROG_TYPE_CGROUP_SOCKOPT,
	BPF_PROG_TYPE_TRACING,
	BPF_PROG_TYPE_STRUCT_OPS,
	BPF_PROG_TYPE_EXT,
	BPF_PROG_TYPE_LSM,
	BPF_PROG_TYPE_SK_LOOKUP,
};
```

因为不同内核的版本和编译配置选项不同，一个内核并不会支持所有的程序类型。可以通过 `bpftool feature probe | grep program_type` 查询当前系统支持的程序类型。

```sh
# CentOS8.5系统
[root@xdlinux ➜ /root ]$ bpftool feature probe | grep program_type
eBPF program_type socket_filter is available
eBPF program_type kprobe is available
eBPF program_type sched_cls is available
eBPF program_type sched_act is available
eBPF program_type tracepoint is available
eBPF program_type xdp is available
eBPF program_type perf_event is available
eBPF program_type cgroup_skb is available
eBPF program_type cgroup_sock is available
eBPF program_type lwt_in is available
eBPF program_type lwt_out is available
eBPF program_type lwt_xmit is available
eBPF program_type sock_ops is available
eBPF program_type sk_skb is available
eBPF program_type cgroup_device is available
eBPF program_type sk_msg is available
eBPF program_type raw_tracepoint is available
eBPF program_type cgroup_sock_addr is available
eBPF program_type lwt_seg6local is available
eBPF program_type lirc_mode2 is NOT available
eBPF program_type sk_reuseport is available
eBPF program_type flow_dissector is available
eBPF program_type cgroup_sysctl is available
eBPF program_type raw_tracepoint_writable is available
eBPF program_type cgroup_sockopt is NOT available
eBPF program_type tracing is NOT available
eBPF program_type struct_ops is available
eBPF program_type ext is NOT available
eBPF program_type lsm is NOT available
eBPF program_type sk_lookup is available
```

这些类型主要分为3大使用场景：

* **跟踪**

tracepoint、kprobe、perf_event等，主要用于从系统中提取跟踪信息，进而为监控、排错、性能优化等提供数据支撑。

* **网络**

xdp、sock_ops、cgroup_sock_addr、sk_msg等，主要用于对网络数据包进行过滤和处理

* **安全和其他**

lsm用于安全，其他还有flow_dissector、lwt_in等

## 3. eBPF最佳实践

> 从前面可以看出来 eBPF 程序本身并不困难，**困难的是为其寻找合适的事件源来触发运行**。

下面说明eBPF各类型程序怎么找对应的插桩点，为实际开发提供指导。

主要基于阿里云智能可观测团队的这篇文章学习：[深入浅出 eBPF｜你要了解的 7 个核心问题](https://developer.aliyun.com/article/985159)

### 3.1. 寻找内核的插桩点

对于监控和诊断领域来说，`跟踪类` eBPF 程序的事件源包含 3 类：

1. 内核函数（kprobe）
2. 内核跟踪点（tracepoint）
3. 性能事件（perf_event）

#### 3.1.1. 内核中都有哪些内核函数、内核跟踪点或性能事件？

* 使用调试信息获取内核函数、内核跟踪点

查看：/sys/kernel/debug/tracing/events

```sh
[root@xdlinux ➜ /root ]$ ls /sys/kernel/debug/tracing/events
alarmtimer        dma_fence       header_page  kyber     oom             rpm       timer
amdgpu            drm             huge_memory  libata    page_isolation  rseq      tlb
amdgpu_dm         enable          hyperv       mac80211  page_pool       rtc       ucsi
avc               exceptions      i2c          mce       pagemap         sched     udp
block             fib             ib_mad       mdio      percpu          scsi      vmscan
bpf_test_run      fib6            initcall     migrate   power           signal    vsyscall
bpf_trace         filelock        intel_iommu  module    printk          skb       wbt
bridge            filemap         iomap        mptcp     qdisc           smbus     workqueue
cfg80211          fs_dax          iommu        msr       random          sock      writeback
cgroup            ftrace          irq          napi      ras             spi       x86_fpu
clk               gpu_scheduler   irq_matrix   neigh     raw_syscalls    swiotlb   xdp
compaction        hda             irq_vectors  net       rcu             syscalls  xen
context_tracking  hda_controller  kmem         netlink   rdma_core       task      xfs
cpuhp             hda_intel       kvm          nmi       regmap          tcp       xhci-hcd
devlink           header_event    kvmmmu       nvme      resctrl         thermal
```

* 使用 `bpftrace` 获取内核函数、内核跟踪点

```sh
# 查询所有内核插桩和跟踪点
sudo bpftrace -l

# 使用通配符查询所有的系统调用跟踪点
bpftrace -l 'tracepoint:syscalls:*'

# 使用通配符查询所有名字包含"open"的跟踪点
# 使用该方式报错了，可以用grep匹配
# bpftrace -l '*open*'
bpftrace -l | grep open
```

在自己的测试环境上查看的结果：

```sh
# 所有跟踪点有很多
[root@xdlinux ➜ /root ]$ bpftrace -l|wc -l
94998

# 通配符查看系统调用跟踪点
[root@xdlinux ➜ /root ]$ bpftrace -l 'tracepoint:syscalls:*' |wc -l
656
[root@xdlinux ➜ /root ]$ bpftrace -l 'tracepoint:syscalls:*' |head -n5 
tracepoint:syscalls:sys_enter_accept
tracepoint:syscalls:sys_enter_accept4
tracepoint:syscalls:sys_enter_access
tracepoint:syscalls:sys_enter_acct
tracepoint:syscalls:sys_enter_add_key

# 所有名字包含"open"的跟踪点
[root@xdlinux ➜ /root ]$ bpftrace -l "*open*"           
stdin:1:1-7: ERROR: No probe type matched for *open*
*open*
~~~~~~
# 换成grep
[root@xdlinux ➜ /root ]$ bpftrace -l |grep open|head -n5
kfunc:__audit_mq_open
kfunc:__dev_open
kfunc:__ia32_compat_sys_mq_open
kfunc:__ia32_compat_sys_open
kfunc:__ia32_compat_sys_open_by_handle_at
```

* 使用`perf list`获取性能事件

```sh
[root@xdlinux ➜ /root ]$ perf list tracepoint

# 执行后会进入下述less界面，可用vim操作进行移动和搜索
List of pre-defined events (to be used in -e):

  alarmtimer:alarmtimer_cancel                       [Tracepoint event]
  alarmtimer:alarmtimer_fired                        [Tracepoint event]
  alarmtimer:alarmtimer_start                        [Tracepoint event]
  alarmtimer:alarmtimer_suspend                      [Tracepoint event]
  amdgpu:amdgpu_bo_create                            [Tracepoint event]
  amdgpu:amdgpu_bo_list_set                          [Tracepoint event]
  amdgpu:amdgpu_bo_move                              [Tracepoint event]
```

#### 3.1.2. 如何查看内核函数/跟踪点的参数和数据结构？

对于内核函数和内核跟踪点，在需要跟踪它们的传入参数和返回值的时候，又该如何查询这些数据结构的定义格式呢？

* 使用调试信息获取

以系统调用的`sys_enter_openat`为例，查看调试信息下的`format`文件

可看到其数据结构

```sh
[root@xdlinux ➜ /root ]$ cat /sys/kernel/debug/tracing/events/syscalls/sys_enter_openat/format
name: sys_enter_openat
ID: 614
format:
	field:unsigned short common_type;	offset:0;	size:2;	signed:0;
	field:unsigned char common_flags;	offset:2;	size:1;	signed:0;
	field:unsigned char common_preempt_count;	offset:3;	size:1;	signed:0;
	field:int common_pid;	offset:4;	size:4;	signed:1;

	field:int __syscall_nr;	offset:8;	size:4;	signed:1;
	field:int dfd;	offset:16;	size:8;	signed:0;
	field:const char * filename;	offset:24;	size:8;	signed:0;
	field:int flags;	offset:32;	size:8;	signed:0;
	field:umode_t mode;	offset:40;	size:8;	signed:0;

print fmt: "dfd: 0x%08lx, filename: 0x%08lx, flags: 0x%08lx, mode: 0x%08lx", ((unsigned long)(REC->dfd)), ((unsigned long)(REC->filename)), ((unsigned long)(REC->flags)), ((unsigned long)(REC->mode))
```


## 4. 小结



## 5. 参考

1、[深入浅出 eBPF｜你要了解的 7 个核心问题](https://developer.aliyun.com/article/985159)

2、[06事件触发：各类eBPF程序的触发机制及其应用场景](https://time.geekbang.org/column/article/483364)

3、[BPF 跟踪机制之原始跟踪点 rawtracepoint 介绍、使用和样例](https://www.ebpf.top/post/bpf_rawtracepoint/)

4、GPT
