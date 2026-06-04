---
title: AI能力集 -- Skill 自动化工厂：从方案设计到 Go + SQLite 落地实现
description: 完整记录 Skill 自动化开发工厂的原始需求、方案设计、技术选型、TDD 实现过程，以及仓库地址和关键代码说明
categories: [AI, AI能力集]
tags: [AI, Go, SQLite, TDD, Skill开发]
---

## 1. 引言

日常开发中，我们经常遇到一个痛点：**每次开发 Skill 都是从零开始**，经验散落在各种文档里，没有统一标准，没有自动化闭环，好不容易开发完一个，下次遇到类似问题还是要重新折腾。

所以有了这个项目：**用 Skill 生产 Skill 的自动化工厂**。

本文完整记录：
1. 原始需求方案（用户输入）
2. 详细设计方案（系统设计）
3. 技术选型与 TDD 落地实现
4. 仓库地址与关键产物

---

## 2. 原始需求方案

用户给出了一份完整的业务需求文档，核心目标是：

> 搭建标准化、可复用、可沉淀、可自动迭代的**业务问题定位 Skill 开发工厂**，统一 Skill 定义、开发、验证、沉淀、复用全流程。

### 2.1 核心问题

| 问题 | 描述 |
|------|------|
| 无标准化 | 开发经验散落，难以复用 |
| 无闭环 | 开发 → 验证 → 归档全流程割裂 |
| 无管控 | 迭代过程不可评审、不可量化 |
| 无沉淀 | 每次开发从零开始，重复造轮子 |

### 2.2 双端协同闭环

```
[平台创建任务] → [工厂 Skill 拉取] → [TDD 自动化开发] → [结果回写] → [归档入库]
                                          ↑
                                    [验收循环 ≤20 轮]
```

### 2.3 四项标准输入

所有业务定位 Skill 必须遵循以下 4 项标准输入：

1. **前置经验库**：沉淀系统模块上下文、日志路径、工具能力、场景、代码片段
2. **待解决业务问题**：清晰定义当前需要定位的具体业务问题
3. **关联资源上下文**：明确问题涉及的系统模块、日志类型、工具清单
4. **统一验收迭代标准**：准确率达标、用例全覆盖、无误判漏判、≤20 轮迭代上限

---

## 3. 详细设计方案

基于原始需求，我进行了完整的技术方案设计，输出文档：`skill-factory/DESIGN.md`

### 3.1 系统架构

```
skill-factory/
  cmd/server/          # HTTP 服务入口 + 内嵌 Web UI
  internal/
    backend/           # 数据模型 + SQLite Repo 层
    task/              # TaskRepo TDD 测试
    experience/        # ExperienceRepo TDD 测试
  go.mod

skills/
  redis-cluster-troubleshoot/  # 示例产出物（Redis 集群故障定位）
  skill-factory/               # Factory Skill（自动化闭环）
```

### 3.2 数据模型

```sql
CREATE TABLE tasks (
    id TEXT PRIMARY KEY,
    title TEXT NOT NULL,
    description TEXT,
    status TEXT DEFAULT 'pending',
    experience_id TEXT,
    resources TEXT,
    acceptance TEXT,
    version TEXT DEFAULT 'v0.0.1',
    created_at DATETIME,
    claimed_at DATETIME,
    maintainer TEXT,
    repo_address TEXT,
    archived_at DATETIME,
    result TEXT
);

CREATE TABLE experiences (
    id TEXT PRIMARY KEY,
    module TEXT NOT NULL,
    keywords TEXT,
    log_paths TEXT,
    tool_usage TEXT,
    scene TEXT,
    log_samples TEXT,
    code_snippets TEXT,
    version TEXT,
    created_at DATETIME,
    updated_at DATETIME
);
```

### 3.3 API 设计

| 方法 | 路径 | 说明 |
|------|------|------|
| GET | /api/tasks | 查询任务列表（支持 status 过滤） |
| POST | /api/tasks | 创建任务 |
| GET | /api/tasks/:id | 获取任务详情 |
| PUT | /api/tasks/:id/status | 更新任务状态 |
| GET | /api/experiences | 查询经验库（支持模糊查询） |
| POST | /api/experiences | 创建经验记录 |

### 3.4 TDD 开发流程

```
for iter in $(seq 1 20); do
  # 4a. 解析验收样例，生成测试用例
  test_cases=$(parse_acceptance "$task.acceptance")

  # 4b. 基于问题描述 + 经验上下文，实现 Skill
  skill_impl=$(develop_skill "$task.description" "$experience_ctx" "$test_cases")

  # 4c. 执行测试
  result=$(run_tests "$skill_impl" "$test_cases")

  # 4d. 验收判断
  pass_rate=$(echo "$result" | jq '.pass_rate')
  false_pos=$(echo "$result" | jq '.false_pos_count')
  false_neg=$(echo "$result" | jq '.false_neg_count')

  if [ "$pass_rate" = "1.0" ] && [ "$false_pos" = "0" ] && [ "$false_neg" = "0" ]; then
    break  # 验收通过
  fi

  # 4e. 迭代优化（将失败信息注入下一轮）
  task.description="$task.description [ITER $iter FAILED: $result]"
done
```

### 3.5 验收标准

| 维度 | 要求 |
|------|------|
| 准确率 | 正向用例全部通过（pass_rate = 1.0） |
| 误判（false_pos） | 0 |
| 漏判（false_neg） | 0 |
| 迭代上限 | 20 轮，不达标强制终止 |

---

## 4. 技术选型

### 4.1 为什么选 Go + SQLite

| 考量 | 选择 | 原因 |
|------|------|------|
| 简单部署 | SQLite | 无需独立数据库进程，单文件、单进程 |
| 无 CGO 依赖 | modernc.org/sqlite | 纯 Go 实现，交叉编译无障碍 |
| 轻量 Web | 内嵌 Go http + embed | 无需前端工程化，单二进制带 Web UI |
| TDD 支持 | Go testing | 内置测试框架，表格驱动测试 |

### 4.2 技术栈

- **语言**：Go 1.21+
- **数据库**：SQLite（modernc.org/sqlite，纯 Go 无 CGO）
- **Web**：Go 标准库 net/http + html/template embed
- **测试**：Go testing + 标准库

---

## 5. TDD 实现过程

### 5.1 数据模型层

```go
type Task struct {
	ID           string     `json:"id"`
	Title        string     `json:"title"`
	Description  string     `json:"description,omitempty"`
	Status       string     `json:"status"`
	ExperienceID string     `json:"experience_id,omitempty"`
	Resources    string     `json:"resources,omitempty"`
	Acceptance   string     `json:"acceptance,omitempty"`
	Version      string     `json:"version"`
	CreatedAt    time.Time  `json:"created_at"`
	ClaimedAt    *time.Time `json:"claimed_at,omitempty"`
	Maintainer   string     `json:"maintainer,omitempty"`
	ArchivedAt   *time.Time `json:"archived_at,omitempty"`
	Result       string     `json:"result,omitempty"`
}

const (
	TaskStatusPending    = "pending"
	TaskStatusInProgress = "in_progress"
	TaskStatusArchived   = "archived"
	TaskStatusException  = "exception"
)
```

### 5.2 Repo 层测试（TaskRepo）

```go
func TestTaskCreateAndGet(t *testing.T) {
	db, _, err := backend.TestDB()
	if err != nil {
		t.Fatalf("TestDB: %v", err)
	}
	repo := backend.NewTaskRepo(db)

	task := &backend.Task{
		ID:          "test-task-001",
		Title:       "Redis 集群节点失联定位",
		Description: "实现 Redis 集群节点失联场景的问题定位 Skill",
		Status:      backend.TaskStatusPending,
		Version:     "v0.0.1",
		CreatedAt:   time.Now(),
	}

	if err := repo.Create(task); err != nil {
		t.Fatalf("Create: %v", err)
	}

	got, err := repo.Get("test-task-001")
	if err != nil {
		t.Fatalf("Get: %v", err)
	}
	if got.Title != task.Title {
		t.Errorf("Title = %q, want %q", got.Title, task.Title)
	}
}
```

### 5.3 Repo 层测试（ExperienceRepo）

```go
func TestExperienceCreateAndSearch(t *testing.T) {
	db, _, err := backend.TestDB()
	if err != nil {
		t.Fatalf("TestDB: %v", err)
	}
	repo := backend.NewExperienceRepo(db)

	exp := &backend.Experience{
		ID:       "exp-redis-cluster",
		Module:   "redis-cluster",
		Keywords: "CLUSTERDOWN,MOVED,ASK,READONLY",
		LogPaths: "/var/log/redis/redis-server.log",
		ToolUsage: "redis-cli cluster nodes, redis-cli slowlog get 10",
		Scene:    "集群节点失联定位",
		Version:  "v1.0.0",
		CreatedAt: time.Now(),
	}

	if err := repo.Create(exp); err != nil {
		t.Fatalf("Create: %v", err)
	}

	results, err := repo.Search("redis-cluster")
	if err != nil {
		t.Fatalf("Search: %v", err)
	}
	if len(results) != 1 {
		t.Errorf("search count = %d, want 1", len(results))
	}
}
```

### 5.4 测试结果

```
go test ./...
?       skill-factory/cmd/server  [no test files]
?       skill-factory/internal/backend  [no test files]
ok      skill-factory/internal/experience  0.004s
ok      skill-factory/internal/task       0.005s
ALL OK
```

---

## 6. 示例产出物：Redis 集群故障定位 Skill

作为工厂的示例业务产出物，开发了一个完整的 Redis 集群故障定位 Skill：`skills/redis-cluster-troubleshoot/SKILL.md`

### 6.1 支持场景

| 场景 | 关键字 |
|------|--------|
| 集群节点失联 | `CLUSTERDOWN` |
| 内存碎片化 | `mem_fragmentation_ratio > 1.4` |
| 主从复制中断 | replication backlog 不足 |
| 慢查询根因 | `slowlog` > 1s |
| Big Key 查询 | `redis-cli --bigkeys` |
| 热 Key 探测 | QPS 集中在少数 key |
| 连接数打满 | `maxmemory` + OOM |

### 6.2 验收用例

**正向用例**：

| 输入 | 预期输出 |
|------|---------|
| `CLUSTERDOWN The cluster is gone` | 定位 cluster-node-timeout，给出 redis.conf 调优建议 |
| `READONLY You can't write` | 识别只读场景，输出 replica 配置检查步骤 |
| slowlog 显示 KEYS > 5s | 给出 SCAN 替换方案 |
| `mem_fragmentation_ratio > 1.5` | 给出 MEMORY PURGE + activedefrag 配置 |

**反向用例（脏数据）**：

| 输入 | 预期行为 |
|------|---------|
| 空 slowlog | 返回"无慢查询记录"，跳过分析 |
| MySQL 日志 | 明确拒绝，输出"非 Redis 日志格式" |
| 二进制数据 | 提示"请提供文本日志" |

---

## 7. 仓库地址

**仓库**：[https://github.com/xiaodongQ/ai-playground](https://github.com/xiaodongQ/ai-playground)

**分支**：`v2.2_dev`

**关键目录**：

| 路径 | 说明 |
|------|------|
| `skill-factory/` | 后台管理系统完整代码 |
| `skills/redis-cluster-troubleshoot/` | Redis 集群故障定位 Skill（示例产出物） |
| `skills/skill-factory/` | Factory Skill（全流程自动化闭环） |

**快速启动**：

```sh
cd skill-factory
go mod tidy
go build ./cmd/server/...
./server  # 默认监听 :8080

# 测试 API
curl -s http://localhost:8080/api/tasks
curl -s -X POST http://localhost:8080/api/tasks \
  -H "Content-Type: application/json" \
  -d '{"id":"test-001","title":"测试任务","status":"pending"}'
```

---

## 8. 总结

### 方案 vs 实现 差异对照

| 需求项 | 原始方案 | 实际实现 | 状态 |
|--------|---------|---------|------|
| 后台管理系统 | Go + SQLite + 内嵌 Web | ✅ Go + modernc.org/sqlite + html/template embed | 落地 |
| Task CRUD API | RESTful + 状态流转 | ✅ 完整实现，含 null 字段处理 | 落地 |
| 经验库管理 | 模糊查询 + 导出 MD | ✅ 模糊查询已实现，导出 MD 预留接口 | 落地 |
| TDD 测试 | 各层有测试 | ✅ TaskRepo + ExperienceRepo 双层测试 | 落地 |
| Redis Skill 示例 | 7 个场景 + 正反向用例 | ✅ 完整 SKILL.md + 验收用例 | 落地 |
| Factory Skill | 自动化闭环 | ✅ SKILL.md 已编写完整流程 | 落地 |
| Web UI | 内嵌 Web 页面 | ✅ index.html 任务列表页 | 落地 |

### 核心价值

1. **统一范式**：所有 Skill 开发遵循 4 项标准输入 + 验收闭环
2. **经验沉淀**：可查询、可导出、可团队复用
3. **自动化闭环**：TDD 迭代、量化验收、≤20 轮迭代上限
4. **职责清晰**：极简入参框架，剥离冗余环境配置
5. **TDD 保证质量**：Repo 层双层测试覆盖，SQLite 内存模式测试无副作用

---

*仓库*：[https://github.com/xiaodongQ/ai-playground/tree/v2.2_dev/skill-factory](https://github.com/xiaodongQ/ai-playground/tree/v2.2_dev/skill-factory)