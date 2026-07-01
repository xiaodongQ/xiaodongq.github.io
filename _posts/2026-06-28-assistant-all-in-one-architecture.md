---
title: 个人AI工作台（三） -- xworkbench 功能介绍页
description: 完整的 xworkbench 功能介绍页面，交互式文档，包含全部 8 个核心模块的详细说明
categories: [AI, 个人AI工作台]
tags: [Agent, 个人助手, xworkbench]
last_modified_at: 2026-06-28
---

## 1. 引言

前两篇分别介绍了 [All-In-One 助手的基础构建](https://xiaodongq.github.io/2026/06/10/assistant-all-in-one/) 和 [新增的高级特性](https://xiaodongq.github.io/2026/06/19/assistant-all-in-one-advance-feature/)，本文直接嵌入完整的功能介绍页面。

代码位于 [xiaodongQ/xworkbench](https://github.com/xiaodongQ/xworkbench)，截图和样式基于该项目的实际界面。

---

## 2. 功能介绍

> 📥 单文件版本下载：[点击此处查看](/assets/xworkbench/xworkbench-intro-standalone.html)，[点击此处下载](/assets/xworkbench/xworkbench-intro-standalone.html){: download=""}（所有样式和图片内嵌，可离线使用）

<iframe src="/assets/xworkbench/xworkbench-intro.html" width="100%" height="900" style="border:none;" loading="lazy"></iframe>

---

## 3. 快速启动

```sh
# 克隆并进入项目
git clone <repo>
cd xworkbench

# 编译（macOS 默认）
./scripts/build.sh  # → ./bin/xworkbench

# 三平台编译
./scripts/build.sh -a  # → xworkbench-darwin / xworkbench-linux / xworkbench-windows

# 启动服务（默认端口 8902）
./scripts/run.sh
```

访问 http://localhost:8902 即可使用。