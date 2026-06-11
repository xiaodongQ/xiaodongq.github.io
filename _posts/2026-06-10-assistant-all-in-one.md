---
title: AI能力集 -- 构建个人All-In-One助手应用
description: 将之前尝试过的自动任务系统
categories: [AI, AI能力集]
tags: [Hermes, Agent, 自部署]
---

## 1. 引言

在近期几个尝试和之前折腾过的自动任务系统基础上，结合自己的一些刚需来开发一个个人助手：
* [AI能力集 -- 开发一个任务自动执行系统](https://xiaodongq.github.io/2026/04/19/ai-auto-task-system/)
* [AI能力集 -- 开发一个 Skill 工厂](https://xiaodongq.github.io/2026/06/05/skill-factory-impl/)
* [AI能力集 -- /loop 三天就废?如何设置长定时任务](https://xiaodongq.github.io/2026/06/05/claudecode-loop-task/)

## 2. 需求描述（输入）

在原有demo基础上进行分析。（归档在[ai-playground](https://github.com/xiaodongQ/ai-playground)）

分析下skill-factory和ai-task-system v2.4，是否能合成一个系统（all in one）。另外我还想加上一些其他功能：

1、主页上能让我快捷添加/删除一些网页链接，用于我平时的跳转（左上角）

比如 github主页：https://github.com/xiaodongQ/、博客地址：https://xiaodongq.github.io/ 等

2、主页上能让我添加/删除一些目录地址，点击时自动用对应系统的资源管理器打开（左中）

3、能在页面添加定时任务，定时任务可以让AI CLI来执行命令。支持Claude Code和Codebuddy（headless命令为cbc -p，支持--model指定模型）

4、能读取我本地的todo.md文件（路径可以让我设置指定一个），主页展示todo项（左下）

5、可以为系统添加定时任务和查看系统上启用的计划任务，尤其是windows系统

## 3. AI分析探索

上述是提示词输入给Claude Code的Plan模式：

### 3.1. 思考过程

```sh
  用户希望我：

  分析 skill-factory 和 ai-task-system v2.4 是否能合成一个 all-in-one 系统
  添加 5 个新功能：
  左上角：快捷网页链接（可增删）
  左中：目录快捷跳转（点击用资源管理器打开）
  定时任务：让 AI CLI（Claude Code / Codebuddy cbc -p）执行命令
  读取本地 todo.md 展示
  定时任务（尤其是 Windows）
  现在处于 Plan 模式。我需要：

  阶段1：用 Explore 子代理探索代码
  阶段2：用 Plan 代理设计
  阶段3：审核
  阶段4：写最终计划
  阶段5：调用 ExitPlanMode
  让我先并行启动 Explore 代理来研究两个系统。

  需要了解：

  skill-factory 的结构（已有大致了解）
  ai-task-system v2.4 的结构
  两者能否融合
  让我启动 2 个 Explore 代理：

  一个深度探索 skill-factory
  一个深度探索 ai-task-system v2.4
  或者：

  探索 ai-task-system v2.4（因为 skill-factory 刚看过）
  探索两个系统的差异和潜在融合点
  我倾向于 2 个 Explore 代理：

  代理 1：探索 ai-task-system v2.4
  代理 2：探索两个系统的差异和现有可复用的代码/工具/数据模型
  不过 skill-factory 我已经看得差不多了，主要需要探索 ai-task-system。让我启动 2 个并行的 Explore 代理。

  但首先，我可能想先简单看一下 ai-task-system 目录结构，再决定。Plan 模式允许我读取文件。让我用 ls 看一下。
  ...
```

### 3.2. 输出探索报告和方案

输出的几个文档：
* [AI Task System v2.4 深度探索报告](/images/srcfiles/skill-factory-ai-task-system-v2-4-sleepy-mitten-agent-acdee42e2dbc38772.md)
* [Skill-Factory × AI-Task-System v2.4 — All-in-One 个人工作台](/images/srcfiles/skill-factory-ai-task-system-v2-4-sleepy-mitten.md)
* ["all-in-one" 个人工作台 — 设计方案](/images/srcfiles/skill-factory-ai-task-system-v2-4-sleepy-mitten-agent-aaa8f0a08bb7aea5f.md)

设计方案中的部分内容：

> 项目代号：**workbench**（暂定，最终可改）
> 基线：保留 `skill-factory`（Go + SQLite + 漂亮 UI + PTY + 经验库），融合 `ai-task-system v2.4` 的调度器/执行器/评估器，并新增 5 个功能
> 关键事实校对：
> - `skill-factory` 入口 `cmd/server/main.go`（Go 1.25，net/http + embed.FS），3 张表 tasks/experiences/skill_versions
> - `ai-task-system v2.4` 入口 `backend/main.py`（FastAPI + aiosqlite），3 张表 tasks/executions/evaluations，调度器 5s 轮询 + 30s 心跳 + 120s stale 阈值
> - 4 种确认信号在 `cli_executor.py:62-115`：`needs_user_input` 关键词 + `parse_confirm_request` 正则 / 嵌套 JSON 解析
> - **重要修正**：v2.4 自带的 `tests/__init__.py` 是空的；真实的 pytest 文件在父目录 `ai-task-system/tests/` 下，v2.4 实际无现成 Python 测试可移植
> - skill-factory 已用 `creack/pty`（POSIX 端正常）+ `gorilla/websocket` + `modernc.org/sqlite`（纯 Go，跨平台无需 CGO）

---

**一、整体架构决策：**

推荐方案：**单 Go 二进制 + 同进程调度/PTY/Web**（"all-in-one" 实质落地）

用户明确说"all in one"，且 skill-factory 已经是漂亮的单二进制；选 Go 单体。

**理由**：

| 维度          | 单 Go 二进制（推荐）                                  | 双进程（Go + Python）                                                                            |
| ------------- | ----------------------------------------------------- | ------------------------------------------------------------------------------------------------ |
| 部署          | 1 个文件 / 1 个进程 / 1 个 sqlite 文件                | 2 个进程，Python 虚拟环境 + Go 二进制 + 2 套配置                                                 |
| 启动 / 关停   | 1s 内冷启；停机=kill 一个进程                         | 需协调子进程生命周期、端口、孤儿清理                                                             |
| 跨平台        | `go build` 矩阵：darwin/linux/windows 三平台单文件    | Python 依赖（aiosqlite/uvicorn/fastapi）在 Windows 路径处理多坑（`\` vs `/`、UAC、Service 包装） |
| 内存 / 性能   | 同进程调用，零序列化                                  | IPC（HTTP/stdio）多 ~5-10ms/调用 + 序列化                                                        |
| 共享 DB       | 同一 `*sql.DB` 句柄                                   | 需要约定文件锁、并发模式                                                                         |
| 用户预期      | "all in one" 直接满足                                 | 用户仍感知"两个系统"                                                                             |
| 调度器 / 心跳 | goroutine + `time.Ticker`，`context.Context` 优雅退出 | asyncio + 进程间状态共享（额外写一份心跳文件）                                                   |


**二、关键 Go 库选型：**

| 用途                  | 库                                                                              | 说明                                                                                        |
| --------------------- | ------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------- |
| HTTP 路由             | stdlib `net/http`（Go 1.25 已支持 `mux.HandleFunc("POST /api/x", h)` 模式匹配） | 沿用 skill-factory，不引入第三方路由                                                        |
| WebSocket             | `github.com/gorilla/websocket`                                                  | 沿用                                                                                        |
| SQLite                | `modernc.org/sqlite`                                                            | 纯 Go，**跨平台无 CGO**（关键：Windows 编译一次过）                                         |
| UUID                  | `github.com/google/uuid`                                                        | 沿用                                                                                        |
| Cron                  | `github.com/robfig/cron/v3`                                                     | 行业标准，支持秒级 / 时区 / 解析 `Next(t)`；同时支持 `cron.ParseStandard("0 9 * * *")` 5 段 |
| 跨平台进程            | stdlib `os/exec`                                                                | 跨平台（Windows 自动用 `TerminateProcess` 代替 SIGKILL）                                    |
| Markdown 写回         | stdlib `bufio` + `os` + 正则                                                    | 不引入第三方，逻辑简单                                                                      |
| 进程内服务（Windows） | `github.com/kardianos/service`                                                  | 可选：把二进制注册成 Windows Service；先做"开机启动 + 托盘"再决定                           |
| 嵌入前端              | stdlib `embed`                                                                  | 沿用                                                                                        |
| 日志                  | stdlib `log/slog`                                                               | 替代 v2.4 的 RotatingFileHandler，结构化 + 易对接                                           |

## 4. 代码实现

```
🎉 整体收工
6 个 Phase 全部完成
Phase	范围	状态
Phase 1	9 张表 + models 扩展 + 迁移逻辑	✅
Phase 2	AI CLI 执行器 + WS + 任务执行 API	✅
Phase 3	5 新功能后端 + 前端 5 widget + 4 modal	✅
Phase 4	pty build tag 隔离 + 三平台编译	✅
Phase 5	5 份文档	✅
Polish	4 个 form modal 替代 prompt()	✅
项目最终形态

skill-factory/
├── cmd/server/        2,881 行 Go + 1,127 行 HTML
├── internal/          9 个包（backend/executor/hub/scheduler/shortcuts/todo/...）
├── docs/              4 份文档（CLI/MIGRATION/SCHEDULER + DESIGN）
├── data/              6 份 db 备份（v1→v2 fresh→phase2/3/3-ui/4-modal）
├── DESIGN.md          166 行
├── README.md          122 行
└── go.mod             Go 1.25 + robfig/cron + gorilla/websocket
关键数字
* Go 代码：2,881 行
* 前端 HTML：1,127 行（增长自 v1 的 707 行）
* 三平台二进制：macOS 15.0 MB / Linux 15.5 MB / Windows 15.9 MB
* 测试：6 包全通过
* API 端点：30+
* 数据表：9 张
* WebSocket 频道：6 个
* AI CLI 类型：claude / cbc / shell

跑起来

cd /Users/xd/Documents/workspace/repo/ai-playground/skill-factory
go build -o skill-factory ./cmd/server
DB_PATH=./data/skill-factory.db ADDR=:8080 ./skill-factory
# 浏览器开 http://localhost:8080
数据备份齐全（6 份），跨平台编译通过，5 个新功能 + 30+ API + 调度器 + 4 modal UI 全部跑通。可作为 v0.1 收工。
```

## 5. 编译运行



## 6. 过程问题

### 6.1. 关于参考Karpathy启发的编码原则

由于之前加过`受 Andrej Karpathy 启发的编码原则`，AI思考时一直在强调 "精准修改"和"不要改进相邻代码"原则，其实这次的任务是可以大范围重构的，我对之前的页面并不满意。

应对操作：从`~/.claude/CLAUDE.md`里去掉这条：`3. 精准修改`，其他几项感觉还是挺有意义的

```
用户选"现在改前端（5 widget）"。

按 plan § 5：

12 列 grid 布局
5 个新 widget（链接/目录/todo/定时/AI 任务）
沿用现有 vanilla JS + 手写 CSS
WS 客户端
拆出 app.js 模块
但 index.html 现在 707 行，要"重写"还是"插入新 section"？按"精准修改"和"不要改进相邻代码"原则，应该在现有结构上追加 5 个 section，不破坏原有 Tab 体系。

实际上，phase 3 widget 是给主页"个人 dashboard"用的，跟原有 5 Tab 不冲突。我可以在 index.html 顶部加一个 dashboard section（默认显示），其他 Tab 保留。

或者更简单：在 index.html 顶部/侧边加一个固定的"快捷面板"，里面嵌入 5 个 widget。

按 plan § 5 设计的 12 列 grid：

左 4 列：链接 / 目录 / todo 三宫格
中 5 列：AI 任务列表
右 3 列：定时任务 + 7 天柱图
这是一个新的 home dashboard 布局。我应该重写 index.html 顶部区域为这个布局，把现有 Tab 移到"More"位置或者下拉里。

但重写 707 行的工作量大，按"精准修改"我应该：

把现有内容保留作为 Tab（"Task Manager" / "Experiences" / "AI Chat" / 等）
在主页面之前插入一个 "Home" section
不过 plan § 5 写的是"重写为 12 列 grid"。让我做个折中：在主区上方加 12 列 grid（Home Dashboard），下面留原 Tab 内容（可在 Tab 之间切换）。

实际上，看现状：

index.html 有 5 Tab（Dashboard / Tasks / Experiences / Automation / AI Chat）
5 Tab 里"Automation"可能就是定时任务的预留位置
"Dashboard" 已经有 7 天柱图
最简洁的做法：

在原有 5 Tab 体系上，扩展内容
把 5 个新 widget 嵌入到合适的 Tab 里
添加 / 修改 CSS 让布局支持
不重写，只追加。这符合"精准修改"原则。
```

可在思考过程中，看到这条规则也是有触发：`2. 简洁优先`

```
让我重写 DESIGN.md。简洁、聚焦"已实现"而非"方案"，从 v1 演进到 v2。

按"简洁优先"，DESIGN.md 大约 250 行够了。
```

### 6.2. 主动要求重构

输入：你可以重构这个页面，不需要受限于精准修改原则，进行合理拆分设计

可看到思考过程里，简洁优先原则是挺起作用的：

```
用户让我重构 index.html 这个页面，不受"精准修改"原则限制，可以做合理拆分设计。这是 Phase 3 时我就提到要做但当时受限于"精准修改"原则没做的——博客文章里也提到了用户决定去除该原则。

现在 index.html 1127 行了，确实需要拆分。让我设计一下：

当前结构：

<head> + <style> (含 widget CSS 等)
<body>
Sidebar (5 Tab 导航)
<main> (5 个 Tab page)
6 个 modal (task/exp/link/dir/todo-path/scheduled)
<script> (大量 JS 混在一起)
重构策略：
按"简洁优先"和"合理拆分"：

index.html 极简化：只剩骨架 + embed 引用
拆 CSS 到独立文件：static/css/base.css (设计系统) + static/css/widgets.css (5 widget) + static/css/modals.css (4 modal) — 用 embed 嵌入
拆 JS 到模块：纯 Go embed 不能 import JS 文件，但可以用 <script> 标签分文件（每个 widget 一个 .js），或用一个 app.js 主入口 + 内嵌 // @ts-check 风格

...

但这样太多文件了，简洁优先。让我精简到 3 层：
...

让我再做下分类 — 用 1 widget = 1 文件的策略：

static/js/
  api.js              — 通用：fetchJSON / statusTag / fmt / esc / debounce
  core.js             — switchTab / reloadCurrentTab / dom helpers
  widgets/
    links.js          — loadLinks + showLinkModal + close + submit + delete
    dirs.js           — loadDirs + showDirModal + close + submit + open + delete
    todo.js           — loadTodo + toggle + showTodoPathModal + close + submit
    scheduler.js      — loadScheduler + start/stop/reload + loadScheduledSummary
    executions.js     — loadRecentExecutions
  views/
    dashboard.js      — loadDashboard (调用 widget + render chart + recent tasks) + wrap init
    tasks.js          — Tasks Tab 全套 + task modal
    experiences.js    — Experiences Tab + exp modal
    automation.js     — Automation Tab (loadScheduled + showScheduledModal + runScheduled + deleteScheduled)
    aichat.js         — AI Chat + xterm

11 个 JS 文件。感觉多了一点。再精简：
static/js/
  api.js              — 通用：fetchJSON / statusTag / fmt / esc / debounce / switchTab / reloadCurrentTab
  views/
    dashboard.js      — Dashboard Tab + 5 widget + 4 modal（links/dirs/todo/scheduler/executions）
    tasks.js          — Tasks Tab + task modal
    experiences.js    — Experiences Tab + exp modal
    automation.js     — Automation Tab + scheduled modal
    aichat.js         — AI Chat
```