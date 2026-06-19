---
title: 个人AI工作台（二） -- All-In-One助手新增高级特性
description: 续篇，介绍第一篇之后新增的高级特性
categories: [AI, 个人AI工作台]
tags: [Agent, 个人助手, xworkbench]
---

## 1. 引言

续篇，在[构建个人All-In-One助手应用](https://xiaodongq.github.io/2026/06/10/assistant-all-in-one/)的基础上，按需叠加了大量新功能。本文按功能大类组织，介绍思路和实现方式，代码位于 [xiaodongQ/xworkbench](https://github.com/xiaodongQ/xworkbench)。

## 2. AI 任务执行增强

### 2.1 AI 继续对话（--resume）

**问题：** `claude -p` 默认每次都是全新会话，无法在同一个上下文中继续追问。

**思路：** `claude -p --output-format json` 执行后会返回一个 `uuid` 字段，后续用 `--resume <uuid>` 可以基于前一个会话继续对话。

**实现：**

1. **解析 uuid**：执行完成时从 JSON 输出中提取 `uuid` 存入 `executions.resume_uuid` 字段
2. **继续对话 API**：`POST /api/executions/{id}/continue`，用 `--resume <uuid>` 构建新命令，创建新 execution 并异步执行
3. **前端 UI**：执行详情弹窗底部有 resume_uuid 时显示「💬 继续对话」按钮，点击展开输入框

关键代码路径：`cmd/server/main.go` 的 `handleExecutionContinue`，`internal/executor/runner/build.go` 的 `WithResume` 选项。

### 2.2 评估闭环（自动换模型重试）

**问题：** AI 执行一次效果不好，需要人工重新调参数再跑。

**思路：** 执行 → AI 评估打分 → 分数低于阈值则换更强模型重试，最多 N 轮。

**实现：** `POST /api/tasks/{id}/run-loop` 接口，实现评估闭环逻辑。评估使用 `--output-format json` 的结构化输出，从 `result` 字段提取评分和评语。

### 2.3 Prompt 格式优化

**问题：** Windows 命令行长度限制 8191 字符，长 prompt 直接被截断。

**思路：** 通过 stdin 传递 prompt，不走命令行参数。

**实现：** `evaluator` 包调用 `claude -p` 时加 `runner.WithStdin()` 选项，prompt 从标准输入流入。

同时任务执行 prompt 简化为 `BuildTaskPromptShort`，只保留任务描述和验收标准两个核心部分。

### 2.4 经验库多经验关联

**问题：** 一个任务可能涉及多个经验领域，之前只能关联一个。

**思路：** 任务与经验库从一对一改为多对多关联，中间表 `task_experiences`。

**实现：** 创建 `task_experiences` 表（task_id, experience_id 联合主键），任务编辑弹窗改为 checkbox 多选experience。

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

**实现：** `internal/ratelimit/ratelimit.go` 提供中间件函数，按 IP 或 token 统计频率。

## 4. 任务治理能力

### 4.1 任务评论

**思路：** 任务和执行详情都可以评论，方便记录上下文和讨论。

**实现：** `task_comments` 和 `execution_comments` 两张表（结构一致：id/content/author/mentions/parent_id），支持嵌套评论（parent_id）。API：`GET/POST /api/tasks/{id}/comments`，`GET/POST /api/executions/{id}/comments`。

### 4.2 任务审计日志

**思路：** 任务状态变更需要记录，便于回溯和调试。

**实现：** `task_events` 表（task_id/event_type/actor/payload），在关键操作处（创建/认领/状态变更/优先级变更等）统一记录。

### 4.3 任务依赖

**思路：** 某些任务必须等前置任务完成才能开始。

**实现：** `task_dependencies` 表（task_id/depends_on/type），硬依赖阻塞认领，软依赖仅起提示作用。添加时做循环依赖检测（不允许 A→B→A）。

### 4.4 任务模板

**思路：** 常用任务结构可以保存为模板，一键创建。

**实现：** `task_templates` 表，预设模板体为 JSON（含 title/description/acceptance 等字段），创建时实例化。

### 4.5 保存的过滤器

**思路：** 任务列表的筛选条件可以保存，方便快速切换视图。

**实现：** `saved_filters` 表存 filter_json，支持设为默认排序。

### 4.6 Webhook 派发

**思路：** 任务状态变更时自动通知外部系统（如飞书/钉钉/其他服务）。

**实现：** `webhooks` 表存 url/secret/events/enabled/fail_count。Dispatcher 监听事件，匹配后发送 HTTP POST，支持失败计数。

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

## 7. UI 改进

### 7.1 区块高度拖拽调整

**思路：** 快捷目录、快捷链接、待办事项各占区域高度需要手动微调。

**实现：** 每个区块底部加拖动柄（resize-handle-h），mousedown/mousemove/mouseup 实现拖动。关键是调整高度前 `container.style.flex = 'none'` 让 flex 盒子的 flex:1 约束失效，高度值存入 localStorage 持久化。

### 7.2 经验库字段精简

**问题：** 经验库 7 个字段太多，实际只用到 4 个。

**思路：** 将 log_paths/tool_usage/log_samples/code_snippets 合并到 details 一个 JSON 字段。

**实现：** 新字段 `details` TEXT，存量数据通过迁移函数自动合并。API 返回时解析 JSON。

### 7.3 任务表单精简

**移除字段：** module（后端从未使用）、resources（用户认为不必要）。

**实现：** 从 task modal HTML、`submitTask()` JS、`handleTaskCreate/Update` Go 中移除相关字段。

## 8. 后续思路

- 任务执行超时考虑 Graceful Shutdown（给进程发 SIGTERM 等一段时间再 SIGKILL）
- 经验库和任务模板的智能推荐（根据关键词匹配）
- Webhook 发送失败后的重试队列
- 移动端页面适配
