---
title: 终端 AI 编程 Agent 全横评：Pi / Oh My Pi / OpenCode / Crush
description: 深入解析四个主流开源终端编程 Agent 项目，从极简底座到全能选手，帮你找到最适合的代码助手
categories: [AI, 编程工具]
tags: [AI, 编程Agent, 终端, Pi, OpenCode, Crush, Claude-Code]
---

## 前言

最近在研究极简编程 Agent 框架，发现这个赛道有几个很有意思的项目，定位各异，从"只给 4 个工具的极简底座"到"开箱即用的全能选手"都有。今天把这几个项目梳理清楚，方便后续跟工作台能力做结合。

涉及的项目：Pi Agent、Oh My Pi、OpenCode、Crush。

---

## 一、Pi Agent — 极简主义的极端实践者

**一句话定位**：Mario Zechner（libGDX 作者）开发的极简终端编程 Agent，核心哲学是"Agent 只需要 4 个工具 + 几百词系统提示词就足够"。

### 核心设计哲学

绝大多数 Agent 堆砌十几甚至几十个工具、上万 Token 提示词、内置子代理和规划模块。Pi 走的是完全相反的路：

- 仅内置 **4 个基础原语工具**，不预装任何多余能力
- 系统提示词仅 **200~300 Token**（对比 Claude Code 约 10000 Token）
- 默认 **YOLO 模式**：无频繁权限弹窗，工具调用全程透明可追溯
- 核心公式：`Agent = LLM + 工具循环 + 运行时底座`
- 所有高级能力（联网、PDF、子代理）全部通过**扩展按需安装**

### 仅有 4 个核心工具

Pi 原生只带 4 个指令，所有代码操作都靠它们组合完成：

| 工具 | 作用 |
|------|------|
| `read` | 读取项目任意文件、目录结构 |
| `write` | 新建文件、写入完整文件内容 |
| `edit` | 差分修改已有代码（精准局部编辑） |
| `bash` | 执行终端命令、跑测试、安装依赖 |

### 主要特性

**全模型无关**。兼容所有 OpenAI 兼容接口：GPT、Claude、Gemini、DeepSeek、GLM、Ollama 本地大模型、Groq 等，可完全本地离线运行。

**四种运行模式**：

- 交互模式（默认）：终端持续对话，反复迭代改代码
- 单次打印模式（`pi -p`）：一条指令执行完直接退出
- JSON 输出模式：结构化结果，方便脚本调用
- RPC 服务模式：可对接 Zed 编辑器等 IDE 插件

**会话管理**：

- 本地永久保存所有对话记录（`~/.pi/agent/sessions`，JSONL 格式）
- 会话回退、分叉（fork）、重命名
- 一键导出会话为 HTML 报告、训练数据集文件

**三层扩展生态**：

- Extensions（扩展）：底层 TypeScript 钩子，修改 Agent 运行逻辑
- Skills（技能包）：开箱即用功能包（联网搜索、PDF 解析、语音、表格处理、子代理）
- Prompt 模板：自定义不同任务的系统提示词

### 速度表现

这是 Pi 最值得关注的地方。

- **冷启动** <200ms，对比 Aider/Claude Code（2~5 秒）
- **内存占用** 常驻仅 30~50MB，主流 Agent 普遍 200MB~800MB
- **Token 消耗** 只有 Claude Code 的 35%~51%，因为系统提示词只有 200~300 Token

### 适合人群

- 想自建轻量化本地编码 AI 助手的开发者
- 厌烦臃肿 Agent 工具、追求极简可控工作流的程序员
- 需要把 Agent 会话数据留存、二次训练的工程师
- 想要一套可自由对接任意大模型的 Agent 底座

---

## 二、Oh My Pi — Pi 的"完整版"

**一句话定位**：Pi Agent 的主力增强分叉版本，作者 Can Bölük 在原版极简 Pi 的代码基础上彻底重构重写，定位从「极简 Agent 底座」变成**开箱即用的全能终端编码智能体**。

### 核心区别

| | 原版 Pi | Oh My Pi |
|---|---|---|
| 代码量 | 约 1500 行 TS | 数万行（TS+Bun + Rust 原生内核） |
| 工具数量 | 4 个 | 32 个内置工具 |
| 提示词 | 200~300 Token | 内置大量编码专用提示词 |
| LSP/DAP | 无 | 原生深度集成 |
| 需要配置 | 大量 | 装上就能干活 |

### 独有核心功能

**Hashline 哈希锚点编辑**（最核心创新）。放弃传统行号替换，用文件内容哈希定位代码修改，大幅解决 AI 改代码改错行、覆盖冲突代码的问题，多轮迭代编辑准确率提升 60%+。

**原生 LSP + DAP 调试深度集成**：

- 13 种 LSP 语义操作：符号重命名、查找所有引用、自动修复、代码重构
- 27 种 DAP 调试能力：单步调试、查看堆栈、断点修 bug

**进程内 Rust 原生运行**。原版 Pi 会调用系统 shell、rg、find 等外部程序；Oh My Pi 把文件检索、shell（自研 brush shell）、AST 解析全部写进进程内部，不 fork 外部进程，文件扫描速度比原版快 2~3 倍。

**其他标配能力**：

- 内置无头浏览器工具
- 40+ 大模型厂商路由
- 原生支持 MCP 协议
- 并行子代理
- PDF/压缩包解析

### 速度对比

- 冷启动：原版 Pi <200ms；Oh My Pi 约 600-900ms
- 单文件小修改：两者速度接近
- 本地 Ollama 场景：Oh My Pi 编辑容错率远高于原版，整体完成速度更快

### 选哪个

- **原版 Pi**：想自研 Agent、追求最小体积、只需要基础文件 + shell 能力
- **Oh My Pi**：只想拿来写代码、改 bug、调试项目，想要 LSP、调试、并行子代理等全套能力

---

## 三、OpenCode — Go 写的极速选手

**一句话定位**：Go 语言编写、单二进制极速终端编码 Agent，全网同赛道裸性能最快的开源编码 Agent 之一。

> 注意：原版仓库 `opencode-ai/opencode` 已经**归档停止维护**，原作者带着代码迁移到新项目 Crush。社区 fork 版仍在更新。

### 核心架构

- 核心语言：原生 Go（Bubble Tea 做 TUI 界面），单文件二进制打包，无运行时依赖
- 代码体量：约 1.8 万行 Go 代码
- 设计思路：预设全套工程化能力 + 极致运行性能，不是极简底座，是开箱即用成品 Agent

### 三大专属运行模式

1. **Plan 规划模式**：AI 先完整梳理项目、输出改造步骤清单，确认后再执行修改
2. **Build 构建模式**：默认干活模式，边思考边改代码、跑测试、修复报错
3. **General 闲聊模式**：普通问答、文档阅读、脚本处理

### 核心功能特性

**碾压级性能**（最大卖点）：

- 冷启动：30~50ms（原版 Pi≈200ms，Oh My Pi≈700ms）
- 全部文件检索、shell、AST 解析全部内置进程内实现，不 fork 外部程序
- 同大型重构任务，耗时只有原版 Pi 的 55%~65%

**原生内置全套能力**：

- 12 个内置工具（文件读写、批量编辑、终端执行、文件搜索）
- 原生 LSP 代码语义解析、符号跳转、重构修改
- 并行多子代理
- 完整会话系统
- 原生 MCP 协议、Git 操作、无头浏览器文档爬取

**支持 75+ 大模型厂商**，内置一批免费可直接调用的编程专用模型。

### 缺点

- 可定制深度不如原版 Pi
- 项目已归档不再迭代新版本，主力开发迁移到 Crush

---

## 四、Crush — OpenCode 的正统续作

**一句话定位**：Charm 团队（ Bubble Tea、Gum 作者）收购原 OpenCode 作者后推出的新品，Go 原生内核，TUI 体验业内天花板。

### 来历

2025 年原 OpenCode 作者和团队分家：

- 原作者被 **Charmbracelet** 收购，把 Go 原版代码改名 **Crush**，持续主力迭代（正统血脉）
- 另一波分支开发者用 TS 重写，保留名字叫 OpenCode（旧名分支，不再是原版 Go 架构）

### 核心优势

**全 Go 自研内核**，所有文件检索、Shell 执行、AST 解析、正则搜索全部内置进程实现，完全不 fork 外部进程。

**原生深度 LSP 绑定**，基于标准 LSP 协议对接，兼容性最好。

**行业最早全量支持 MCP 协议**，通过 Model Context Protocol 对接任意第三方工具：网页爬取、数据库、Git、云服务、本地脚本，支持 stdio/HTTP/SSE 三种传输。

**会话黑科技**：

- 同项目多并行隔离会话，互不干扰上下文
- 会话中途无缝切换大模型，历史上下文完全保留（独有能力）
- 内置 Token 花费统计、推理耗时看板

**全平台兼容性断层领先**：macOS/Linux/Windows PowerShell/WSL/Android/BSD 全系列系统。

### 速度横向对比

| 项目 | 冷启动 | 备注 |
|------|--------|------|
| Crush | 30~45ms | 全网编码 Agent 第一梯队 |
| OpenCode | 30~50ms | 已归档 |
| 原版 Pi | <200ms | 极简底座里算快的 |
| Oh My Pi | 600~900ms | 功能最多，启动略慢 |

### Crush vs OpenCode（分家后核心差异）

| | Crush | 社区 OpenCode |
|---|---|---|
| 代码语言 | Go | TypeScript 重写 |
| 更新维护 | 原作者全职开发 | 社区维护 |
| 扩展性 | 原生 MCP | 自研插件系统 |
| TUI | Charm 全套栈 | 较弱 |
| 协议 | FSL | MIT |

---

## 五、横向对比总结

| | Pi Agent | Oh My Pi | OpenCode | Crush |
|---|---|---|---|---|
| 代码量 | ~1500 行 TS | 数万行 | ~1.8 万行 Go | ~2.5 万行 Go |
| 工具数量 | 4 个 | 32 个内置 | 12 个内置 | 全套 |
| 系统提示词 | 200~300 Token | 较长 | 较长 | 较长 |
| LSP/DAP | ❌ | ✅ 深度集成 | ✅ | ✅ 原生标准 |
| MCP | ❌ 需扩展 | ✅ | ✅ | ✅ 最早全量 |
| 冷启动 | <200ms | 600-900ms | 30~50ms | 30~45ms |
| 可扩展性 | 极高（底座） | 中 | 中 | 中 |
| 定位 | 极简底座 | 全能开箱即用 | 高性能成品 | 高性能成品+最新 |

### 选型建议

- **自研 Agent、极简二次开发**：留原版 Pi
- **日常写代码、调试改 bug、想要最多功能**：选 Oh My Pi
- **追求极致启动速度、本地跑 7B-24B 模型**：选 OpenCode（社区版）或 Crush
- **想跟进原作者最新迭代**：直接选 Crush

---

## 六、跟工作台结合的思考

回到最初研究这个方向的目的——给 xworkbench 找合适的 Agent 能力。这几个项目的路线差异其实对应了不同的结合思路：

**Pi** 的扩展机制（Extensions/Skills/Packages）非常适合作为经验库的能力载体——把 best practice 沉淀成可复用 Skills，对接 xworkbench 的经验库。

**Crush/OpenCode** 的高性能和 MCP 协议支持，适合作为自动化面板里的任务执行引擎，配合 xworkbench 的任务调度和目录快捷键能力。

**Oh My Pi** 如果追求开箱即用的编码体验，可以直接嵌入工作台的 Web Terminal，作为内置编程 Agent 选项。

这个方向值得深入，后续考虑先从 Pi 的 Skills 机制和 xworkbench 经验库的对应关系入手。

---

## 七、Pi 原版的性能短板详解

先说结论：原版 Pi 在架构层本身几乎没有代码性能 bug，它的所有慢，都是**设计取舍**带来的瓶颈，不是代码写得差。

### 4 个核心性能短板

**1. 进程外部调用开销（最大硬瓶颈）**

原版 Pi 基于 Node.js，所有文件搜索、grep、目录遍历、shell 执行，全都调用系统外部二进制（rg、find、bash），每次调用都要 fork 新进程：

- 小文件修改无感
- 大型项目遍历文件：频繁创建销毁进程，耗时比内存内原生实现慢 2~3 倍
- 跨轮 bash 环境不保留，每次新开终端，状态丢失

**2. 无内置代码索引 / 语义检索**

只有基础 `read` 读文件，没有 LSP、AST 解析、代码向量索引：

- 找全项目所有同名函数：只能一遍遍 read 整份文件
- 大仓库（10 万行 +）任务会疯狂堆轮次，越跑越慢
- 只能靠你手动装扩展补检索能力

**3. 对小参数量本地模型极度不友好（最容易踩坑）**

Pi 的极简提示词设计是为顶尖云端大模型设计的：

- 7B/12B 本地小模型很容易写错工具格式、分不清工作目录、重复循环调用同一个命令
- 一旦工具调用出错，就会多轮重试，整体耗时直接翻倍
- 没有内置容错重试逻辑，错了就从头再来

**4. Node.js 运行时的先天短板**

- 冷启动虽快，但长时间长会话后 GC 卡顿明显
- 没有并行子代理能力，所有任务串行执行
- 会话历史只有基础压缩，超长对话 KV 缓存会持续膨胀，容易 OOM

### 它没有的性能问题

- 没有冗余循环、没有多余 Token 打印、没有臃肿依赖逻辑
- 系统提示词极短，预填充速度是天生优势
- 内存空闲占用极低（30~50MB）

### 怎么让原版 Pi 变快

1. 安装 `smart-at` 文件检索扩展，替换系统 rg 遍历
2. 开启会话自动压缩：`pi config set session.compress true`
3. 本地使用至少 24B 及以上代码模型，避免 7B 模型反复报错重试
4. 用 Bun 代替 Node 运行 Pi，单轮调度速度提升 30%

### 提速结论

- 云端用：全网最快的通用编码 Agent 之一，省 token = 省时间 + 省钱
- 本地用：目前本地大模型适配速度最优的 Agent 框架
- 如果你经常用本地 Ollama 跑编码 Agent，Pi 的速度体验会断层领先其他方案

---

## 八、腾讯 CodeBuddy 接入指南

腾讯 CodeBuddy 可以接入 Crush、Pi、Oh-My-Pi 所有兼容 OpenAI 接口的 Agent。需要分清两个概念：

- **网页/VSCode 登录账号**：扫码登录的个人 CodeBuddy 账号不能直接复用登录态
- **CodeBuddy OpenAI 兼容 API**：在腾讯云后台拿到专属 API Key + 接口地址，所有兼容 OpenAI 格式的 Agent 全都能接入

### 获取接入凭证

1. 进入腾讯云 CodeBuddy 控制台
2. 进入【API 密钥管理】，生成专属 SecretID/SecretKey
3. CodeBuddy 国内标准 OpenAI 兼容端点格式：

```
https://api.coze.cn/v1
```

4. 可用模型 ID（原生支持工具调用）：

| 模型 ID | 说明 |
|---------|------|
| `codebuddy-coder-pro` | 主力代码大模型 |
| `codebuddy-coder-fast` | 高速轻量版 |
| `codebuddy-ultra` | 全能增强版 |

### 在 Crush 中配置 CodeBuddy

**配置文件方式**（推荐）：

打开 Crush 全局配置文件：

- macOS/Linux：`~/.config/crush/crush.json`
- Windows：`%USERPROFILE%\.config\crush\crush.json`

```json
{
  "providers": {
    "codebuddy": {
      "name": "CodeBuddy",
      "api_key": "你的API Key",
      "base_url": "https://api.coze.cn/v1"
    }
  },
  "models": {
    "default": {
      "provider": "codebuddy",
      "model": "codebuddy-coder-pro"
    }
  }
}
```

**交互式界面配置**：

1. 终端输入 `crush` 启动
2. 按 `Ctrl+L` 打开模型列表
3. 选择【Add Custom Provider】填入上述信息
4. 保存即可随时切换

### 在 Pi / Oh-My-Pi 中配置

配置文件路径：

- Pi：`~/.pi/agent/models.json`
- Oh-My-Pi：`~/.omp/providers.json`

```json
{
  "providers": {
    "codebuddy": {
      "name": "CodeBuddy",
      "api_key": "你的API Key",
      "base_url": "https://api.coze.cn/v1"
    }
  },
  "default": "codebuddy"
}
```

### 关键限制说明

1. **网页扫码账号无法直接登录**：Crush/Pi 不能读取 CodeBuddy 网页端的登录 Cookie，只能走 API 计费额度，网页端免费额度和 API 额度是分开两套额度
2. **工具调用兼容性极强**：CodeBuddy 全系模型原生支持 Function Call，在 LSP、子代理、文件编辑场景下报错率比很多国内模型更低
3. **国内网络优势**：不用科学网络即可稳定调用，延迟远低于 GPT/Claude
4. **不能反向集成**：Crush/Pi 没法作为插件塞进 CodeBuddy 客户端，只能是 CodeBuddy 作为模型算力供给给这些终端 Agent

### 进阶玩法：复用 CodeBuddy 本地服务

如果安装了 CodeBuddy CLI，可以启动本地代理服务，让 Crush 对接本地地址：

```bash
codebuddy proxy --port 8123
```

然后在配置里把 `base_url` 改为 `http://localhost:8123/v1`，可复用本地登录的账号权限。

---

*参考资料：Terminal-Bench 2.0 编码基准测试、各项目 GitHub 仓库及官方文档*
