---
title: 历史经验Skill化系列（一） -- 火焰图
description: 火焰图 Skill 化，从数据采集到生成到解读，配套 CLI 工具链
categories: [AI, 历史经验Skill化]
tags: [AI, 性能分析, 火焰图, perf, 排查]
---

## 前言

最近开启新的系列，将历史博客中的经验和能力 AI 化，转换为更便捷的 Skill。如火焰图、eBPF、gperf-tool、wireshark 抓包、google sanitize 等等。

火焰图（Flame Graph）由 Brendan Gregg 发明，是性能分析领域最直观的可视化工具。

本系列是**历史经验 Skill 化**的第一篇，火焰图知识体系见之前博客：[《并发与异步编程——性能分析工具：gperftools和火焰图》](https://xiaodongq.github.io/2025/03/14/async-io-example-profile/)。

### 火焰图类型

火焰图有多种类型，适用于不同的性能分析场景：

| 类型         | 横轴         | 采样事件                 | 适用场景            |
| ------------ | ------------ | ------------------------ | ------------------- |
| On-CPU       | CPU 时间     | `cpu-clock` / `cycles`   | CPU 热点            |
| Off-CPU      | 阻塞时间     | `sched:sched_stat_sleep` | 锁竞争 / I/O 等待   |
| Memory       | 内存操作频率 | `branches` / `cache-misses` | 内存热点分析     |
| Wake         | 唤醒延迟     | `sched:sched_wakeup`     | 延迟分析 / 调度问题 |
| Hot/Cold     | CPU + 阻塞   | 组合                     | 混合负载全景        |
| Differential | 差值         | 对比两个 profile         | 版本 / 配置变更对比 |

### Off-CPU、Memory、Wake 火焰图与 eBPF

**Off-CPU 火焰图**展示的是进程不在 CPU 上运行的时间——包括等待锁、等待 I/O、sleep 等阻塞场景。这对于分析"CPU 不高但响应慢"的问题特别有用。数据来源依赖 `perf` 采集 `sched:sched_stat_sleep` 和 `sched:sched_switch` 等内核事件。

**Wake 火焰图**追踪任务被唤醒的路径，分析延迟来源——哪些操作唤醒了当前任务，唤醒链路有多长。依赖 `perf` 采集 `sched:sched_wakeup` 事件。

**Memory 火焰图**聚焦内存访问热点，采样 `branches`、`cache-misses`、`kmem:*` 等事件，帮助定位内存分配异常或缓存未命中问题。

这些高级火焰图（Off-CPU、Wake、Memory）本质上依赖 **eBPF（extended Berkeley Packet Filter）** 提供的内核级别的动态追踪能力。eBPF 允许在内核中安全地运行自定义程序，采集各类内核事件，是现代性能分析的核心基础设施。

### 相关 eBPF 博客

本博客有完整的 eBPF 学习系列，可搭配火焰图一起使用：

- [eBPF学习实践系列（一）—— 初识eBPF](https://xiaodongq.github.io/2024/06/06/ebpf_learn/)
- [eBPF学习实践系列（二）—— bcc tools 网络工具集](https://xiaodongq.github.io/2024/06/10/bcc-tools-network/)
- [eBPF学习实践系列（三）—— 基于libbpf开发实践](https://xiaodongq.github.io/2024/06/15/libbpf-future/)
- [eBPF学习实践系列（四）—— eBPF的各种追踪类型](https://xiaodongq.github.io/2024/06/19/ebpf-trace-type/)
- [eBPF学习实践系列（五）—— 分析tcplife.bpf.c程序](https://xiaodongq.github.io/2024/06/20/ebpf-practice-case/)

---

（后文待续）
