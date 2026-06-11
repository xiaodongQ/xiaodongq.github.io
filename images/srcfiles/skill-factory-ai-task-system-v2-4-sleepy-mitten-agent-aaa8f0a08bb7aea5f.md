# "all-in-one" 个人工作台 — 设计方案

> 项目代号：**workbench**（暂定，最终可改）
> 基线：保留 `skill-factory`（Go + SQLite + 漂亮 UI + PTY + 经验库），融合 `ai-task-system v2.4` 的调度器/执行器/评估器，并新增 5 个功能
> 关键事实校对：
> - `skill-factory` 入口 `cmd/server/main.go`（Go 1.25，net/http + embed.FS），3 张表 tasks/experiences/skill_versions
> - `ai-task-system v2.4` 入口 `backend/main.py`（FastAPI + aiosqlite），3 张表 tasks/executions/evaluations，调度器 5s 轮询 + 30s 心跳 + 120s stale 阈值
> - 4 种确认信号在 `cli_executor.py:62-115`：`needs_user_input` 关键词 + `parse_confirm_request` 正则 / 嵌套 JSON 解析
> - **重要修正**：v2.4 自带的 `tests/__init__.py` 是空的；真实的 pytest 文件在父目录 `ai-task-system/tests/` 下，v2.4 实际无现成 Python 测试可移植
> - skill-factory 已用 `creack/pty`（POSIX 端正常）+ `gorilla/websocket` + `modernc.org/sqlite`（纯 Go，跨平台无需 CGO）

---

## 1. 整体架构决策

### 推荐方案：**单 Go 二进制 + 同进程调度/PTY/Web**（"all-in-one" 实质落地）

用户明确说"all in one"，且 skill-factory 已经是漂亮的单二进制；选 Go 单体。

**理由**：

| 维度 | 单 Go 二进制（推荐） | 双进程（Go + Python） |
|---|---|---|
| 部署 | 1 个文件 / 1 个进程 / 1 个 sqlite 文件 | 2 个进程，Python 虚拟环境 + Go 二进制 + 2 套配置 |
| 启动 / 关停 | 1s 内冷启；停机=kill 一个进程 | 需协调子进程生命周期、端口、孤儿清理 |
| 跨平台 | `go build` 矩阵：darwin/linux/windows 三平台单文件 | Python 依赖（aiosqlite/uvicorn/fastapi）在 Windows 路径处理多坑（`\` vs `/`、UAC、Service 包装） |
| 内存 / 性能 | 同进程调用，零序列化 | IPC（HTTP/stdio）多 ~5-10ms/调用 + 序列化 |
| 共享 DB | 同一 `*sql.DB` 句柄 | 需要约定文件锁、并发模式 |
| 用户预期 | "all in one" 直接满足 | 用户仍感知"两个系统" |
| 调度器 / 心跳 | goroutine + `time.Ticker`，`context.Context` 优雅退出 | asyncio + 进程间状态共享（额外写一份心跳文件） |

**风险与缓解**：

- **PTY 在 Windows 不可用** → 用 build tag 隔离（`pty_unix.go` / `pty_stub.go`），UI 端运行时探测
- **`creack/pty` Windows 替代** → 本设计不引入 ConPTY（API 复杂），Windows 上 PTY Tab 直接隐藏；调度子进程用 `os/exec`（Windows 用 `TerminateProcess`）足够
- **测试 1:1 移植成本** → v2.4 实际无 pytest 文件，"136 tests" 在父目录且不专属于 v2.4；通过黑盒脚本 + Go 表驱动测试覆盖等价逻辑，**不必逐行复刻**
- **Go 端的 `4 种人工确认信号`移植** → 整段逻辑很简单（关键词列表 + 正则 + 嵌套 JSON 解析），Go 用 `regexp` + 字符串扫描 200 行内可等价；**建议直接移植**（用户体感差异最大）

### 替代方案（不推荐但记录）：双进程

若以后调度器需要分布式扩展，再切到 Go 调 Python sidecar：Go 暴露 `/api/execute`，内部 `httpx`→`subprocess.Popen` 起 Python。但 v2.4 自身就有 1/10 的调度弱点，**没有值得保留的独有逻辑**，纯做 IPC 桥接是负价值。

---

## 2. 数据模型（最终 SQLite schema）

### 表处理决策

| 表 | 处理 | 理由 |
|---|---|---|
| `tasks` | **合并升级** | 字段合：v2.4 多了 `priority/started_at/completed_at/executor_model/evaluator_model/max_iterations/improvement_threshold/last_heartbeat/user_input`；保留 skill-factory 的 `experience_id/resources/acceptance/repo_address/maintainer` |
| `experiences` | 保留 | skill-factory 独有的工程化字段（log_paths/tool_usage/scene/code_snippets）很有价值 |
| `skill_versions` | 保留 | TDD 验收闭环核心 |
| `executions` | 新增 | 来自 v2.4，每次 CLI 跑一次记录 |
| `evaluations` | 新增 | 来自 v2.4，LLM 评分 |
| `web_links` | **新增** | 功能 1 |
| `dir_shortcuts` | **新增** | 功能 2 |
| `app_settings` | **新增** | K-V 存 todo_md_path / 默认模型 / 主题等 |
| `scheduled_tasks` | **新增** | 功能 3，定时 + AI CLI |
| `app_meta` | **新增** | schema_version / migrate_log / install_id，单实例足够 |

### 完整 CREATE TABLE（合并版，去 IF NOT EXISTS 干扰，仅核心列）

```sql
-- tasks 合并：skill-factory 业务字段 + v2.4 调度字段
CREATE TABLE IF NOT EXISTS tasks (
    id              TEXT PRIMARY KEY,
    title           TEXT NOT NULL,
    description     TEXT,
    module          TEXT,                          -- skill-factory
    status          TEXT DEFAULT 'pending',        -- pending/running/waiting_input/evaluated/failed/cancelled/archived/exception
    priority        INTEGER DEFAULT 0,             -- v2.4
    experience_id   TEXT,                          -- skill-factory
    resources       TEXT,
    acceptance      TEXT,                          -- TDD 用例
    version         TEXT DEFAULT 'v0.0.1',
    repo_address    TEXT,                          -- skill-factory
    executor_model  TEXT DEFAULT 'claude-opus-4-6',
    evaluator_model TEXT DEFAULT 'claude-opus-4-6',
    iteration_count INTEGER DEFAULT 0,
    max_iterations  INTEGER DEFAULT 3,
    improvement_threshold INTEGER DEFAULT 7,
    user_input      TEXT,                          -- 人工确认
    last_heartbeat  DATETIME,
    result          TEXT,
    created_at      DATETIME,
    claimed_at      DATETIME,
    started_at      DATETIME,
    completed_at    DATETIME,
    archived_at     DATETIME,
    maintainer      TEXT,
    FOREIGN KEY (experience_id) REFERENCES experiences(id)
);
CREATE INDEX IF NOT EXISTS idx_tasks_status_priority ON tasks(status, priority DESC, created_at);
CREATE INDEX IF NOT EXISTS idx_tasks_heartbeat ON tasks(status, last_heartbeat);

-- experiences 保留 skill-factory
CREATE TABLE IF NOT EXISTS experiences (
    id TEXT PRIMARY KEY, module TEXT NOT NULL, keywords TEXT,
    log_paths TEXT, tool_usage TEXT, scene TEXT, log_samples TEXT,
    code_snippets TEXT, version TEXT, created_at DATETIME, updated_at DATETIME
);

-- skill_versions 保留
CREATE TABLE IF NOT EXISTS skill_versions (
    id TEXT PRIMARY KEY, task_id TEXT, version TEXT,
    test_cases TEXT, accuracy REAL, iter_count INTEGER,
    status TEXT, created_at DATETIME,
    FOREIGN KEY (task_id) REFERENCES tasks(id)
);

-- executions 来自 v2.4
CREATE TABLE IF NOT EXISTS executions (
    id TEXT PRIMARY KEY, task_id TEXT NOT NULL, source TEXT DEFAULT 'manual', -- manual/scheduled
    scheduled_task_id TEXT,        -- 关联 scheduled_tasks.id，仅 source=scheduled 时使用
    command TEXT NOT NULL,
    working_dir TEXT,
    model TEXT,
    started_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    completed_at DATETIME, output TEXT, error TEXT, exit_code INTEGER,
    FOREIGN KEY (task_id) REFERENCES tasks(id),
    FOREIGN KEY (scheduled_task_id) REFERENCES scheduled_tasks(id)
);
CREATE INDEX IF NOT EXISTS idx_executions_task ON executions(task_id, started_at DESC);

-- evaluations 来自 v2.4
CREATE TABLE IF NOT EXISTS evaluations (
    id TEXT PRIMARY KEY, task_id TEXT NOT NULL, execution_id TEXT NOT NULL,
    evaluator_model TEXT NOT NULL, score INTEGER NOT NULL, comments TEXT,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (task_id) REFERENCES tasks(id),
    FOREIGN KEY (execution_id) REFERENCES executions(id)
);

-- 功能 1：网页链接
CREATE TABLE IF NOT EXISTS web_links (
    id TEXT PRIMARY KEY, name TEXT NOT NULL, url TEXT NOT NULL,
    icon_url TEXT,                        -- 可空，前端回退到 favicon 服务
    sort_order INTEGER DEFAULT 0,
    category TEXT,                        -- 可选分组：dev/blog/tool...
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- 功能 2：目录快捷
CREATE TABLE IF NOT EXISTS dir_shortcuts (
    id TEXT PRIMARY KEY, name TEXT NOT NULL, path TEXT NOT NULL UNIQUE,
    icon TEXT,                            -- emoji 或图标名
    sort_order INTEGER DEFAULT 0,
    last_opened_at DATETIME,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- 功能 3：定时任务
CREATE TABLE IF NOT EXISTS scheduled_tasks (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    cron_expr TEXT NOT NULL,              -- robfig/cron 5 段表达式
    timezone TEXT DEFAULT 'Local',
    enabled INTEGER DEFAULT 1,            -- 0/1
    command_type TEXT NOT NULL,           -- 'claude' | 'codebuddy' | 'cbc' | 'shell'
    model TEXT,                           -- claude/codebuddy 时填
    prompt TEXT,                          -- claude/codebuddy 时填
    shell_cmd TEXT,                       -- command_type=shell 时填
    working_dir TEXT,                     -- 子进程 cwd
    timeout_seconds INTEGER DEFAULT 1800,
    allowed_tools TEXT,                   -- claude: "Bash,Read,Edit,Grep,Glob"
    next_run_at DATETIME,                 -- robfig 解析
    last_run_at DATETIME,
    last_status TEXT,                     -- success/failed/running/error
    last_execution_id TEXT,               -- FK→executions.id
    run_count INTEGER DEFAULT 0,
    fail_count INTEGER DEFAULT 0,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (last_execution_id) REFERENCES executions(id)
);
CREATE INDEX IF NOT EXISTS idx_sched_enabled ON scheduled_tasks(enabled, next_run_at);

-- 功能 4：todo.md 路径 / 全局开关
CREATE TABLE IF NOT EXISTS app_settings (
    key TEXT PRIMARY KEY,
    value TEXT,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
);
-- 预置 key：todo_md_path / default_executor_model / default_evaluator_model / theme / scheduler_poll_interval

-- schema 元信息
CREATE TABLE IF NOT EXISTS app_meta (
    key TEXT PRIMARY KEY, value TEXT
);
-- 预置 key：schema_version
```

**迁移策略**：`InitSchema` 用 `PRAGMA user_version` 做版本号（0→1=加新表，1→2=给 tasks 加新列），幂等。skill-factory 现存用户的 3 张表字段全部保留；v2.4 用户的旧库用一次性迁移 SQL 加列。

---

## 3. 后端模块设计

### 包结构（在 skill-factory/ 基础上扩展）

```
skill-factory/
  cmd/server/
    main.go              # 入口：装配 DB / Scheduler / Executor / Hub / HTTP / PTY
    index.html           # 内嵌 SPA（embed.FS）
    pty_unix.go          # build tag: //go:build unix  → 走 creack/pty
    pty_windows.go       # build tag: //go:build windows → 占位，UI 隐藏 Tab
  internal/
    backend/
      models.go          # 合并所有 struct（Task/Experience/SkillVersion/Execution/Evaluation/...）
      sqlite.go          # OpenDB / PRAGMA
      schema.go          # InitSchema + 迁移
      repo_tasks.go      # 原 repo.go 的 TaskRepo
      repo_experiences.go
      repo_skill_versions.go
      repo_executions.go
      repo_evaluations.go
      repo_web_links.go
      repo_dir_shortcuts.go
      repo_scheduled.go
      repo_settings.go
      server.go          # 原 server.go
    scheduler/
      scheduler.go       # 主循环（受 robfig/cron 驱动 + 心跳 + stale 恢复）
      heartbeat.go       # 30s 心跳刷新
      stale.go           # 启动时重置僵尸
      reconcile.go       # 对账：cron next_run_at 与 DB 一致性
    executor/
      runner.go          # 统一执行接口 Run(execution) (output, error, exitCode)
      claude.go          # claude --print / -c 命令构造
      codebuddy.go       # codebuddy -p / cbc -p
      shell.go           # 通用 shell 执行
      confirm.go         # needs_user_input + parse_confirm_request（移植自 cli_executor.py:62-115）
      retry.go           # 指数退避（移植自 retry.py）
    evaluator/
      evaluator.go       # 评分（移植自 evaluator.py）
      prompts.go
    hub/
      hub.go             # WebSocket 连接管理（gorilla/websocket）
      channels.go        # 频道类型常量
    pty/
      pty.go             # WebSocket↔PTY 桥（原 pty.go 上提一层）
    shortcuts/
      open.go            # 跨平台 open：macOS open / Linux xdg-open / Windows explorer
    todo/
      parser.go          # todo.md 解析（regex）
      writer.go          # 写回（保留其他 markdown 块）
    wsmsg/
      types.go           # 消息结构（task_update / task_output / exec_started ...）
  web/
    index.html           # 重写后的 SPA（见 §4）
  go.mod
  DESIGN.md
  README.md
```

### 关键 Go 库选型

| 用途 | 库 | 说明 |
|---|---|---|
| HTTP 路由 | stdlib `net/http`（Go 1.25 已支持 `mux.HandleFunc("POST /api/x", h)` 模式匹配） | 沿用 skill-factory，不引入第三方路由 |
| WebSocket | `github.com/gorilla/websocket` | 沿用 |
| SQLite | `modernc.org/sqlite` | 纯 Go，**跨平台无 CGO**（关键：Windows 编译一次过） |
| UUID | `github.com/google/uuid` | 沿用 |
| Cron | `github.com/robfig/cron/v3` | 行业标准，支持秒级 / 时区 / 解析 `Next(t)`；同时支持 `cron.ParseStandard("0 9 * * *")` 5 段 |
| 跨平台进程 | stdlib `os/exec` | 跨平台（Windows 自动用 `TerminateProcess` 代替 SIGKILL） |
| Markdown 写回 | stdlib `bufio` + `os` + 正则 | 不引入第三方，逻辑简单 |
| 进程内服务（Windows） | `github.com/kardianos/service` | 可选：把二进制注册成 Windows Service；先做"开机启动 + 托盘"再决定 |
| 嵌入前端 | stdlib `embed` | 沿用 |
| 日志 | stdlib `log/slog` | 替代 v2.4 的 RotatingFileHandler，结构化 + 易对接 |

---

## 4. 前端设计

### 主页布局（Grid 12 列）

```
┌──────────────┬──────────────────────────────────────────────────────────────┐
│              │ 顶部 Header：Logo + Scheduler 状态指示灯（运行/暂停）          │
│  Sidebar     ├─────────────┬──────────────────────────────┬─────────────────┤
│  导航：      │ 左栏 4 col  │  中栏 5 col                  │  右栏 3 col     │
│              │             │                              │                 │
│ 总览(默认)   │ ┌─────────┐ │ ┌───────── 任务面板 ───────┐ │ ┌─ 定时任务 ─┐ │
│ 任务        │ │网页链接 │ │ │ 工具条：状态过滤 / +新建  │ │ │ 下次运行倒计时│ │
│ 经验库       │ │ 网格卡片 │ │ ├──────────────────────────┤ │ │ 启用/禁用开关│ │
│ AI 终端(可选)│ └─────────┘ │ │ 任务表格 (status pill)   │ │ │ Cron 表达式  │ │
│ 自动化(可折) │ ┌─────────┐ │ │                          │ │ │ 手动跑一次   │ │
│ 定时任务    │ │目录快捷 │ │ │                          │ │ └──────────────┘ │
│ 设置        │ │ 列表    │ │ └──────────────────────────┘ │ ┌─ 评估 / 7d柱图┐│
│              │ └─────────┘ │                              │ │  (沿用原 chart)││
│              │ ┌─────────┐ │                              │ └──────────────┘│
│              │ │ todo.md │ │                              │                 │
│              │ │ 待办/完成│ │                              │                 │
│              │ └─────────┘ │                              │                 │
└──────────────┴─────────────┴──────────────────────────────┴─────────────────┘
       160px                任务面板可全宽（grid-column: span 8 / 12）
```

- **总览 Tab**（默认）：保留 skill-factory 风格。1) 4 stat 卡片 + 7 天柱图 + 最新任务表 / 2) 左栏三宫格：网页链接 / 目录快捷 / todo.md
- **任务 Tab**：完整任务表（沿用 skill-factory）+ 点行展开右侧"执行历史"（executions/evaluations）
- **经验库 Tab**：不变
- **定时任务 Tab**（新增）：列表 + 编辑器（Cron 表达式自动解析下次运行时间）
- **AI 终端 Tab**：仅 `GOOS != windows` 时显示；Windows 隐藏并显示"本平台不支持"
- **设置 Tab**（新增）：todo.md 路径、默认模型、调度间隔、import/export JSON

### WebSocket 频道

单条连接 `/api/ws`，消息头带 `channel`：

| channel | 触发场景 | 关键事件 |
|---|---|---|
| `scheduler` | 调度器启停、stale 恢复 | `started/stopped/tick` |
| `task` | 任务状态变化 | `status` `{id,status}` |
| `exec` | 每次执行流式输出 | `started/output/error/finished` `{execution_id, chunk}` |
| `scheduled` | 定时任务触发 | `fired/finished` `{scheduled_task_id, execution_id, status}` |
| `shortcut` | 目录打开结果 | `open_result` `{id, ok, err}` |
| `todo` | todo.md 外部变更 | `refresh` |

### index.html section 划分（描述）

```html
<body>
  <aside class="sidebar">                  <!-- 导航 5-6 个 Tab -->
  <main>
    <header>Scheduler 状态指示灯 + 主题切换</header>

    <section id="page-overview" data-tab="overview">
      <div class="stat-grid">...</div>     <!-- 4 卡片 -->
      <div class="chart">...</div>         <!-- 7 天柱图 -->
      <div class="overview-grid">
        <div id="web-links-panel"></div>   <!-- 左上：网页链接网格 -->
        <div id="dir-shortcuts-panel"></div>  <!-- 左中：目录快捷列表 -->
        <div id="todo-panel"></div>        <!-- 左下：todo.md 两栏 -->
        <div id="recent-tasks-panel"></div><!-- 右：最新任务 -->
      </div>
    </section>

    <section id="page-tasks" hidden>...</section>
    <section id="page-experiences" hidden>...</section>
    <section id="page-scheduled" hidden>...</section>
    <section id="page-ai-terminal" hidden>...</section>
    <section id="page-settings" hidden>...</section>
  </main>

  <!-- Modals: task-modal, exp-modal, link-modal, dir-modal, sched-modal, todo-edit-modal -->
  <script src="app.js"></script>
</body>
```

把 707 行单文件 + 写死的全局函数，重构为：模块化 `app.js`（用 IIFE/对象命名空间拆分 `api / store / ui / ws`），可读性优先，**不上框架**（零依赖、零构建）。

---

## 5. 5 个新功能的关键实现细节

### 功能 1：网页链接

**表 `web_links`** 字段：`id, name, url, icon_url, sort_order, category, created_at`

**API**：
- `GET    /api/web-links`（支持 `?category=` 过滤）
- `POST   /api/web-links`
- `PUT    /api/web-links/{id}`（编辑 name/url/category）
- `DELETE /api/web-links/{id}`
- `POST   /api/web-links/reorder`（body: 排序后的 id 数组，更新 sort_order）

**前端**：
- 网格卡片，每卡 64×64 ico + name（截断）
- ico 优先级：`icon_url` > `https://www.google.com/s2/favicons?domain=<host>&sz=64` > 占位图标
- 卡片右上角小图标 → 弹出"编辑/删除"
- `+` 卡 → 打开 modal，粘贴 URL 自动从 `<host>` 派生 name（用 URL 解析，截取主域首段）

**Go 伪代码（提取 host）**：
```go
import "net/url"
u, _ := url.Parse(rawURL)
host := u.Hostname() // 不含端口
iconURL := "https://www.google.com/s2/favicons?domain=" + host + "&sz=64"
```

### 功能 2：目录快捷

**表 `dir_shortcuts`** 字段：`id, name, path, icon, sort_order, last_opened_at, created_at`

**API**：
- `GET    /api/dir-shortcuts`
- `POST   /api/dir-shortcuts`（创建时 Go 端立即 `os.Stat` 校验，失败返 400）
- `PUT    /api/dir-shortcuts/{id}`
- `DELETE /api/dir-shortcuts/{id}`
- `POST   /api/dir-shortcuts/{id}/open` → 调系统资源管理器 + 更新 `last_opened_at`

**跨平台 `open` 实现**（`internal/shortcuts/open.go`）：
```go
//go:build !windows
func Open(path string) error {
    return exec.Command("open", path).Start()            // macOS
    // Linux: exec.Command("xdg-open", path).Start()
}
//go:build windows
func Open(path string) error {
    return exec.Command("explorer", path).Start()
    // 或 cmd /c start "" "<path>"
}
```
Linux 用 `runtime.GOOS == "linux"` 分支，无需 build tag。

**安全**：
- `os.Stat` 校验存在 + 是目录（不是文件）
- 白名单前缀（可选，配置项）：只允许 `~` / `/Users/...` / `/home/...` / Windows 盘符下路径，防止误开 `/etc`
- 不递归列举内容（懒加载，避免大目录卡 UI）

### 功能 3：定时任务 + AI CLI

**表 `scheduled_tasks`** 见 §2。**关键决策**：

- `command_type` enum: `claude` | `codebuddy` | `cbc` | `shell`
  - `claude`：用 `claude --print --verbose --allowedTools <tools> --model <m> --session-id <sid?> "<prompt>"`
  - `codebuddy`：用 `codebuddy -p -m <m> "<prompt>"`（v2.4 的格式）
  - `cbc`：**用户原文 "cbc -p --model"**，先按"codebuddy 的别名"实现，Go 端按 `command_type` 路由到不同 binary；若 `cbc` 在 PATH 中有但 `codebuddy` 没有，自动 fallback。**实施时需用户在 Phase 1 确认 cbc 是不是真的二进制名**
  - `shell`：直接 `sh -c <shell_cmd>`（也支持 Windows `cmd /c`）
- `allowed_tools`：claude 才用，默认 `"Bash,Read,Edit,Grep,Glob"`
- `next_run_at`：每次 `robfig/cron` 触发后或编辑后更新（用于 UI 显示"下次跑"）

**API**：
- `GET    /api/scheduled`
- `POST   /api/scheduled`
- `PUT    /api/scheduled/{id}`（重算 next_run_at）
- `DELETE /api/scheduled/{id}`（同时 `cron.Remove(id)`）
- `POST   /api/scheduled/{id}/run-now`（立即跑，不影响 cron 调度）
- `POST   /api/scheduled/{id}/toggle`（enabled 翻转）
- `GET    /api/cron/next?expr=...&tz=...`（前端编辑器实时解析）

**执行器关键流程**（`internal/executor/runner.go`）：
```
1. scheduled_tasks 行锁（UPDATE ... SET last_status='running' WHERE id=?)
2. INSERT executions（source='scheduled', scheduled_task_id=...）
3. 构造命令（同 manual task 路径）
4. exec.CommandContext(ctx, ...) → 带超时（timeout_seconds）
5. goroutine 1: 读 stdout，逐行 wsmsg.Broadcast(exec, "output", chunk)
6. goroutine 2: 读 stderr，同上
7. cmd.Wait()
8. 收集全部 output/error，UPDATE executions
9. 写回 scheduled_tasks.last_status / last_run_at / run_count / fail_count
10. cron.Schedule 触发后用 Schedule.Next(time.Now()) 写回 next_run_at
```

**WS 流式**：与任务执行共用 `exec` channel，按 `execution_id` 区分（前端按当前选中过滤）。

**Session 续接**：和 v2.4 一样支持 `claude -c --session-id <sid>`，在 scheduled_tasks 增加可选 `session_id` 字段（默认空 → 不续接）。v2.4 注释里也提到"跨重启 session 会丢"，本设计保持一致不解决持久化。

### 功能 4：todo.md 解析

**设置**：`app_settings` 表存 key `todo_md_path`，默认 `~/todo.md`（启动时 Go 端 expand `~`）。

**API**：
- `GET    /api/settings`
- `PUT    /api/settings/{key}`（todo_md_path 变更时立即 reload）
- `GET    /api/todo` → 解析后结构化
- `PUT    /api/todo/{line_index}/toggle`（body: `{done: true/false}`，写回 md）
- `POST   /api/todo`（新增一行）
- `DELETE /api/todo/{line_index}`

**解析正则**（`internal/todo/parser.go`）：
```go
var todoRe = regexp.MustCompile(`^(\s*)-\s+\[( |x|X)\]\s+(.+)$`)

type Item struct {
    Line  int    `json:"line"`     // 0-based 原始文件行号
    Indent string `json:"indent"`
    Done  bool   `json:"done"`
    Text  string `json:"text"`
}

func Parse(content string) []Item
```
- 文件按行扫描，正则匹配；非匹配行原样保留（写回时用）
- 输出时按"未完成 / 已完成"两栏，前端纯渲染

**写回策略**（保真）：维护 `[]string lines`（原文），修改/新增/勾选都改原行号后整体重写（先写 `.bak`，再 rename）。**不使用就地 regex 替换**，避免破坏 checkbox 中间字符。

**文件 I/O 边界**：
- 文件不存在 → 200 OK，`items: []`，UI 提示"未配置或文件不存在"
- 文件不可读 → 403 提示权限
- 路径跨平台：Windows 允许 `C:\Users\xd\todo.md` 和 `~\todo.md`（`~` expand 用 `os.UserHomeDir`）

### 功能 5：Windows 调度

- **调度**：`robfig/cron/v3` 跨平台，纯 Go，Windows 行为与 Linux 一致（依赖 Go runtime time）
- **进程**：`os/exec` 自动 Windows 化（信号用 `TerminateProcess` 替代 SIGKILL）
- **PTY**：build tag 隔离（`pty_unix.go` / `pty_windows.go`），UI 探测 `navigator.userAgentData.platform` 或后端发个 `runtime: "windows"` 标志；Windows 上"AI 终端"Tab 直接不渲染
- **时区**：cron 默认 Local；`scheduled_tasks.timezone` 字段支持 `"Asia/Shanghai"`，启动时 `time.LoadLocation(tz)` 失败回退 Local 并 log
- **开机自启 / Service**：
  - 短期：写注册表 `HKCU\Software\Microsoft\Windows\CurrentVersion\Run`（Go 用 `golang.org/x/sys/windows/registry`）一行 cmd 启动
  - 中期：引入 `github.com/kardianos/service`，支持 `workbench install/start/stop`
  - macOS 同期支持 `launchd` plist（write `~/Library/LaunchAgents/com.xd.workbench.plist`）
  - Linux：`systemd --user` unit

---

## 6. 关键文件清单

### 新增 Go 文件（按目录）

```
cmd/server/main.go                              # 改：装配新组件
cmd/server/index.html                           # 改：全新 SPA
cmd/server/pty_unix.go                          # 改：//go:build unix
cmd/server/pty_windows.go                       # 新：占位，返回 "not supported"
internal/scheduler/scheduler.go                 # 新
internal/scheduler/heartbeat.go                 # 新
internal/scheduler/stale.go                     # 新
internal/executor/runner.go                     # 新（统一接口）
internal/executor/claude.go                     # 新（移植 cli_executor.py:26-56）
internal/executor/codebuddy.go                  # 新
internal/executor/shell.go                      # 新
internal/executor/confirm.go                    # 新（移植 4 种信号检测）
internal/executor/retry.go                      # 新（移植 retry.py）
internal/evaluator/evaluator.go                 # 新（移植 evaluator.py）
internal/evaluator/prompts.go                   # 新
internal/hub/hub.go                             # 新
internal/hub/channels.go                        # 新
internal/pty/pty.go                             # 新（从 cmd/server/pty.go 提取）
internal/shortcuts/open.go                      # 新（跨平台 open）
internal/shortcuts/open_unix.go                 # 新
internal/shortcuts/open_windows.go              # 新
internal/todo/parser.go                         # 新
internal/todo/writer.go                         # 新
internal/wsmsg/types.go                         # 新
internal/backend/schema.go                      # 新（合并版 schema + 迁移）
internal/backend/repo_executions.go             # 新
internal/backend/repo_evaluations.go            # 新
internal/backend/repo_web_links.go              # 新
internal/backend/repo_dir_shortcuts.go          # 新
internal/backend/repo_scheduled.go              # 新
internal/backend/repo_settings.go               # 新
```

### 修改 skill-factory 现有文件

- `cmd/server/main.go`：装配 Scheduler + Executor + Hub + 新路由
- `cmd/server/index.html`：全新 SPA（见 §4）
- `cmd/server/pty.go`：拆出 → `internal/pty/pty.go` + `pty_unix.go`
- `internal/backend/models.go`：合并 + 新增所有 struct
- `internal/backend/repo.go`：拆为多个 `repo_*.go`
- `internal/backend/sqlite.go`：加 `PRAGMA journal_mode=WAL`（并发友好）
- `internal/backend/server.go`：保留
- `go.mod`：加 `robfig/cron/v3`，其他已有

### 配置文件

- `config.yaml`（可选，仿 v2.4）：`scheduler.poll_interval / executor.timeout / evaluator.model / log.level`
- 不写也行，**全部默认 + DB 覆盖**（app_settings 表存 override）

### 测试文件

```
internal/scheduler/scheduler_test.go            # 调度器：cron 表达式解析 + stale 恢复
internal/executor/claude_test.go                # claude 命令构造 + 参数注入
internal/executor/codebuddy_test.go             # 同上
internal/executor/confirm_test.go               # 4 种确认信号（关键词 + JSON 嵌套）
internal/executor/retry_test.go                 # 指数退避
internal/executor/runner_test.go                # mock exec 进程，验证 ws 推送
internal/todo/parser_test.go                    # 各种 markdown 行样式
internal/todo/writer_test.go                    # 写回保真
internal/shortcuts/open_test.go                 # 平台分支（编译时已隔离）
internal/backend/repo_*_test.go                 # 全部 Repo 单元测试，沿用 skill-factory TestDB
cmd/server/main_test.go                         # HTTP handler 集成测试
```

### 文档

- `DESIGN.md`：**重写**，从 skill-factory 单产品扩为 all-in-one 设计
- `README.md`：**新写**，含安装、跨平台说明、5 大功能截图位
- `docs/MIGRATION.md`：从 v2.4 / skill-factory 旧库迁移指南
- `docs/CLI.md`：支持的 AI CLI（claude / codebuddy / cbc）说明
- `CHANGELOG.md`：v3.0 起点

---

## 7. 实施阶段

### Phase 1 — 基础架构整合（Day 1-3）
**目标**：新 schema 跑通、新表 CRUD、调度器骨架

- 合并 schema，新增 6 张表，迁移逻辑
- 拆分 repo_*.go
- 引入 `robfig/cron/v3`，骨架 scheduler 跑起来（先不接 executor）
- Hub + WS 框架（仅 scheduler 频道）
- 拆 pty_unix.go / pty_windows.go
- **验收**：`go test ./...` 全绿；`/api/scheduled` CRUD 工作；空 cron 任务"立即跑"返回 stub

### Phase 2 — AI CLI 执行器（Day 4-6）
**目标**：重写 v2.4 的核心能力

- executor/{runner,claude,codebuddy,shell,confirm,retry}.go
- 移植 4 种人工确认信号（用 Go 写一遍 + 等价 Go 测试）
- 移植指数退避
- 移植 evaluator（CLI 模式）
- 接入 executions/evaluations 表
- WS `exec` channel 流式输出
- **验收**：手动建一个 task → 选 claude → 跑通；output 实时推到前端；勾选 --session-id 续接；timeout 触发；exit code=1 时重试 2 次后标 failed

### Phase 3 — 5 个新功能前后端（Day 7-10）
**目标**：5 个功能 + 主页布局

- Day 7：web_links + dir_shortcuts（前后端 + 跨平台 open）
- Day 8：scheduled_tasks + cron 编辑器 + run-now + 流式输出
- Day 9：todo.md 解析 + 写回 + 设置页
- Day 10：index.html 重写（grid 布局 + 全部 JS 逻辑）
- **验收**：5 个功能每个都有"创建→展示→使用"完整 happy path；UI 在 1280px 宽下不破版

### Phase 4 — 跨平台测试（Day 11-12）
**目标**：在 macOS / Linux / Windows 三平台分别跑过

- 用 `GOOS=windows GOARCH=amd64 go build` 验证编译
- GitHub Actions 三平台 matrix：ubuntu-latest / macos-latest / windows-latest
- 实际跑：`workbench start` → 创建定时任务（1 分钟后触发）→ 验证触发
- Windows PTY 隐藏：UI 验证 + 截图
- 跨平台 open：每个平台各测一个目录
- **验收**：CI 三平台全绿；手动冒烟全过

### Phase 5 — 文档与发布（Day 13）
**目标**：可分发的 v3.0

- 重写 DESIGN.md
- 写 README（快速开始 + 5 功能 + 跨平台）
- 写 MIGRATION.md（旧 skill-factory / v2.4 数据迁移）
- `goreleaser` 配置：darwin/amd64+arm64、linux/amd64+arm64、windows/amd64
- 写 `xd-workbench.service` / plist / 开机自启说明
- **验收**：`go install` 单命令跑起来；`workbench --version` 输出 v3.0.0

---

## 8. 风险评估

| 风险 | 等级 | 缓解 |
|---|---|---|
| 单 Go 二进制 vs 双进程取舍 | **中** | 用户已明确"all in one"；在 DESIGN.md 写明"为何不双进程"备查 |
| "136 个 Python 测试"不可复用 | **低** | **重要事实**：v2.4 的 `tests/` 目录是空的（仅 `__init__.py`），父目录 `ai-playground/ai-task-system/tests/` 有 pytest 文件但属更早版本（v2.2 / v2.3 共用）且测试 `_executor / _database / _evaluator` 调的是旧接口。**结论**：直接重写 Go 等价测试，不做 Python→Go 翻译 |
| 4 种人工确认信号移植偏差 | **中** | v2.4 逻辑简单（关键词 in / 正则匹配），Go 端用 `strings.Contains` + `regexp` 等价实现；准备一份"对照测试集"（v2.4 fixture → Go 期望输出）一次性验证 |
| Windows PTY 不可用影响核心工作流 | **低** | PTY 是"AI 对话 Tab"的可选功能；核心是"调度器 + AI CLI + 流式输出"，这些走 `os/exec` 完全跨平台；UI 用 build tag + 运行时探测隐藏 Tab |
| claude / codebuddy / cbc CLI 假设在 PATH | **中** | 启动时 health-check：`exec.LookPath("claude")` / `codebuddy` / `cbc`，缺失则在 settings 页提示；不强制阻断（用户可能只用到一部分） |
| 调度器时区错乱（DST / 跨时区机器） | **低** | 默认 `Local` + 存 `time.Location` 字符串；前端编辑器用 `Intl.DateTimeFormat().resolvedOptions().timeZone` 默认 |
| 并发安全：多 goroutine 写同一 task | **中** | 用 SQLite `UPDATE ... WHERE id=? AND status='pending'` 原子认领（同 v2.4 思路）；行级锁足够，SQLite WAL 模式 |
| 单 sqlite 文件并发写瓶颈 | **低** | 个人工作台，并发量 < 10；WAL 模式 + `SetMaxOpenConns(1)` 避免 SQLITE_BUSY |
| 用户改 `cbc` 命令名是否真实 | **中** | **Phase 1 需用户确认**："cbc" 是独立二进制，还是 `codebuddy` 的别名？写进 README/CLI.md |
| 旧 skill-factory 用户的 3 张表字段保留完整 | **低** | schema 升级不动老字段，只 `ALTER TABLE ADD COLUMN` 加新列；IF NOT EXISTS 全程兜底 |
| embed.FS 单文件上限 | **低** | 707→预计 1500 行的 index.html 远低于 Go embed 限制（实际无明确上限，实测 1MB+ 都行） |
| Go 1.25 是非常新的版本 | **低** | 用户机器 Go 版本可能 < 1.25；可在 Phase 1 第一步验证 `go version`，必要时降到 1.22（stdlib `mux` 模式从 1.22 起支持） |

---

## 附录 A：核心执行器 Go 接口（伪代码）

```go
// internal/executor/runner.go
type RunRequest struct {
    ExecutionID     string
    TaskID          string
    Source          string         // "manual" | "scheduled"
    ScheduledTaskID string         // optional
    CommandType     string         // "claude" | "codebuddy" | "cbc" | "shell"
    Model           string
    Prompt          string
    ShellCmd        string
    WorkingDir      string
    TimeoutSeconds  int
    AllowedTools    string
    SessionID       string
}

type RunResult struct {
    Output   string
    Error    string
    ExitCode int
    Duration time.Duration
}

type Runner interface {
    Run(ctx context.Context, req RunRequest, onChunk func(stream, line string)) (*RunResult, error)
}

type OSRunner struct{ hub *hub.Hub }

func (r *OSRunner) Run(ctx context.Context, req RunRequest, onChunk func(string, string)) (*RunResult, error) {
    var cmd *exec.Cmd
    switch req.CommandType {
    case "claude":    cmd = buildClaudeCmd(req)
    case "codebuddy": cmd = buildCodebuddyCmd(req)
    case "cbc":       cmd = buildCBCCmd(req)
    case "shell":     cmd = buildShellCmd(req)
    default:          return nil, fmt.Errorf("unknown command_type: %s", req.CommandType)
    }
    if req.WorkingDir != "" { cmd.Dir = req.WorkingDir }
    cmd.Env = os.Environ()
    timeoutCtx, cancel := context.WithTimeout(ctx, time.Duration(req.TimeoutSeconds)*time.Second)
    defer cancel()
    return r.exec(timeoutCtx, cmd, onChunk)
}

func (r *OSRunner) exec(ctx context.Context, cmd *exec.Cmd, onChunk func(string, string)) (*RunResult, error) {
    stdout, _ := cmd.StdoutPipe()
    stderr, _ := cmd.StderrPipe()
    if err := cmd.Start(); err != nil { return nil, err }
    var wg sync.WaitGroup
    wg.Add(2)
    go func() { defer wg.Done(); pipeTo(stdout, "stdout", onChunk) }()
    go func() { defer wg.Done(); pipeTo(stderr, "stderr", onChunk) }()
    wg.Wait()
    err := cmd.Wait()
    exit := 0
    if err != nil { exit = 1 } // 简化；用 ExitCode()
    return &RunResult{ExitCode: exit, Duration: ...}, err
}
```

## 附录 B：跨平台 open（伪代码）

```go
// internal/shortcuts/open.go
func Open(path string) error {
    switch runtime.GOOS {
    case "darwin":  return exec.Command("open", path).Start()
    case "linux":   return exec.Command("xdg-open", path).Start()
    case "windows": return exec.Command("explorer", path).Start()
    default:        return fmt.Errorf("unsupported OS: %s", runtime.GOOS)
    }
}
```

## 附录 C：todo.md 解析（伪代码）

```go
var re = regexp.MustCompile(`^(\s*)-\s+\[( |x|X)\]\s+(.+)$`)

func Parse(content string) []Item {
    var out []Item
    for i, line := range strings.Split(content, "\n") {
        m := re.FindStringSubmatch(line)
        if m == nil { continue }
        out = append(out, Item{
            Line: i, Indent: m[1], Done: m[2] != " ",
            Text: strings.TrimRight(m[3], " \r"),
        })
    }
    return out
}

func ToggleLine(content string, lineIdx int, done bool) string {
    lines := strings.Split(content, "\n")
    if lineIdx < 0 || lineIdx >= len(lines) { return content }
    m := re.FindStringSubmatch(lines[lineIdx])
    if m == nil { return content }
    mark := " "
    if done { mark = "x" }
    lines[lineIdx] = m[1] + "- [" + mark + "] " + m[3]
    return strings.Join(lines, "\n")
}
```

---

## 实施前的 2 个待用户确认项

1. **`cbc` 是不是独立二进制**？还是 `codebuddy` 的 alias？——影响 `command_type='cbc'` 的实现（直接 exec `cbc`，还是映射到 `codebuddy`）
2. **Go 版本**：环境是 Go 1.25（skill-factory 用了）；用户本地若 < 1.22 则需降级（去掉 stdlib mux 模式匹配语法）

