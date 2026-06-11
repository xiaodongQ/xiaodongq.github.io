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
