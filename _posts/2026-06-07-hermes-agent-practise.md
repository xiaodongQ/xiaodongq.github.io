---
title: AI能力集 -- Hermes Agent 部署与实践记录
description: 记录 NousResearch/hermes-agent 从零部署到实际使用的完整过程,以及过程中的踩坑、验证和最终落地感受
categories: [AI, AI能力集]
tags: [Hermes, Agent, 自部署]
---

## 1. 引言

OpenClaw用得比较顺手，一直没按照Hermes，此处安装使用下。

相关链接:
* [NousResearch/hermes-agent 仓库](https://github.com/NousResearch/hermes-agent)
* [Hermes Agent指导文档](https://hermes-agent.nousresearch.com/docs/zh-Hans/)
* [配置文档](https://hermes-agent.nousresearch.com/docs/zh-Hans/user-guide/configuration)

---

## 2. 部署过程

### 2.1. 部署步骤

一行命令部署：`curl -fsSL https://hermes-agent.nousresearch.com/install.sh | bash`

```sh
[root@xdlinux ➜ ~ ]$ curl -fsSL https://hermes-agent.nousresearch.com/install.sh | bash

┌─────────────────────────────────────────────────────────┐
│             ⚕ Hermes Agent Installer                    │
├─────────────────────────────────────────────────────────┤
│  An open source AI agent by Nous Research.              │
└─────────────────────────────────────────────────────────┘

✓ Detected: linux (rocky)
→ Root install on Linux — using FHS layout
→   Code:    /usr/local/lib/hermes-agent
→   Command: /usr/local/bin/hermes
→   Data:    /root/.hermes (unchanged)
→   uv Python: /usr/local/share/uv/python (world-readable)
→ Installing managed uv into /root/.hermes/bin ...
✓ Managed uv installed (uv 0.11.19 (x86_64-unknown-linux-gnu))
→ Checking Python 3.11...
→ Python 3.11 not found, installing via uv...
Installed Python 3.11.15 in 21.01s
 + cpython-3.11.15-linux-x86_64-gnu (python3.11)
warning: `/usr/local/share/uv/bin` is not on your PATH. To use installed Python executables, run `export PATH="/usr/local/share/uv/bin:$PATH"` or `uv python update-shell`.
✓ Python installed: Python 3.11.15
→ Checking Git...
✓ Git 2.47.3 found
→ Checking Node.js (for browser tools)...
✓ Node.js v24.13.0 found
→ Checking internet connectivity for package install and web tools...
⚠ Could not reach https://duckduckgo.com/
⚠ Network checks failed. Hermes install may complete, but web search and dependency downloads can fail.
→ Verify internet/DNS and retry if pip install fails.
→ Checking ripgrep (fast file search)...
...
```

安装时网络有点问题，让小龙虾自行解决，代码安装在`/root/hermes-install/hermes-agent/`了。
* 走 gh-proxy.com 镜像 git clone 源码（164M，1 分钟下完）
* 直接 pip install -e .（pip 走阿里云 PyPI 镜像，秒装）
* 入口点自动注册到 pyenv shim，代码位置：/root/hermes-install/hermes-agent/（安装用的临时目录，可保留）
* 直接装在 system python，介意可重建 venv 搬过去

版本：

```sh
[root@xdlinux ➜ ~ ]$ hermes --version
Hermes Agent v0.16.0 (2026.6.5) · upstream c9863772
Project: /root/hermes-install/hermes-agent
Python: 3.12.13
OpenAI SDK: 2.24.0
Up to date
```

#### 2.1.1. 重建

让小龙虾用venv方式重建下：

```sh
venv 重建完成，doctor 那个 "Not in virtual environment" 警告消失。

新结构：
* venv：/root/hermes-install/hermes-agent/venv/
* 三个命令：/usr/local/bin/hermes{,agent,-acp} → symlink 到 venv/bin/
* 不再依赖 pyenv shim

踩了个小坑：
* uv venv 默认不装 pip 到 venv 里（uv 想让你用 uv pip）
* 第一次 source venv/bin/activate && pip install -e . 时 pip 仍是 system 的，装错地方了（看 Requirement already satisfied: mdurl~=0.1 in /root/.pyenv/... 这行才发现的）
* 修正：pip uninstall -y hermes-agent → uv pip install --python venv/bin/python -e .
* 副作用：crewai 那批版本冲突也顺手被解了（pydantic 2.13.2→2.13.4、requests 2.32.5→2.33.0 等都搬进 venv，system python 干净了）
```

安装正常：

```sh
[root@xdlinux ➜ ~ ]$ which hermes
/usr/local/bin/hermes
```

### 2.2. 启动验证

命令示例：

```sh
[root@xdlinux ➜ ~ ]$ hermes -h
usage: hermes [-h] [--version] [-z PROMPT] [-m MODEL] [--provider PROVIDER] [-t TOOLSETS] [--resume SESSION]
              [--continue [SESSION_NAME]] [--worktree] [--accept-hooks] [--skills SKILLS] [--yolo] [--pass-session-id]
              [--ignore-user-config] [--ignore-rules] [--tui] [--cli] [--dev]
              {chat,model,fallback,secrets,migrate,gateway,proxy,lsp,setup,postinstall,whatsapp,slack,send,login,logout,auth,status,cron,webhook,portal,kanban,hooks,doctor,security,dump,debug,backup,checkpoints,import,config,pairing,skills,bundles,plugins,curator,memory,tools,computer-use,mcp,sessions,insights,claw,version,update,uninstall,acp,profile,completion,dashboard,desktop,gui,logs,prompt-size}
              ...

Hermes Agent - AI assistant with tool-calling capabilities
...
Examples:
    hermes                        Start interactive chat
    hermes chat -q "Hello"        Single query mode
    hermes --tui                  Launch the modern TUI (or set display.interface: tui)
    hermes --cli                  Force the classic REPL (overrides display.interface: tui)
    hermes -c                     Resume the most recent session
    hermes -c "my project"        Resume a session by name (latest in lineage)
    hermes --resume <session_id>  Resume a specific session by ID
    hermes setup                  Run setup wizard
    hermes logout                 Clear stored authentication
    hermes auth add <provider>    Add a pooled credential
    hermes auth list              List pooled credentials
    hermes auth remove <p> <t>    Remove pooled credential by index, id, or label
    hermes auth reset <provider>  Clear exhaustion status for a provider
    hermes model                  Select default model
    hermes fallback [list]        Show fallback provider chain
    hermes fallback add           Add a fallback provider (same picker as `hermes model`)
    hermes fallback remove        Remove a fallback provider from the chain
    hermes config                 View configuration
    hermes config edit            Edit config in $EDITOR
    hermes config set model gpt-4 Set a config value
    hermes gateway                Run messaging gateway
    hermes -s hermes-agent-dev,github-auth
    hermes -w                     Start in isolated git worktree
    hermes gateway install        Install gateway background service
    hermes sessions list          List past sessions
    hermes sessions browse        Interactive session picker
    hermes sessions rename ID T   Rename/title a session
    hermes logs                   View agent.log (last 50 lines)
    hermes logs -f                Follow agent.log in real time
    hermes logs errors            View errors.log
    hermes logs --since 1h        Lines from the last hour
    hermes debug share             Upload debug report for support
    hermes update                 Update to latest version
    hermes dashboard              Start web UI dashboard (port 9119)
    hermes dashboard --stop       Stop running dashboard processes
    hermes dashboard --status     List running dashboard processes

For more help on a command:
    hermes <command> --help
```

### 2.3. 配置模型

`hermes model`：

```sh
[root@xdlinux ➜ ~ ]$ hermes model
  Current model:    (not set)
  Active provider:  MiniMax

No MiniMax (China) API key configured.
MINIMAX_CN_API_KEY (or Enter to cancel): **************************************************
    API key saved.

Base URL [https://api.minimaxi.com/anthropic]:
  Found 7 model(s) from models.dev registry

Default model set to: MiniMax-M3 (via MiniMax (China))
```

---

## 3. 使用场景

[待补充:实际跑过的业务场景、配置过程、跑出来的结果]

---

## 4. 问题记录

[待补充:部署或使用过程中遇到的坑]

### 4.1. 问题1

错误信息:
```
[待补充]
```

解决方式:
[待补充]

---

## 5. 总结

[待补充:核心收获、飞轮、钩子]
