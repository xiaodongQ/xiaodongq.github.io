---
title: AI能力集 -- Hermes Agent 部署与实践记录
description: 记录 NousResearch/hermes-agent 从零部署到实际使用的完整过程,以及过程中的踩坑、验证和最终落地感受
categories: [AI, AI能力集]
tags: [Hermes, Agent, 自部署]
---

## 1. 引言

[待补充:部署背景、目标、为什么选 hermes-agent]

相关链接:
* [NousResearch/hermes-agent 仓库](https://github.com/NousResearch/hermes-agent)

---

## 2. 部署过程

### 2.2. 部署步骤

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
→ Checking ffmpeg (TTS voice messages)...
→ Trying cargo install ripgrep (no sudo needed)...
    Updating crates.io index
  Downloaded ripgrep v15.1.0
  Downloaded 1 crate (217.1KiB) in 5.79s
  Installing ripgrep v15.1.0
    Updating crates.io index
       Fetch [========>                        ] 8 complete; 3 pending
```

### 2.3. 启动验证

[待补充:服务起来后的健康检查、Web UI 截图]

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
