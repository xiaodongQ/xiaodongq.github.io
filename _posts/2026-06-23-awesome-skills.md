---
title: awesome Skill和工具合集
description: awesome Skill 合集 - 持续记录试用过的 AI Skill
categories: [AI, AI能力集]
tags: [Skill]
---

## 1. 引言

随着 AI 编程工具（Claude Code、CodeBuddy 等）的 Skill / SubAgent 生态越来越丰富，开源社区涌现出大量实用的 Skill，覆盖内容创作、文档处理、图像生成等众多场景。

本篇文章作为个人的 `awesome-skills` 清单，持续整理试用过的开源 Skill，并按使用场景分类记录其背景、安装方式、使用方法与注意事项，方便快速检索与复用。

## 2. 概览

> 待补充：表格形式列出本篇涵盖的所有 Skill（分类 / 名称 / 一句话简介）

## 3. 工具类

### 3.1. playwright-cli：浏览器控制

`playwright-cli` VS `playwright MCP`

两者底层都是 Playwright 浏览器内核，核心差异是数据传输、运行架构、适用 AI 环境：
* Playwright MCP：MCP 协议服务端，把完整页面无障碍快照直接塞进 LLM 上下文窗口；
* Playwright-CLI（@playwright/cli）：命令行工具，DOM / 截图 / 快照全部存本地磁盘，只给模型返回极简元素 ID 引用

安装：  
```sh
# 安装
npm install -g @playwright/cli@latest
# 安装后查看
playwright-cli --help

# 为Claude Code设置为skill
# 而后Claude Code就可 slash command调用了
playwright-cli install --skills
```

核心维度横向对比表：

| 对比维度      | Playwright MCP                                 | Playwright-CLI                                      |
| ------------- | ---------------------------------------------- | --------------------------------------------------- |
| **Token消耗** | 极高，4–10倍CLI                                | 极低，节省80%–95%                                   |
| 文件系统依赖  | 不需要，纯内存                                 | 必须读写本地磁盘                                    |
| 兼容客户端    | 所有MCP标准客户端（Claude Desktop、通用Agent） | 带Shell权限编码助手（Cursor、Claude Code、Copilot） |
| 功能完整性    | 默认阉割大量高级API                            | 完整开放全部Playwright能力                          |
| 会话持久      | 服务常驻，原生长会话                           | 需手动管理会话ID，配置复杂                          |
| 扩展能力      | 仅原生工具，无Skill包                          | 支持自定义Skill技能模板                             |
| 页面数据传递  | 完整无障碍树直传上下文                         | 仅返回元素ID，快照存磁盘                            |
| 最佳场景      | 探索式自主Agent、无Shell沙箱、长期自主探索测试 | 开发代码生成、批量E2E测试、前端调试、爬虫           |
| 部署环境      | 云端隔离、容器、无本地权限                     | 本地开发环境、拥有完整终端权限                      |

选型建议（直接照场景选）

1）选 Playwright MCP：
1. 使用 Claude Desktop、通用MCP AI客户端，**没有本地Shell权限**；
2. 搭建完全自主探索式Agent、自修复测试，需要AI反复深度分析页面结构；
3. 云端/容器隔离环境，禁止读写本地文件；
4. 任务流程不长，不在乎token成本，优先追求开箱即用标准化集成。

2）选 Playwright-CLI：
1. 用 Cursor、Claude Code、GitHub Copilot 等编码IDE助手；
2. 做前端调试、批量E2E自动化测试、自动生成Playwright测试脚本；
3. 长流程多步骤自动化，需要控制LLM token开销、降低调用成本；
4. 需要完整Playwright高级能力（批量截图、网络拦截、多浏览器并发）；
5. 本地开发环境，拥有完整终端读写文件权限。

### 3.2. claude-code-setup

claude-code-setup 是 Anthropic 官方认证 Claude Code 插件，全称 Claude Automation Recommender（自动化配置推荐器）。

自动扫描当前代码仓库、识别技术栈，智能推荐整套 Claude Code 扩展配置（MCP、Skills、Hooks、子代理、斜杠命令），专门解决新手 / 新项目不知道该装什么 MCP、怎么配置扩展生态的痛点。

核心工作原理：
1. 扫描项目结构、依赖、源码特征，判断技术栈（React/Vue/Node/Python/ 后端服务等）
2. 分五大维度筛选适配扩展，每个类别优先给出 1~2 个最高性价比推荐，避免信息过载
3. 输出完整可复制的配置命令 / JSON 片段，直接复制就能接入 Playwright MCP、MarkItDown MCP 等你之前关注的工具

安装：  
```sh
# 添加官方市场，/plugin后安装 claude-code-setup 即可

# 使用，/claude-automation-recommender 触发
❯ /claude-automation-recommender
───────────────────────────────────
/claude-automation-recommender      (claude-code-setup) Analyze a codebase and recommend Claude Code automations (h…
```

在我的项目里执行的实例如下：会给不少有用的建议，还可以继续对话指定让AI补充一些具体方面的建议

```sh
/claude-code-setup:claude-automation-recommender

⏺ 我将分析 xworkbench 代码库,推荐适合的 Claude Code 自动化配置。先做代码库分析。
  Read 2 files, listed 6 directories (ctrl+o to expand)
⏺ 基于 xworkbench 代码库的分析,以下是推荐的 Claude Code 自动化配置(每类 1-2 项最相关的):
```

### 3.3. herdr：比tmux更好用的AI终端复用器

**越用越感觉好用**

![herdr使用示例](/images/1783848026295-image.png)

个人使用经验：
* 主题建议：`dracula`或者`nord`，对当前选择的session区分得更清楚
* **不同目录**创建不同的`workspace`工作区：这样左上侧展示更清晰。`tab标签页`不会体现在左侧，建议仅在同一个workspace里用。

#### 3.3.1. 基本介绍和安装

> [herdr](https://github.com/ogulcancelik/herdr)
>
> [文档](https://herdr.dev/zh-cn/docs/concepts/)

很实用的特性：
* tmux特性：本次打开的终端，下次输入`herdr`进入还是保持的
* 各菜单支持vim基本操作，上下控制`j/k`
* 支持鼠标点击操作、右键操作
* AI Agent展示，并且点击某个agent时，会自动跳转到对应窗口

**使用**：直接从仓库地址下载单二进制即可，添加到`PATH`路径。

**配置文件**在：`~/.config/herdr`下面

几个概念：

1、工作区（workspace）
* 工作区是最顶层的项目容器。为每个仓库、任务或调查使用一个工作区。
* 工作区拥有标签页和窗格。它在侧边栏中的状态由内部的智能体汇总而来,让你一眼看出哪个项目需要关注。

2、标签（tab）
* 标签页是工作区内的一种布局。用标签页来分隔不同视图,比如 agents、logs、server 或 review。
* 标签页可以通过 CLI 和 socket API 寻址。

3、窗格
* 窗格是一个真实的终端。Herdr 渲染终端输出,把输入传回进程,并在客户端分离后保留窗格。
* 窗格可以向右或向下分割。它们可以手动重命名、通过 CLI 读取、接收输入,以及被关闭。

4、会话（session）
* 会话是一个持久的 Herdr 服务器命名空间。默认的 herdr 命令连接到默认会话。
* 命名会话是彼此独立的运行时命名空间，`herdr session list`可查看

#### 3.3.2. 快捷键

> 基本所有操作都可以在页面上鼠标操作。

**前缀键（prefix）**是 `ctrl+b`，输入后即可用快捷键进行快速控制。

下面记录一些实操比较实用的快捷键，示例说明：`ctrl+b` + `q`这种表示先输入`prefix`前缀键后 -> **松开** -> 再输入`q`。

1、全局操作类
* 查看各快捷键：`ctrl+b`然后`?`，随时查看快捷键
* 退出herdr：`ctrl+b` + `q`。后续要进入的话输入`herdr`即可，原来的会话还是在的。在页面点击`menu`->`detach`效果一样。
* 重新加载配置文件：`ctrl+b` + `shift` + `r`
* 设置：`ctrl+b` + `s`

2、导航类操作
* 工作区(workspace)导航：`ctrl+b` + `w`，进入后可以**快速裂屏(split)**，`prefix+j/k/l/h`切换位置。支持**右键**后鼠标操作。
* 新建工作区：`ctrl+b` + `shift` + `n`

* 会话(session)导航：`ctrl+b` + `g`，进入后可以选择不同会话（可跨工作区），还支持过滤名称、过滤状态（鼠标按键即可）
* 新建会话：`ctrl+b` + `shift` + `g`，会创建新的worktree（会让你先确认worktree名称）

#### 3.3.3. windows下使用（手动编译）

> 预发布版本里有windows的产物，比如：[release-preview-2026-07-07](https://github.com/ogulcancelik/herdr/releases#release-preview-2026-07-07-f5354780e4ef)

由于windows下我使用Claude Code时Agent里没显示，以及我需要支持codebuddy，修改代码后手动编译下。

~~手动编译，`rust-toolchain.toml`里限定了编译工具链为`1.96.1"`，自己本地更新了`cargo 1.97.0`~~
~~* 可用`rustup override set stable`来解除自己本地的版本强要求（不修改项目里的限制）~~
~~* 恢复则用`rustup override unset`~~

编译报错，提示需要zig：

```sh
...
    cargo:rerun-if-env-changed=ZIG

       --- stderr

       thread 'main' (2101680) panicked at build.rs:77:10:
       failed to execute zig build for vendored libghostty-vt: Os { code: 2, kind: NotFound, message: "No such file or directory" }
       note: run with `RUST_BACKTRACE=1` environment variable to display a backtrace
     warning: build failed, waiting for other jobs to finish...
```

Zig 是一门编译型、静态强类型、系统级编程语言，由 Andrew Kelley 开发，主打替代 C 语言，兼顾高性能、内存安全、极简语法、无 GC、无隐藏控制流。核心特点：
* **对标 C，可无缝互操作**。可以直接调用 C 库、编译 C 代码、导出 C ABI，不用绑定层；能逐步替换现有 C 项目。
* **手动内存管理，但大幅降低内存 bug**。没有 GC、没有 RAII；靠显式分配器、可选错误处理、编译期空指针检查杜绝野指针、内存泄漏。
* **零运行时隐藏开销**。没有隐式拷贝、没有异常栈展开、无隐形构造析构，性能贴近裸 C。
* 强大编译期计算（Comptime）
* 一体化工具链。比如：`zig build`：读取项目 build.zig 构建工程（替代 Make/CMake）；`zig fetch`：包管理器，拉取第三方依赖到全局缓存
* **跨平台、交叉编译原生支持**。一条命令就能编译 Windows/macOS/Linux/ 嵌入式固件，不用装对应平台 SDK。

下载一份zig，放到本地，添加到PATH环境变量。重新编译即可，建议编译release版本（`16MB release` vs `160MB debug`的大小区别）：

```sh
[root@xdlinux ➜ herdr git:(master) ✗ ]$ cargo build --release
    Finished `release` profile [optimized] target(s) in 0.10s
```

### 3.4. hookify

用于创建自定义钩子的插件，从Claude Code官方插件市场安装即可。

工作原理：
- Hookify 在这些事件上触发：PreToolUse、PostToolUse、Stop、UserPromptSubmit
- 读取 .claude/hookify.*.local.md 配置文件中的规则
- 规则匹配时显示警告或阻止操作

可用命令：
- /hookify - 从对话分析创建钩子
- /hookify:list - 列出所有配置的钩子
- /hookify:configure - 交互式启用/禁用钩子

### 3.5. loop-me

> 在这个集合里，里面还有一些其他的skill推荐：[mattpocock/skills](https://github.com/mattpocock/skills)

安装：`npx skills@latest add mattpocock/skills`

通过交互式“拷问”会话，深入挖掘用户需求，以生成高度详细且无歧义的自动化工作流规范。它专注于识别用户生活中的重复模式（“循环”），并将其转化为可由 AI 智能体直接执行的明确指令，从而实现任务的有效委托和自动化，确保规范清晰到无需额外提问即可被实现。
* 使用前：用户手动定义工作流时，常常因描述模糊或遗漏细节，导致在实际开发或自动化过程中需要频繁沟通和返工，耗费大量时间和精力。
* 使用后：此技能通过交互式提问，帮助用户产出高度清晰、无歧义的工作流规范，确保 AI 智能体可以直接实现，无需额外澄清，显著提升效率。

## 4. 文档处理类

### 4.1. markitdown：多格式文件转为Markdown

微软 AutoGen 团队开源的 Python 库 + 命令行工具，主打多格式文件统一转为结构化 Markdown，专为 LLM/RAG/AI 工作流设计，核心目标不是还原精美视觉排版，而是提取对大模型有用的语义结构（标题、列表、表格、链接、层级）。

支持类型：  
```
1. Office 文档
  .docx Word、.pptx PPT、.xlsx/.xls Excel、Outlook .msg 邮件
2. 电子书与 PDF
  PDF（文字版 + 扫描件 OCR）、EPUB 电子书
3. 媒体文件
  图片：JPG/PNG/TIFF，内置 OCR 提取图片文字、读取 EXIF 元数据
  音频：MP3/WAV，语音转文字（ASR）、提取录音元数据
4. 网页 & 网络资源
  HTML、YouTube 链接（自动抓取字幕转录）、RSS、维基百科页面
5. 结构化文本
  CSV、JSON、XML、Jupyter .ipynb 笔记本
6. 压缩包
  ZIP 文件：递归解压批量转换包内所有文件
```

仓库：https://github.com/microsoft/markitdown

安装：  
```sh
git clone git@github.com:microsoft/markitdown.git
cd markitdown
pip install -e 'packages/markitdown[all]'
```

### 4.2. OfficeCLI (20260712更新)

> [OfficeCLI](https://github.com/iOfficeAI/OfficeCLI)

说明见：[README_zh](https://github.com/iOfficeAI/OfficeCLI/blob/main/README_zh.md)
* 开源免费。**单一可执行文件**。无需安装 Office。零依赖。全平台运行。（单一自包含可执行文件，`.NET`运行时已内嵌 -- 无需安装任何依赖，无需管理运行时）
* OfficeCLI 的内置 HTML 渲染引擎，高度还原文档原貌 —— 这正是让 AI 拥有"眼睛"的关键。 它把 `.docx` / `.xlsx` / `.pptx` 渲染为 `HTML` 或 `PNG`，闭合 **"渲染 → 看 → 改"** 的循环。

安装：
* 包管理器安装：`npm install -g @officecli/officecli`
* 或者到GitHub下载：[GitHub Releases](https://github.com/iOfficeAI/OfficeCLI/releases)

**添加Skill**：
* 有上述CLI后，下载`https://officecli.ai/SKILL.md`作为skill即可，创建一个`officecli`的目录

关闭自动更新：
* OfficeCLI 会在后台自动检查更新。通过 `officecli config autoUpdate false` 关闭，或通过 OFFICECLI_SKIP_UPDATE=1 跳过单次检查。配置文件位于 `~/.officecli/config.json`。


## 5. 综合办公类

### 5.1. 豆包电脑版

豆包桌面端是字节自研的电脑全域 AI 助手，主打全局悬浮窗、**本地文件操作**、**内置 AI 浏览器**、文档协同、多模态全能创作、桌面智能 Agent，打通电脑所有软件、网页、本地文件，区别于网页版 / 手机 App，深度适配电脑办公学习场景。

试了下挺好用，不过有额度限制。

**任务请求：**  
![req-ppt-task](/images/1782489570650-2026-06-2623.55.50.png)

**结果：**  
![ppt-result](/images/1782489752360-2026-06-2700.01.47.png)

**实际产物：**

1、生成的html分享文件：  
[xwork-bench-share-index.html](/images/srcfiles/xwork-bench-share-index.html)

2、生成的ppt：  
[xworkbench-v2-share-ppt.pdf](/images/srcfiles/xworkbench-v2-share-ppt.pdf)

### 5.2. OpenHuman

> [OpenHuman中文文档](https://openhuman.org.cn/docs/overview/what-is-openhuman)

OpenHuman 是面向个人工作流的桌面 AI Agent：它试图把你的本地知识库、日历、邮件、浏览器、协作工具和模型能力连成一个长期运行的个人上下文系统。
* OpenHuman 的思路是把上下文沉淀为可追踪的记忆结构，并让这些记忆可以被用户看见、编辑和迁移。
* 基于 Obsidian / Markdown，OpenHuman 同时包含桌面 GUI、Rust Core、Memory Tree、Obsidian Wiki、模型路由和集成层。
* OpenHuman 的核心不是单个聊天窗口，而是一套围绕个人上下文长期运行的桌面系统。它把桌面端、Rust Core、本地工作区、Obsidian 可读记忆、模型路由、OAuth 集成和原生工具连接成一个闭环：先收集上下文，再整理记忆，最后让 Agent 在用户授权范围内执行任务。

试用：

下载后启动，自动安装环境：  
![自动安装环境](/images/1782834425369-image.png)

按提示依次配置：  
![配置](/images/1782835012436-image.png)

语义检索，可选向量数据库：  
![向量数据库](/images/1782835174556-image.png)

记忆库，基于obsidian：  
![记忆库设置](/images/1782835250817-image.png)

自定义模型，此处用`/v1`形式(openai格式，mimimax地址 `https://api.minimaxi.com/v1`)：  
![自定义模型](/images/1782837080533-image.png)

## 6. 多媒体类

### 6.1. khazix-skills/aihot：中文 AI 资讯查询

> [AI HOT SKILL](https://github.com/KKKKhazix/khazix-skills/blob/main/aihot/SKILL.md)

AI HOT (aihot.virxact.com) 中文 AI 资讯查询 Skill。让 Agent 用最自然的中文查询拿到 aihot.virxact.com 上每天的 AI HOT 日报和全部 AI 动态，不需要打开浏览器。SKILL.md 标准格式，跨 Claude Code / Codex CLI / Cursor / Gemini CLI / OpenCode / 任何兼容平台可用。

### 6.2. BestBlogs：AI 驱动的私人阅读助手

> [BestBlogs](https://github.com/ginobefun/BestBlogs)

每天上下班路上都在听的小宇宙播客，很多AI相关技术文章、资讯等汇总整理。

支持CLI：（貌似有点问题）

```sh
npm install -g @bestblogs/cli
bestblogs auth login           # 输入 API Key（在设置页生成）
bestblogs discover today       # 今天最值得读的内容
bestblogs read deep <id>       # 深度阅读一篇
```

## 7. 总结

> 待补充：使用心得、对比、推荐场景
