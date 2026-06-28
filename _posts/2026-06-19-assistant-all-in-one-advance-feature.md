---
title: 个人AI工作台（二） -- All-In-One助手新增高级特性
description: 续篇，介绍第一篇之后新增的高级特性；2026-06-27 重组章节结构，9/10/11/12 四节
categories: [AI, 个人AI工作台]
tags: [Agent, 个人助手, xworkbench]
last_modified_at: 2026-06-27
---

## 1. 引言

续篇，在[构建个人All-In-One助手应用](https://xiaodongq.github.io/2026/06/10/assistant-all-in-one/)的基础上，按需叠加了大量新功能。本文按功能大类组织，介绍思路和实现方式，代码位于 [xiaodongQ/xworkbench](https://github.com/xiaodongQ/xworkbench)。

## 2. AI 任务执行增强

### 2.1 AI 继续对话（--resume）

**问题：** `claude -p` 默认每次都是全新会话，无法在同一个上下文中继续追问。

**思路：** `claude -p --output-format json` 执行后会返回一个 `session_id` 字段，后续用 `--resume <session_id>` 可以基于前一个会话继续对话。

**实现：**

1. **解析 session_id**：执行完成时从 JSON 输出中提取 `session_id` 存入 `executions.resume_uuid` 字段
2. **继续对话 API**：`POST /api/executions/{id}/continue`，用 `--resume <uuid>` 构建新命令，创建新 execution 并异步执行
3. **前端 UI**：执行详情弹窗底部有 resume_uuid 时显示「💬 继续对话」按钮，点击展开输入框

关键代码路径：`cmd/server/main.go` 的 `handleExecutionContinue`，`internal/executor/runner/build.go` 的 `WithResume` 选项。

持续对话的实际测试：

* claude code，`session_id`字段：（**注意不是`uuid`**）

```sh
[MacOS-xd@qxd ➜ xworkbench git:(main) ✗ ]$ claude -p 测试 --output-format json
{"type":"result","subtype":"success","is_error":false,"duration_ms":11430,"duration_api_ms":11239,"num_turns":1,"result":"你好！测试收到。我在这里待命，有什么可以帮你的吗？","stop_reason":"end_turn","session_id":"6f71aa4f-fc91-456d-b7d5-2f3b3ff8d64e","total_cost_usd":0.21196874999999998,"usage":{"input_tokens":0,"cache_creation_input_tokens":33007,"cache_read_input_tokens":0,"output_tokens":227,"server_tool_use":{"web_search_requests":0,"web_fetch_requests":0},"service_tier":"standard","cache_creation":{"ephemeral_1h_input_tokens":0,"ephemeral_5m_input_tokens":0},"inference_geo":"","iterations":[],"speed":"standard"},"modelUsage":{"MiniMax-M2.7":{"inputTokens":0,"outputTokens":227,"cacheReadInputTokens":0,"cacheCreationInputTokens":33007,"webSearchRequests":0,"costUSD":0.21196874999999998,"contextWindow":200000,"maxOutputTokens":32000}},"permission_denials":[],"terminal_reason":"completed","fast_mode_state":"off","uuid":"15e3acf3-5ba6-485b-9d14-e390ddce5ee9"}

[MacOS-xd@qxd ➜ xworkbench git:(main) ✗ ]$ claude -p 刚刚发送过什么 -r 6f71aa4f-fc91-456d-b7d5-2f3b3ff8d64e

你刚刚发送的是 **"测试"** 这条消息。
```

* codebuddy

```sh
# 分了很多段，`type`的类型作为不同分段的区分，很多段都有sessionId，是同一个。
# 可以选择一个类型来获取sessionId，比如："type": "ai-title",
[MacOS-xd@qxd ➜ xworkbench git:(main) ✗ ]$ cbc -p 测试 --output-format json
[
  {
    "type": "message",
    "role": "user",
    "content": [
      {
        "type": "input_text",
        "text": "<system-reminder data-role=\"memory\"><memory>\n# auto memory\n\nYou have a persistent, file-based memory system at `/Users/xd/.codebuddy/projects/Users-xd-Documents-workspace-repo-xworkbench/memory`. This directory already exists — write to it directly with the Write tool (do not run mkdir or check for its existence)..........ear here.\n</memory></system-reminder>"
      },
      {
        "type": "input_text",
        "text": "<system-reminder>\nAs you answer the user's questions, you can use the following context:\n# codebuddyMd\nCod...you should follow if appropriate.\">\n\nContents of /Users/xd/.codebuddy/CODEBUDDY.md (user's private global instructions for all projects):\n\n与用户交流使用中文，生成的文件名等信息还是用英文，合理规划。\n\n现复杂度较高的项目时，需要合理评估优先考虑工业级的方案而不是demo 玩具性质。\n\n## AI 行为准则\n\n> 受 Andrej Karpathy 启发的编码原则\n\n### 1. 编码前思考\n\n- **不要假设........ur task.\n</system-reminder>\n"
      },
      ...
      {
        "type": "input_text",
        "text": "<user_query>测试</user_query>"
      }
    ],
    "providerData": {
      "agent": "cli"
    },
    "id": "efdb3bcb-b7a0-41ed-8494-d378038fe4aa",
    "timestamp": 1781968910641,
    "sessionId": "a6a12155-bd74-484f-b718-97b53da756fe"
  },
  {
    "type": "file-history-snapshot",
    "id": "918db229-b821-42bb-9cb1-757051e41174",
    "timestamp": 1781968910651,
    "isSnapshotUpdate": false,
    "snapshot": {
      "messageId": "efdb3bcb-b7a0-41ed-8494-d378038fe4aa",
      "trackedFileBackups": {}
    }
  },
  ...
},
{
  "type": "ai-title",
  "aiTitle": "测试",
  "sessionId": "a6a12155-bd74-484f-b718-97b53da756fe",
  "timestamp": 1781968912976
},
...


# 继续对话
[MacOS-xd@qxd ➜ xworkbench git:(main) ✗ ]$ cbc -p 刚刚发了什么 -r a6a12155-bd74-484f-b718-97b53da756fe
上一条我回复的是：

> 你好！我已就绪，可以帮你处理软件工程相关的任务。有什么需要协助的吗？

就是一个简单的欢迎回应，因为你发的"测试"看起来像是在测试连接是否正常。
```


### 2.2 评估闭环（自动换模型重试）

**问题：** AI 执行一次效果不好，需要人工重新调参数再跑。

**思路：** 执行 → AI 评估打分 → 分数低于阈值则换更强模型重试，最多 N 轮。评估 prompt 要求 LLM 输出 `评分: X` 与 `评语: ...`，解析失败或真低分时不互相 fallback。

**效果：** 任务自动多轮尝试，最终输出最优结果。

### 2.3 Prompt 格式优化

**问题：** Windows 命令行长度限制 8191 字符，长 prompt 直接被截断。

**思路：** 通过 stdin 传递 prompt，不走命令行参数。任务执行 prompt 包含经验库上下文，供 AI CLI 参考。

### 2.4 经验库多经验关联

**问题：** 一个任务可能涉及多个经验领域，之前只能关联一个。

**思路：** 任务与经验库从一对一改为多对多关联，任务编辑弹窗支持多选经验。

### 2.5 Prompt 精简（移除冗余段）

**问题：** `BuildTaskPrompt` 拼出的 prompt 里同时有 `# 用户指令` 和 `# 任务背景` / `# 任务描述` 几段都引用 `task.Description`，内容重复且增加 token 开销。

**思路：** `# 任务背景` 段已经包含了任务描述全文，`# 用户指令` 段去掉。

**实现：** `internal/task/prompt.go:BuildTaskPrompt` 删除 `# 用户指令` + `t.Description` 两行。

## 3. 远程 Agent 系统

### 3.1 Agent 注册与心跳

**思路：** 允许外部程序注册为 Agent，xworkbench 通过心跳检测 Agent 是否存活（30s 无心跳判离线）。注册后以 token 标识，心跳超时自动标记 offline。

### 3.2 任务认领与上报

**思路：** Agent 可以主动认领任务（按优先级排序），执行完成后上报结果（success/failed/error）。支持开关自动认领。

### 3.3 速率限制

**问题：** Agent API 暴露在外，需要防止滥用。

**思路：** 关键端点统一加速率限制，默认 60 req/min，按 IP 或 token 统计，支持环境变量调整或禁用。

### 3.4 Agent 管理面板（代理 Tab）

**思路：** 在「代理」Tab 加管理面板：列出所有 Agent，支持释放任务、重置 token、切换 auto-claim、删除等操作。也是连接 Relay 体系与 SSH 远端执行的桥梁（详见 9.2）。

## 4. 任务治理能力

### 4.1 任务评论

**思路：** 任务和执行详情都可以评论，方便记录上下文和讨论。后端 API 保留，前端 UI 已精简。

### 4.2 任务审计日志

**思路：** 任务状态变更统一记录到审计日志，便于回溯和调试。

### 4.3 任务依赖

~~**思路：** 某些任务必须等前置任务完成才能开始。~~

> **状态：已移除**。详见 12.2。

### 4.4 任务模板

~~**思路：** 常用任务结构可以保存为模板，一键创建。~~

> **状态：已移除**。详见 12.2。

### 4.5 保存的过滤器

~~**思路：** 任务列表的筛选条件可以保存，方便快速切换视图。~~

> **状态：已移除**。详见 12.2。

### 4.6 Webhook 派发

~~**思路：** 任务状态变更时自动通知外部系统（如飞书/钉钉/其他服务）。~~

> **状态：已移除**。详见 12.2。

### 4.7 任务优先级

**思路：** 任务有优先级，高优先级任务优先被认领和执行。

## 5. Relay 代理体系

### 5.1 HTTP 请求代理

**问题：** 某些内部服务没有外网权限，需要通过 xworkbench 服务器转发。

**思路：** xworkbench 作为 HTTP 代理，透传请求到目标 URL，自动携带认证头，并记录每次代理请求的来源/目标/状态。

### 5.2 服务器端命令执行

**问题：** 需要在 xworkbench 所在机器上远程触发脚本执行。

**思路：** 提供命令执行 API，在服务器端 shell 执行并返回结果。

### 5.3 API Key 认证

**问题：** Relay API 暴露需要认证。

**思路：** Bearer Token 或 X-API-Key 头认证，默认 key 可配置。

## 6. 运维能力

### 6.1 启停脚本改进

**问题：** 之前 `lsof -ti:port` 会误报端口被占用（Chrome 的 CLOSE_WAIT 也被检测到），导致无法重启。

**思路：** 只检查 LISTEN 状态，忽略 CLOSE_WAIT/TIME_WAIT 等其他状态。6.26 进一步改用端口监听检测，避免 stale PID 问题；打包产物改为按日期分目录存放。

### 6.2 统一日志输出

**思路：** 所有日志统一写入 `data/xworkbench.log`，使用 ISO8601 时间戳，各子包直接使用共享 logger。

### 6.3 评估输出截断

**问题：** 超大输出直接送评估浪费 token 且容易超时。

**思路：** 超过 100KB 的输出截断后再送评。

### 6.4 SQLite 并发修复（SQLITE_BUSY）

**问题：** 两个场景触发 `SQLITE_BUSY`：① PRAGMA 设置在懒连接池下只对首个连接生效；② 调度器与 RunNow 重叠时同 task 并发写 executions 表。

**思路：** ① PRAGMA 改为 DSN 参数形式，每个新连接自动生效，启动时验证 WAL 模式；② 调度器用 singleflight 合并同 task 的并发执行。

## 7. UI 改进

### 7.1 区块高度拖拽调整

**思路：** 快捷目录、快捷链接、待办事项各占区域高度需要手动微调。实现方式是每个区块底部加拖动柄，高度值存入 localStorage 持久化。

### 7.2 经验库字段精简

**问题：** 经验库字段过多。

**思路：** 将多个辅助字段合并为一个 JSON 字段存储，减少冗余。

### 7.3 任务表单精简

**移除字段：** module、resources。

## 8. 后续思路复盘

**至 2026-06-24 复盘：**

- 任务执行超时 → **已完成**：默认 30 分钟 ctx 超时，区分超时与 PATH 缺失。
- 经验库智能推荐 → 任务模板已移除，未启动。
- Webhook 重试队列 → 已移除。
- 移动端适配 → 进展较小，仍为 PC 优先。

**新增关注点：**

- 任务 + Agent 全链路可观测
- SSH 远端 Agent 任务池稳定性
- AI 评估反幻觉：会话链评估合并多轮输入

---

## 9. 后续新增的高级特性（6.19-6.24）

### 9.1 AI 自治

**问题：** AI 自治 3 个能力（run-loop / reevaluate / learn）后端已有，前端没有入口。

**思路：** 提供统一开关控制，3 个能力接入 UI：「🔁 重评」「🧠 学习」「🔁🔁 Run-Loop」。

### 9.2 SSH 远端执行器

**问题：** 之前任务只能在本地机器跑，多机器协同场景需要把任务下发到远端。

**思路：** 借 Agent 体系实现 SSH 远端执行，支持 password / private key 鉴权。远端机器绑定到 dir_shortcut，前端可选择本地或远端 agent 运行，并支持续传 session。

### 9.3 会话链评估

**问题：** 一次会话有多轮 execution，单次评估输出不全面。

**思路：** 把同会话链的所有 execution 的 input/output 合并后，一次性送评。

### 9.4 配置体系重构

**问题：** 用户偏好散落在 SQLite 表和 config.json 嵌套字段，优先级不清。

**思路：** 全部上移到 config.json 顶层字段，不再有 AppSettings 优先级链。SQLite app_settings 表删除。

### 9.5 系统配置页重构

**问题：** "数据管理"页概念模糊、布局拥挤。

**思路：** 改名"系统配置"提为独立 Tab，子 tab 简化为：快捷目录 / 快捷链接 / 默认 CLI。原"快捷"拆为两个独立子 tab。

### 9.6 代理 Tab 强化

- Relay API 统一加认证中间件
- 命令执行 / HTTP 转发两栏分色
- 暗色主题 UI 优化

### 9.7 评估 / 日志 / 调度 微改进

- 评估 UI 优化（去问号图标、用 title 提示）
- 调度 sessionId 提取修复，支持 resume
- 修复 `--resume` 必须用 `session_id` 而非 `uuid`
- 调度器 status 不再依赖中间态，改用 execution id + completed_at 判断

### 9.8 exec-detail 历史展示

对话历史按 resume_uuid 分组展示，支持过滤。

### 9.9 任务页 UI 微调

表格列宽调整、时间列加宽、状态列显示英文、Windows 缩放兼容。

### 9.10 调度器下次执行时间

**问题：** 定时任务列表只能看"上次执行"，无法预知下次什么时候跑。

**思路：** 调度器内部 cron.Entry 有 `.Next()` 方法，直接查询下次触发时间，不在 handler 层现场计算（避免时间漂移）。仅 enabled 任务显示。

## 10. Bug 修复与细节优化（6.24 之后）

### 10.1 任务执行链路修复

- **远程 agent**：claim 响应直接返回拼好的 prompt，避免 agent 端漏注入
- **手动执行**：补上经验库注入，修复与自动任务行为不一致
- **resume_uuid**：修复非空字符串边界误判
- **WS 频道**：chunk 推送统一走 exec 频道，避免重复

### 10.2 任务表布局修复

td 恢复 table-cell 语义，flex 行为下沉到内层 div，修复 Safari 排序图标换行错乱。

### 10.3 执行/评估模型独立配置

执行要快+便宜，评估要稳+准，两者分开配置。前端两处下拉独立选择。

### 10.4 execution.status 显式状态 + 手动取消

**问题：** 执行记录"一直显示运行中"，根因是 ctx 超时后错误信息丢失 + WS 断连后无刷新 + 无取消接口。

**思路：** executions 表加显式 status 字段（running/success/failed/timeout/cancelled/build_error），替代靠 completed_at + exit_code 拼凑的隐式判定。新增手动取消接口。

### 10.5 继续对话延续原 CLI

硬编码 CLI 的问题：session 延续了但 CLI 切换了。改为记录原 exec 的 cli_type，继续对话时沿用。

### 10.6 AI 自治区块加回 + Run Loop 异步化

4 个问题一次性修：① AI 自治按钮从未渲染，补回；② Run Loop 同步阻塞 HTTP，改异步；③ scheduler 加优雅关闭；④ 开关从过期数据读取的问题修复。

### 10.7 代理页生成 Linux 调用脚本

一键生成可拷贝的 curl 脚本，自动注入 relay.api_key，用户只需改 URL 和业务参数。

### 10.8 调度器 AI 默认超时 1h → 10min

AI 任务实际很少跑超过 10 分钟，1 小时让"卡住"的任务占着端口太久。

### 10.9 调度器 next_run_at 实时刷新

下次执行时间在每次触发后主动重算，而非只在 Reload 时刷新。

### 10.10 其它微改进

UI 精简、tooltip 边界自适应、快捷示例支持 `@every m/h` 粒度、Windows 兼容等。

## 11. 新增高级特性（6.26）

### 11.1 AI 沙盒

**背景：** AI 任务的 CWD 是 xworkbench 二进制目录，Write 工具会污染源码树。

**思路：** 强制 AI 工作在 `data/ai-sandbox/` 目录（CWD 隔离）+ `.gitignore` 防止入仓。scheduler 任务、PTY 交互、config 写操作不适用沙盒。

**后续回退：** 曾尝试 post-write 用 `git status` 自动 revert，但会误伤 AI 修 bug 的合法工作流，最终回退到两层防御。未来方向是 OS 级沙箱（`sandbox-exec` / `bwrap`）。

### 11.2 危险权限放开（--dangerously-skip-permissions）

**需求：** 某些场景需要 AI CLI 完全放开权限，默认应关闭防止误操作。

**思路：** 提供独立开关，开启后 claude/cbc 传入 `--dangerously-skip-permissions`，shell/evaluator 不受影响。UI 加红色边框警示 + confirm 确认。与 AI 沙盒正交，可独立开关。

### 11.3 AI 自治全链路修复

6.26 集中重构，修复 4 类问题：① 配置读写并发安全（RWMutex + copy-on-write）；② handleSetConfig 三阶段校验 + 失败回滚；③ run-loop 任务级去重防并发；④ 前端跨 Tab 状态同步 + 开关防抖。

---

## 12. 已精简 / 移除的特性

### 12.1 仅前端 UI 精简

评论区块、活动历史区块从 task-modal 移除（合并到 exec-detail-modal），后端 API 保留。

### 12.2 完整移除

任务依赖、任务模板、Webhook 派发、保存的过滤器已完整移除（前端 + 后端 + 表 + 路由）。删除原因：前端无调用 + 接入成本高，个人项目自用为主，暂不需要。

### 12.3 状态对照表

| 章节 | 状态 |
|------|------|
| 2.1 AI 继续对话 | ✅ |
| 2.2 评估闭环 | ✅ |
| 2.3 Prompt 格式优化 | ✅ |
| 2.4 经验库多经验关联 | ✅ |
| 3.x Agent 系统 | ✅ |
| 4.1-4.2 评论/审计 | ⚠️ 后端保留，前端精简 |
| 4.3-4.6 | ❌ 已删除 |
| 4.7 任务优先级 | ✅ |
| 5.x Relay 代理 | ✅ |
| 6.x 运维能力 | ✅ |
| 7.x UI 改进 | ✅ |
| 11.x 新增特性 | ✅ |
