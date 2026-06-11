# AI Task System v2.4 深度探索报告

> 路径：`/Users/xd/Documents/workspace/repo/ai-playground/ai-task-system/v2.4/`
> 模式：只读探索，零修改

---

## 1. 项目定位与版本演进

### 1.1 项目定位（来自 `ai-task-system/README.md`、`CLAUDE.md`）

`ai-task-system` 是一个**多 Agent CLI 编排层**，统一调度 Claude Code / OpenAI Codex / CodeBuddy 等本地 AI 编程工具，含 v1 ~ v5 共 5 个版本迭代，**v4/v5 是当前活跃版本，v1 ~ v2.4 已归档**。

### 1.2 演进路径

```
V1:  单 Agent  + 任务池  + 评估迭代
     ↓
V2:  多 Agent  + 任务池  + 评估迭代
     ↓
V3:  CodeBuddy 原生适配  + 双超时防护
     ↓
V4:  多 Agent 抽象层  + CLI/TUI/REPL  + 任务路由
     ↓
V5:  V4 × 生产化  + 进程池  + 持久化队列  + REST API
```

`v2.4` 处于 V2 末期的子版本（介于 V2 与 V3 之间），是 V2 主线最后一个小版本。

### 1.3 v2.4 的新特性（来自 `v2.4/README.md`）

- **页面交互式人工确认**：填空式 + 连续会话，executor 格式化输出结构化确认请求
- **实时进度展示**：流式输出 + WebSocket 推送 + 运行时长显示
- **提前结束任务**：SIGKILL 真正杀掉子进程，支持终止按钮
- **服务重启兜底**：僵尸任务检测与恢复，心跳机制

---

## 2. 整体目录结构与文件清单

```
v2.4/
├── README.md                 # 版本说明（21 行）
├── CLAUDE.md                 # （位于父级，不在 v2.4 内）
├── requirements.txt          # 10 个依赖
├── config.yaml               # 调度/执行/任务/评估/日志 5 段配置
├── .gitignore
├── backend/                  # 后端核心
│   ├── __init__.py
│   ├── main.py               # FastAPI 入口（68 行）
│   ├── config.py             # YAML 配置 + 日志（95 行）
│   ├── database.py           # aiosqlite + Pydantic 模型（335 行）
│   ├── scheduler.py          # 轮询调度器（350 行）
│   ├── executor.py           # FastAPI 适配层（72 行）
│   ├── cli_executor.py       # 真正调起 CLI 的子进程封装（249 行）
│   ├── evaluator.py          # 评分（CLI 模式 + API 占位）（103 行）
│   ├── retry.py              # 指数退避重试（64 行）
│   ├── prompts.py            # 人工确认的 JSON 提示模板（34 行）
│   ├── websocket_manager.py  # WebSocket 广播（43 行）
│   └── api/
│       ├── __init__.py
│       └── routes.py         # REST 路由（197 行）
├── frontend/
│   ├── __init__.py
│   └── index.html            # 单文件 SPA（758 行）
├── docs/
│   └── CLAUDE.md             # 仅一行："AI Task System v2.4 - Global Settings"
└── tests/
    └── __init__.py           # 空文件，无实际测试
```

**模块数**：13 个 Python 文件 + 1 个 HTML + 1 个 YAML + 1 个 txt，**总规模约 2000 行**。

---

## 3. 技术栈

| 层 | 选型 |
|---|---|
| Web 框架 | **FastAPI 0.109.0** + uvicorn[standard] 0.27.0 |
| 数据库 | **aiosqlite 0.19.0**（异步 SQLite） |
| 校验 | Pydantic 2.5.0 |
| HTTP 客户端 | httpx 0.26.0 |
| 测试 | pytest 7.4.0 + pytest-asyncio 0.23.0 |
| LLM SDK | openai>=1.12.0（evaluator 占位用，**未实际接入**） |
| WebSocket | websockets>=12.0 |
| 配置 | PyYAML>=6.0 |
| 调度 | **无第三方库**（自实现 asyncio 轮询） |
| 前端 | 单文件 `index.html` + **TailwindCSS CDN** + 原生 JS（无构建工具） |

**结论**：纯 Python 异步 Web 应用 + 单文件前端，零运维复杂度，**冷启动只需 `pip install` + `uvicorn`**。

---

## 4. 数据模型（SQLite Schema）

### 4.1 三张表（来自 `backend/database.py:60-106`）

#### `tasks`（核心表）
```sql
CREATE TABLE tasks (
    id            TEXT PRIMARY KEY,           -- UUID
    title         TEXT NOT NULL,
    description   TEXT NOT NULL,              -- 给 AI 的 prompt
    status        TEXT DEFAULT 'pending',     -- 状态机
    priority      INTEGER DEFAULT 0,          -- 调度优先级
    created_at    DATETIME DEFAULT CURRENT_TIMESTAMP,
    claimed_at    DATETIME,                   -- 调度器认领时间
    started_at    DATETIME,                   -- 实际执行开始
    completed_at  DATETIME,                   -- 结束时间
    executor_model     TEXT DEFAULT 'claude-opus-4-6',
    evaluator_model    TEXT DEFAULT 'gpt-4',
    iteration_count    INTEGER DEFAULT 0,     -- 评估不达标已重试次数
    max_iterations     INTEGER DEFAULT 3,
    improvement_threshold INTEGER DEFAULT 7,  -- 评分阈值
    result         TEXT,                       -- 最终输出
    feedback_md    TEXT,                       -- 评估反馈
    user_input     TEXT,                       -- 人工确认输入
    last_heartbeat DATETIME                    -- 僵尸检测
);
CREATE INDEX idx_tasks_status_heartbeat ON tasks(status, last_heartbeat);
```

**关于"定时任务"字段的结论**：

- **没有任何"定时调度"语义字段** —— 没有 `cron_expression`、`run_at`、`scheduled_at`、`interval_seconds` 等任何表示"何时自动触发"的列。
- `priority` 字段是**抢占顺序权重**，不是时间窗口。
- 触发方式是**轮询 pending 队列**，**没有时间维度**。

#### `executions`（执行历史）
```sql
CREATE TABLE executions (
    id            TEXT PRIMARY KEY,
    task_id       TEXT NOT NULL REFERENCES tasks(id),
    executor_model TEXT NOT NULL,
    started_at    DATETIME DEFAULT CURRENT_TIMESTAMP,
    completed_at  DATETIME,
    output        TEXT,
    error         TEXT,
    command       TEXT                          -- 实际执行的命令行
);
```

#### `evaluations`（评估历史）
```sql
CREATE TABLE evaluations (
    id              TEXT PRIMARY KEY,
    task_id         TEXT NOT NULL REFERENCES tasks(id),
    execution_id    TEXT NOT NULL REFERENCES executions(id),
    evaluator_model TEXT NOT NULL,
    score           INTEGER NOT NULL,            -- 0-10
    comments        TEXT,
    created_at      DATETIME DEFAULT CURRENT_TIMESTAMP
);
```

### 4.2 状态机

```
pending → running → (completed|failed|waiting_input)
                    ↓
                evaluating → evaluated | re-execute（重试，最多 max_iterations 次）
                    ↓
                evaluated（终态）

任意状态 → cancelled（用户主动）
```

---

## 5. 核心功能深度解析

### 5.1 任务调度（**轮询模式，非定时模式**）

**位置**：`backend/scheduler.py`

**调度方式**：`asyncio` 轮询循环，**完全在进程内**，不依赖 APScheduler / Celery / cron / schedule。

```python
# scheduler.py:143-151
async def _poll_loop(self):
    """Main loop: claim and execute one task at a time."""
    await self.db.init()
    while self._running:
        try:
            await self._process_pending_tasks()
        except Exception as e:
            logger.error(f"Poll loop error: {e}")
        await asyncio.sleep(self.poll_interval)  # 默认 5s
```

**关键设计**：

1. **原子认领**（`scheduler.py:153-159`，`database.py:128-146`）
   ```python
   async def _process_pending_tasks(self):
       async with self._lock:                  # 单调度器互斥
           task = await self.db.claim_one_task()
           ...
   ```
   `claim_one_task` 在 SQLite 上用 `UPDATE ... WHERE status='pending'` 做"读+写"原子切换，**多进程安全但单进程内仍靠 asyncio Lock**。

2. **心跳**（`scheduler.py:121-137`）
   - 每 30s 刷新 `last_heartbeat`
   - 启动时扫描 `running` 任务，若心跳超过 120s（`stale_threshold`）则重置为 `pending`

3. **僵尸回收**（`scheduler.py:86-119`）
   - 没有心跳 → 重置为 pending
   - 心跳超龄 → 重置为 pending
   - 绝对超时（`started_at` 超过 `task_timeout`，默认 600s）→ 标记 failed

4. **并发控制**：通过 `self._lock = asyncio.Lock()`，**实际只允许 1 个任务同时执行**（与 `config.concurrency: 2` 字段矛盾 —— 字段存在但未真正实现并发调度）

5. **可启动/停止**：`/api/scheduler/start`、`/api/scheduler/stop`、`/api/scheduler/status`（`main.py:36-54`）

### 5.2 AI CLI 集成（**关键能力**）

**位置**：`backend/cli_executor.py`

#### 5.2.1 命令构造（`cli_executor.py:26-56`）

```python
def build_command(self, task_id, description, model=None, session_id=None, allowed_tools=None):
    if self.cli == "codebuddy":
        cmd = ["codebuddy", "-p"]
        if model: cmd.extend(["-m", model])
        cmd.append(description)
    else:  # 默认 claude
        cmd = ["claude", "--print", "--verbose"]
        if allowed_tools or self.allowed_tools:
            cmd.extend(["--allowedTools", allowed_tools or self.allowed_tools])
        if model: cmd.extend(["--model", model])
        if session_id: cmd.extend(["--session-id", session_id])
        cmd.append(description)
```

**两条命令模式**：
- `claude --print --verbose --allowedTools "Bash,Read,Edit,Grep,Glob" --model claude-opus-4-6 --session-id <sid> "<task>"`
- `codebuddy -p -m <model> "<task>"`
- 续接会话：`claude -c --model <m> --session-id <sid> "<user_input>"`（`cli_executor.py:47-56`）

#### 5.2.2 子进程执行（`cli_executor.py:117-188`）

- 用 `asyncio.create_subprocess_exec` 启动，**stdout/stderr/stdin 全 PIPE**
- 边读边通过 `output_callback` 推给 WebSocket
- 超时（默认 1800s）→ `proc.kill()` + 标 `exit_code = -1`
- 返回 `(full_output, error, cmd_str, exit_code)`

#### 5.2.3 人工确认检测（`cli_executor.py:62-115`）

- **启发式检测**（`needs_user_input`）：扫描 17 种中英文短语（`[Y/n]`、`是否要`、`请确认`、`Continue?` 等）
- **JSON 结构化**（`parse_confirm_request`）：正则提取含 `confirm_type` 字段的 JSON，可识别 4 种类型：
  - `single_choice`（单选）
  - `fill_blank`（填空）
  - `confirm`（一般确认）
  - `continue_session`（继续对话）

触发时任务转入 `waiting_input` 状态，HTTP `POST /api/tasks/{id}/submit_input` 接收用户回复（`routes.py:121-151`）。

#### 5.2.4 评估器（`backend/evaluator.py`）

- **CLI 模式**（`use_cli: true`）：调 `claude --print` 给输出打分（`evaluator.py:72-99`），prompt 模板要求"评分: X/10"
- **API 模式**（占位未实现）：`_evaluate_via_api` 直接返回 `5, "API 评估待实现"`
- 默认评分 5（出错时兜底）
- 评估不达标（score < `improvement_threshold`，默认 7）→ 标记 `re-execute`，下一轮把 `feedback_md` 作为新 prompt 喂回去

#### 5.2.5 重试（`backend/retry.py`）

- `RetryExecutor` 包装 `CLIExecutor`
- 指数退避：`base_delay * 2^attempt`，max 30s，加 ±0.5s 抖动
- 默认 3 次

### 5.3 平台兼容性（**显著不足**）

**关键发现**：

- `grep -E "platform.system|sys.platform|os.name|windows|win32|posix" backend/*.py` → **0 命中**
- `proc.kill()` 在 Windows 上是 `TerminateProcess()`，**不会发 SIGKILL** —— 代码注释里写 "SIGKILL 真正杀掉子进程"（`scheduler.py:1`），但实际只在 POSIX 行为正确
- **没有任务计划程序（Task Scheduler）/ launchd / cron 的集成代码**
- **没有跨平台调度器适配层**

**结论**：v2.4 的"调度"是**进程内 asyncio 轮询**，不依赖 OS 定时器，因此进程死了调度就停。**Windows 上可启动，但需用户自己用 Task Scheduler 把它注册为开机自启服务**。

### 5.4 评估 → 重试 闭环

**位置**：`scheduler.py:245-282`

```python
if score < task.improvement_threshold:
    if task.iteration_count < task.max_iterations:
        await self.db.increment_iteration(task_id)
        await self.db.update_task_status(task_id, "re-execute", feedback_md=feedback_md)
    else:
        await self.db.update_task_status(task_id, "evaluated", feedback_md=feedback_md)
```

- `re-execute` 状态在 schema 中没有显式声明（只在 `update_task_status` 的状态分支里被允许），但调度器下次轮询时仍会通过 `claim_one_task` 把它当 pending 领取
- 每次重试把 `feedback_md` 拼回 prompt，**形成自改进循环**

---

## 6. API 接口（`backend/api/routes.py` + `main.py`）

| 方法 | 路径 | 功能 |
|---|---|---|
| GET | `/` | 返回 `frontend/index.html`（SPA） |
| GET | `/api/health` | 健康检查 |
| POST | `/api/scheduler/start` | 启动调度器 |
| POST | `/api/scheduler/stop` | 停止调度器 |
| GET | `/api/scheduler/status` | 调度器状态 |
| WS | `/ws` | WebSocket 实时推送 |
| POST | `/api/tasks` | 创建任务 |
| GET | `/api/tasks?status=` | 列表 |
| GET | `/api/tasks/{id}` | 详情 |
| PUT | `/api/tasks/{id}` | 更新 |
| DELETE | `/api/tasks/{id}` | 删除（仅终态可删） |
| POST | `/api/tasks/{id}/cancel` | 取消（SIGKILL 子进程） |
| POST | `/api/tasks/{id}/submit_input` | 提交人工输入 |
| GET | `/api/tasks/{id}/executions` | 执行历史 |
| GET | `/api/tasks/{id}/evaluations` | 评估历史 |
| GET | `/api/stats` | 统计 |

**注**：UI 期望的 `/api/tasks/{id}/retry`、`/api/config`、`/api/config/{key}` 端点 **在 `routes.py` 中没有实现**（HTML 调了但 API 不存在 —— 这是 v2.4 的一个 bug）。

---

## 7. 前端 UI（`frontend/index.html`）

**文件**：`/Users/xd/Documents/workspace/repo/ai-playground/ai-task-system/v2.4/frontend/index.html`（758 行）

**技术**：HTML + TailwindCSS CDN + 原生 JS，**无构建步骤**，**无 React/Vue**。

**布局**（从上到下）：

```
┌─────────────────────────────────────────────────┐
│  Header:  AI 任务系统 v2.4  |  设置按钮         │
├─────────────────────────────────────────────────┤
│  Scheduler 状态条（运行中/已停止 + 启停按钮）   │
├─────────────────────────────────────────────────┤
│  Stats 5 卡片：总数/待执行/进行中/已完成/待输入 │
├─────────────────────────────────────────────────┤
│  任务创建表单：标题/描述/执行模型/评估模型/     │
│              最大迭代/改进阈值                   │
├─────────────────────────────────────────────────┤
│  任务列表：过滤 + 分页 + 卡片（标题/状态/操作） │
└─────────────────────────────────────────────────┘
```

**3 个弹窗**：
1. **设置**（`#settings-modal`）：CLI 选择（claude/codebuddy）、执行/评估模型配置
2. **任务详情**（`#task-modal`）：实时输出 + 评估结果 + 终止按钮
3. **人工确认**（`#confirm-modal`）：根据 `confirm_type` 动态渲染单选/填空/会话输入

**WebSocket 消息类型**（`index.html:247-279`）：
- `task_output`：流式输出片段
- `task_status`：状态变化
- `confirm_request`：弹人工确认
- `task_ready`：触发列表刷新

**轮询**：`setInterval(loadTasks, 15000)` + `setInterval(loadSchedulerStatus, 10000)` 作为 WS 兜底。

---

## 8. 配置文件（`v2.4/config.yaml`）

**5 段配置**：

| 段 | 关键字段 | 默认 | 说明 |
|---|---|---|---|
| `scheduler` | `poll_interval` | 5 | 轮询间隔（秒） |
| | `cli` | `claude` | 默认 CLI 工具 |
| | `heartbeat_interval` | 30 | 心跳刷新间隔 |
| | `stale_threshold` | 120 | 僵尸判定（秒） |
| | `concurrency` | 2 | **字段存在但未实现** |
| `executor` | `timeout` | 1800 | CLI 子进程超时 |
| | `max_auto_retries` | 3 | 自动重试次数 |
| | `auto_retry_delay` | 180 | 重试延迟 |
| | `allowed_tools` | `Bash,Read,Edit,Grep,Glob` | Claude Code 工具白名单 |
| `task` | `timeout` | 600 | 任务绝对超时 |
| | `no_output_timeout` | 120 | **字段存在但 scheduler 未用**（CLI 子进程 timeout 才是真正的截断） |
| | `stale_threshold` | 120 | 与 scheduler 段重复 |
| `evaluator` | `api_base` | `""` | API 模式（占位） |
| | `model` | `""` | 评估模型 |
| | `use_cli` | `true` | 用 `claude --print` 评估 |
| `log` | `level` | `INFO` | 日志级别 |
| | `file` | `server.log` | 滚动日志路径 |
| | `max_bytes` | 10MB | 切割阈值 |
| | `backup_count` | 5 | 保留份数 |

**加载**：`backend/config.py:42-62`，缺失字段与 `DEFAULT_CONFIG` 合并。

---

## 9. 能力评估

### 9.1 "系统定时任务 + 跨平台调度"能力评分

| 维度 | 评分 | 说明 |
|---|---|---|
| **定时触发** | **1/10** | **无任何定时触发语义**。没有 cron 表达式、没有 `run_at`、没有 `interval`。只有"轮询 pending 队列"。要把任务安排到指定时间运行，需要外部调用 `POST /api/tasks` 才行。 |
| **跨平台调度** | **3/10** | Python 本身跨平台，asyncio 跨平台，aiosqlite 跨平台。**但没有任何 Windows/macOS 特定的调度适配**，没有 `pywin32`、没有 `launchd` 包装、没有 `systemd` unit、没有 `Task Scheduler` XML 生成器。`proc.kill()` 在 Windows 上语义不同。 |
| **持久化** | 6/10 | SQLite 文件存任务，能跨重启恢复（`recover_stale_tasks`），但**配置不持久**（`updateConfig` API 在 routes.py 缺失）。 |
| **可靠性** | 7/10 | 心跳 + 僵尸回收 + SIGKILL + 重试，机制完整。但单进程崩溃 = 调度停摆。 |
| **实时性** | 8/10 | WebSocket 流式输出 + 状态推送，体验良好。 |
| **可观测性** | 5/10 | 滚动日志 + 统计 + 评估历史，没有 Prometheus / 指标端点。 |

### 9.2 与"AI CLI 集成"相关的强项

- **零胶水代码接入 Claude Code / Codebuddy**：在 v2.4 之前需要适配，v2.4 已统一在 `cli_executor.py:26-56`
- **真正的流式输出**：不像 v2 早期版本要等子进程结束才返回
- **真正的 SIGKILL 终止**：通过 `register_process` + `proc.kill()` 映射 task_id → Process
- **续接 session**：`build_continue_command` 支持 `claude -c` 续接，但 scheduler.py 当前的 `submit_user_input` 没有传 `session_id`（存疑 bug，见 `scheduler.py:332-350`）

### 9.3 已知问题 / 不足

1. **API 与 UI 不一致**：`/api/tasks/{id}/retry`、`/api/config`、`/api/config/{key}` 在 HTML 中被调用但 `routes.py` 未实现
2. **concurrency 字段不生效**：配置写 2，实际只跑 1 个
3. **no_output_timeout 字段不生效**：`task.no_output_timeout` 读取了但代码里没真正按"无输出时长"去 kill
4. **session_id 丢失**：人工确认后 `submit_user_input` 重新进 pending 队列，**新 execution 不会带 session_id**，等价于"重新开一个会话"，但代码注释自夸说"we don't have session_id persistence across restarts"
5. **evaluator API 模式未实现**：`evaluator.py:101-103` 直接返回占位
6. **没有测试**：`tests/` 只有 `__init__.py`，CLAUDE.md 描述的 136 个测试是 v4 的
7. **无任何跨平台调度适配**（如 launchd、Task Scheduler、systemd timer）
8. **没有依赖锁**：requirements.txt 无 hash 锁定
9. **配置变更不可持久**：UI 上的设置（CLI 选择、模型列表）走 `updateConfig` 调到不存在的端点

---

## 10. 对比 v2 主线其他版本

| 维度 | v2.2 | v2.3 | **v2.4** |
|---|---|---|---|
| 数据库 | aiosqlite | aiosqlite | aiosqlite |
| 调度 | 轮询 | 轮询 | 轮询 + 心跳 + 僵尸回收 |
| 人工确认 | 无 | 无 | **有**（4 种类型） |
| 实时输出 | 否 | 否 | **是**（WS 流式） |
| 终止任务 | 软取消 | 软取消 | **SIGKILL 硬终止** |
| 续接 session | 无 | 无 | 命令已支持，状态机未串通 |

---

## 11. 总结

**v2.4 是什么**：
- 一个 **"AI Agent 任务执行池"**，不是定时任务系统
- 把"创建任务 → 自动调度 → 调起 Claude Code / Codebuddy 子进程 → 流式收集输出 → 评估 → 不达标自动重试 → 人可介入"做成一个 Web 应用
- **任务触发方式**：用户/外部通过 HTTP/UI 推入 `pending` 队列，进程内 asyncio 轮询认领执行
- **跨平台**：Python 层面跨平台，但**没有任何 OS 级调度器集成**

**v2.4 不是什么**：
- **不是** cron 替代品 —— 没有"每天 9 点跑"的能力
- **不是** 后台守护进程 —— 它本身需要被托管（uvicorn 进程）
- **不是** 分布式任务系统 —— 单进程，单 SQLite 文件，多实例会互抢

**核心数据模型一句话**：1 张 `tasks` 表（status 状态机 + 心跳字段 + AI 模型选择），2 张从表（executions 记录每次执行，evaluations 记录每次评分）。

**最有价值的代码段**（如果要复用）：
- `cli_executor.py:26-56` —— 命令构造（防 shell 注入）
- `cli_executor.py:117-188` —— 流式子进程 + 超时
- `cli_executor.py:62-115` —— 人工确认信号检测
- `database.py:128-146` —— 原子任务认领（`UPDATE ... WHERE status='pending'`）
- `scheduler.py:86-119` —— 僵尸回收

**最薄弱的代码段**：
- 跨平台调度（完全缺失）
- API 与 UI 对齐（多处 404）
- evaluator API 模式（占位）
