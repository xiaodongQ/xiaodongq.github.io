---
title: AI 能力集 -- AI 碎片知识小结
categories: [AI, AI 能力集]
tags: [AI, 工具链，Agent]
date: 2026-03-28
---

## 1. 引言

整理一些最近的 AI 碎片知识，来源也比较零碎：公众号推送、技术群群聊、短视频、刷推等等。

---

## 2. 使用经验类

### 2.1. 终端工具

#### macOS / Linux
- **Ghostty** - 现代高性能终端，支持 GPU 加速、分屏、ligatures
- **WezTerm** - 跨平台终端，Lua 配置灵活，支持多路复用

#### Windows
- **WezTerm for Windows** - 同样支持，配置与 macOS/Linux 通用
  - 参考：[终端也能这么爽？WezTerm：我用过配置最猛、体验最丝滑的终端！](https://mp.weixin.qq.com/s/v7tZO3M-vtU2kosuAB2vtQ)
  
- **Windows Terminal + PowerShell 7**（备选方案）
  - Windows Terminal：微软官方终端，支持多标签、分屏、GPU 加速
  - PowerShell 7：跨平台 Shell，兼容 bash 语法，支持管道、对象处理
  - 优势：开箱即用，无需配置；劣势：自定义能力弱于 WezTerm

### 2.2. Claude Code 工具链

#### 核心仓库
- **everything+claude+code** - Claude Code 资源聚合仓库，收录插件、脚本、使用技巧

#### 必备插件
| 插件 | 功能 | 备注 |
|------|------|------|
| **claude-hud** | 显示 Claude 使用情况和上下文统计 | 实时查看 token 消耗、会话长度 |
| **cc-switch** | 不同模型快速切换 | Minimax 作为 Opus 的 Plan B 备份 |
| **super-power** | 技能包扩展 | 提供额外工具和命令 |
| **happy** | 开源 App，可远程连接 Claude | 支持移动端/桌面端远程调用 |

#### 使用经验
1. **和 Claude 探讨：先确认再执行**
   - 复杂任务先让 Claude 输出计划/思路
   - 确认无误后再执行具体操作
   - 避免盲目执行导致的返工

2. **项目初始化策略**
   - 各子目录单独 `git init`，模块化管理
   - 大目录再 init 顶层仓库，找 Claude 生成 `.claude.md` 规范文件
   - 分层管理，便于多 Agent 协作

### 2.3. Agent 开发

#### Hello Agent 仓库
- **hello-agent** - Agent 开发入门模板仓库
- 包含基础 Agent 结构、工具调用示例、测试框架
- 适合快速上手 Agent 开发，理解核心概念

### 2.4. Skills 设计模式

谷歌发布的 **5 个 Agent Skill 设计模式**（实践经验总结）：

| 模式 | 适用场景 | 核心思想 |
|------|---------|---------|
| **1. Planner-Executor** | 复杂任务分解 | 规划器负责拆解，执行器负责落地 |
| **2. Critic-Refiner** | 质量敏感任务 | 批评者找问题，优化者迭代改进 |
| **3. Router-Specialist** | 多领域任务 | 路由器识别意图，分派给专业 Agent |
| **4. Memory-Augmented** | 长上下文任务 | 外挂记忆库，突破上下文限制 |
| **5. Human-in-the-Loop** | 高风险决策 | 关键节点引入人工确认 |

> 实践建议：根据任务复杂度选择模式，简单任务用单 Agent，复杂任务用多模式组合。

### 2.5. 其他工具

#### 手机端浏览器选择
测试过以下几款：
- **Via 浏览器** - 轻量、无广告、支持脚本、高度自定义 ✅ **最终选择**
- **X 浏览器** - 功能丰富，但稍显臃肿
- **Edge** - 同步方便，但资源占用较高

选择 Via 的理由：
- 体积极小（<1MB）
- 支持自定义 User-Agent
- 支持油猴脚本
- 无推送、无新闻、无干扰

---

## 3. 概念

### 3.1. Harness Engineering（驾驭工程）

参考：[Harness Engineering（驾驭工程）](https://www.runoob.com/ai-agent/harness-engineering.html)

Harness Engineering（驾驭工程）是围绕 AI 智能体设计和构建约束机制、反馈回路、工作流控制和持续改进循环的系统工程实践。它不优化模型本身，而是优化模型运行的"环境"。核心哲学八个字：**人类掌舵，智能体执行**（Human Steer, Agent Execute）。

#### AI 工程范式的三次跃迁
| 阶段 | 核心 | 局限 |
|------|------|------|
| **Prompt Engineering** | 提示词优化 | 依赖单次输入，难以处理复杂任务 |
| **Context Engineering** | 上下文管理 | 受限于模型上下文窗口 |
| **Harness Engineering** | 环境/约束设计 | 突破单模型限制，构建系统级能力 |

---

## 4. 待续

本文持续更新中，后续计划补充：
- [ ] 更多 Claude Code 插件评测
- [ ] Agent 协作实战案例
- [ ] 一人团队 Multi-Agent 系统架构详解

---

*最后更新：2026-03-28*
