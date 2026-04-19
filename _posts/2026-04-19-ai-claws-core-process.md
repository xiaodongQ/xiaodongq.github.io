---
title: OpenClaw系列 -- picoclaw框架源码解析
categories: [AI, OpenClaw系列]
tags: [AI, picoclaw, 开源框架]
---

## 1. 引言

[上篇](https://xiaodongq.github.io/2026/03/19/openclaw-alternatives-comparison/)介绍了几个`OpenClaw`平替的开源项目，本文梳理学习几个Claw系列项目的核心工作流代码，原理上应该都是Agent的的ReAct循环+工具调用。

想法：分析学习项目代码不需要大而全，尤其现在AI生成代码速度远远超过个人能阅读的速度。只要关注自己的核心需求，并收缩一些注意力。

* [picoclaw](https://github.com/sipeed/picoclaw)

思路：
开发一个任务领取系统，工作上提效；
知识库；


## 基本介绍

PicoClaw 是一个受 [NanoBot](https://github.com/HKUDS/nanobot) 启发的超轻量级个人AI助手。基于Go语言从零重构，由`AI Agent`自身驱动了整个架构迁移和代码优化。

特性介绍：
* 超轻量级: **核心功能内存占用 <10MB** — 比 OpenClaw 小 99%
* 极低成本: 高效到足以在 $10 的硬件上运行 — 比 Mac mini 便宜 98%
* 闪电启动: 启动速度快 400 倍，即使在 0.6GHz 单核处理器上也能在**1秒内启动**
* 真正可移植: 跨 RISC-V、ARM、MIPS 和 x86 架构的**单二进制文件，一键运行**
* AI 自举: 纯 Go 语言原生实现 — 95% 的核心代码由 Agent 生成，并经由"人机回环"微调
* ...

## 架构图


