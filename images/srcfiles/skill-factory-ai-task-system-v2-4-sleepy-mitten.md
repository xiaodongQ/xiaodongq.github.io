# Skill-Factory × AI-Task-System v2.4 — All-in-One 个人工作台

## Context（为什么做这件事）

用户维护两个并行项目，**重复能力**（任务管理 + Web UI + AI CLI）+ **互补短板**（skill-factory 无调度/执行引擎，v2.4 无经验库/PTY）造成精力分散。同时日常需要 5 类高频操作（网页跳转、目录跳转、定时 AI 任务、todo 跟踪、跨平台部署），目前散落在多个工具里。

**目标**：把两个系统融成**单 Go 二进制**的「个人工作台」，加上 5 个新功能，作为日常的 homepage/launcher 统一入口。

**用户已确认的关键决策**：
- **后端栈**：单 Go 二进制（重写 v2.4 的 cli_executor/scheduler/evaluator 到 Go）
- **`cbc` 是 `codebuddy` 的别名/简写**：定时任务里 `cbc` 和 `codebuddy` 二选一即可，统一用 `cbc -p --model <m> "<task>"`
- **数据迁移**：从零开始（旧 db 备份为 `.bak`，新 schema 重建）
- **定时精度**：标准 5 字段 cron 表达式（`robfig/cron/v3`）+ `@every Ns` 间隔备选

---

## 1. 目标架构

```
┌──────────────────────────────────────────────────────────┐
│ Browser: 单页 SPA（index.html 改写为 12 列 grid）          │
│ ┌──── 左 4 列 ────┬──── 中 5 列 ────┬── 右 3 列 ──┐       │
│ │ ★ 网页链接      │ AI 任务列表      │ ⏰ 定时任务 │       │
│ │ ★ 目录快捷      │ + 详情 + WS 流   │ + 7 天柱图 │       │
│ │ ★ todo.md       │ + 创建/重试      │ 经验库     │       │
│ └─────────────────┴─────────────────┴─────────────┘       │
│ ┌────────────── PTY / 7天统计 / 调度器状态 ─────────────┐  │
│ └──────────────────────────────────────────────────────┘  │
└────────────────────┬─────────────────────────────────────┘
                     │ HTTP REST + WebSocket
┌────────────────────▼─────────────────────────────────────┐
│ Go 单进程（skill-factory 扩展）                              │
│  internal/                                                │
│   ├ backend/      models + repo + schema (合并扩展)        │
│   ├ scheduler/    robfig/cron 包装 (定时任务引擎)          │
│   ├ executor/     claude/cbc/shell runner + 流式 stdout    │
│   ├ evaluator/    LLM 评分 (可选 v0.1 先不做)              │
│   ├ hub/          WebSocket 广播中心                       │
│   ├ pty/          PTY (build tag 隔离 Windows)             │
│   ├ shortcuts/    跨平台 open dir + web 跳转              │
│   ├ todo/         todo.md 解析 + 写回                     │
│   └ wsmsg/        WS 消息类型定义                          │
└────────────────────┬─────────────────────────────────────┘
                     │
        ┌────────────▼────────────┐
        │  SQLite (./data/all-in-one.db) │
        │  9 张表（见 §2 schema）        │
        └──────────────────────────┘
```

---

## 2. 数据模型（9 张表）

**关键原则**：保留 skill-factory 强项（experience / skill_versions / TDD 验收），补充 v2.4 调度字段，新增 6 张表满足 5 个新功能。Schema 用 `PRAGMA user_version` 幂等演进（v1=初版，v2+ 加新表）。

### 2.1 保留 + 扩展 `tasks` 表

合并 skill-factory 现有 + v2.4 调度字段：

```sql
CREATE TABLE tasks (
    id TEXT PRIMARY KEY,
    title TEXT NOT NULL,
    description TEXT,
    status TEXT DEFAULT 'pending',        -- pending/in_progress/archived/exception
    priority INTEGER DEFAULT 5,            -- v2.4 抢占权重
    experience_id TEXT,                    -- skill-factory 强项
    resources TEXT,
    acceptance TEXT,                       -- TDD 验收标准
    version TEXT DEFAULT 'v0.0.1',
    created_at DATETIME,
    claimed_at DATETIME,
    started_at DATETIME,                   -- v2.4 字段
    completed_at DATETIME,                 -- v2.4 字段
    maintainer TEXT,
    repo_address TEXT,
    archived_at DATETIME,
    result TEXT,
    -- 调度相关
    executor_model TEXT,                   -- v2.4: claude 用 --model
    cbc_model TEXT,                        -- v2.4: codebuddy/cbc 用 --model/-m
    iteration_count INTEGER DEFAULT 0,
    max_iterations INTEGER DEFAULT 20,
    improvement_threshold REAL,
    last_heartbeat DATETIME,
    last_error TEXT
);
```

### 2.2 保留 `experiences` / `skill_versions`

```sql
-- 完整保留 skill-factory/cmd/server/.../internal/backend/repo.go 的两表
CREATE TABLE experiences (...);   -- 见原 models.go:32-44
CREATE TABLE skill_versions (...); -- 见原 models.go:46-55
```

### 2.3 新增 6 张表

```sql
-- v2.4 的执行/评估记录
CREATE TABLE executions (
    id TEXT PRIMARY KEY,
    task_id TEXT,                         -- 关联 tasks（NULL 表示定时任务触发）
    scheduled_task_id TEXT,               -- 关联 scheduled_tasks（NULL 表示手动/任务触发）
    source TEXT NOT NULL,                 -- 'manual' | 'scheduled' | 'retry'
    command TEXT NOT NULL,                -- 实际执行的命令字符串
    model TEXT,
    started_at DATETIME,
    completed_at DATETIME,
    output TEXT,                          -- stdout 完整内容
    error TEXT,                           -- stderr
    exit_code INTEGER
);
CREATE INDEX idx_executions_task ON executions(task_id, started_at DESC);
CREATE INDEX idx_executions_scheduled ON executions(scheduled_task_id, started_at DESC);

CREATE TABLE evaluations (
    id TEXT PRIMARY KEY,
    task_id TEXT,
    execution_id TEXT,
    evaluator_model TEXT,
    score REAL,                           -- 0-10
    comments TEXT,
    created_at DATETIME
);

-- 新功能 1: 网页链接
CREATE TABLE web_links (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,                   -- 显示名
    url TEXT NOT NULL,
    icon_url TEXT,                        -- 可选自定义 ico，否则走 favicon 回退
    sort_order INTEGER DEFAULT 0,
    created_at DATETIME
);

-- 新功能 2: 目录快捷
CREATE TABLE dir_shortcuts (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    path TEXT NOT NULL,                   -- 本地绝对路径
    sort_order INTEGER DEFAULT 0,
    created_at DATETIME,
    last_accessed_at DATETIME
);

-- 新功能 3: 定时任务
CREATE TABLE scheduled_tasks (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    cron_expr TEXT NOT NULL,              -- 5 字段标准 cron 或 @every Ns
    command_type TEXT NOT NULL,           -- 'claude' | 'cbc' | 'shell'
    model TEXT,                           -- command_type 是 shell 时忽略
    prompt TEXT,                          -- claude/cbc 的 prompt；shell 时为 command
    working_dir TEXT,
    enabled INTEGER DEFAULT 1,            -- 0/1
    last_run_at DATETIME,
    last_status TEXT,                     -- 'success' | 'failed' | 'timeout'
    last_execution_id TEXT,               -- 关联最近一次 executions.id
    created_at DATETIME
);

-- 新功能 4 + 设置
CREATE TABLE app_settings (
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL,
    updated_at DATETIME
);
-- 预置 key: 'todo_md_path' / 'timezone' / 'default_model_claude' / 'default_model_cbc'

-- v0.1 通用 KV（版本号、迁移标记等）
CREATE TABLE app_meta (
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL
);
```

**Go 侧 init 流程**：
```go
// internal/backend/repo.go 改造
func InitSchema(db *sql.DB) error {
    v, _ := getUserVersion(db)
    if v < 1 { applyV1(db) }    // 合并 tasks + experiences + skill_versions + 6 新表
    if v < 2 { applyV2(db) }    // 未来扩展
    return nil
}
```

---

## 3. 后端模块拆分

### 3.1 新增 Go 包（在 `skill-factory/internal/` 下）

| 包 | 职责 | 关键依赖 |
|---|---|---|
| `scheduler/` | 包装 `robfig/cron/v3`，解析 cron/间隔，触发回调写 `executions` | `github.com/robfig/cron/v3` |
| `executor/` | 子进程流式执行 + 4 种人工确认信号检测 | Go stdlib `os/exec` |
| `executor/runner/` | claude / cbc / shell 三种 Runner 接口 | — |
| `hub/` | WebSocket 中心：6 个 channel 广播 | `gorilla/websocket`（已有） |
| `shortcuts/open.go` | 跨平台 `open` 实现 + `os.Stat` 校验 | stdlib |
| `todo/parser.go` | 正则 `^(\s*)-\s+\[( |x|X)\]\s+(.+)$` | stdlib |
| `todo/writer.go` | 写回策略：先写 `.bak` 再 rename | stdlib |
| `wsmsg/types.go` | 消息结构 + 序列化 | stdlib |
| `pty/pty.go`（Unix）| macOS/Linux 真 PTY（沿用 creack/pty） | `github.com/creack/pty`（已有） |
| `pty/pty_windows.go` | Windows stub，返回「不支持」 | — |

### 3.2 CLI 命令构造（从 cli_executor.py:26-56 移植）

```go
// internal/executor/runner/build.go
func BuildCommand(typ, model, sessionID, prompt string) ([]string, error) {
    switch typ {
    case "claude":
        cmd := []string{"claude", "--print", "--verbose"}
        if model != "" { cmd = append(cmd, "--model", model) }
        if sessionID != "" { cmd = append(cmd, "--session-id", sessionID) }
        cmd = append(cmd, prompt)
        return cmd, nil
    case "cbc", "codebuddy":
        // 二选一即可：PATH 中有 cbc 用 cbc，否则回落 codebuddy
        bin := "cbc"
        if _, err := exec.LookPath("cbc"); err != nil {
            if _, err2 := exec.LookPath("codebuddy"); err2 == nil {
                bin = "codebuddy"
            } else {
                return nil, errors.New("neither cbc nor codebuddy found in PATH")
            }
        }
        cmd := []string{bin, "-p"}
        if model != "" { cmd = append(cmd, "--model", model) }  // 兼容 -m，优先 --model
        cmd = append(cmd, prompt)
        return cmd, nil
    case "shell":
        // 走 sh -c 形式（用 exec.Command 自行 quote，不传 bash）
        return []string{prompt}, nil  // 调用方根据需要 WrapShell
    default:
        return nil, fmt.Errorf("unknown command_type: %s", typ)
    }
}
```

### 3.3 流式执行（移植 cli_executor.py:117-188）

```go
// internal/executor/exec.go
type Result struct {
    Output string; Error string; CmdStr string; ExitCode int
}

func Run(ctx context.Context, cmd []string, onChunk func(string)) (*Result, error) {
    c := exec.CommandContext(ctx, cmd[0], cmd[1:]...)
    stdout, _ := c.StdoutPipe()
    stderr, _ := c.StderrPipe()
    if err := c.Start(); err != nil { return nil, err }

    var out, errBuf strings.Builder
    var wg sync.WaitGroup
    wg.Add(2)
    go func() { defer wg.Done(); buf := make([]byte, 4096); for { n, e := stdout.Read(buf); if n>0 { s := string(buf[:n]); out.WriteString(s); onChunk(s) }; if e!=nil { break } } }()
    go func() { defer wg.Done(); buf := make([]byte, 4096); for { n, e := stderr.Read(buf); if n>0 { s := string(buf[:n]); errBuf.WriteString(s); onChunk("[err] " + s) }; if e!=nil { break } } }()

    err := c.Wait()
    wg.Wait()
    return &Result{Output: out.String(), Error: errBuf.String(), CmdStr: strings.Join(cmd, " "), ExitCode: c.ProcessState.ExitCode()}, err
}
```

### 3.4 4 种人工确认信号（移植 cli_executor.py:62-115）

```go
// internal/executor/confirm.go
var confirmSignals = []string{
    "?", "[Y/n]", "[是/否]", "[y/n]", "[Yes/No]",
    "是否要", "要不要", "是否需要", "请确认",
    "不确定", "需要更多信息", "请告诉我", "请选择",
    "Press Enter", "按 Enter", "输入选择",
    "Continue?", "Proceed?", "Confirm",
}

func NeedsUserInput(output string) bool {
    for _, s := range confirmSignals {
        if strings.Contains(output, s) { return true }
    }
    return false
}

var confirmJSONRe = regexp.MustCompile(`\{[^{}]*"confirm_type"[^{}]*\}`)

func ParseConfirmRequest(output string) map[string]any {
    match := confirmJSONRe.FindString(output)
    if match == "" { return nil }
    var m map[string]any
    if json.Unmarshal([]byte(match), &m) == nil {
        if _, ok := m["confirm_type"]; ok { return m }
    }
    return nil
}
```

### 3.5 调度器骨架

```go
// internal/scheduler/scheduler.go
type Scheduler struct {
    cron *cron.Cron
    db   *sql.DB
    hub  *hub.Hub
    location *time.Location
}

func New(db *sql.DB, hub *hub.Hub) *Scheduler {
    loc, _ := time.LoadLocation("Local")
    return &Scheduler{
        cron: cron.New(cron.WithLocation(loc)),
        db:   db,
        hub:  hub,
        location: loc,
    }
}

func (s *Scheduler) Start() error {
    // 1. 加载 enabled=1 的所有 scheduled_tasks
    rows, _ := s.db.Query(`SELECT id,name,cron_expr,command_type,model,prompt,working_dir FROM scheduled_tasks WHERE enabled=1`)
    defer rows.Close()
    for rows.Next() { /* rows.Scan + s.cron.AddFunc(cronExpr, s.makeHandler(...)) */ }
    s.cron.Start()
    return nil
}

func (s *Scheduler) makeHandler(st ScheduledTask) func() {
    return func() {
        cmd, _ := BuildCommand(st.CommandType, st.Model, "", st.Prompt)
        res, _ := Run(context.Background(), cmd, func(chunk string) {
            s.hub.Broadcast("scheduled", map[string]any{
                "scheduled_task_id": st.ID, "chunk": chunk,
            })
        })
        // 写 executions（source='scheduled'）+ 更新 last_run_at/last_status
    }
}
```

### 3.6 跨平台目录打开

```go
// internal/shortcuts/open.go
func OpenDir(path string) error {
    if _, err := os.Stat(path); err != nil { return fmt.Errorf("path not accessible: %w", err) }
    var cmd *exec.Cmd
    switch runtime.GOOS {
    case "darwin":  cmd = exec.Command("open", path)
    case "linux":   cmd = exec.Command("xdg-open", path)
    case "windows": cmd = exec.Command("explorer", path)
    default:        return fmt.Errorf("unsupported OS: %s", runtime.GOOS)
    }
    return cmd.Start()  // 异步，不等退出
}
```

### 3.7 todo.md 解析

```go
// internal/todo/parser.go
var itemRe = regexp.MustCompile(`^(\s*)-\s+\[( |x|X)\]\s+(.+)$`)

type Item struct {
    LineNo int    `json:"line_no"`
    Indent string `json:"indent"`
    Done   bool   `json:"done"`
    Text   string `json:"text"`
}

func Parse(content string) []Item {
    var items []Item
    for i, line := range strings.Split(content, "\n") {
        m := itemRe.FindStringSubmatch(line)
        if m == nil { continue }
        items = append(items, Item{
            LineNo: i + 1,
            Indent: m[1],
            Done:   m[2] != " ",
            Text:   m[3],
        })
    }
    return items
}

func ToggleAndWrite(path string, items []Item) error {
    content, err := os.ReadFile(path)
    if err != nil { return err }
    lines := strings.Split(string(content), "\n")
    for _, it := range items {
        marker := " "
        if it.Done { marker = "x" }
        lines[it.LineNo-1] = it.Indent + "- [" + marker + "] " + it.Text
    }
    bak := path + ".bak"
    if err := os.WriteFile(bak, []byte(strings.Join(lines, "\n")), 0644); err != nil { return err }
    return os.Rename(bak, path)  // 原子替换
}
```

---

## 4. API 端点（REST + WebSocket）

### 4.1 保留（兼容 skill-factory）

```
GET    /api/tasks              支持 status / offset / limit
POST   /api/tasks
GET    /api/tasks/{id}
PUT    /api/tasks/{id}/status
GET    /api/experiences        支持 module 模糊
POST   /api/experiences
GET    /api/experiences/{id}
GET    /api/stats
GET    /api/pty                PTY (Windows 返回 503)
```

### 4.2 新增（任务执行相关，移植 v2.4）

```
POST   /api/tasks/{id}/run                 立即执行（command_type 来自 experience 关联或默认 claude）
POST   /api/tasks/{id}/cancel              取消（kill 子进程）
POST   /api/tasks/{id}/submit-input        人工确认提交
GET    /api/tasks/{id}/executions
GET    /api/tasks/{id}/evaluations
POST   /api/scheduler/start
POST   /api/scheduler/stop
GET    /api/scheduler/status
WS     /ws
```

### 4.3 新增（5 个新功能）

```
# 网页链接
GET    /api/web-links
POST   /api/web-links
PUT    /api/web-links/{id}
DELETE /api/web-links/{id}
POST   /api/web-links/{id}/open           （前端其实直接 window.open，不走后端）

# 目录快捷
GET    /api/dir-shortcuts
POST   /api/dir-shortcuts
PUT    /api/dir-shortcuts/{id}
DELETE /api/dir-shortcuts/{id}
POST   /api/dir-shortcuts/{id}/open       走 internal/shortcuts.OpenDir

# 定时任务
GET    /api/scheduled
POST   /api/scheduled
PUT    /api/scheduled/{id}
DELETE /api/scheduled/{id}
POST   /api/scheduled/{id}/run-now        立即跑一次
GET    /api/scheduled/{id}/next-runs      返回 cron 解析后的接下来 N 次时间
POST   /api/scheduler/reload              重新加载 DB 改动

# todo.md
GET    /api/todo                          读 path, 解析, 返回结构化
PUT    /api/todo/{line_no}/toggle         勾选/取消
GET    /api/todo/path                     返回当前 path
PUT    /api/todo/path                     更新 path（写 app_settings）

# 设置
GET    /api/settings
PUT    /api/settings/{key}
```

### 4.4 WebSocket 频道（6 个）

```go
// internal/wsmsg/types.go
const (
    ChannelScheduler  = "scheduler"  // 调度器状态/启动/停止
    ChannelTask       = "task"       // 任务状态变更
    ChannelExec       = "exec"       // 任务执行的 stdout/stderr 流
    ChannelScheduled  = "scheduled"  // 定时任务触发 + 输出
    ChannelShortcut   = "shortcut"   // （可选）快捷方式打开通知
    ChannelTodo       = "todo"       // todo.md 解析结果
)
```

---

## 5. 前端改造（`cmd/server/index.html`）

### 5.1 布局（12 列 grid）

```
┌─────────────────────────────────────────────────────────────────┐
│ Header:  Skill-Factory  ●scheduler  v1.0.0   [+ New Task]      │
├──────────────┬──────────────────────────┬────────────────────────┤
│ ★ Links (4c) │  AI Tasks (5c)           │  ⏰ Scheduled (3c)     │
│ ┌──┬──┬──┐   │  ┌─ filter: [all▾] ┐    │  ┌─ + New Schedule ─┐  │
│ │GH│博客│ +│   │  │ pending: 5     │    │  │ @every 30m       │  │
│ └──┴──┴──┘   │  │ in_prog: 2     │    │  │ cbc → "..."      │  │
│ + Add Link    │  │ archived: 12   │    │  │ [enable] [run]   │  │
│               │  └────────────────┘    │  └──────────────────┘  │
│ ★ Dirs (4c)   │  ┌─ task list ────┐    │                        │
│ ┌──────────┐  │  │ ● 解析 slowlog  │    │  ★ 7-day chart        │
│ │ ~/code   │  │  │ ● 排查 cluster │    │  ███▆▃█▆▄             │
│ │ ~/notes  │  │  │ ● ...         │    │                        │
│ │ + Add    │  │  └────────────────┘    │  ★ 经验库 (3c, 折叠)    │
│ └──────────┘  │  ┌─ detail panel ─┐   │                        │
│               │  │ (WS 流式输出)  │    │                        │
│ ★ Todo (4c)   │  └────────────────┘    │                        │
│ ┌──────────┐  │                          │                        │
│ │ ☐ 写周报  │  │                          │                        │
│ │ ☑ 改 PR   │  │                          │                        │
│ │ ☐ 读论文  │  │                          │                        │
│ └──────────┘  │                          │                        │
├──────────────┴──────────────────────────┴────────────────────────┤
│ PTY / 调度日志（折叠抽屉）                                          │
└─────────────────────────────────────────────────────────────────┘
```

### 5.2 改造点

- 沿用现有 vanilla JS + 手写 CSS（不上框架）
- 拆出 `app.js` 模块（任务/链接/目录/todo/定时 5 个子模块）
- 保留 xterm.js 终端、7 天柱状图、design system 风格
- 5 个新模块的前端 widget（每模块约 100-150 行 JS）

### 5.3 WS 客户端（伪代码）

```js
const ws = new WebSocket(`ws://${location.host}/ws`);
const handlers = { task: renderTask, exec: appendChunk, scheduled: renderScheduled, todo: renderTodo, scheduler: renderStatus, shortcut: noop };
ws.onmessage = e => {
  const msg = JSON.parse(e.data);
  (handlers[msg.channel] || (() => {}))(msg.payload);
};
```

---

## 6. 关键文件清单

### 6.1 新增（Go）

```
skill-factory/internal/
  backend/
    schema.go              重写：合并 v1+v2 schema，PRAGMA user_version
    repo.go                重写：拆 6 个 repo（Task/Experience/Execution/Evaluation/WebLink/DirShortcut/Scheduled/AppSettings）
  scheduler/
    scheduler.go           包装 robfig/cron
    load.go                从 DB 加载 enabled=1
  executor/
    exec.go                Run + 流式 + ctx
    confirm.go             NeedsUserInput + ParseConfirmRequest
    runner/build.go        BuildCommand(typ, model, session, prompt)
    runner/shell.go        shell runner（用 sh -c 形式）
  hub/
    hub.go                 6 频道广播中心
  shortcuts/
    open.go                跨平台 OpenDir
    open_test.go
  todo/
    parser.go              Parse + ToggleAndWrite
    parser_test.go
  wsmsg/
    types.go               6 频道常量 + 消息 struct
  pty/
    pty_unix.go            沿用 creack/pty（macOS/Linux）
    pty_windows.go         stub: 返回 "unsupported on Windows"
```

### 6.2 修改

```
skill-factory/cmd/server/main.go        装配：DB → 6 repo → scheduler → hub → 路由
skill-factory/cmd/server/index.html     重写为 12 列 grid
skill-factory/cmd/server/pty.go         保留，提取到 internal/pty
skill-factory/internal/backend/models.go  扩展 Task 字段 + 新增 6 个 model
skill-factory/internal/backend/repo.go    拆分扩展
skill-factory/go.mod                    新增依赖：robfig/cron/v3
```

### 6.3 测试（每个新包对应 `_test.go`）

```
internal/scheduler/    scheduler_test.go    验证 cron 解析 + DB 加载 + 触发写 execution
internal/executor/     exec_test.go         mock 进程（echo 命令）测流式
internal/executor/     confirm_test.go      4 种信号检测
internal/shortcuts/    open_test.go         mock runtime.GOOS
internal/todo/         parser_test.go       各种 markdown 格式
internal/backend/      repo_*_test.go       沿用现有 TDD 模式
```

### 6.4 文档

```
skill-factory/DESIGN.md       重写：v2 all-in-one 设计
skill-factory/README.md       新写：启动、配置、API 速查
skill-factory/docs/MIGRATION.md  v1 → v2 迁移指南（schema 变更）
skill-factory/docs/CLI.md     claude / cbc / shell 命令格式
```

---

## 7. 实施阶段（5 阶段，每阶段含验收）

### Phase 1: 基础架构（第 1-3 天）
- [ ] 新 schema 落地（schema.go + 6 新表）
- [ ] 6 个 repo 拆分 + 单测
- [ ] models.go 扩展 Task 字段
- [ ] main.go 装配 6 repo
- [ ] hub 包 + WS handler
- [ ] 启动后 `/api/stats` 仍 200，DB 9 张表都存在
- **验收**：`curl /api/stats` + `sqlite3 .schema` 验证

### Phase 2: AI CLI 执行器（第 4-6 天）
- [ ] BuildCommand 三种 type
- [ ] Run 流式 + ctx 超时
- [ ] 4 种人工确认信号
- [ ] 任务执行 API（POST /run, /cancel, /submit-input）
- [ ] WS `exec` 频道流式推送
- **验收**：创建任务 → 跑 `echo hello` 测试 → 看到 WS 流式输出

### Phase 3: 5 个新功能前后端（第 7-10 天）
- [ ] 网页链接 CRUD + 渲染
- [ ] 目录快捷 CRUD + OpenDir + 跨平台
- [ ] 定时任务 CRUD + 调度器 Start/Stop + 触发写 executions
- [ ] todo.md 解析 + 勾选写回
- [ ] 设置 API（todo path 等）
- **验收**：5 个 widget 在 UI 上完整可用，cron 触发能看到 executions 行

### Phase 4: 跨平台（第 11-12 天）
- [ ] `pty_unix.go` / `pty_windows.go` build tag 隔离
- [ ] Windows 编译通过（`GOOS=windows go build`）
- [ ] macOS/Linux 编译通过
- [ ] OpenDir 三平台测试
- [ ] 调度器跨平台启动测试
- **验收**：三个 OS 上 `go build` 均通过；Windows 启动后 `/api/pty` 返回 503 + UI 隐藏

### Phase 5: 文档与端到端（第 13 天）
- [ ] 重写 DESIGN.md
- [ ] 写 README.md / MIGRATION.md / CLI.md
- [ ] 端到端冒烟：创建链接/目录/todo/定时 → 触发 → 执行 → 写库
- **验收**：开箱即用 `make run`，5 个新功能在 UI 上各跑一遍

---

## 8. 关键风险与缓解

| 风险 | 缓解 |
|---|---|
| 单 Go 重写 v2.4 行为可能与原版偏差 | 写 Go 等价测试对比（v2.4 自带 tests/ 为空，重写为 Go 测试集） |
| Windows 下 `creack/pty` 不可用 | build tag 隔离 + UI 隐藏 PTY Tab + 提示降级 |
| `cbc` 不在 PATH 时定时任务失败 | 启动时 health-check + 在 settings 里提示安装；执行时 exec.LookPath 回落到 codebuddy |
| cron 表达式解析错误导致定时任务不触发 | `robfig/cron` 自带 Parse，返回错误时 DB 标 `last_status='parse_error'` 并 UI 提示 |
| todo.md 写回时崩溃损坏原文件 | 先写 `.bak` 再 atomic rename；写前 stat 比对 size 防止覆盖 |
| skill-factory.db 旧数据丢失 | README 提示备份；不主动删除旧表（v1 schema 保留在 v1 migration 块） |
| WebSocket 跨多 tab 时重复连接 | 暂不处理（个人工具，单 tab 够用） |

---

## 9. 验证方式（端到端）

启动：
```bash
cd /Users/xd/Documents/workspace/repo/ai-playground/skill-factory
go build -o /tmp/skill-factory-v2 ./cmd/server
DB_PATH=./data/all-in-one.db ADDR=:8080 /tmp/skill-factory-v2
# 旧 db 备份
mv data/skill-factory.db data/skill-factory.db.v1.bak
```

冒烟（curl 一遍 5 个新功能）：
```bash
# 1. 网页链接
curl -X POST localhost:8080/api/web-links -d '{"name":"GitHub","url":"https://github.com/xiaodongQ/"}'
curl localhost:8080/api/web-links

# 2. 目录快捷
curl -X POST localhost:8080/api/dir-shortcuts -d '{"name":"Code","path":"~/code"}'
curl -X POST localhost:8080/api/dir-shortcuts/{id}/open   # macOS 弹出 Finder

# 3. 定时任务
curl -X POST localhost:8080/api/scheduled -d '{"name":"ping","cron_expr":"@every 30s","command_type":"shell","prompt":"echo hi"}'
sleep 35
curl localhost:8080/api/executions | jq '.[0]'

# 4. todo
echo "- [ ] 写周报\n- [x] 改 PR" > /tmp/todo.md
curl -X PUT localhost:8080/api/todo/path -d '{"value":"/tmp/todo.md"}'
curl localhost:8080/api/todo | jq

# 5. Windows 兼容（仅编译验证）
GOOS=windows go build -o /tmp/sf.exe ./cmd/server && echo OK
```

UI：浏览器打开 [http://localhost:8080](http://localhost:8080)，验证 12 列 grid 布局 + 5 个 widget + WS 流式输出 + 7 天柱状图。

---

## 10. 不在 v1 范围

- **evaluator（LLM 打分）**：v2.4 现有 evaluator 是 CLI 模式调 `claude --print` 打分；v0.1 暂不做，tasks 直接用 TDD pass_rate 作 acceptance
- **PTY 跨平台 Windows ConPTY 实现**：v0.1 直接 stub，后续可选 `iyzio/conpty`
- **Windows Service 注册（kardianos/service）**：v0.1 进程内 cron 即可，后续可加
- **多用户 / 鉴权**：个人工具，单机本地
- **国际化**：中文为主
