---
title: AI能力集 -- AI 碎片知识小结
categories: [AI, AI能力集]
tags: [AI, 工具链，Agent]
date: 2026-03-28
---

## 1. 引言

整理一些最近的 AI 碎片知识，来源也比较零碎：公众号推送、技术群群聊、短视频、刷推等等。

---

## 2. 使用经验类

### 2.1. 终端工具

- **Ghostty** - 现代高性能终端，支持 GPU 加速、分屏、ligatures
  - 但是只能在Linux和Mac上用，自己的Mac系统版本低试了下用不了。加上之前用来ssh连接的`Windterm`，对Claude Code的终端显示有时有问题，所以笔记本上也换成`Wezterm`了
- **WezTerm** - 同样支持Windows，配置与 macOS/Linux 通用
  - 参考：[WezTerm使用介绍](https://mp.weixin.qq.com/s/v7tZO3M-vtU2kosuAB2vtQ)
  - 由 Rust 编写、GPU 加速的跨平台终端模拟器与多路复用器
  - 优势
    - 高性能渲染
    - **多路复用与会话管理（核心优势）**
        - **本地多路复用**：无需`tmux`，原生支持标签页、窗格分屏（水平 / 垂直）、窗口管理
        - 远程会话：其中SSH域通过libssh2直接连接远程服务器，支持会话复用，可配置默认域自动连接
        - 会话持久化：意外关闭终端后可恢复会话
    - Windows 专属集成
        - PowerShell优化：完美兼容 `PowerShell 7+`，支持命令行补全、语法高亮
        - 文件关联：支持通过 WezTerm 打开命令行文件（.cmd, .bat, .ps1）
    - 高级定制能力
        - Lua 配置系统：完整的 Lua API，可自定义键盘映射、外观、启动行为等，配置文件位于 `%USERPROFILE%\.config\wezterm\wezterm.lua`
        - 主题系统：内置 240+ 配色方案，支持动态切换，可自定义窗口框架、标签栏样式
        - 事件钩子：支持启动、退出、窗口创建 / 关闭等事件的自定义脚本，可集成第三方工具
        - 插件生态：通过 Lua 脚本扩展功能，支持自定义状态栏、快捷键、工作区管理
    - 配置可以参考：[wezterm-config](https://github.com/QianSong1/wezterm-config)，使用了一下，快捷键和样式都挺好，也[fork](https://github.com/xiaodongQ/wezterm-config)了一份。
      - 尤其是 `ctrl + alt + |或/`来分屏，并用 `ctrl + alt + j/k/h/l` 来切换，跟vim+tmux的体验一样
      - 进一步提升体验：安装`PowerShell 7`，并且`wezterm`脚本里配置，可体验新版本PowerShell带来的效率提升（如自动补全）
        - 比如这里的配置：[wezterm配置分享](https://zhuanlan.zhihu.com/p/1973514411802108537)
  
- （备选方案） **Windows Terminal + PowerShell 7**
  - Windows Terminal：微软官方终端，支持多标签、分屏、GPU 加速
  - PowerShell 7：跨平台 Shell，兼容 bash 语法，支持管道、对象处理
  - 优势：开箱即用，无需配置；劣势：自定义能力弱于 WezTerm

### 2.2. Claude Code 工具链

#### 2.2.1. 核心仓库

- **everything claude code** - Claude Code 资源聚合仓库，收录插件、脚本、使用技巧

#### 2.2.2. 推荐插件和工具

| 插件            | 功能                             | 备注                                   |
| --------------- | -------------------------------- | -------------------------------------- |
| **claude-hud**  | 显示 Claude 使用情况和上下文统计 | 实时查看 token 消耗、会话长度          |
| **cc-switch**   | 不同模型快速切换                 | 比如用Minimax 作为 Opus 的 Plan B 备份 |
| **super-power** | 技能包扩展                       | 提供额外工具和命令                     |
| **happy**       | 开源 App，可远程连接 Claude      | 支持移动端/桌面端远程调用              |

#### 2.2.3. 使用经验
1. **和 Claude 探讨：先确认再执行**
   - 复杂任务先让 Claude 输出计划/思路
   - 确认无误后再执行具体操作
   - 避免盲目执行导致的返工

2. **项目初始化策略**
   - 各子目录分别执行 `/init`，生成独立的 md 文档（如 README.md、规范文档）
   - 总目录下再执行一次 `/init`，作为索引说明，汇总各子目录功能
   - 分层管理，便于多 Agent 协作和知识隔离

### 2.3. Agent 开发

#### 2.3.1. Hello Agent 仓库
- **hello-agent** - Agent 开发入门模板仓库
- 包含基础 Agent 结构、工具调用示例、测试框架
- 适合快速上手 Agent 开发，理解核心概念

### 2.4. Agent Skill 设计模式

谷歌近期发布的 **5 个 Agent Skill 设计模式**（原文：[@GoogleCloudTech](https://x.com/GoogleCloudTech/status/2033953579824758855)，作者 @Saboo_Shubham_ 和 @lavinigam）：

| 模式                              | 解决的问题                      | 核心思路                               |
| --------------------------------- | ------------------------------- | -------------------------------------- |
| **1. Tool Wrapper（工具包装器）** | Agent 需要特定库/框架的专业知识 | 按需加载知识，不硬编码到 system prompt |
| **2. Generator（生成器）**        | 每次生成的文档结构不一致        | 模板 + 风格指南约束输出格式            |
| **3. Reviewer（审查器）**         | 代码审查标准散落、不可维护      | 检查清单可插拔，分离"查什么"和"怎么查" |
| **4. Inversion（反转）**          | Agent 信息不足时就猜测执行      | 翻转控制流：Agent 当采访者，先问再做   |
| **5. Pipeline（流水线）**         | 复杂任务中 Agent 跳过步骤       | 钻石门控强制执行严格顺序，每步确认     |

> 参考阅读：[Agent Skill 的五种设计模式：从 SKILL.md 格式到内容设计](https://cobb789.ofox.ai/posts/agent-skill-design-patterns-adk/)
>
> 实践建议：模式可组合使用（如 Pipeline + Reviewer），根据任务复杂度选择。Inversion 模式被低估——强制"先问再做"能避免 80% 无用输出。

## 3. 20260412更新

### 3.1. OpenRouter查看各家模型用量统计

[OpenRouter](https://openrouter.ai/rankings) 是一个统一的大模型 API 聚合平台。
* 通过 OpenRouter 的一个 API 端点，可以访问来自不同提供商的数百个 AI 模型
* 统一计费 - 只需要在一个平台充值，就可以使用所有接入的模型，无需分别向各个厂商付费
* 智能路由 - 可以设置自动选择最便宜/最快的模型，或者在某个模型不可用时自动切换到备选模型
* 统一接口格式 - 采用类似 OpenAI 的 API 格式，调用不同模型时只需改变 model 参数

`OpenRouter`的**调用量数据**已成为衡量全球AI模型受欢迎程度的**重要风向标**。
* 除了调用量，还可以查看模型评测、各模型工具调用次数等等
* 还有AI工具的使用token排行，可以了解到近期流行的AI工具，比如最近的爱马仕（Hermes Agent）

比如这周的调用量情况：  
![model-rankings](/images/2026-04-12-openrouter-ranking.png)

模型用量的top app：  
![token-used-top-app](/images/2026-04-12-top-app.png)

### 3.2. CC-Switch工具说明

`CC-Switch`是一款专为 AI 编程助手（特别是 Claude Code）设计的**跨平台配置管理工具**。  
简单来说，它就像是一个“万能遥控器”或“中控面板”，帮你**统一管理**各种 AI 模型的 API 密钥、地址配置，让你无需手动修改复杂的配置文件，就能在不同的大模型之间一键切换。

核心功能：
* 统一管理配置：它支持管理 Claude Code、Codex、Gemini CLI 等多种编程工具的配置文件。你不需要去翻找 `.json` 或 `.toml` 文件手动修改，直接在它的图形界面里操作。
* 一键切换模型：你可以预设多个模型（比如今天想用 GPT-4o，明天想用 DeepSeek），在 CC-Switch 界面点一下就能立刻生效。
* 本地代理与故障转移：它能在本地搭建一个代理服务器。如果某个模型接口挂了，它可以自动切换到备用接口，保证你的编程工作流不中断。
* 可视化监控：可以查看 API 的使用量统计、延迟测试等数据。

#### 3.2.1. CC-Switch 与 OpenRouter 的关系

它们是“工具”与“服务”的互补关系，经常被开发者组合在一起使用，以实现“花最少的钱，用最爽的模型”。
* CC-Switch是工具，OpenRouter是服务
* OpenRouter 提供了统一的接口，而 CC-Switch 提供了便捷的切换界面。

**通常操作方案**：
* 1、注册 OpenRouter 获取 API Key
* 2、填入 CC-Switch
* 3、在 CC-Switch 中配置并一键切换。

#### 3.2.2. Linux下CLI版本使用

桌面UI版本，直接用原始仓库的即可。Linux下的命令行版本，可以看这个fork后的CLI版本：[SaladDay/cc-switch-cli](https://github.com/SaladDay/cc-switch-cli)。

下载下来就一个文件，执行就会进入tui页面：
![cc-switch-cli](/images/2026-04-12-cc-switch-cli.png)

命令：
* `cc-switch env tools`查看本地安装了哪些AI Cli工具，如Claude code/Codex/Gemini/OpenCode
* `cc-switch provider list`查看提供商
* 其他命令文档，可见：[文档](https://github.com/SaladDay/cc-switch-cli/blob/main/README_ZH.md)

### 3.3. 其他工具

#### 3.3.1. 手机端浏览器选择
测试过以下几款：
- **Via 浏览器** - 轻量、无广告、支持脚本、高度自定义 ✅ **最终选择**
- **X 浏览器** - 跟Via差不多，但是感觉自定义搜索不好用（默认百度不大好用）
- **Edge** - 同步方便，使用也不错，前进后退没via好用

选择 Via 的理由：
- 体积极小（<1MB）
- 支持自定义 User-Agent
- 支持油猴脚本
- 无推送、无新闻、无干扰

---

## 4. 概念

### 4.1. Harness Engineering（驾驭工程）

参考：[Harness Engineering（驾驭工程）](https://www.runoob.com/ai-agent/harness-engineering.html)

Harness Engineering（驾驭工程）是围绕 AI 智能体设计和构建约束机制、反馈回路、工作流控制和持续改进循环的系统工程实践。它不优化模型本身，而是优化模型运行的"环境"。核心哲学八个字：**人类掌舵，智能体执行**（Human Steer, Agent Execute）。

#### 4.1.1. AI 工程范式的三次跃迁

| 阶段                    | 核心          | 局限                           |
| ----------------------- | ------------- | ------------------------------ |
| **Prompt Engineering**  | 提示词优化    | 依赖单次输入，难以处理复杂任务 |
| **Context Engineering** | 上下文管理    | 受限于模型上下文窗口           |
| **Harness Engineering** | 环境/约束设计 | 突破单模型限制，构建系统级能力 |

---

