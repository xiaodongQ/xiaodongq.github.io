---
title: AI能力集 -- 折腾了一个 Skill 工厂出来,顺便把 TDD 走通了
description: 把"用 Skill 产 Skill"这个折腾过程完整记下来,从最初的需求拆解、方案设计,到 Go + SQLite 的 TDD 落地,中间踩了哪些坑、为啥选这个技术栈,都写在里面
categories: [AI, AI能力集]
tags: [AI, Go, SQLite, TDD, Skill开发]
---

## 1. 引言

这阵子一直在搞 Skill,搞着搞着发现一个问题:**每开发一个 Skill 都是从零开始**。经验散落在各种文档、对话记录里,没有统一标准,好不容易搞完一个,下次遇到类似问题还是得重新折腾一遍。

我寻思着,与其每次都重新踩坑,不如干脆搞个**自动化工厂**出来 —— 用 Skill 生产 Skill,把开发、验证、沉淀、复用这条链路彻底打通。

这个项目折腾了有一阵子,中间砍过方案、换过技术栈,最后是用 Go + SQLite + TDD 落地的。这文章就把完整的折腾过程、为什么这么选、中间踩了啥坑,都摆出来,免得后来人重复趟雷。

相关链接:
* [仓库](https://github.com/xiaodongQ/ai-playground/tree/v2.2_dev/skill-factory)
* [Redis 集群故障定位 Skill(示例产出物)](https://github.com/xiaodongQ/ai-playground/tree/v2.2_dev/skills/redis-cluster-troubleshoot)

---

## 2. 我最早想要啥

最早的需求其实是从我自己踩过的坑里长出来的。每次接到"做个新的定位 Skill"的需求,都得重复这些事:

- 找历史经验:这个系统模块之前出过啥问题、有啥日志路径、哪些工具能查
- 写 Skill 描述:基于经验,描述清楚要解决的问题
- 开发实现:写代码、写文档
- 验收:跑测试、看漏判误判
- 归档:用完的脚本扔一边,下次想找都找不到

这一套跑下来,**重复劳动占了 60% 以上**。我想的是把这些事**标准化**,让 Agent 能按一个统一范式自动跑下去。

所以核心目标就一句话:**搭建标准化、可复用、可沉淀、可自动迭代的业务问题定位 Skill 开发工厂**。

四项标准输入,也是我后来从实践里倒推出来的:

1. **前置经验库**:沉淀系统模块上下文、日志路径、工具能力、场景、代码片段
2. **待解决业务问题**:清晰定义当前要定位的具体业务问题
3. **关联资源上下文**:明确问题涉及的系统模块、日志类型、工具清单
4. **统一验收迭代标准**:准确率达标、用例全覆盖、无误判漏判、≤20 轮迭代上限

这四项缺一不可,少了哪一项,后面 TDD 跑起来都会出问题。

---

## 3. 设计上的核心想法

### 3.1. 整体架构

折腾到最后,发现最清爽的结构就两层:**一个后台管理 + 一个 Factory Skill**。

```text
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

- 后台管理主要管两类东西:**任务(Task)** 和 **经验(Experience)**
- Factory Skill 负责拉任务、调用 TDD 流程、结果回写
- Web UI 内嵌到 Go 二进制里,单文件就能跑,部署零依赖

### 3.2. 数据模型

数据库我用的是 SQLite(纯 Go 实现,无 CGO,后面会讲为啥这么选)。两张表就够了:

```sql
-- 任务表:每个待开发的 Skill 是一行
CREATE TABLE tasks (
    id TEXT PRIMARY KEY,
    title TEXT NOT NULL,
    description TEXT,
    status TEXT DEFAULT 'pending',     -- pending / in_progress / archived / exception
    experience_id TEXT,                -- 关联到经验库
    resources TEXT,                    -- 关联资源上下文
    acceptance TEXT,                   -- 验收标准
    version TEXT DEFAULT 'v0.0.1',
    created_at DATETIME,
    claimed_at DATETIME,
    maintainer TEXT,
    repo_address TEXT,
    archived_at DATETIME,
    result TEXT                        -- 最终产物地址
);

-- 经验表:沉淀的系统模块上下文
CREATE TABLE experiences (
    id TEXT PRIMARY KEY,
    module TEXT NOT NULL,              -- 哪个系统模块
    keywords TEXT,                     -- 关键字/错误码
    log_paths TEXT,                    -- 日志路径
    tool_usage TEXT,                   -- 排查工具
    scene TEXT,                        -- 适用场景
    log_samples TEXT,                  -- 日志样例
    code_snippets TEXT,                -- 代码片段
    version TEXT,
    created_at DATETIME,
    updated_at DATETIME
);
```

一开始我想用 PostgreSQL 或者 MySQL,后来发现这事**单兵作战完全用不上**,SQLite 反而合适 —— 单文件、零部署,跟整个项目的"轻量"定位一致。

### 3.3. API 设计

API 走标准 RESTful,接口精简到最少:

| 方法 | 路径 | 说明 |
|------|------|------|
| GET | `/api/tasks` | 查任务列表,支持 status 过滤 |
| POST | `/api/tasks` | 创建任务 |
| GET | `/api/tasks/:id` | 拿任务详情 |
| PUT | `/api/tasks/:id/status` | 改状态 |
| GET | `/api/experiences` | 查经验库,支持模糊搜 |
| POST | `/api/experiences` | 录入新经验 |

没有复杂的多用户、权限、审计之类的东西 —— 那些是后面再说的事,先把核心闭环跑通。

### 3.4. TDD 循环

整个 TDD 流程,核心就是一个 shell 脚本级别的循环:

```sh
for iter in $(seq 1 20); do
  # 4a. 解析验收样例,生成测试用例
  test_cases=$(parse_acceptance "$task.acceptance")

  # 4b. 基于问题描述 + 经验上下文,实现 Skill
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

  # 4e. 迭代优化(把失败信息注入下一轮)
  task.description="$task.description [ITER $iter FAILED: $result]"
done
```

20 轮上限是**经验值**,再多就是无底洞了。**false_pos(误判)和 false_neg(漏判)都必须为 0**,这个是硬指标,不能"大部分通过就行"。

---

## 4. 为啥选 Go + SQLite

这一节单独写一下选型,因为中间我犹豫过好几次。

| 考量维度 | 最终选择 | 真实原因 |
|----------|----------|----------|
| 部署简单 | SQLite | 没有独立 DB 进程,单文件,跟整个项目"轻量"定位一致 |
| 交叉编译 | modernc.org/sqlite | **这才是选 Go 的关键** —— 纯 Go 驱动,无 CGO,Linux/Mac/Windows 都能编译 |
| Web 层 | 标准库 net/http + embed | 用不上 Gin/Echo 那种,内嵌 HTML 模板够用,少一个依赖 |
| 测试 | Go testing | 内置,表格驱动测试写起来很顺 |

最关键的是 **modernc.org/sqlite 这个库**。普通的 `mattn/go-sqlite3` 是 CGO 实现的,意味着你交叉编译的时候得在目标机器上装 C 编译器 —— 这事对我来说完全不可接受。modernc 这个库是**纯 Go 翻译的 SQLite**,代价是包大一点、性能差一点,但能换来"一处编译,到处运行",这个 trade-off 我愿意付。

---

## 5. 落地实现的关键代码

这块不打算把所有代码贴出来(完整版在仓库里),只挑几个我觉得有代表性的。

### 5.1. 数据结构定义

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

`time.Time` 用指针是踩过坑的:零值时间在 JSON 里会序列化成 `"0001-01-01T00:00:00Z"`,前端拿到一脸懵。用指针 + `omitempty` 才干净。

### 5.2. TaskRepo 测试

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

测试用的是 **SQLite 内存模式**(`:memory:`),跑完一个测试 case 就销毁,**完全无副作用**。这才是单元测试该有的样子 —— 不要为了测个 CRUD 去搞个 test DB 起来。

### 5.3. ExperienceRepo 测试

```go
func TestExperienceCreateAndSearch(t *testing.T) {
    db, _, err := backend.TestDB()
    if err != nil {
        t.Fatalf("TestDB: %v", err)
    }
    repo := backend.NewExperienceRepo(db)

    exp := &backend.Experience{
        ID:        "exp-redis-cluster",
        Module:    "redis-cluster",
        Keywords:  "CLUSTERDOWN,MOVED,ASK,READONLY",
        LogPaths:  "/var/log/redis/redis-server.log",
        ToolUsage: "redis-cli cluster nodes, redis-cli slowlog get 10",
        Scene:     "集群节点失联定位",
        Version:   "v1.0.0",
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

模糊搜索用的是 SQLite 原生的 `LIKE`,没引第三方搜索引擎 —— 这种小规模数据量(经验库也就几百条),LIKE 完全够用,**别过度工程化**。

### 5.4. 最终测试结果

```text
$ go test ./...
?       skill-factory/cmd/server  [no test files]
?       skill-factory/internal/backend  [no test files]
ok      skill-factory/internal/experience  0.004s
ok      skill-factory/internal/task       0.005s
ALL OK
```

干净利落,4 个测试文件全绿。

---

## 6. 示例产出物:Redis 集群故障定位 Skill

光有工厂本身没说服力,我顺手用这个工厂产出了一个真实业务 Skill —— Redis 集群故障定位。

### 6.1. 它能覆盖啥

7 个核心场景,都是线上真出过问题的:

| 场景 | 关键字/触发 |
|------|-------------|
| 集群节点失联 | `CLUSTERDOWN` |
| 内存碎片化 | `mem_fragmentation_ratio > 1.4` |
| 主从复制中断 | replication backlog 不足 |
| 慢查询根因 | `slowlog` > 1s |
| Big Key 查询 | `redis-cli --bigkeys` |
| 热 Key 探测 | QPS 集中在少数 key |
| 连接数打满 | `maxmemory` + OOM |

### 6.2. 验收用例

**正向用例**(必须识别正确):

| 输入 | 预期输出 |
|------|---------|
| `CLUSTERDOWN The cluster is gone` | 定位到 `cluster-node-timeout`,给 `redis.conf` 调优建议 |
| `READONLY You can't write` | 识别只读场景,输出 replica 配置检查步骤 |
| slowlog 显示 KEYS > 5s | 给出 SCAN 替换方案 |
| `mem_fragmentation_ratio > 1.5` | 给出 MEMORY PURGE + activedefrag 配置 |

**反向用例(脏数据)**(必须明确拒绝):

| 输入 | 预期行为 |
|------|---------|
| 空 slowlog | 返回"无慢查询记录",跳过分析 |
| MySQL 日志 | 明确拒绝,输出"非 Redis 日志格式" |
| 二进制数据 | 提示"请提供文本日志" |

反向用例这块我特意强化过 —— **最容易出事故的就是把 MySQL 日志当 Redis 解析**,所以"非 Redis 日志格式"这种识别必须稳。

---

## 7. 仓库地址

仓库在 [xiaodongQ/ai-playground](https://github.com/xiaodongQ/ai-playground),分支 `v2.2_dev`。

关键目录:

| 路径 | 说明 |
|------|------|
| `skill-factory/` | 后台管理系统完整代码 |
| `skills/redis-cluster-troubleshoot/` | Redis 集群故障定位 Skill(示例产出物) |
| `skills/skill-factory/` | Factory Skill(全流程自动化闭环) |

快速启动:

```sh
cd skill-factory
go mod tidy
go build ./cmd/server/...
./server  # 默认监听 :8080

# 测试 API
curl -s http://localhost:8080/api/tasks
curl -s -X POST http://localhost:8080/api/tasks \
  -H "Content: application/json" \
  -d '{"id":"test-001","title":"测试任务","status":"pending"}'
```

一行 `go mod tidy` + 一个二进制,完事。

---

## 8. 总结

这阵子折腾下来,最大的收获不是 Go 怎么写、SQLite 怎么连、TDD 怎么跑 —— 这些网上一搜一大把。

真正的收获是:**当你能把"开发一个 Skill"这件事本身标准化、自动化、闭环化,它就从"手艺活"变成了"流水线活"**。每个新 Skill 都不再是从零开始,而是基于历史经验 + 统一范式 + 量化验收来产出。

如果硬要总结出几条能"兜得住"的:

1. **经验库必须先于 Skill 沉淀**,否则你产出的 Skill 都是空中楼阁
2. **20 轮迭代上限不是教条**,是止损线 —— 真跑不通就回头看需求定义
3. **误判漏判都是 0,不能打折扣**,这是定位类 Skill 的命根子
4. **技术选型上,无 CGO 优先**,部署体验比性能重要 100 倍

下一步打算把经验库做"导出为 Markdown"的能力,这样老的 wiki 知识可以**反向灌进**这个工厂。**每多一个源,这个工厂就更值一点** —— 这就是飞轮吧。

---

*仓库*:[https://github.com/xiaodongQ/ai-playground/tree/v2.2_dev/skill-factory](https://github.com/xiaodongQ/ai-playground/tree/v2.2_dev/skill-factory)
