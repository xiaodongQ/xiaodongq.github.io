---
title: 问题定位和性能优化案例集锦 -- 工具补充实验
description: 作为问题定位和性能优化案例集锦的补充，实验并记录工具用法。
categories: [Troubleshooting]
tags: [Troubleshooting]
---

## 1. 背景

限于 [问题定位和性能优化案例集锦](https://xiaodongq.github.io/2025/04/15/excellent-trouble-shooting/) 的篇幅，其中的几个工具实验在本篇中进行记录。

## 2. 系统指标

### 2.1. nmaps：进程的内存段信息

虚拟内存布局，可见之前的梳理：[CPU及内存调度（二） -- Linux内存管理](https://xiaodongq.github.io/2025/03/20/memory-management/)

```sh
# smaps内容
[CentOS-root@xdlinux ➜ ~ ]$ cat /proc/$(pidof mysqld)/smaps
# ----------------- 内存段的基本信息 ---------------
# 该内存段的虚拟地址范围，smaps里有很多段范围信息
    # r-xp 是权限标志，表示可读、不可写、可执行、私有（非共享）。查看完整文件结果可看到还有`rw-s`、`r-xp`等等
    # 00000000：偏移量，表示文件映射到内存中的偏移位置
    # fd:00：设备号，fd 是主设备号，00 是次设备号
    # 136301417：inode号，标识文件
    # /usr/libexec/mysqld：内存映射的文件路径
55a5d35ad000-55a5d70ba000 r-xp 00000000 fd:00 136301417                  /usr/libexec/mysqld
# ------------------ 内存大小相关 ---------------
# 内存段的总大小，包括未使用的部分
Size:              60468 kB
# KernelPageSize 和 MMUPageSize，是 内核和硬件 MMU（内存管理单元）支持的页面大小，通常为 4 KB
KernelPageSize:        4 kB
MMUPageSize:           4 kB
# ------------------ RSS 和 PSS 相关 ---------------
# Resident Set Size，常驻物理内存
Rss:               28692 kB
# Proportional Set Size，按比例分配的内存大小。此处和Rss一样，说明没有共享内存
Pss:               28692 kB
# ------------------ 共享和私有内存 ---------------
# 共享的干净（未修改）和脏（已修改）内存大小
Shared_Clean:          0 kB
Shared_Dirty:          0 kB
# 私有的干净和脏内存大小
Private_Clean:     28692 kB
Private_Dirty:         0 kB
# ------------------ 引用和匿名内存 ---------------
# 最近被访问过的内存大小为 28692 KB
Referenced:        28692 kB
# 匿名内存（未映射到文件的内存）大小为 0 KB
Anonymous:             0 kB
# 延迟释放的内存大小为 0 KB
LazyFree:              0 kB
# ------------------ 大页和共享内存相关字段 ---------------
# 匿名大页内存大小
AnonHugePages:         0 kB
# 通过 PMD（Page Middle Directory）映射的`共享内存`大小
# 64位系统，通过`四级页表`（`页全局目录PGD`+`页上级目录PUD`+`页中间目录PMD`+`页表项PTE`），映射 `2^48 = 256TB`的虚拟地址空间
ShmemPmdMapped:        0 kB
# 通过 PMD 映射的`文件内存`大小
FilePmdMapped:         0 kB
# 共享的 HugeTLB（透明大页）内存大小
Shared_Hugetlb:        0 kB
# 私有的 HugeTLB 内存大小
Private_Hugetlb:       0 kB
# ------------------ 交换和锁定内存 ---------------
# 被交换到磁盘的内存量
Swap:                  0 kB
# 按比例分配的交换内存量
SwapPss:               0 kB
# 锁定在物理内存中的内存大小。这些内存页不会被操作系统交换到磁盘，而是始终驻留在物理内存中
Locked:                0 kB
# 内存段是否符合透明大页（Transparent Huge Pages, THP）的条件
THPeligible:    0
# 内存保护密钥（Memory Protection Key）
ProtectionKey:         0
# 该内存段的虚拟内存标志位
    # rd: 可读（Read）。
    # ex: 可执行（Execute）。
    # mr: 可映射读取（May Read）。
    # mw: 可映射写入（May Write）。
    # me: 可映射执行（May Execute）。
    # dw: 脏页可写（Dirty Write）。
    # sd: 交换时丢弃（Swapped Discard）
VmFlags: rd ex mr mw me dw sd
```

作为对比，`/proc/$(pidof mysqld)/maps`中的内容就比较少了，只有内存段的基本信息：

```sh
# maps内容
[CentOS-root@xdlinux ➜ ~ ]$ cat /proc/$(pidof mysqld)/maps
55a5d35ad000-55a5d70ba000 r-xp 00000000 fd:00 136301417                  /usr/libexec/mysqld
55a5d70ba000-55a5d722f000 r--p 03b0c000 fd:00 136301417                  /usr/libexec/mysqld
55a5d722f000-55a5d75b6000 rw-p 03c81000 fd:00 136301417                  /usr/libexec/mysqld
...
55a5d7f4e000-55a5da7d0000 rw-p 00000000 00:00 0                          [heap]
...
```

## 3. bcc/bpftrace、perf-tools系列工具

### 3.1. bcc syscount

用`syscount`统计错误码出现的次数：

```sh
[CentOS-root@xdlinux ➜ ~ ]$ /usr/share/bcc/tools/syscount -e ENOSPC       
Tracing syscalls, printing top 10... Ctrl+C to quit.
```

也可根据错误码查看eBPF的程序代码细节：

```sh
# syscount -e ENOSPC 用于统计返回 ENOSPC 错误的系统调用次数
# 添加 --ebpf 参数后，会显示底层的 eBPF 程序代码，而不是直接运行统计功能
[CentOS-root@xdlinux ➜ ~ ]$ /usr/share/bcc/tools/syscount -e ENOSPC --ebpf
#define FILTER_ERRNO 28

#ifdef LATENCY
struct data_t {
    u64 count;
    u64 total_ns;
};

BPF_HASH(start, u64, u64);
BPF_HASH(data, u32, struct data_t);
#else
BPF_HASH(data, u32, u64);
#endif

#ifdef LATENCY
TRACEPOINT_PROBE(raw_syscalls, sys_enter) {
    u64 pid_tgid = bpf_get_current_pid_tgid();

#ifdef FILTER_PID
    if (pid_tgid >> 32 != FILTER_PID)
        return 0;
#endif

    u64 t = bpf_ktime_get_ns();
    start.update(&pid_tgid, &t);
    return 0;
}
#endif
    ...
```

### 3.2. kdump 和 crash

1、kdump：

```sh
# 触发系统panic：
[CentOS-root@xdlinux ➜ ~ ]$ echo c > /proc/sysrq-trigger
# 查看dump文件
[CentOS-root@xdlinux ➜ ~ ]$ ll /var/crash 
drwxr-xr-x 2 root root 67 Mar 30 10:29 127.0.0.1-2025-03-30-10:29:58
[CentOS-root@xdlinux ➜ ~ ]$ ll /var/crash/127.0.0.1-2025-03-30-10:29:58 
# 上次内核的dmesg信息
-rw------- 1 root root  98K Mar 30 10:29 kexec-dmesg.log
-rw------- 1 root root 295M Mar 30 10:29 vmcore
# 崩溃时的dmesg信息
-rw------- 1 root root  80K Mar 30 10:29 vmcore-dmesg.txt
```

2、crash：用于分析系统coredump文件

分析dump文件需要内核vmlinux，安装对应内核的dbgsym包（没有则手动下载rmp安装：http://debuginfo.centos.org）

内核调试符号包：kernel-debuginfo、kernel-debuginfo-common。可以到阿里云的镜像站下载对应内核版本，比较快。

`rpm -ivh`手动安装，会安装到：`/usr/lib/debug/lib/modules`

**分析方法：**

1、加载：

```sh
[CentOS-root@xdlinux ➜ download ]$ crash /var/crash/127.0.0.1-2025-03-30-10\:29\:58/vmcore /usr/lib/debug/lib/modules/`uname -r`/vmlinux

crash 7.3.0-2.el8
...
This GDB was configured as "x86_64-unknown-linux-gnu"...

WARNING: kernel relocated [324MB]: patching 103007 gdb minimal_symbol values

      KERNEL: /usr/lib/debug/lib/modules/4.18.0-348.7.1.el8_5.x86_64/vmlinux
    DUMPFILE: /var/crash/127.0.0.1-2025-03-30-10:29:58/vmcore  [PARTIAL DUMP]
        CPUS: 16
        DATE: Sun Mar 30 10:29:39 CST 2025
     ...

crash> 
```

2、常用命令：ps、bt、log

```sh
crash> ps
   PID    PPID  CPU       TASK        ST  %MEM     VSZ    RSS  COMM
>     0      0   0  ffffffff96a18840  RU   0.0       0      0  [swapper/0]
>     0      0   1  ffff9a2403880000  RU   0.0       0      0  [swapper/1]
      0      0   2  ffff9a2403884800  RU   0.0       0      0  [swapper/2]
...

crash> bt
PID: 35261  TASK: ffff9a25a9511800  CPU: 2   COMMAND: "zsh"
 #0 [ffffb694057a3b98] machine_kexec at ffffffff954641ce
 #1 [ffffb694057a3bf0] __crash_kexec at ffffffff9559e67d
 #2 [ffffb694057a3cb8] crash_kexec at ffffffff9559f56d
 #3 [ffffb694057a3cd0] oops_end at ffffffff9542613d
 #4 [ffffb694057a3cf0] no_context at ffffffff9547562f
 #5 [ffffb694057a3d48] __bad_area_nosemaphore at ffffffff9547598c
 #6 [ffffb694057a3d90] do_page_fault at ffffffff95476267
 #7 [ffffb694057a3dc0] page_fault at ffffffff95e0111e
    [exception RIP: sysrq_handle_crash+18]
    RIP: ffffffff959affd2  RSP: ffffb694057a3e78  RFLAGS: 00010246
...

crash> log
[    0.000000] Linux version 4.18.0-348.7.1.el8_5.x86_64 (mockbuild@kbuilder.bsys.centos.org) (gcc version 8.5.0 20210514 (Red Hat 8.5.0-4) (GCC)) #1 SMP Wed Dec 22 13:25:12 UTC 2021
[    0.000000] Command line: BOOT_IMAGE=(hd0,gpt6)/vmlinuz-4.18.0-348.7.1.el8_5.x86_64 root=/dev/mapper/cl_desktop--mme7h3a-root ro crashkernel=auto resume=/dev/mapper/cl_desktop--mme7h3a-swap rd.lvm.lv=cl_desktop-mme7h3a/root rd.lvm.lv=cl_desktop-mme7h3a/swap rhgb quiet
[    0.000000] x86/fpu: Supporting XSAVE feature 0x001: 'x87 floating point registers'

crash> kmem -i
                 PAGES        TOTAL      PERCENTAGE
    TOTAL MEM  8013423      30.6 GB         ----
         FREE  7215135      27.5 GB   90% of TOTAL MEM
         USED   798288         3 GB    9% of TOTAL MEM
       SHARED    32189     125.7 MB    0% of TOTAL MEM
      BUFFERS      915       3.6 MB    0% of TOTAL MEM
       CACHED   481884       1.8 GB    6% of TOTAL MEM
         SLAB    27734     108.3 MB    0% of TOTAL MEM

   TOTAL HUGE        0            0         ----
    HUGE FREE        0            0    0% of TOTAL HUGE

   TOTAL SWAP   262143      1024 MB         ----
    SWAP USED        0            0    0% of TOTAL SWAP
```
