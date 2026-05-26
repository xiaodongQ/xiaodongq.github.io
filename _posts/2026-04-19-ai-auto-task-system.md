---
title: AI能力集 -- 开发一个任务自动执行系统
description: 记录开发个人AI领取任务系统的全过程，从v1到v5的演进，包括踩坑和解决方案
categories: [AI, AI能力集]
tags: [AI, Claude Code, 自动化]
---

## 1. 引言

需求场景很简单：个人任务有时有多个，添加到任务池后由AI自动申领后执行，完成后由另一个AI进行评估。整个过程我希望能看到详细记录。

### 1.1. 最初想法

两个思路：
* Claude Code的`/loop`功能，定期向指定目录获取任务进行执行
* OpenClaw及类似agent软件（Hermes、PicoClaw等等）

几个Claw系列项目的核心工作流，原理上都是Agent的ReAct循环+工具调用：
* [picoclaw](https://github.com/sipeed/picoclaw)

想法：分析学习项目代码不需要大而全，尤其现在AI生成代码速度远远超过个人能阅读的速度。只要关注自己的核心需求，收缩注意力即可。

### 1.2. 开发过程

第一版是在手机上用 happy-coder 远程控制 Claude Code 写的（当时电脑不在身边），后续迭代用了 OpenClaw。

```
第一版(happy-coder + Claude Code) → 后续迭代(OpenClaw)
```

整个过程记录在了截图中，后来逐步演进成 v1-v5 多个版本。

---

## 2. 方案设计

### 2.1. 需求拆解

需要实现的功能：
* 任务池：添加/删除待办任务
* AI自动申领：从池子里拿任务执行
* 执行过程追踪：什么时候领取、什么时候执行、耗时多久
* 评估机制：另一个AI来评估执行结果
* 可视化界面：看任务状态和过程记录

### 2.2. 技术选型

| 组件     | 选型                    | 原因                                       |
| -------- | ----------------------- | ------------------------------------------ |
| 执行引擎 | Claude Code CLI / claw  | 本地CLI直接执行，支持 `--print` 非交互模式 |
| 评估     | OpenAI API / Claude API | 可配置不同模型评估                         |
| 后端     | FastAPI + SQLite        | 轻量，无需额外服务                         |
| 前端     | HTML + Tailwind         | 单文件，够用就行                           |

### 2.3. 核心模块设计

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

### 3.1. V1 — 最初的原型

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

### 3.2. V2 — Claude Code 集成版

V1 改进版，接入 Claude Code CLI，支持多Agent并行：
* Claude Code CLI 执行引擎
* Web 界面 + API 双接口
* 多 Agent 并行执行
* 任务调度器（60s 轮询间隔）

### 3.3. V3 — CodeBuddy 原生适配版

* 100% 遵循 CodeBuddy CLI 规范
* 单机无容器、零配置一键启动
* WebSocket 实时同步
* 双超时防护（绝对超时 + 无输出超时）
* Git 版本自动提交

### 3.4. V4 — 多 Agent 抽象层（活跃版本）

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

### 3.5. V5 — 增加特性

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

### 4.1. 任务状态机

```
pending → waiting(依赖) → running → completed → evaluating → evaluated
                    ↘ failed (auto-retry → pending)
                    ↘ stale (heartbeat 超时 → pending)
```

### 4.2. 调度器核心逻辑

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

### 4.3. 执行器封装

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

### 5.1. 任务执行界面

![任务执行中](/images/ai-task-system-task-execution.png)

图中显示了一个"分析任务"弹窗：
* 状态：执行中
* 执行引擎：minimax-2.7
* 评估方式：CLI默认
* 迭代进度：0/3

### 5.2. 任务详情+评估

![任务详情+评估](/images/ai-task-system-task-detail-eval.png)

可以看到：
* 命令详情：`claude --print --verbose --model claude "任务描述 18"`
* 模型、开始/完成时间
* 输出内容：AI 返回了询问具体含义
* 评估历史：评分 7/10

### 5.3. 手机端远程控制

这是用 happy-coder 在手机上远程控制 Claude Code 开发的截图：

![手机端开发](/images/ai-task-system-mobile-dev.png)

当时在出差路上，用手机操作完成了第一版开发。可以看到：
* 待办列表自动流转
* Task 1-6 已完成（绿色勾选）
* Task 7 正在执行（蓝色选中）
* 底部显示 AI 状态（germinating...）

---

## 6. 配置说明

### 6.1. config.yaml

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

### 6.2. 数据目录

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

代码：[ai-task-system](https://github.com/xiaodongQ/ai-playground/tree/main/ai-task-system)

---

## 8. 附录：版本演进路径

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

## 9. 开源AI智能体编排系统：Multica

### 9.1. 基本介绍

> [multica-ai/multica](https://github.com/multica-ai/multica/blob/main/README.zh-CN.md)

Multica 是一个托管式 Agent 平台，它聚焦于将 AI 编程智能体变成你团队中真正的“队友”。它的目标是解决 AI 编程中任务分配、执行追踪和经验沉淀的问题。Multica 管理完整的 Agent 生命周期：从任务分配到执行监控再到技能复用。
- 定位：**AI 项目管理平台**（Task Management）
- 粒度：项目 / 任务 / Agent / 技能
- 重点：**编程 Agent 协作、任务生命周期、技能复用**
- 场景：软件开发、工程任务、AI 辅助研发

对比 [Paperclipai/paperclip](https://github.com/paperclipai/paperclip)，paperclip的定位是一个 AI 员工编排平台，其核心理念是帮助你建立一个由 AI 组成的“零人力公司”（zero-human company）。在这个系统中，你扮演“董事会”的角色，负责设定公司的顶层目标和战略，而具体的执行则交给 AI 员工团队。
- 定位：**AI 公司操作系统**（Orchestration）
- 粒度：公司 / 部门 / 角色 / 预算 / 治理
- 重点：**目标驱动、组织化、成本可控、全链路自治**
- 场景：跑产品、创业公司、全流程业务

默认情况下安装后，需要连接云端。也支持**自部署(`self-host`)**，即在本地安装服务端。下面只操作自部署模式，云端模式见原始链接。

### 9.2. 在线安装

1、使用`--with-server`参数，即可同时安装server服务（基于容器），不加则只安装`CLI`。

```sh
[root@xdlinux ➜ ~ ]$ curl -fsSL https://raw.githubusercontent.com/multica-ai/multica/main/scripts/install.sh | bash -s -- --with-server

  Multica — Self-Host Installer
  Provisioning server infrastructure + installing CLI

✓ Docker is available
==> Setting up Multica server...
==> Using self-host assets from v0.2.28...
==> Cloning Multica repository...
Cloning into '/root/.multica/server'...
remote: Enumerating objects: 1747, done.
remote: Counting objects: 100% (1747/1747), done.
remote: Compressing objects: 100% (1600/1600), done.
Receiving objects:  21% (370/1747), 7.04 MiB | 65.00 KiB/s
...
```

2、`multica setup self-host`

### 9.3. 离线安装（手动编译）

网络有点慢，直接GitHub上下载zip包，进行本地构建。

参考：[self-host-quickstart](https://multica.ai/docs/zh/self-host-quickstart)

#### 9.3.1. 编译本地产物

```sh
git clone https://github.com/multica-ai/multica.git
cd multica

# make selfhost会从 GitHub Container Registry 拉取官方预编译的 backend + web 镜像并启动。
# 会进行：
  # 如果没有 .env 文件，从 .env.example 自动生成一份并生成随机 JWT_SECRET
  # 拉取官方 Docker 镜像（PostgreSQL、Multica backend、Multica frontend）
  # 用 docker-compose.selfhost.yml 启动全部服务
  # 等后端 /health 端点准备就绪
make selfhost
# 网络原因，拉取镜像会比较慢
#  ✔ Image pgvector/pgvector:pg17                            Pulled                                        1002.6s
#  ✔ Image ghcr.io/multica-ai/multica-backend:latest         Pulled                                         386.5s
#  ⠹ Image ghcr.io/multica-ai/multica-web:latest [⣿⣿⣿⣿⣄⣿⣿⣿⣿] 63.96MB / 93.11MB Pulling                    1353.3s
```

```sh
# make selfhost-build 会从当前代码构建（推荐开发/自托管）
  # 这会：
  # 1. 从当前 checkout 构建 server/ Go 代码
  # 2. 构建 Next.js 前端
  # 3. 通过 Docker Compose 启动完整栈（PostgreSQL + backend + web）
# make selfhost-build 实际执行的是：
  # docker compose -f docker-compose.selfhost.yml -f docker-compose.selfhost.build.yml up -d --build
  # 前者 docker-compose.selfhost.yml 定义 postgres + backend + frontend 三个服务
  # 后者 docker-compose.selfhost.build.yml 覆盖 backend 和 frontend 的 image 字段，改指向本地 multica-backend:dev 和 multica-web:dev，并用本地 Dockerfile / Dockerfile.web build
```

#### 9.3.2. 运行安装脚本

```sh
 install.sh --offline --with-server 的实际行为

  关键：它不会 build，只启动服务。

  流程是：
  1. setup_server() — 确保源码目录存在，.env 存在
  2. 直接 docker compose up -d（在离线模式下读 $SOURCE_DIR 的 compose 文件）

  所以 离线模式你需要先 build 好镜像，然后 install.sh 才能启动它们。


 设置环境变量后执行：
  export MULTICA_OFFLINE_MODE=1
  export MULTICA_SOURCE_DIR=/home/workspace/repo/multica-main    # 源码目录
  export MULTICA_INSTALL_DIR=$HOME/.multica/server               # 运行时目录

  # 执行离线自托管安装
  curl -fsSL https://raw.githubusercontent.com/multica-ai/multica/main/scripts/install.sh | bash -s -- --offline
  --with-server
```

### 9.4. 问题记录

#### 9.4.1. Go版本提示需要>= 1.26.1

`make`提示需要`go >= 1.26.1`，我当前系统是`1.23.1`，可以先升级下系统默认的新版本`1.25.9`，再修改下`server/go.mod`里的go版本要求：`go >= 1.25.1`（若编译时某些库版本要求更高，再考虑下载新版本）

另外，若github的依赖库下载慢，可以配置go代理，`go env -w GOPROXY=https://goproxy.cn,direct`。

```sh
[root@xdlinux ➜ multica-main ]$ dnf upgrade go
Last metadata expiration check: 0:08:00 ago on Fri 08 May 2026 09:22:04 PM CST.
Dependencies resolved.
==============================================================================================
 Package                      Architecture            Version                          Repository                  Size
==============================================================================================
Upgrading:
 golang                       x86_64                  1.25.9-1.el9_7                   appstream                  1.2 M
 golang-bin                   x86_64                  1.25.9-1.el9_7                   appstream                   37 M
...

# 新版本Go
[root@xdlinux ➜ multica-main ]$ go version
go version go1.25.9 (Red Hat 1.25.9-1.el9_7) linux/amd64
```

#### 9.4.2. 问题：Alpine Linux 官方软件源在国内访问超时，导致 apk add 安装包失败

```sh
[root@xdlinux ➜ multica-main ]$ make selfhost-build
==> Building Multica from the current checkout...
docker compose -f docker-compose.selfhost.yml -f docker-compose.selfhost.build.yml up -d --build
[+] up 0/17
 ⠹ Image pgvector/pgvector:pg17 [⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀] Pulling
 ...
=> [backend internal] load build context              0.1s
 => => transferring context: 3.88MB                   0.1s
 => ERROR [backend stage-1 2/9] RUN apk add --no-cache ca-certificates tzdata                   10.6s
 => CANCELED [backend builder 2/9] RUN apk add --no-cache git   0.0s
 => CANCELED [frontend deps  2/11] RUN corepack enable && corepack prepare pnpm@10.28.2 --activate    0.0s
 => CANCELED [frontend runner 2/6] WORKDIR /app           0.0s
------
 > [backend stage-1 2/9] RUN apk add --no-cache ca-certificates tzdata:
0.181 fetch https://dl-cdn.alpinelinux.org/alpine/v3.21/main/x86_64/APKINDEX.tar.gz
```

