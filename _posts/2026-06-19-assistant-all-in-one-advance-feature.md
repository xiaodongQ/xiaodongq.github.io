---
title: 个人AI工作台（二） -- All-In-One助手新增高级特性
description: 续篇，介绍第一篇之后新增的高级特性；2026-06-24 校对实现状态，新增 9、10 两节
categories: [AI, 个人AI工作台]
tags: [Agent, 个人助手, xworkbench]
last_modified_at: 2026-06-24
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

**思路：** 执行 → AI 评估打分 → 分数低于阈值则换更强模型重试，最多 N 轮。

**实现：** `POST /api/tasks/{id}/run-loop` 接口实现评估闭环逻辑。评估 prompt 要求 LLM 输出 `评分: X` 与 `评语: ...` 格式，由 `internal/evaluator` 解析后写入 `evaluations` 表（`Score=-1` 表示解析失败，`0` 表示真低分，**不互相 fallback**）。

**当前状态：** 截至 2026-06，`run-loop` 与下面的"AI 自治"3 个能力（run-loop / reevaluate / learn）一并接通，并由 `config.json` 的 `ai_loop_enabled` 顶层字段统一开关控制（详见 9.1）。

### 2.3 Prompt 格式优化

**问题：** Windows 命令行长度限制 8191 字符，长 prompt 直接被截断。

**思路：** 通过 stdin 传递 prompt，不走命令行参数。

**实现：** `evaluator` 包调用 `claude -p` 时加 `runner.WithStdin()` 选项，prompt 从标准输入流入。

**修正：** 任务执行 prompt 早期被简化为 `BuildTaskPromptShort`（只含描述+验收标准），但后续发现手动任务执行与 agent claim 都需要把经验库喂给 AI CLI，**已回退为 `BuildTaskPrompt` 完整版**（`internal/task/prompt.go`，`cmd/server/main.go:618` 注释），`BuildTaskPromptShort` 仍保留以备后续手动模式单独使用。

### 2.4 经验库多经验关联

**问题：** 一个任务可能涉及多个经验领域，之前只能关联一个。

**思路：** 任务与经验库从一对一改为多对多关联，中间表 `task_experiences`。

**实现：** 创建 `task_experiences` 表（task_id, experience_id 联合主键），任务编辑弹窗改为 checkbox 多选experience。

### 2.5 Prompt 精简（移除冗余段）

**问题：** `BuildTaskPrompt` 拼出的 prompt 里同时有 `# 用户指令` 和 `# 任务背景` / `# 任务描述` 几段都引用 `task.Description`，内容重复且增加 token 开销。

**思路：** `# 任务背景` 段已经包含了任务描述全文，`# 用户指令` 段去掉。

**实现：** `internal/task/prompt.go:BuildTaskPrompt` 删除 `# 用户指令` + `t.Description` 两行（commit `7101ee5`，2026-06-24）。

## 3. 远程 Agent 系统

### 3.1 Agent 注册与心跳

**思路：** 允许外部程序注册为 Agent，xworkbench 通过心跳检测 Agent 是否存活（30s 无心跳判离线）。

**实现：**

- `agents` 表：存 name/token_hash/capabilities/version/status/auto_claim_enabled
- `POST /api/agents/register`：注册返回 token（SHA-256 存 hash）
- `POST /api/agents/{id}/heartbeat`：更新 last_heartbeat
- 调度器定期扫描 `ListStaleAgents()`，超时设为 offline

### 3.2 任务认领与上报

**思路：** Agent 可以主动认领任务（按优先级排序），执行完成后上报结果（success/failed/error）。

**实现：**

- `POST /api/tasks/claim-next`：Agent 领最高优先级任务
- `POST /api/tasks/{id}/claim`：Agent 指定认领某任务
- `POST /api/tasks/{id}/report`：Agent 上报执行结果（exit_code/error/message）
- `Agent.AutoClaimEnabled`：Agent 可开关自动认领

### 3.3 速率限制

**问题：** Agent API 暴露在外，需要防止滥用。

**思路：** 关键端点（注册/心跳/认领/上报）统一加速率限制中间件，默认 60 req/min。

**实现：** `internal/ratelimit/ratelimit.go` 提供中间件函数，按 IP 或 token 统计频率。阈值可通过 `RATE_LIMIT_PER_MIN` 环境变量调整（设 `0` 可禁用）。

### 3.4 Agent 管理面板（代理 Tab）

**问题：** 仅有 Agent API（register/heartbeat/claim/report），前端没有可视化查看与管理入口。

**思路：** 在 5 Tab 里的「代理」Tab 加 Agent 管理面板：列出所有 Agent、一键释放/重置 token/切换 auto-claim/删除。

**实现：**

- `GET /api/agents` 列全部 agent（含 status/last_heartbeat/bound_dir_shortcut_id）
- `POST /api/agents/{id}/release-tasks`：释放该 agent 已认领的任务
- `POST /api/agents/{id}/reset-token`：重置 token
- `POST /api/agents/{id}/auto-claim`：切换自动认领
- `POST /api/agents/{id}/bind-dir-shortcut`：绑定到远程机器的 `dir_shortcut`（type=remote，含 host/user/key_path）
- `DELETE /api/agents/{id}`：删除 agent

这部分是 5.x Relay 体系与 3.x Agent 系统的连接点，详见 9.2 SSH 远端执行器。

## 4. 任务治理能力

### 4.1 任务评论

**思路：** 任务和执行详情都可以评论，方便记录上下文和讨论。

**实现：** `task_comments` 和 `execution_comments` 两张表（结构一致：id/content/author/mentions/parent_id），支持嵌套评论（parent_id）。API：`GET/POST /api/tasks/{id}/comments`，`GET/POST /api/executions/{id}/comments`。

**当前状态：** 后端 API 仍保留供脚本调用；**前端 UI 区块已精简**（exec-detail-modal 和 task-modal 上的评论区块于 2026-06-21 被 `ae11c06` / `5c91b95` 移除）。详见 10.1。

### 4.2 任务审计日志

**思路：** 任务状态变更需要记录，便于回溯和调试。

**实现：** `task_events` 表（task_id/event_type/actor/payload），在关键操作处（创建/认领/状态变更/优先级变更等）统一记录。

### 4.3 任务依赖

~~**思路：** 某些任务必须等前置任务完成才能开始。~~

~~**实现：** `task_dependencies` 表（task_id/depends_on/type），硬依赖阻塞认领，软依赖仅起提示作用。添加时做循环依赖检测（不允许 A→B→A）。~~

> **状态：已移除**（2026-06-20，commit `7450caf`）。后端 `TaskDependencyRepo` + 路由 + handler + `task_dependencies` 表全部删除；`TaskRepo.ClaimTask` / `NextClaimable` 的 `NOT EXISTS task_dependencies` 阻挡 SQL 一并清理。详见 10.2。

### 4.4 任务模板

~~**思路：** 常用任务结构可以保存为模板，一键创建。~~

~~**实现：** `task_templates` 表，预设模板体为 JSON（含 title/description/acceptance 等字段），创建时实例化。~~

> **状态：已移除**（2026-06-20，commit `7450caf`）。详见 10.2。

### 4.5 保存的过滤器

~~**思路：** 任务列表的筛选条件可以保存，方便快速切换视图。~~

~~**实现：** `saved_filters` 表存 filter_json，支持设为默认排序。~~

> **状态：已移除**（2026-06-23，commit `a87e28b`）。`saved_filters` 表 DROP，路由、handler、前端入口一并删除。详见 10.2。

### 4.6 Webhook 派发

~~**思路：** 任务状态变更时自动通知外部系统（如飞书/钉钉/其他服务）。~~

~~**实现：** `webhooks` 表存 url/secret/events/enabled/fail_count。Dispatcher 监听事件，匹配后发送 HTTP POST，支持失败计数。~~

> **状态：已移除**（2026-06-20，commit `7450caf`）。`internal/webhook` 整个包 + `WebhookRepo` + 6 个路由 + 全部 handler 清除；同时 `handleTaskUpdate` 等处的 `whDisp.Dispatch(...)` 调用全部清空。详见 10.2。

### 4.7 任务优先级

**思路：** 任务有优先级，高优先级任务优先被认领和执行。

**实现：** `tasks.priority` 整数字段（越大越优先），支持 webhook 通知 `task.priority_changed` 事件。

## 5. Relay 代理体系

### 5.1 HTTP 请求代理

**问题：** 某些内部服务没有外网权限，需要通过 xworkbench 服务器转发。

**思路：** xworkbench 作为 HTTP 代理，透传请求到目标 URL，自动携带认证头。

**实现：** `POST /api/relay/proxy`，请求 body 含 url/method/headers/body/timeout_ms。内部维护 `relay_logs` 表记录每次代理请求的来源/目标/大小/状态，支持查询统计。

### 5.2 服务器端命令执行

**问题：** 需要在 xworkbench 所在机器上远程触发脚本执行。

**思路：** 提供命令执行 API，在服务器端 shell 执行并返回结果。

**实现：** `POST /api/exec`，body 含 command/cwd/timeout_ms，返回 output/error_out/exit_code/duration_ms。

### 5.3 API Key 认证

**问题：** Relay API 暴露需要认证。

**思路：** Bearer Token 或 X-API-Key 头认证，默认 key 可配置。

**实现：** `checkRelayAuth` 中间件，校验失败返回友好提示（含 hint）。

## 6. 运维能力

### 6.1 启停脚本改进

**问题：** 之前 `lsof -ti:port` 会误报端口被占用（Chrome 的 CLOSE_WAIT 也被检测到），导致无法重启。

**思路：** 只检查 LISTEN 状态，忽略 CLOSE_WAIT/TIME_WAIT 等其他状态。

**实现：**
```bash
# macOS
lsof -i :$port -sTCP:LISTEN
# Linux
ss -tln | grep ":$port "
```

重启脚本输出前后 PID 对比：`pid=12345 (前: 12344)`。

### 6.2 统一日志输出

**思路：** 所有日志（含 executor/evaluator/scheduler 等子包）统一写入 `data/xworkbench.log`，使用 ISO8601 时间戳。

**实现：** zap logger 初始化时设置 `zapcore.ISO8601TimeEncoder`，通过 `loglib.Set` 同步到全局，各子包直接使用 `logger.Logger.Infow/Errorw`。

### 6.3 评估输出截断

**问题：** 超大输出直接送评估浪费 token 且容易超时。

**思路：** 超过 100KB 的输出截断后再送评。

**实现：** `evaluator.go` 中判断 `len(output) > 100*1024`，超长截断并附加 `[...output truncated...]` 标记。

### 6.4 SQLite PRAGMA 与并发执行修复（SQLITE_BUSY）

**问题：** 两个场景触发 `SQLITE_BUSY`：

1. `OpenDB` 里直接 `db.Exec("PRAGMA ...")` 设置 `busy_timeout` / `journal_mode` / `foreign_keys` —— 这些是 **per-connection** 的，但 `database/sql` 是懒连接池，第一次 `Exec` 只在已有连接上生效，后续 lazy 创建的连接回退默认（busy_timeout=0 / journal_mode=DELETE），实际读写隔离与并发全靠运气。
2. 调度器 + RunNow 重叠时，同 task 两个 goroutine 同时 `INSERT INTO executions`，写锁争用。

**思路：**

1. PRAGMA 用 `modernc.org/sqlite` 驱动的 DSN 参数 `_pragma=key(value)`，驱动层在**每个新连接打开时**自动执行，确保 per-connection 生效。启动期再 `PRAGMA journal_mode` QueryRow 验证 WAL 真的生效，**fail-fast**。
2. `Scheduler.doExecute` 用 `singleflight.Group` 包装，同 task ID 的并发触发（cron 与 RunNow 重叠，或 cron 周期 < 子进程时长）合并到一次执行。

**实现：**

- `internal/backend/server.go:OpenDB` 改 DSN：
  - `_pragma=busy_timeout(5000)&_pragma=journal_mode(WAL)&_pragma=foreign_keys(ON)&_pragma=synchronous(NORMAL)`
  - 限连接池：`SetMaxOpenConns(8)` / `SetMaxIdleConns(4)` / `SetConnMaxLifetime(time.Hour)`
  - 启动期 `QueryRow("PRAGMA journal_mode")` 校验，非 `wal` 直接返回错误并关闭 db（避免带着隐患运行）
- `internal/scheduler/scheduler.go`：
  - 新增 `singleflight.Group` 字段
  - `execute(taskID string, fn func())` 包装 `fn`：同 taskID 合并，后续调用者拿到首次执行结果
  - 启动日志 `db: opened` 输出 path / journal_mode / busy_timeout_ms / max_open_conns
- `scripts/e2e.sh` 新增 `case_concurrent_scheduled`：启 2 个 `@every 5s` 任务并发跑，验证不再报 SQLITE_BUSY
- `go.mod` 加 `golang.org/x/sync v0.21.0`（singleflight 依赖）

## 7. UI 改进

### 7.1 区块高度拖拽调整

**思路：** 快捷目录、快捷链接、待办事项各占区域高度需要手动微调。

**实现：** 每个区块底部加拖动柄（resize-handle-h），mousedown/mousemove/mouseup 实现拖动。关键是调整高度前 `container.style.flex = 'none'` 让 flex 盒子的 flex:1 约束失效，高度值存入 localStorage 持久化。

### 7.2 经验库字段精简

**问题：** 经验库 7 个字段太多，实际只用到 4 个。

**思路：** 将 log_paths/tool_usage/log_samples/code_snippets 合并到 details 一个 JSON 字段。

**实现：** 新字段 `details TEXT`，由 `migrateExperiencesToDetails` 自动合并存量数据。API 返回时无需额外解析（`details` 直接以字符串返回）。最终 `experiences` 表字段：`id/module/keywords/scene/details/version/created_at/updated_at`（7→5）。

### 7.3 任务表单精简

**移除字段：** module（后端从未使用）、resources（用户认为不必要）。

**实现：** 从 task modal HTML、`submitTask()` JS、`handleTaskCreate/Update` Go 中移除相关字段（commit `c73f73e`，2026-06-19）。

> **注：** SQLite `tasks` 表 schema 中 `resources` 列、`task_experiences` 等仍保留以兼容老库，但前端 form 不再暴露。

## 8. 后续思路（原 8 节复盘）

上次列的 4 条后续思路，至 2026-06-24 复盘：

- ~~任务执行超时考虑 Graceful Shutdown~~ → **已完成**：`executor.Run` 默认 30 分钟 ctx 超时；`scheduled_tasks.last_status` 增加 `timeout` / `build_error` 两个取值，区分超时与 PATH 缺失。
- ~~经验库和任务模板的智能推荐~~ → 任务模板**已被移除**（10.2），智能推荐未启动。
- ~~Webhook 发送失败后的重试队列~~ → **已被移除**（10.2），重试队列不适用。
- ~~移动端页面适配~~ → 进展较小，仍为 PC 优先。

新增关注点：

- 任务 + Agent 的全链路可观测（executions 采样、Agent 离线告警）
- SSH 远端 Agent 任务池稳定性（断连恢复、跨平台二进制分发）
- AI 评估的反幻觉：会话链评估合并多轮输入，避免单次抽样的偏误（详见 9.3）

---

## 9. 后续新增的高级特性（6.19-6.24 之间接入）

> 上一版之后接入的能力。这些在原 6 节"运维能力"中未涵盖，但属于"高级特性"范畴，故另起一节。

### 9.1 AI 自治（总开关 + 3 个能力接通）

**问题：** 之前有 5 个"断头"后端能力（TaskEvent / SavedFilter / TaskTemplate / TaskDependency / Webhook），前 2 个接通了 UI，后 3 个删了；又新增 3 个 AI 自治能力（run-loop / reevaluate / learn），前端没有入口。

**思路：**

- 后端 `ai_loop_enabled` 顶层开关（**不放在 `app_settings` 表**，2026-06-23 重构后与 `scheduler_enabled` 等一同迁入 `config.json` 顶层，详见 9.4）
- 前端 AI 自治设置搬到"高级设置"区块，与调度器同层
- 3 个能力接进 UI：`handleTaskReevaluate`（新模型重评最新 execution）、`handleTaskRunLoop`（评估闭环）、`handleTaskLearn`（从执行记录生成经验写入 experiences 表）

**实现：**

- `internal/evaluator/evaluator.go` + `internal/task/prompt.go` 增 `LearnFromExecution`
- 3 个 handler 共用同一开关检查 `s.aiLoopEnabled()()`，每次请求都查（`Save()` 后下次请求生效，无需 reload）
- 前端 `views/automation.js` exec-detail-modal 加 "🔁 重评" / "🧠 学习" / "🔁🔁 Run-Loop" 三个按钮（灰显时表示开关未启用）

### 9.2 SSH 远端执行器（Agent 模式）

**问题：** 之前任务执行只能在 xworkbench 所在机器跑，多机器协同场景（Linux 服务 + Windows Agent）需要把任务下发到远端。

**思路：** 借 Agent 体系 + 远程 dir_shortcut，把 SSH 远端执行接进来。

**实现：**

- `internal/executor/ssh_helpers.go` + `ssh_runner.go`：基于 `golang.org/x/crypto/ssh`，支持 password / private key 鉴权（`ssh.ParsePrivateKey` 自动识别 PEM 格式）
- 远端机器以 `dir_shortcut` 表达：新增 `type=remote` 类型，字段 `remote_host/remote_user/auth_method/remote_password/key_path/port`
- `Agent.BoundDirShortcutID` 字段把 agent 绑到某台远端机器
- `handleTaskRun` 根据 `req.AgentID` 判断走本机还是 SSH：agent 非空 → 查 `agentDB.GetByID` → 拿 `BoundDirShortcutID` → `dirDB.GetByID` → 构造 `executor.SSHConfig` → 流式读 stdout/stderr
- 前端 task 详情面板加"运行位置"下拉（local / 远端 agent）+ "续传 session" 选项（`req.ResumeSessionID`）
- Agent 报错清晰化：未绑 dir_shortcut / dir_shortcut 非 remote / 缺 host/user 等都返回明确 4xx 错误信息

**测试：**

- 单元测试 `ssh_helpers_test.go` skip（需真 ssh client）
- 端到端用本地 sshd + socat 验证（详见 `docs/superpowers/plans/`）

### 9.3 会话链评估（evaluate-chain）

**问题：** 一次会话里有多轮 execution（续问、追问），单评一次输出不全面。

**思路：** 把同 `resume_uuid` 的所有 execution 的 input/output 合并后，一次性送评。

**实现：**

- `POST /api/executions/{id}/evaluate-chain`：根据 `exec.ResumeSessionID`（即 `resume_uuid`）查 `ListByResumeUUID`，无则 fallback 到单 execution
- `evaluator.RunAndSaveChain`：合并 `chain[0..N]` 的 prompt + output，调用同一 `evalPromptTpl` 打分
- 默认 120s timeout，模型选择跟随 `config.json.preferred_cli` + `models[cli].default`
- 前端 automation.js exec-detail-modal 在"📊 AI 评估"旁加"📊📊 评估整链" 按钮

**字段修正：** `session_group_id` 已被 `ebca91b` 统一为 `resume_uuid`，文档与代码使用同一字段名。

### 9.4 配置体系重构（config.json 单一来源）

**问题：** 6 个用户偏好（`aichat_default_cli` / `default_terminal` / `preferred_cli` / `todo_md_path` / `ai_loop_enabled` / `scheduler.enabled`）原本散落在 SQLite `app_settings` 表与 `config.json` 嵌套字段，读取时有优先级链歧义。

**思路：** 全部上移到 `config.json` 顶层字段，**不再有 AppSettings 优先级链**。

**实现：**

- `internal/config/config.go` 新增顶层 bool/string 字段，初始化时 `migrateConfig()` 做兜底合并
- 前端 `aichat.js:loadCliSetting()` 走 `GET /api/config`（不再走已删除的 `/api/settings/*`）
- 改 CLI 默认值：`PUT /api/config` body `{"aichat_default_cli":"claude"}`
- `app_settings` SQLite 表整体删除

**配置类型分区（记清）：**

- **顶层偏好字段**：`default_terminal` / `preferred_cli` / `ai_loop_enabled` / `aichat_default_cli` / `todo_md_path` / `scheduler_enabled` —— 改 `config.json` 即可，启动时 `internal/config.Load` 加载
- **部署级 nested**：`terminal.{detect_paths, types}` / `models.{claude, cbc}.{default, options}` / `relay.api_key`

### 9.5 系统配置页重构（数据管理 → 系统配置）

**问题：** 早期"数据管理"页有 4 个子 tab（导入/导出/备份/快捷），概念模糊、布局拥挤。

**思路：** 改名"系统配置" + 提升为独立 Tab，与其它业务 Tab 平级；子 tab 简化为 3 个：快捷目录 / 快捷链接 / 默认 CLI。

**实现：**

- 原"数据管理"4 子 tab → 提升为独立 Tab（`config`），由 4 子 tab 简化为 3 个：📁 快捷目录 / 🔗 快捷链接 / 🤖 默认 CLI（commit `d6a0048`）
- 原"快捷"拆分：原合一个的"快捷" tab 拆为独立的"快捷目录"（`dir_shortcuts`）和"快捷链接"（`web_links`）两个子 tab（commit `4e84262`）
- 修复 `localStorage` 恢复 + 子 tab active 高亮缺失（`77c37d3`）
- 空 db 导出时 nullable 字段为 null 修复，避免前端崩（`2ba328a`）

### 9.6 代理 Tab 强化

- 5.1/5.2 路由加 `relayAuth` 中间件（Bearer Token / X-API-Key），`relay.api_key` 在 `config.json` 顶层
- 命令执行 / HTTP 转发 两栏分色（`14d6975`）：执行走粉、代理走青
- 暗色主题对比度优化 + 按钮底部对齐 + form-spacer（`13cc8b2`）

### 9.7 评估 / 日志 / 调度 三个微改进

- 评估行去问号图标，用 title 提示替代（`6360465`）
- 评估支持整个会话链：见 9.3
- 调度 sessionId 提取修复 + 启动器支持 resume（`315395d`）
- 抓 claude `session_id`（不是 `uuid`），避免 `--resume` 报 "No conversation found"（`e014849`，`cmd/server/main.go:extractResumeSessionID` 注释详细记录）
- 合并评估整链：见 9.3
- 调度器 status 上一次执行不再用 `last_status="running"` 中间态（主 goroutine 阻塞时写不进去），改用 `last_execution_id` 对应 `exec.completed_at` 是否为空判断

### 9.8 exec-detail 历史展示

- 对话历史区块：展示 `command / output / error / uuid`，按 resume_uuid 分组（`189ff06`）
- 修复对话历史 API 支持 `resume_uuid` 过滤（`180ac4b`）
- 优化对话历史展示 UX（`3427515`）

### 9.9 任务页 UI 微调

- 表格列宽调整（防操作列溢出 + 排序图标换行，`9144fe0`）
- 时间列加宽到 150 + 操作列缩到 320（`96891e0`）
- 任务页状态列显示英文（`a877c8f`）
- 移除全局 `body` zoom，缩放仅作用于 Windows；OS 检测加 fallback（`baa3ff9`）

### 9.10 调度器下次执行时间注入（next_run_at）

**问题：** 定时任务列表只能看"上次执行"，用户反馈"没法预知下次什么时候跑"，反复刷新页面也得不到准确值。

**思路：** 调度器内部有每个任务的 `cron.Entry`，用其 `.Next` 方法直接查下次触发时间。**不要在 handler 里现场 `cron.Parse + Next(time.Now())`**——后者会随 now 漂移，导致 UI 一直跳秒。

**实现链路：**

- `backend.ScheduledTask` 加 `NextRunAt *time.Time` 字段（`cf019d6`，先加字段未注入）
- `internal/scheduler/scheduler.go` 暴露 `(s *Scheduler) NextRunAt(taskID string) (time.Time, bool)`，走内部 `entry.Next()`，拿不到（未 enabled / 解析失败 / scheduler 未加载）返回 `(zero, false)`
- `Scheduler` 内部维护两个 map：
  - `entries map[taskID]cron.EntryID` —— Reload 时构建，供生产 `Start()` 后 cron 引擎自动 `Entry.Next` 更新
  - `nextRun map[taskID]time.Time` —— Reload 时主动 `Schedule.Next(time.Now())` 算一次，**测试场景不调 Start()**，这个 map 让 `NextRunAt` 在 prod/test 两种场景行为一致
- `handleScheduledList` 注入：list 循环里 `if nxt, ok := s.sch.NextRunAt(t.ID); ok { t.NextRunAt = &nxt }`（`69dfe7a`）
- 前端 `views/automation.js` 表格「下次执行时间」列：仅 `enabled` 任务显示；⏰ icon + info 色（`f8c93e3`）区别于「上次」中性色
- 4 个测试覆盖：
  - `@every` 描述符解析（`e3e2b03`）
  - 非法 cron 不阻断整列表（`943e6ce`）
  - disabled 任务 `next_run_at` 字段不出现（`3310a3c`）
  - `newTestServer` 启 scheduler 适配（`13034fd`）

**附（同一时期的并发修复）：** SQLite OpenDB 改用 DSN `_pragma=` 参数 + 限连接池（`2da84db`），调度器用 `golang.org/x/sync/singleflight.Group` 合并同 task 的重叠执行（cron 周期 < 子进程时长，或 cron 与 RunNow 重叠）—— 详见 6.4 节。

### 9.11 任务执行链路 bug 修复（6.24 之后）

上一版只写了能力上线，下列 4 个 commit 都是能力落地后才发现的稳定性 / 正确性 bug 修复：

- **`b12fb7e` 远程 agent claim 响应改返预生成 prompt**：原 claim/claim-next 只返 task + experiences 原始数据，agent 端必须自己拼 prompt，容易漏注入；改为接口直接返回拼好的 prompt 字符串
- **`1d6db92` 手动任务执行注入经验库**：手动点"▶ 运行"时 `BuildTaskPrompt` 没传 experience，导致 prompt 缺经验上下文（与自动任务行为不一致）；同时前端表单从旧单值 `experience_id`（逗号串）切到新 `experience_ids` 数组
- **`ebd3bc9` 自动化页 5 处 `resume_uuid` 误判**：原 `if (x.resume_uuid)` 判断是否有会话链，5 处遗漏非空字符串边界（如 `"0"` 仍 truthy 但语义无意义）
- **`6292757` scheduled 频道 chunk 推送改走 exec 频道**：原 `ChannelScheduled` 重复推 stdout/stderr，改为统一走 `ChannelExec` + 前端 `automation.js` 按 `event` 字段过滤（`docs/wsmsg` ChannelScheduled 注释同步更新 `7688f52`）

### 9.12 任务表 td 恢复表格语义（`c922745`）

**问题：** 早前把任务表 td 改成 flex 布局后，td 实际丢掉了 table cell 语义，导致 `text-align: center` 等表格属性失效，部分浏览器（Safari）排序图标换行错乱。

**解决：** td 恢复 `display: table-cell`，flex 行为下沉到内层 div（行/列分离）。这是个不起眼但"修了才发现表格长好看了"的视觉 fix。

---

## 10. 已精简 / 移除的特性

> 这些是上一版写到、但实际并未落地 / 已被精简 / 已被移除的能力。为保持博客与代码可对照，集中记于此。

### 10.1 仅前端 UI 精简（后端 API 保留）

| 特性 | 原章节 | 状态 |
|------|--------|------|
| exec-detail-modal 评论区块 | 4.1 | `ae11c06` 移除 UI；后端 `/api/executions/{id}/comments` 保留 |
| exec-detail-modal 活动历史区块 | 4.2 | `ae11c06` 移除 UI；后端 `task_events` 表 + `/api/tasks/{id}/events` 保留 |
| task-modal 评论 / 活动历史 / 对话历史 / AI 自治 区块 | 4.1/4.2/2.x | `5c91b95` 移除（合并到 exec-detail-modal） |

### 10.2 完整移除（前端 + 后端 + 表 + 路由）

| 特性 | 原章节 | commit | 影响范围 |
|------|--------|--------|----------|
| 任务依赖 TaskDependency | 4.3 | `7450caf` | -394 行：APIServer 字段 / 6 个路由 / 8 个 repo 方法 / SQL NOT EXISTS 阻挡 |
| 任务模板 TaskTemplate | 4.4 | `7450caf` | 同上：7 个 repo 方法 / `task_templates` 表 |
| Webhook 派发 | 4.6 | `7450caf` | 同上：6 个路由 / 8 个 repo 方法 / `webhooks` 表 / `internal/webhook` 包 |
| 保存的过滤器 SavedFilter | 4.5 | `a87e28b` | `saved_filters` 表 DROP，路由 / handler / UI 一并清除 |

**删除原因（统一）：** 之前是"前端 0 调用 + 后端完整"的 5 个断头能力。"接通 UI"成本 > 实际使用价值（个人项目，自用为主），决定先批量删除 TaskTemplate / TaskDependency / Webhook 3 个；TaskEvent / SavedFilter 保留后端接通 UI（TaskEvent 仍走 audit 日志，SavedFilter 在 6.23 也一并删了）。详见 commit message 与 `docs/superpowers/plans/`。

### 10.3 其它被精简的项

- **任务表单字段**：`module` / `resources` 表单字段移除（`c73f73e`），schema 仍保留以兼容老库
- **`scripts/build-all.sh`**：`7180062` 删除（产物名仍叫旧名 `skill-factory`，跟 `build.sh -a` 重复）
- **`--resume <uuid>` 早期误用**：从 `cmd/server/main.go:extractResumeSessionID` 注释看到，老版本用单次 `uuid` 传给 `--resume` 会报 "No conversation found with session ID"，**必须用 `session_id`**（`e014849` 修复）

### 10.4 状态对照表

| 原章节 | 状态 |
|--------|------|
| 2.1 AI 继续对话 | ✅ 实际已落地（修正：`--resume` 必须传 `session_id` 而非 `uuid`） |
| 2.2 评估闭环 | ✅ 已落地，受 `ai_loop_enabled` 控制（见 9.1） |
| 2.3 Prompt 格式优化 | ✅ 已落地；BuildTaskPromptShort 仍存在但**已回退**为完整版（修复手动任务缺经验的 bug） |
| 2.4 经验库多经验关联 | ✅ 仍落地，`task_experiences` 中间表 |
| 3.1 Agent 注册与心跳 | ✅ |
| 3.2 任务认领与上报 | ✅ |
| 3.3 速率限制 | ✅（增加 `RATE_LIMIT_PER_MIN` 环境变量） |
| **3.4 Agent 管理面板** | ✅ 新增（6.22，详 3.4 + 9.2） |
| 4.1 任务评论 | ⚠️ 后端保留，前端 UI 精简 |
| 4.2 任务审计日志 | ⚠️ 后端保留（`task_events` 表），前端 UI 精简 |
| 4.3 任务依赖 | ❌ 已删除 |
| 4.4 任务模板 | ❌ 已删除 |
| 4.5 保存的过滤器 | ❌ 已删除 |
| 4.6 Webhook 派发 | ❌ 已删除 |
| 4.7 任务优先级 | ✅ 仍落地 |
| 5.1 HTTP 请求代理 | ✅ |
| 5.2 服务器端命令执行 | ✅ |
| 5.3 API Key 认证 | ✅ |
| 6.1 启停脚本改进 | ✅ |
| 6.2 统一日志输出 | ✅（`logger.Logger.Infow/Errorw`） |
| 6.3 评估输出截断 | ✅ |
| 7.1 区块高度拖拽调整 | ✅ |
| 7.2 经验库字段精简 | ✅（7→5 字段） |
| 7.3 任务表单精简 | ✅（`c73f73e`） |
| **7.4 任务页 UI 微调** | ✅ 新增（见 9.9） |
| 8 后续思路 | 🔁 复盘见 8 |
