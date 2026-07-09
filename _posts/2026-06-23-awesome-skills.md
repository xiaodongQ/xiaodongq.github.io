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

  Claude Code Automation Recommendations

  Codebase Profile

  - 类型: Go 1.25 后端单二进制 + 嵌入前端 (vanilla JS)
  - 关键依赖: gorilla/websocket、modernc.org/sqlite(纯 Go)、creack/pty、robfig/cron/v3、zap
  - 规模: 65 个 .go 文件 / 14 张 SQLite 表 / 91 个 HTTP 路由
  - 已配置: .claude/CLAUDE.md、6 个 openspec-* 技能、playwright-cli 技能、opsx commands、settings.local.json 已放行
  WebFetch+Edit

  ---
  🔌 MCP Servers

  GitHub MCP

  Why: 项目用 git 管理,已有 .github/workflows/,Claude Code 平时改完代码需要走 gh pr create / gh issue view 时,装上
  GitHub MCP 后能直接 mcp__plugin_github_github__* 操作 PR/Issue/Actions,比手动切 gh 流畅很多;也避免每次都让 Claude 拼
  URL。
  前置: gh auth login 已完成(本机已有)
  安装: claude mcp add --transport http github https://api.githubcopilot.com/mcp/(走 OAuth,首次会触发授权)

  context7

  Why: 大量用了 gorilla/websocket、robfig/cron/v3、modernc.org/sqlite 这类库,API 表面经常会跨小版本变(典型:gorilla
  websocket 的 CloseMessage code 常量、cron 的 WithSeconds 选项)。需要查库的最新签名/行为时,context7 实时拉官方文档,比
  WebFetch 抓 GitHub README 准。
  安装: claude mcp add context7

  ---
  🎯 Skills

  xworkbench-add-endpoint

  Why: CLAUDE.md §12 已经把"加新端点"流程写得很死板(5 步:加路由→添 repo→写 handler→前端 fetchJSON→写
  httptest)。这就是教科书级 skill 用例 —— 把文档里那段直接转成 /xworkbench-add-endpoint 技能,Claude 接到"加个
  /api/foo"指令时按 5 步执行,不会漏写测试。
  创建: .claude/skills/xworkbench-add-endpoint/SKILL.md
  调用: Both(用户 /xworkbench-add-endpoint,Claude 也会自动用)
  模板:
  ---
  name: xworkbench-add-endpoint
  description: Use when adding a new HTTP endpoint to xworkbench. Follows the 5-step pattern (route → repo → handler →
  frontend → test) defined in CLAUDE.md §12.
  ---
  # Add xworkbench HTTP endpoint
  按 CLAUDE.md §12 的 5 步走...

  xworkbench-e2e

  Why: ./scripts/e2e.sh 支持 basic / fast / 全量 / 远端 URL 多种模式,默认跑全量比较重。包成 skill 后 Claude 在改动 API
  后能自动跑 fast 模式(复用运行中的 server)验证,不打扰用户。
  创建: .claude/skills/xworkbench-e2e/SKILL.md
  调用: Both
  模板:
  ---
  name: xworkbench-e2e
  description: Use when verifying API changes work end-to-end. Wraps ./scripts/e2e.sh with smart mode selection (fast vs
   basic vs full).
  ---
  # Run e2e tests
  判断改动范围 → 选模式...

  ---
  ⚡ Hooks

  PostToolUse: 改 .go 后自动 gofmt + go vet

  Why: CLAUDE.md §13.9 明确写"gofmt 一定要跑,Go 1.25 工具链强约束,CI 会卡" —— 这就是自动化的标准场景。每次 Edit/Write 完
   .go 文件,跑 gofmt -w + go vet 当场发现问题,不用等 CI 撞墙。
  位置: .claude/settings.json
  配置:
  {
    "hooks": {
      "PostToolUse": [{
        "matcher": "Edit|Write",
        "hooks": [{
          "type": "command",
          "command": "if [[ \"$CLAUDE_FILE\" == *.go ]]; then gofmt -w \"$CLAUDE_FILE\" && go vet ./...; fi"
        }]
      }]
    }
  }
  注意: CLAUDE_FILE 是 Claude Code 暴露给 hook 的环境变量,需根据实际 schema 调整(若不支持,可改成在 hook 脚本里 ls *.go
  扫最近改动)。

  ---
  🤖 Subagents

  go-handler-reviewer(针对 main.go handleXxx)

  Why: cmd/server/main.go 91 个路由,大量 handleXxx 函数,Claude 写新 handler 时容易抄老 handler 的反模式(漏 writeErr、忘
  writeJSON、错误吞掉 context、用 log.Println 而非 zap)。一个专门审 Go HTTP handler 的 subagent,按项目约定(看
  terminal_api_test.go 风格 + CLAUDE.md §12)对照检查,比通用 code-reviewer 更贴这个项目。
  位置: .claude/agents/go-handler-reviewer.md
  模板:
  ---
  name: go-handler-reviewer
  description: Reviews xworkbench HTTP handlers against project conventions. Use after editing cmd/server/main.go or
  adding a new handleXxx function.
  tools: Read, Grep, Glob, Bash
  ---
  你专审 xworkbench 的 Go HTTP handler...
  检查清单:
  - 错误用 writeErr(w, code, msg) 而非 http.Error
  - 成功用 writeJSON(w, data) 而非手动 marshal
  - 路由在 routes() 注册了吗
  - 测试文件 *_api_test.go 写了吗
  - context 透传了吗(尤其 DB/Cache 操作)

  ---
  已有的(无需再加)

  - ✅ openspec-*/opsx commands —— spec 驱动工作流已配置
  - ✅ playwright-cli skill —— 浏览器自动化已配置
  - ✅ settings.local.json 放行 Edit —— 写权限已开
  - ✅ CLAUDE.md(项目 + 用户)—— 上下文已加载

  ---
  想看更多吗? 告诉我聚焦哪类:
  - "再来 3 个 MCP server 方案"(比如 Linear / Slack / Sentry)
  - "再给几个 hook"(比如 PreToolUse 拦 config.json 编辑,PostToolUse 跑 go test 相关包)
  - "再给几个 subagent"(比如 security-reviewer 看 scheduler、performance-analyzer 看 DB query)

  想直接落地? 我可以挑其中任意 1-2 项直接帮你写好文件。
```

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
