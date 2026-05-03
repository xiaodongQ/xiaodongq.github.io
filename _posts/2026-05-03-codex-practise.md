---
title: Codex系列 -- Codex实战手记
description: Codex实战手记，持续更新实践和技巧
categories: [AI, Codex系列]
tags: [AI, Codex]
pin: true
---

## 1. 引言

平常使用`Claude Code`比较多，在 [Claude Code系列 -- Claude Code实战手记](https://xiaodongq.github.io/2026/03/04/claude-code-practise/) 里进行了记录。本篇用于记录一些`OpenAI Codex`相关的实践笔记。

## 2. 安装和基本使用

### 2.1. 安装

方式1：[官网](https://chatgpt.com/zh-Hans-CN/codex/)下载Codex可视化应用（在MacOS环境下载下来300多MB、安装800多MB。自己笔记本配置比较低风扇呼呼响，此处简单试用）

方式2：安装Codex CLI（**最常用**）：`npm install -g @openai/codex`

暂时安装`codex@0.57.0`，minimax和codex新版本可能有兼容性问题，见[Minimax的说明](https://platform.minimaxi.com/docs/token-plan/codex-cli)。

> 新一点的版本（比如0.125.0）用minimax会报错：⚠ Model metadata for `codex-MiniMax-M2.7` not found. Defaulting to fallback metadata; this can degrade performance and cause issues.
>
> 而codex@0.57.0使用minimax时，经常会重连。对于minimax模型来说，还是Claude Code合适点。

```sh
[MacOS-xd@qxd ➜ test git:(main) ]$ npm install -g @openai/codex@0.57.0
added 1 package in 12s
[MacOS-xd@qxd ➜ test git:(main) ]$ codex --version
codex-cli 0.57.0
```

`~/.codex`下的文件结构：

```sh
[MacOS-xd@qxd ➜ .codex git:(main) ]$ ls -ltrha
total 2392
drwxr-xr-x    3 xd  staff    96B May  3 12:16 sqlite
drwxr-xr-x    3 xd  staff    96B May  3 12:16 tmp
drwxr-xr-x    2 xd  staff    64B May  3 12:16 memories
-rw-r--r--    1 xd  staff     3B May  3 12:16 .personality_migration
drwxr-xr-x    3 xd  staff    96B May  3 12:16 skills
drwxr-xr-x    3 xd  staff    96B May  3 12:16 plugins
-rw-------    1 xd  staff   214B May  3 12:16 config.toml
drwxr-xr-x    4 xd  staff   128B May  3 12:17 vendor_imports
drwxr-xr-x    6 xd  staff   192B May  3 12:17 .tmp
-rw-------    1 xd  staff   176B May  3 16:40 auth.json
-rw-r--r--    1 xd  staff   433B May  3 16:40 .codex-global-state.json
-rw-r--r--    1 xd  staff   433B May  3 16:40 .codex-global-state.json.bak
-rw-r--r--    1 xd  staff   176K May  3 16:43 state_5.sqlite
-rw-r--r--    1 xd  staff    32K May  3 16:43 state_5.sqlite-shm
-rw-r--r--    1 xd  staff   8.1K May  3 16:43 state_5.sqlite-wal
-rw-r--r--    1 xd  staff   352K May  3 16:45 logs_2.sqlite
-rw-r--r--    1 xd  staff    32K May  3 16:45 logs_2.sqlite-shm
-rw-r--r--    1 xd  staff   507K May  3 16:52 logs_2.sqlite-wal
```

### 2.2. 配置文件

登录时，会提示从其他agent工具导入配置，从中也可以看出和`Claude Code`的**对应关系**：
* 配置文件：`.claude/settings.json` 对应 `.codex/config.toml`
* 规则：`CLAUDE.md` 对应 `AGENTS.md`
* skills：`.claude/skills` 对应 `.agents/skills`
* MCP：在Codex的配置文件：`.codex/config.toml` 中进行配置（Claude Code则在`~/.claude.json`）

```sh
Choose what to import
Select which detected items to import.
Settings
~/.claude/settings.json to ~/.codex/config.toml

Instructions
~/.claude/CLAUDE.md to ~/.codex/AGENTS.md

Skills
~/.claude/skills to ~/.agents/skills

Plugins (9)
~/.claude/settings.json

MCP servers
~ to ~/.codex/config.toml

Projects (12)
Work in your existing projects
```

---

这里简单对比下导入`Claude Code`配置前后的变化（**最好还是跟着教程单独配置，导入的内容可能各种坑，此处仅为了实验进行导入**）。

1、配置导入前（先`git init/add/commit`本地管理了`~/.codex`目录，导入实验完成后可以回退）

```sh
[MacOS-xd@qxd ➜ .codex git:(main) ]$ cat config.toml
[marketplaces.openai-bundled]
last_updated = "2026-05-03T04:16:52Z"
source_type = "local"
source = "/Users/xd/.codex/.tmp/bundled-marketplaces/openai-bundled"

[plugins."browser-use@openai-bundled"]
enabled = true
```

2、导入后（**结果**：直接有点问题，OpenAI肯定不需要`ANTHROPIC`相关的几个变量，还是要手动调整下）

```sh
[MacOS-xd@qxd ➜ .codex git:(main) ✗ ]$ cat config.toml
[marketplaces.baoyu-skills]
last_updated = "2026-05-03T08:56:29Z"
source = "/Users/xd/Documents/workspace/repo/baoyu-skills-main"
source_type = "local"

[marketplaces.minimax-skills]
last_updated = "2026-05-03T08:56:29Z"
source = "/Users/xd/Documents/workspace/repo/minimax-ai_skills-main"
source_type = "local"

[marketplaces.openai-bundled]
last_updated = "2026-05-03T04:16:52Z"
source = "/Users/xd/.codex/.tmp/bundled-marketplaces/openai-bundled"
source_type = "local"

[mcp_servers.MiniMax]
args = ["-y"]
command = "/Users/xd/local_tool/minimap_mcp/bin/minimax-coding-plan-mcp"

[mcp_servers.MiniMax.env]
MINIMAX_API_HOST = "https://api.minimaxi.com"
MINIMAX_API_KEY = "sk-cp-KgOfCAZKyPH_oxxxxxx"

[plugins."browser-use@openai-bundled"]
enabled = true

[shell_environment_policy]
inherit = "core"

[shell_environment_policy.set]
ANTHROPIC_AUTH_TOKEN = "sk-cp-KgOfCAZKyPH_oxxxxxx"
ANTHROPIC_BASE_URL = "https://api.minimaxi.com/anthropic"
ANTHROPIC_DEFAULT_HAIKU_MODEL = "MiniMax-M2.7"
ANTHROPIC_DEFAULT_OPUS_MODEL = "MiniMax-M2.7"
ANTHROPIC_DEFAULT_SONNET_MODEL = "MiniMax-M2.7"
ANTHROPIC_MODEL = "MiniMax-M2.7"
API_TIMEOUT_MS = "3000000"
CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC = "1"

[projects."/Users/xd/Documents/Codex/2026-05-03/test"]
trust_level = "trusted"
```

### 2.3. 第三方API接入

这里接入`MiniMax`为例，可见：[Codex CLI中接入MiniMax](https://platform.minimaxi.com/docs/token-plan/codex-cli)。

配置方式：配置到 `model_providers.供应商` 下面，供应商比如`vapi`、`minimax`等。可以快速切换。

```sh
# 当前使用的 Provider
model_provider = "minimax"
# 当前使用的模型codex-MiniMax-M2.7
#model = "MiniMax-M2.7"
model = "codex-MiniMax-M2.7"

# 可以model_providers.xxx定义多个模型提供商，外部`codex --provider xxx`方式临时指定使用
[model_providers.minimax]
name = "MiniMax Chat Completions API"
base_url = "https://api.minimaxi.com/v1"
# 保留这个值，然后在.zshrc里 export MINIMAX_API_KEY="xxx" 设置环境变量
env_key = "MINIMAX_API_KEY"
requires_openai_auth = false
# wire_api = "chat"
request_max_retries = 4
stream_max_retries = 10
stream_idle_timeout_ms = 300000
```

测试执行：

```sh
[MacOS-xd@qxd ➜ learn-claude-code git:(main) ]$ codex
╭────────────────────────────────────────────────────╮
│ ✨ Update available! 0.57.0 -> 0.128.0             │
│ Run npm install -g @openai/codex@latest to update. │
│                                                    │
│ See full release notes:                            │
│ https://github.com/openai/codex/releases/latest    │
╰────────────────────────────────────────────────────╯

╭─────────────────────────────────────────────────────────╮
│ >_ OpenAI Codex (v0.57.0)                               │
│                                                         │
│ model:     codex-MiniMax-M2.7   /model to change        │
│ directory: ~/Documents/workspace/repo/learn-claude-code │
╰─────────────────────────────────────────────────────────╯

  To get started, describe a task or try one of these commands:

  /init - create an AGENTS.md file with instructions for Codex
  /status - show current session configuration
  /approvals - choose what Codex can do without approval
  /model - choose what model and reasoning effort to use
  /review - review any changes and find issues

› 测试
• <think>The user is just saying "测试" which means "test" in Chinese. This seems like a simple test message to see if
  I'm working. I should respond briefly in Chinese since they wrote in Chinese.
  </think>
  你好！我正在运行。我是 Codex，你的编码助手。有什么我可以帮你的吗？
```


