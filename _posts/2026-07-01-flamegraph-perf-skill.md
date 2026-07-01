---
title: 历史经验Skill化系列（一） -- 火焰图
description: 火焰图 Skill 化，从数据采集到生成到解读，配套 CLI 工具链
categories: [AI, 历史经验Skill化]
tags: [AI, 性能分析, 火焰图, perf, 排查]
---

## 1. 引言

最近开启新的系列，将历史博客中的经验和能力AI化，转换为更便捷的Skill。如火焰图、eBPF、gperf-tool、wireshark抓包、google sanitize等等。

火焰图（Flame Graph）由 Brendan Gregg 发明，是性能分析领域最直观的可视化工具。

本系列是**历史经验 Skill 化**的第一篇，火焰图知识体系见之前博客：[《并发与异步编程——性能分析工具：gperftools和火焰图》](https://xiaodongq.github.io/2025/03/14/async-io-example-profile/)。

---

## 2. 火焰图类型

| 类型         | 横轴         | 采样事件                 | 适用场景            |
| ------------ | ------------ | ------------------------ | ------------------- |
| On-CPU       | CPU 时间     | `cpu-clock` / `cycles`   | CPU 热点            |
| Off-CPU      | 阻塞时间     | `sched:sched_stat_sleep` | 锁竞争 / I/O 等待   |
| Memory       | 内存操作频率 | `brk` / `page-faults`    | 内存泄漏 / 异常分配 |
| Hot/Cold     | CPU + 阻塞   | 组合                     | 混合负载全景        |
| Differential | 差值         | 对比两个 profile         | 版本 / 配置变更对比 |

---

## 3. 工具链

完整流程：

```
perf record -F 99 -g -p <PID> -- sleep 30    # 采集 call-stack 采样
perf script                                  # 导出原始数据
stackcollapse-perf.pl                        # 按调用链折叠
flamegraph.pl                                # 生成 SVG
```

**环境安装：**

```bash
# Debian/Ubuntu
sudo apt-get install linux-tools-common linux-tools-$(uname -r)

# 克隆 FlameGraph
git clone https://github.com/brendangregg/FlameGraph.git
```

### 3.1 On-CPU 火焰图

```bash
# 对已运行进程采样
sudo perf record -F 99 -g -p <PID> -- sleep 30

# 或直接启动程序
sudo perf record -F 999 -g -- ./your_program

# 导出并生成 SVG
perf script > out.perf
cd FlameGraph
./stackcollapse-perf.pl out.perf | ./flamegraph.pl > out.svg
```

### 3.2 Off-CPU 火焰图

```bash
sudo perf record -e 'sched:sched_stat_sleep' -e 'sched:sched_switch' -a -g -- sleep 30
perf script | ./stackcollapse-perf.pl | ./flamegraph.pl > offcpu.svg
```

### 3.3 Memory 火焰图

```bash
sudo perf record -e kmem:* -a -g -- sleep 30
perf script | ./stackcollapse-perf.pl | ./flamegraph.pl --colors=mem > mem.svg
```

### 3.4 Differential 火焰图

```bash
./flamegraph.pl --diff=baseline.folded new.folded > diff.svg
```

---

## 4. 常见问题

**函数名是十六进制地址**：Java / Go 程序需要额外符号表，参考 [perf-map-agent](https://github.com/jvm-profiling-tools/perf-map-agent) 和 [fgprof](https://github.com/felixge/fgprof)。

**采样时长**：建议 30 秒以上，覆盖完整业务周期。偶发性热点需要更长采样或多次采集。

**内核态不可见**：加 `-a` 参数可包含所有 CPU 的内核态栈。

---

## 5. Skill 化思路

火焰图能力的 AI 调用接口设计：

```yaml
name: flamegraph
description: "生成并分析 On-CPU / Off-CPU / Memory 火焰图，精确定位性能瓶颈"
capabilities:
  - 生成 CPU 火焰图（perf + FlameGraph）
  - 生成 Off-CPU 火焰图
  - 生成 Memory 火焰图
  - 差分火焰图对比分析
triggers:
  - "CPU 占用高"
  - "性能瓶颈排查"
  - "火焰图分析"
input:
  target: "进程 PID 或可执行文件路径"
  duration: "采样时长（秒），默认 30"
  type: "on_cpu | off_cpu | memory"
output:
  artifact: "SVG 文件路径"
  summary: "Top 5 热点函数及占比"
```

---

## 6. 参考链接

- [FlameGraph 官方仓库](https://github.com/brendangregg/FlameGraph)
- [Flame Graphs 介绍原文](http://www.brendangregg.com/flamegraphs.html)
- [Linux perf Off-CPU Flame Graphs](http://www.brendangregg.com/blog/2014-07-25/off-cpu-flame-graphs.html)
- [fgprof（Go 语言混合 CPU/I/O 分析）](https://github.com/felixge/fgprof)
- [perf-map-agent（Java 火焰图符号表）](https://github.com/jvm-profiling-tools/perf-map-agent)
- [《并发与异步编程——性能分析工具：gperftools和火焰图》](https://xiaodongq.github.io/2025/03/14/async-io-example-profile/)
- [《并发与异步编程——异步demo实验并分析性能》](https://xiaodongq.github.io/2025/03/16/async-io-pracetise-profile/)
