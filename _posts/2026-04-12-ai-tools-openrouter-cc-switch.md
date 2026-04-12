---
title: Claude Code系列 -- CC-Switch和CLIProxyApi组合共享API
description: OpenRouter 模型用量统计与 CC-Switch 配置管理工具使用指南
categories: [AI, Claude Code系列]
tags: [AI, OpenRouter, CC-Switch, CLIProxyAPI, MiniMax]
---

## 1. 引言

最近Coding Plan快到期了，换成了MiniMax的Plus包年套餐（可见最后小节），结合平常使用碰到的一个痛点：IDE和Claude Code、OpenClaw需要用到的Skills、模型API等配置各自都要折腾一遍，用到的环境还涉及了Windows、Linux、Mac等好几个平台。

折腾了一下`CC-Switch`和`CLIProxyApi`，以及linux环境下的`CC-Switch-cli`命令行版本。

顺便看了一下OpenClaw类似的2个应用
* [slock.ai](https://slock.ai/)，agent在群里自行交互完成任务（注册试了下，API问题交互暂未成功）
* [hermes-agent](https://github.com/nousresearch/hermes-agent)，最近比较火的爱马仕（`Hermes`），用Python写的，看群里其他人用的效果好像没有也没有太好。近期升级了一下OpenClaw后比之前体验好一点，考虑迁移试下效果

## 2. CC-Switch 工具

[CC-Switch](https://github.com/farion1231/cc-switch) 是一款专为 AI 编程助手（特别是 Claude Code）设计的**跨平台配置管理工具**。  
简单来说，它就像是一个"万能遥控器"或"中控面板"，帮你**统一管理**各种 AI 模型的 API 密钥、地址配置，让你无需手动修改复杂的配置文件，就能在不同的大模型之间一键切换。

### 2.1. 核心功能

* **统一管理配置**：它支持管理 Claude Code、Codex、Gemini CLI 等多种编程工具的配置文件。你不需要去翻找 `.json` 或 `.toml` 文件手动修改，直接在它的图形界面里操作。
* **一键切换模型**：你可以预设多个模型（比如今天想用 GPT-4o，明天想用 DeepSeek），在 CC-Switch 界面点一下就能立刻生效。
* **本地代理与故障转移**：它能在本地搭建一个代理服务器。如果某个模型接口挂了，它可以自动切换到备用接口，保证你的编程工作流不中断。
* **可视化监控**：可以查看 API 的使用量统计、延迟测试等数据。

### 2.2. OpenRouter介绍

[OpenRouter](https://openrouter.ai/rankings) 是一个统一的大模型 API 聚合平台。
* 通过 OpenRouter 的一个 API 端点，可以访问来自不同提供商的数百个 AI 模型
* 统一计费 - 只需要在一个平台充值，就可以使用所有接入的模型，无需分别向各个厂商付费
* 智能路由 - 可以设置自动选择最便宜/最快的模型，或者在某个模型不可用时自动切换到备选模型
* 统一接口格式 - 采用类似 OpenAI 的 API 格式，调用不同模型时只需改变 model 参数

`OpenRouter` 的**调用量数据**已成为衡量全球 AI 模型受欢迎程度的**重要风向标**。
* 除了调用量，还可以查看模型评测、各模型工具调用次数等等
* 还有 AI 工具的使用 token 排行，可以了解到近期流行的 AI 工具，比如最近的爱马仕（Hermes Agent）

比如这周的调用量情况：  
![model-rankings](/images/2026-04-12-openrouter-ranking.png)

模型用量的 top app：  
![token-used-top-app](/images/2026-04-12-top-app.png)

### 2.3. CC-Switch 与 OpenRouter 的关系

它们是"工具"与"服务"的互补关系，经常被开发者组合在一起使用，以实现"花最少的钱，用最爽的模型"。
* CC-Switch 是工具，OpenRouter 是服务
* OpenRouter 提供了统一的接口，而 CC-Switch 提供了便捷的切换界面。

**通常操作方案**：
1. 注册 OpenRouter 获取 API Key
2. 填入 CC-Switch
3. 在 CC-Switch 中配置并一键切换。

### 2.4. Linux 下 CLI 版本使用

**特别注意：最好先备份下Claude Code的配置，CC-Switch配置模型时会修改配置文件，可能把自己的其他配置覆盖掉。**

桌面 GUI 版本，直接用原始仓库的即可。Linux 下的命令行版本，可以看这个 fork 后的 CLI 版本：[SaladDay/cc-switch-cli](https://github.com/SaladDay/cc-switch-cli)。

下载下来就一个文件，执行就会进入 tui 页面：
![cc-switch-cli](/images/2026-04-12-cc-switch-cli.png)

命令：
* `cc-switch env tools` 查看本地安装了哪些 AI Cli 工具，如 Claude code/Codex/Gemini/OpenCode
* `cc-switch provider list` 查看提供商
* 其他命令文档，可见：[文档](https://github.com/SaladDay/cc-switch-cli/blob/main/README_ZH.md)

## 3. CLIProxyApi（CPA）工具

### 3.1. 基本说明

[CLIProxyAPI](https://github.com/router-for-me/CLIProxyAPI)（简称 `CPA`）是一个为 CLI 提供 OpenAI/Gemini/Claude/Codex 兼容 API 接口的代理服务器，基于 Go 开发。

为什么要使用 CPA：
* 不同 AI 提供商（OpenAI、Claude、Gemini 等）使用不同的 API 格式（其实主要是事实标准的**OpenAI 规范**：`POST /v1/chat/completions` 和 **`Anthropic Claude`规范**：`POST /v1/messages`），CPA 可以进行转换
* 购买了多个平台的大模型提供商，多种认证方式需要分别管理，单一账户的 API 调用配额有限，达到限制后服务中断，影响开发连续性，CPA 可以故障自动转移
* CPA 和 CC-Switch 结合使用，可以参考：[CLIProxyAPI 使用完整教程](https://kelen.cc/posts/cliproxyapi-guide)

### 3.2. 配置步骤

手里有2个coding plan（一个快到期了，这里用千问验证），这里使用下 CPA 实验下。

#### 3.2.1. 下载 CLIProxyAPI 并设置登录密码

* 下载到 github 下载程序包，mac 下可以下载 `CLIProxyAPI_6.9.24_darwin_amd64.tar.gz` 并解压
* 复制配置文件 `cp config.example.yaml config.yaml`，并设置配置文件里的 `secret-key` 字段，即后台登录密码
* 启动服务 `./cli-proxy-api`，而后登录运维页面：`http://localhost:8317/management.html`（用 `secret-key` 配置的密码登录）

#### 3.2.2. 配置模型 AI 提供商

* 左侧可以通过多种方式配置大模型 AI 提供商，如 `Gemini CLI`、`ChatGPT Codex`、`Claude Code` 等，可以添加你所有的账号，CPA 会自动进行轮询使用
* **方式 1**：以 `Claude Code` 为例，在"AI 提供商" -> "Claude API 配置"中添加 `API 密钥` 和 `Base URL`（可以用 Coding Plan 里的）。注意这里点击 `从/v1/models 获取` 会失败，手动配置模型点击测试是成功的，比如 `qwen3.5-plus`，可点击"添加模型"来添加多个模型
* **方式 2**：OAuth 登录，国内好像只有千问和 kimi、iflow，这里用千问（需要邮箱注册，和千问 app 问答是不同的账号）。授权登录后，在"认证文件"页面会自动出来千问，点击"模型"可以看到里面的模型是 `coder-model`

AI 提供商方式添加：  
![cpa-add-provider](/images/2026-04-12-cpa-add-provider.png)

OAuth 方式：  
![cpa-oauth](/images/2026-04-12-cpa-oauth.png)

#### 3.2.3. CC-Switch 配置

到 `CC-Switch` 上添加相应分类（此处 Claude Code）的模型，请求地址是 CPA 的服务地址，默认参数下是 `http://127.0.0.1:8317`，`API Key` 是 `CPA` 上**配置面板**页面的"**API 密钥列表 (api-keys)**"中的密钥，可添加多个供多人使用。

`CC-Switch` 里添加配置示意图：
![cliproxyapi-add-provider](/images/2026-04-12-cliproxyapi-add-provider.png)

#### 3.2.4. Claude Code中使用模型

配置完成后，就可以正常用反代出来的模型了：

![claude code 使用情况](/images/2026-04-12-cc-switch-model.png)

#### 3.2.5. CC Switch的代理模式

1、启用全局代理模式后，配置文件可看到就由代理自动接管了：

```sh
[MacOS-xd@qxd ➜ cc-switch git:(main) ]$ cat ~/.claude/settings.json
{
  "env": {
    "ANTHROPIC_BASE_URL": "http://127.0.0.1:15721",
    "ANTHROPIC_AUTH_TOKEN": "PROXY_MANAGED",
    "API_TIMEOUT_MS": "3000000",
    "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC": 1
  },
  ...
```

代理可以在齿轮处开启：  
![cc-switch-代理启用](/images/2026-04-12-cc-switch-proxy-enable.png)

CC-Switch里效果：  
![cc-switch-proxy](/images/2026-04-12-cc-switch-proxy.png)

Claude Code里模型显示是`Sonnet`：
* 假的，只是它认为，实际调用是代理里配置的一个或多个模型。可以在CC-Switch的代理配置里看到真实使用的模型

```sh
[MacOS-xd@qxd ➜ cc-switch git:(main) ]$ claude
 ▐▛███▜▌   Claude Code v2.1.104
▝▜█████▛▘  Sonnet 4.6 · API Usage Billing
  ▘▘ ▝▝    ~/Documents/workspace/repo/cc-switch

❯ 测试
⏺ Hello! I'm working correctly. How can I help you today?
❯ 你是什么模型
⏺ 我是 Sonnet 4.6 模型（claude-sonnet-4-6），由 Anthropic 提供的 Claude Code CLI 中的 AI 助手。
  有什么我可以帮你的吗？
───────────────────────────────────────────────────
❯
───────────────────────────────────────────────────
  [Sonnet 4.6] █░░░░░░░░░ 12%
  cc-switch git:(main) | 1 CLAUDE.md
  tok: 97k (in: 596, out: 268)
  out: 107.8 tok/s | ⏱️   <1m
```

关闭代理则自动切换回我启用的模型provider了：

```sh
[MacOS-xd@qxd ➜ cc-switch git:(main) ]$ cat ~/.claude/settings.json
{
  "env": {
    "ANTHROPIC_BASE_URL": "https://api.minimaxi.com/anthropic",
    "ANTHROPIC_AUTH_TOKEN": "sk-cp-KgOfCAZKyPH_o....",
    "API_TIMEOUT_MS": "3000000",
    "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC": 1,
    "ANTHROPIC_MODEL": "MiniMax-M2.7",
    "ANTHROPIC_DEFAULT_SONNET_MODEL": "MiniMax-M2.7",
    "ANTHROPIC_DEFAULT_OPUS_MODEL": "MiniMax-M2.7",
    "ANTHROPIC_DEFAULT_HAIKU_MODEL": "MiniMax-M2.7"
  },
```

关闭代理，则是真实模型：

```sh
  [MiniMax-M2.7] ░░░░░░░░░░ 0%
  cc-switch git:(main) | 1 CLAUDE.md
[MacOS-xd@qxd ➜ cc-switch git:(main) ]$ claude
 ▐▛███▜▌   Claude Code v2.1.104
▝▜█████▛▘  MiniMax-M2.7 · API Usage Billing
  ▘▘ ▝▝    ~/Documents/workspace/repo/cc-switch

────────────────────────────────────────────────
❯───────────────────────────────────────────────
  [MiniMax-M2.7] ░░░░░░░░░░ 0%
  cc-switch git:(main) | 1 CLAUDE.md
```

### 3.3. 使用注意事项

1、`CLIProxyApi`（CPA）工具需要一直运行；若使用`CC-Switch`的代理模式，则`CC-Switch`也要一直运行，不使用的话只是方便切换，可以不常驻启动

2、`CC-Switch`添加新配置（供应商/Provider）时，`~/.claude/settings.json`里的配置先备份好，防止被覆盖。原有配置的其他内容，最好在“配置 JSON”里面也增加一下。配置过一次后续就方便了，只要在GUI切换即可，会自动调整`~/.claude/settings.json`里的内容


---

## 4. 题外话：MiniMax Token Plan

最近订阅了 minimax 的 Plus 包年套餐，支持生图和语音。介绍和用量说明可见：[Token Plan 概要](https://platform.minimaxi.com/docs/token-plan/intro)

2026.4.30 之前邀请其他人，各自还有些优惠：
* 🚀 MiniMax Token Plan 惊喜上线！新增语音、音乐、视频和图片生成权益。邀请好友享双重好礼，助力开发体验！好友立享 9 折 专属优惠 + Builder 权益，你赢返利 + 社区特权！
* 👉 立即参与：https://platform.minimaxi.com/subscribe/token-plan?code=2Q71d0qnxm&source=link

### 4.1. 功能说明

```sh
1500 次模型调用 / 5 小时
支持最新 MiniMax M2.7，正常约 50TPS，低峰时段 100TPS
2.5 倍 Starter 套餐用量
约支持 1~2 个 OpenClaw agent
支持主流的编程工具，并持续扩展中
支持图像理解、联网搜索 MCP
生成图像和语音
每周可使用额度为「每 5 小时额度」的 10 倍
```

### 4.2. 标准版各等级用量

单独记一下 `Plus` 对应的模型：
* 生成语音 `speech-2.8-hd`
* 生成图片 `image-01`
* 生成文本 `MiniMax-M2.7`
* 生成音乐 `Music-2.6`，100 首/天（限免），每首<=5min

| 权益 / 模型             | Starter           | Plus                | Max                 |
| :---------------------- | :---------------- | :------------------ | :------------------ |
| M2.7                    | 600 次请求/5 小时 | 1,500 次请求/5 小时 | 4,500 次请求/5 小时 |
| Speech 2.8              | —                 | 4,000 字符/日       | 11,000 字符/日      |
| image-01                | —                 | 50 张/日            | 120 张/日           |
| Hailuo-2.3-Fast 768P 6s | —                 | —                   | 2 个/日             |
| Hailuo-2.3 768P 6s      | —                 | —                   | 2 个/日             |
| Music-2.6               | 100 首/天（限免） | 100 首/天（限免）   | 100 首/天（限免）   |

### 4.3. TODO

生图功能，待实验一下baoyu-skills里各类风格
