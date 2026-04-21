---
title: AI能力集 -- 开发一个任务自动执行系统
description: 记录开发个人AI领取任务系统的全过程，从v1到v5的演进，包括踩坑和解决方案
categories: [AI, AI能力集]
tags: [AI, Claude Code, 自动化]
---

## 1. 引言

需求场景很简单：个人任务有时有多个，添加到任务池后由AI自动申领后执行，完成后由另一个AI进行评估。整个过程我希望能看到详细记录。

### 1.1 最初想法

两个思路：
* Claude Code的`/loop`功能，定期向指定目录获取任务进行执行
* OpenClaw及类似agent软件（Hermes、PicoClaw等等）

几个Claw系列项目的核心工作流，原理上都是Agent的ReAct循环+工具调用：
* [picoclaw](https://github.com/sipeed/picoclaw)

想法：分析学习项目代码不需要大而全，尤其现在AI生成代码速度远远超过个人能阅读的速度。只要关注自己的核心需求，收缩注意力即可。

### 1.2 开发过程

第一版是在手机上用 happy-coder 远程控制 Claude Code 写的（当时电脑不在身边），后续迭代用了 OpenClaw。

```
第一版(happy-coder + Claude Code) → 后续迭代(OpenClaw)
```

整个过程记录在了截图中，后来逐步演进成 v1-v5 多个版本。

---

## 2. 方案设计

### 2.1 需求拆解

需要实现的功能：
* 任务池：添加/删除待办任务
* AI自动申领：从池子里拿任务执行
* 执行过程追踪：什么时候领取、什么时候执行、耗时多久
* 评估机制：另一个AI来评估执行结果
* 可视化界面：看任务状态和过程记录

### 2.2 技术选型

| 组件     | 选型                    | 原因                                       |
| -------- | ----------------------- | ------------------------------------------ |
| 执行引擎 | Claude Code CLI / claw  | 本地CLI直接执行，支持 `--print` 非交互模式 |
| 评估     | OpenAI API / Claude API | 可配置不同模型评估                         |
| 后端     | FastAPI + SQLite        | 轻量，无需额外服务                         |
| 前端     | HTML + Tailwind         | 单文件，够用就行                           |

### 2.3 核心模块设计

```
┌─────────────────────────────────────────────────────────┐
│                     AI 任务系统                          │
├─────────────────────────────────────────────────────────┤
│  任务队列 (SQLite)                                      │
│    - pending → running → completed → evaluating → evaluated
│    - failed (自动重试)
│                                                         │
│  调度器 (Scheduler)                                     │
│    - 轮询 pending 任务                                  │
│    - 心跳保活 + stale 检测                              │
│    - 自动重试 (指数退避)                                │
│                                                         │
│  执行器 (Executor)                                      │
│    - CLI 模式: 调用 `claw --print`                      │
│    - SDK 模式: CodeBuddy Python SDK                     │
│                                                         │
│  评估器 (Evaluator)                                     │
│    - 自动评估执行结果                                   │
│    - 可配置评估模型                                     │
└─────────────────────────────────────────────────────────┘
```

---

## 3. 版本演进

### 3.1 V1 — 最初的原型

基于 CodeBuddy CLI，实现：
* Web UI 任务管理（添加/删除/查看）
* 自动领取执行
* 交叉评估（不同AI模型交叉评估）
* 迭代闭环（评分低于阈值自动重试）

```bash
cd v1
pip install -r requirements.txt
export PYTHONPATH=$(pwd)
uvicorn backend.main:app --reload --port 8000
```

### 3.2 V2 — Claude Code 集成版

V1 改进版，接入 Claude Code CLI，支持多Agent并行：
* Claude Code CLI 执行引擎
* Web 界面 + API 双接口
* 多 Agent 并行执行
* 任务调度器（60s 轮询间隔）

### 3.3 V3 — CodeBuddy 原生适配版

* 100% 遵循 CodeBuddy CLI 规范
* 单机无容器、零配置一键启动
* WebSocket 实时同步
* 双超时防护（绝对超时 + 无输出超时）
* Git 版本自动提交

### 3.4 V4 — 多 Agent 抽象层（活跃版本）

统一的多 Agent CLI 编排层，支持 Claude Code、OpenAI Codex 和 CodeBuddy：

| 特性       | 说明                                |
| ---------- | ----------------------------------- |
| 三种入口   | CLI / TUI（全屏）/ REPL（交互）     |
| 任务路由   | 13 种任务类型 → 最优 Agent 自动选择 |
| 基准测试   | Agent 能力评分，持续跟踪对比        |
| 会话持久化 | 跨会话恢复，session export/import   |

```bash
# CLI 模式
python -m ai_task_system.v4.cli create "任务" -a claude -y -w

# TUI 全屏
python -m ai_task_system.v4 --tui

# REPL 交互
python -m ai_task_system.v4
```

### 3.5 V5 — 增加特性

V4 的生产级扩展，带持久化队列和进程池：

* **进程池**：预热 Worker，故障自动恢复
* **持久化队列**：SQLite WAL，支持优先级/延迟/死信
* **REST API**：18 个端点，API Key 认证
* **WebSocket**：实时任务状态/输出流推送
* **Prometheus**：`/metrics` 端点，Grafana 就绪

```bash
export AI_TASK_API_KEY="my-secret-key"  # 可选
python -m v5.api.app --port 18792
```

---

## 4. 核心实现

### 4.1 任务状态机

```
pending → waiting(依赖) → running → completed → evaluating → evaluated
                    ↘ failed (auto-retry → pending)
                    ↘ stale (heartbeat 超时 → pending)
```

### 4.2 调度器核心逻辑

```python
# scheduler.py 核心循环
while running:
    tasks = db.get_pending_tasks()
    for task in tasks:
        if task.is_runnable():
            executor.execute(task)

    # 心跳保活
    update_heartbeat()

    # Stale 检测
    recover_stale_tasks()

    sleep(poll_interval)
```

### 4.3 执行器封装

```python
# cli_executor.py
def execute(self, task):
    cmd = [
        "claw", "--print", "--verbose",
        "--model", task.model,
        task.description
    ]
    result = subprocess.run(cmd, capture_output=True, text=True)
    return result
```

---

## 5. 效果展示

### 5.1 任务执行界面

![任务执行中](/images/ai-task-system-task-execution.png)

图中显示了一个"分析任务"弹窗：
* 状态：执行中
* 执行引擎：minimax-2.7
* 评估方式：CLI默认
* 迭代进度：0/3

### 5.2 任务详情+评估

![任务详情+评估](/images/ai-task-system-task-detail-eval.png)

可以看到：
* 命令详情：`claude --print --verbose --model claude "任务描述 18"`
* 模型、开始/完成时间
* 输出内容：AI 返回了询问具体含义
* 评估历史：评分 7/10

### 5.3 手机端远程控制

这是用 happy-coder 在手机上远程控制 Claude Code 开发的截图：

![手机端开发](/images/ai-task-system-mobile-dev.png)

当时在出差路上，用手机操作完成了第一版开发。可以看到：
* 待办列表自动流转
* Task 1-6 已完成（绿色勾选）
* Task 7 正在执行（蓝色选中）
* 底部显示 AI 状态（germinating...）

---

## 6. 配置说明

### 6.1 config.yaml

```yaml
scheduler:
  poll_interval: 5
  heartbeat_interval: 30
  stale_threshold: 120

executor:
  engine: cli                 # cli | sdk
  cli_path: claw
  timeout: 1800
  max_auto_retries: 3
  auto_retry_delay: 180

evaluator:
  model: "claude-opus-4-6"
  default_model: gpt-4o

server:
  host: 0.0.0.0
  port: 8000
```

### 6.2 数据目录

| 内容        | 路径                                      |
| ----------- | ----------------------------------------- |
| 会话存储    | `~/.ai_task_system/sessions.json`         |
| 基准分数    | `~/.ai_task_system/benchmark_scores.json` |
| 任务队列 DB | `~/.ai_task_system/tasks.db`              |

---

## 7. 总结

这个系统从最初的简单想法，演进成了 v1-v5 多个版本。核心收获：

1. **轻量优先**：不追求大而全，关注自己的核心需求
2. **快速迭代**：从原型到生产，版本逐步演进
3. **工具组合**：Claude Code + happy-coder + OpenClaw，各取所长
4. **自动化闭环**：任务领取→执行→评估→迭代，全自动流转

代码已开源：[ai-task-system](https://github.com/xiaodongQ/ai-playground/tree/main/ai-task-system)

---

## 附录：版本演进路径

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
