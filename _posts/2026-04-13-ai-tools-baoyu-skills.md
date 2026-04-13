---
title: AI能力集 -- baoyu-skills功能实验
description: baoyu-skills功能实验
categories: [AI, AI能力集]
tags: [AI, Skills]
---

## 1. 引言

[上篇](https://xiaodongq.github.io/2026/04/12/ai-tools-openrouter-cc-switch/)说到最近换了支持生图和语音的token plan，这里来实验一下。

宝玉老师（有很多AI相关知识分享）之前分享了他的 Claude Code 技能集：[baoyu-skills](https://github.com/JimLiu/baoyu-skills)，里面的图片生成功能有很多自媒体也在用。先试试效果，后续看如何跟日常结合起来：比如博客配图、程序架构图等等。

## 2. 功能基本介绍和安装

### 2.1. 功能介绍

功能很多，记住大类别后，按需使用即可，比如之前单独用过`baoyu-post-to-wechat`的API方式推送公众号。

技能分为三大类：
* 内容技能 (Content Skills)：可以生成内容和自媒体发布（公众号、小红书、X等），比如各类风格的图片卡片
* AI 生成技能 (AI Generation Skills)：基于 AI SDK 的生成图像，支持文生图、参考图、宽高比、自定义尺寸、批量生成和质量预设等。（跟第一类里面的生图有些功能类似）
* 工具技能 (Utility Skills)：处理内容，比如下载YouTube视频进行文本转录、字幕转换、多语言翻译；抓取URL转成markdown等

### 2.2. Skill安装

这些Skills也可以在OpenClaw里使用，本文先只用于Claude Code。

前置依赖：
* 已安装 Node.js 环境
* 能够运行 `npx bun` 命令

```sh
# 可以在线设置JimLiu/baoyu-skills，此处我离线下载了包后添加本地市场
/plugin marketplace add /Users/xd/Documents/workspace/repo/baoyu-skills-main

# 输入/plugin后选择安装。安装后如下
/plugin
────────────────────────────────────────────────────────
  Plugins  Discover   Installed   Marketplaces   Errors

  ╭────────────────────────────────────────────────────╮
  │ ⌕ Search…                                          │
  ╰────────────────────────────────────────────────────╯

  ❯ baoyu-skills Plugin · baoyu-skills · ✔ enabled
    claude-hud Plugin · claude-hud · ✔ enabled

# 重新加载一下插件（或者退出claude code后重新进入）
❯ /reload-plugins
  ⎿  Reloaded: 2 plugins · 2 skills · 5 agents · 0 hooks · 0 plugin MCP servers · 0 plugin LSP servers
───────────────────────────────────────────────────
# 而后就可以看到相关skill对应的slash command了
❯ /baoyu
───────────────────────────────────────────────────
/baoyu-comic                    (baoyu-skills) Knowledge comic creator supporting multiple art styles and tones...
/baoyu-imagine                  (baoyu-skills) AI image generation with OpenAI, Azure OpenAI... 
...
```

### 2.3. API配置

部分技能需要 API 密钥或自定义配置，支持多处配置，我自己还是习惯`~/.baoyu-skills/.env`。

此处用`MiniMax`的API，`cat ~/.baoyu-skills/.env`，注意URL区分国际和内地，内地是`https://api.minimaxi.com`：

```sh
# MiniMax
MINIMAX_API_KEY=sk-cp-KgOfCAZKyP...
MINIMAX_IMAGE_MODEL=image-01
MINIMAX_BASE_URL=https://api.minimaxi.com
# global是下面的这个，内地是上面的
# MINIMAX_BASE_URL=https://api.minimax.io
```

## 3. 实践使用

创建一个临时项目目录`/Users/xd/Documents/workspace/repo/tmp_baoyu`，拷贝一些内容这个目录，这里把博客文章拷贝过来，因为需要基于一些内容来生成图片等。第一次使用`baoyu-xxx`相关命令，会让你记录一些偏好保存下来。

```sh
[MacOS-xd@qxd ➜ tmp_baoyu ]$ ls -la
drwxr-xr-x    3 xd  staff    96 Apr 13 18:47 .baoyu-skills
drwxr-xr-x  157 xd  staff  5024 Apr 13 18:49 _posts
```

### 3.1. baoyu-xhs-images：生成小红书风格图片

`/baoyu-xhs-images _posts/2026-04-12-ai-tools-openrouter-cc-switch.md`，后续会交互式让人确认一些内容：

```sh
❯ /baoyu-skills:baoyu-xhs-images _posts/2026-04-12-ai-tools-openrouter-cc-switch.md
⏺ 我来帮你为这篇关于 AI 工具和 OpenRouter/CC Switch 的文章生成小红书图片系列。
  首先检查用户偏好设置（Step 0）：
⏺ Bash(test -f /Users/xd/Documents/workspace/repo/baoyu-skills-main/skills/baoyu-xhs-images/.baoyu-skills/baoyu-xhs-imag
      es/EXTEND.md && echo "project" || echo "not fou…)
  ⎿  not found
  Read 1 file (ctrl+o to expand)
⏺ Bash(test -f "$HOME/.baoyu-skills/baoyu-xhs-images/EXTEND.md" && echo "found" || echo "not found")
  ⎿  not found
⏺ EXTEND.md 未找到，需要先完成首次设置。让我查看设置问题详情：
  Read 1 file (ctrl+o to expand)
⏺ EXTEND.md 未找到，需要先完成首次设置。请回答以下问题：
⏺ User answered Claude's questions:
  ⎿  · 生成的图片需要添加水印吗？请输入水印内容（如名字、@handle），留空则不添加水印 → 不添加水印（推荐）
     · 默认视觉风格偏好是什么？可以输入风格名称或自定义风格 → 不指定（推荐）
     · 偏好设置保存到哪？ → 用户目录
⏺ 正在保存偏好设置到用户目录...
⏺ Bash(mkdir -p "$HOME/.baoyu-skills/baoyu-xhs-images")
  ⎿  Done
⏺ Write(~/.baoyu-skills/baoyu-xhs-images/EXTEND.md)
  ⎿  Wrote 14 lines to ../../../../.baoyu-skills/baoyu-xhs-images/EXTEND.md
       1 ---
       2 version: 1
       3 watermark:
       4   enabled: false
       5   content: ""
       6   position: bottom-right
       7   opacity: 0.7
       8 preferred_style:
       9   name: null
      10   description: ""
     … +4 lines (ctrl+o to expand)
⏺ 偏好设置已保存到 ~/.baoyu-skills/baoyu-xhs-images/EXTEND.md。
  现在进入 Step 1: 内容分析：
  Read 1 file (ctrl+o to expand)
⏺ 现在分析文章内容并创建分析文档...
⏺ Bash(mkdir -p "/Users/xd/Documents/workspace/repo/tmp_baoyu/xhs-images/ai-tools-openrouter-cc-switch/prompts")
  ⎿  Done
⏺ Write(xhs-images/ai-tools-openrouter-cc-switch/analysis.md)
  ⎿  Error writing file
  Listed 1 directory (ctrl+o to expand)
⏺ 已有历史数据，让我查看现有内容：
  Read 2 files, listed 1 directory (ctrl+o to expand)
⏺ 已有分析结果和提纲，但图片尚未生成。
  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  📋 内容分析
    主题: AI工具配置管理 | 类型: 干货教程
    要点: CC-Switch、OpenRouter、CLIProxyApi 三个工具组合使用
    受众: 开发者、技术爱好者
  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  🎨 推荐方案（已保存）
    策略: B Information-Dense（干货教程，信息密集）
    风格: notion · 布局: dense · 预设: knowledge-card
    图片: 5张（封面 + 3内容 + 结尾）
    元素: soft-gradient / hand-drawn-lines, sticky-notes / highlight-box
  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
⏺ User answered Claude's questions:
  ⎿  · 已有分析结果和提纲，是否直接开始生成图片？ → ✅ 确认，直接生成（推荐）
⏺ 好的，开始 Step 3: 生成图片。首先生成封面图（不引用其他图），然后后续图片引用封面图保持风格一致。
  Read 1 file (ctrl+o to expand)
⏺ 提示文件不存在，我需要先创建提示词然后生成图片。让我调用图片生成技能：
⏺ baoyu-skills:baoyu-imagine(Generate XHS cover image)
  ⎿  Initializing…
  ⎿  Error: Agent type 'baoyu-skills:baoyu-imagine' not found. Available agents: general-purpose, statusline-setup,
     Explore, Plan, claude-code-guide
⏺ Skill(baoyu-skills:baoyu-imagine)
  ⎿  Successfully loaded skill
⏺ 检查偏好设置（Step 0）：
⏺ Bash(test -f "$HOME/.baoyu-skills/baoyu-imagine/EXTEND.md" && echo "user" || echo "not found")
  ⎿  not found
⏺ Bash(test -f "$HOME/.baoyu-skills/.env" && echo "found" || echo "not found")
  ⎿  found
⏺ Bash(env | grep -E "MINIMAX_API_KEY|OPENAI_API_KEY|GOOGLE_API_KEY|DASHSCOPE_API_KEY|OPENROUTER_API_KEY" | head -5)
  ⎿  (No output)
⏺ Bash(test -f "$HOME/.baoyu-skills/baoyu-image-gen/EXTEND.md" && echo "legacy found" || echo "legacy not found")
  ⎿  legacy not found
  Read 1 file (ctrl+o to expand)
⏺ 有 MiniMax API Key，直接生成图片。先检查 bun 运行时：
  Searched for 1 pattern (ctrl+o to expand)
⏺ Bash(cd "/Users/xd/Documents/workspace/repo/baoyu-skills-main/skills/baoyu-imagine" && npx -y bun scripts/main.ts
      --prompt "开发者必备！CC-Switch + CLIProxyApi 组合让我切换 AI 模…)
  ⎿  Using minimax / image-01 for single
     Switch model: --model <id> | EXTEND.md default_model.minimax | env MINIMAX_IMAGE_MODEL
     /Users/xd/Documents/workspace/repo/tmp_baoyu/xhs-images/ai-tools-openrouter-cc-switch/01-cover-ai-tools-openro
     uter-cc-switch.png
  ⎿  Shell cwd was reset to /Users/xd/Documents/workspace/repo/tmp_baoyu
  ⎿  (timeout 2m)
⏺ 封面图生成完成！现在生成后续内容图，引用封面图保持风格一致：
...
⏺ ---
  小红书图片系列生成完成！
主题: AI工具配置管理 - CC-Switch + CLIProxyApi 组合
  模式: 快速确认
  策略: B Information-Dense
  风格: notion（简约手绘知性风）
  布局: dense/list
  位置: xhs-images/ai-tools-openrouter-cc-switch/
  已生成文件（5张）
  ┌──────────────────────────────────────────────────────────┬──────────┬───────┐
  │                           文件                            │   类型   │ 大小  │
  ├──────────────────────────────────────────────────────────┼──────────┼───────┤
  │ 01-cover-ai-tools-openrouter-cc-switch.png               │ 封面     │ 184KB │
  ├──────────────────────────────────────────────────────────┼──────────┼───────┤
  │ 02-painpoint-ai-tools-openrouter-cc-switch.png           │ 痛点铺垫  │ 337KB │
  ├──────────────────────────────────────────────────────────┼──────────┼───────┤
  │ 03-ccswitch-openrouter-ai-tools-openrouter-cc-switch.png │ 核心功能  │ 207KB │
  ├──────────────────────────────────────────────────────────┼──────────┼───────┤
  │ 04-cliproxyapi-ai-tools-openrouter-cc-switch.png         │ 配置步骤  │ 255KB │
  ├──────────────────────────────────────────────────────────┼──────────┼───────┤
  │ 05-summary-ai-tools-openrouter-cc-switch.png             │ 总结CTA  │ 296KB │
  └──────────────────────────────────────────────────────────┴──────────┴───────┘
────────────────────────────────────────────────────────────────────────────────────────────────────────
❯
────────────────────────────────────────────────────────────────────────────────────────────────────────
  [MiniMax-M2.7] ███░░░░░░░ 25%
  tmp_baoyu | floating-honking-charm
  1 CLAUDE.md
  tok: 2.5M (in: 1.0M, out: 14k) | ⏱️   5m
  ◐ Bash: .../worksp... | ✓ Bash ×11
  ✓ Read ×4 | ✓ Write ×2
  ✓ AskUserQuestion ×1
  ✓ baoyu-skills:baoyu-imagine: Generat...
  ⏵⏵ accept edits on (shift+tab to cycle)
```