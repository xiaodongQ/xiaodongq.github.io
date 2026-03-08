---
title: AI能力集 -- OpenClaw实战手记
description: OpenClaw实战手记，持续更新实践和技巧
categories: [AI, AI能力集]
tags: [AI, OpenClaw]
---

## 1. 引言

OpenClaw实战手记，持续更新实践和技巧。

几个不错的参考链接：
* 玩转OpenClaw：[一本书玩转 OpenClaw](https://awesome.tryopenclaw.asia/)
  * 开始可跟着这里实践：[OpenClaw 7天学习路径](https://github.com/xianyu110/awesome-openclaw-tutorial/blob/main/LEARNING-PATH.md)
* [OpenClaw 深度使用指南：普通人如何释放 AI Agent 的真正价值](https://mp.weixin.qq.com/s/nbaAYtHFoIxGHigYIkKdow)
* [awesome-openclaw-usecases](https://github.com/hesamsheikh/awesome-openclaw-usecases)
* [awesome-openclaw-skills](https://github.com/VoltAgent/awesome-openclaw-skills)

## 2. 安装和基本说明

> 环境说明：安装在家里一台单独的主机，双系统：`Windows`+`Rocky Linux`（默认），若是自己日常的工作电脑，则安全策略需要更谨慎一点。

### 2.1. 安装和配置

基本步骤：通过`npm`安装（可设置一下国内镜像源） -> 初始化OpenClaw并配置API -> 而后可以接入飞书（也有开源项目可以接入微信的），步骤可见：[Open Claw安装和配置](https://github.com/xiaodongQ/devNoteBackup/blob/master/%E5%90%84%E5%88%86%E7%B1%BB%E8%AE%B0%E5%BD%95/AI%E5%A4%A7%E6%A8%A1%E5%9E%8B%E5%AD%A6%E4%B9%A0%E7%AC%94%E8%AE%B0.md#%E5%AE%89%E8%A3%85-1)。

执行`openclaw tui`即可启动终端页面，也可用`openclaw dashboard`启动web页面（其他机器上访问，可以在机器上起SSH隧道来转发请求：`ssh -N -L 18789:127.0.0.1:18789 root@192.168.1.150`，而后仍用`http://localhost:18789/`访问）

```sh
[root@xdlinux ➜ ~ ]$ openclaw -v
2026.3.2
```

修改配置文件`~/.openclaw/openclaw.json`后，要重启网关服务：`openclaw gateway restart`。
* Gateway网关：负责连接各个聊天平台，管理会话和消息路由
* 默认地址：`http://127.0.0.1:18789/`

### 2.2. 安装目录说明

由于我的环境是`-g`全局安装的，安装在node的目录里：`/home/workspace/local/node-v24.13.0-linux-x64/lib/node_modules/openclaw/`。

```sh
[root@xdlinux ➜ ~ ]$ ll /home/workspace/local/node-v24.13.0-linux-x64/lib/node_modules/openclaw/
total 772K
drwxr-xr-x   3 root root  118 Mar  4 22:43 assets
-rw-r--r--   1 root root 549K Mar  4 22:43 CHANGELOG.md
drwxr-xr-x   8 root root  32K Mar  4 22:43 dist
drwxr-xr-x  28 root root 4.0K Mar  4 22:43 docs
drwxr-xr-x  43 root root 4.0K Mar  4 22:43 extensions
-rw-r--r--   1 root root 1.1K Mar  4 22:43 LICENSE
drwxr-xr-x 438 root root  12K Mar  4 22:43 node_modules
-rwxr-xr-x   1 root root 2.3K Mar  4 22:43 openclaw.mjs
-rw-r--r--   1 root root  15K Mar  4 22:43 package.json
-rw-r--r--   1 root root 120K Mar  4 22:43 README.md
drwxr-xr-x  54 root root 4.0K Mar  4 22:43 skills
```

各目录和文件相关说明：

| 目录/文件       | 说明                                                                            |
| --------------- | ------------------------------------------------------------------------------- |
| `openclaw.mjs`  | ⚙️ CLI 入口脚本（可执行），运行`openclaw`命令时执行的脚本                        |
| `package.json`  | 📦 包配置、依赖、脚本                                                            |
| `README.md`     | 📖 项目说明文档（122KB）                                                         |
| `CHANGELOG.md`  | 📝 版本更新日志（561KB）                                                         |
| `LICENSE`       | 📜 MIT 许可证                                                                    |
| `dist/`         | 🏗️ 编译后的 JavaScript 代码                                                      |
| `docs/`         | 📚 官方文档（28 个子目录）                                                       |
| `extensions/`   | 🔌 渠道/平台集成插件（43 个），Discord、电报、飞书等                             |
| `skills/`       | 🛠️ 内置的技能模块（54 个），比如Notion集成、代码开发代理、GitHub集成、天气查询等 |
| `node_modules/` | 📦 依赖包（438 个）                                                              |
| `assets/`       | 🎨 静态资源文件                                                                  |

### 2.3. 核心配置与数据存储目录

1、`~/.openclaw` 是小龙虾（OpenClaw）核心的配置与数据存储目录，相当于整个系统的 “核心大脑 + 数据仓库”，所有运行时配置、插件数据、日志、缓存等关键信息都集中在这里。

```sh
[root@xdlinux ➜ openclaw-projects ]$ ll ~/.openclaw 
total 68K
drwxr-xr-x 3 root root   18 Mar  4 22:15 agents      # AI 智能体存储目录，存放你创建的自定义 Agent
drwxr-xr-x 3 root root   22 Mar  7 08:02 browser     # 内置浏览器引擎数据
drwxr-xr-x 2 root root   24 Mar  4 22:16 canvas      # 可视化画布数据，小龙虾内置的流程图 / 脑图工具数据存储
drwxr-xr-x 2 root root   88 Mar  5 22:43 completions # 对话补全缓存，缓存AI生成的对话回复、代码补全结果
drwxr-xr-x 2 root root   23 Mar  4 22:16 cron        # 定时任务配置，存放自定义定时任务（如“每日9点爬取行业新闻”）
drwx------ 3 root root   20 Mar  8 10:05 delivery-queue # 任务投递队列，异步任务的临时存储
drwxr-xr-x 2 root root   45 Mar  8 10:05 devices     # 设备绑定信息，记录接入小龙虾的终端设备（如本地 PC、服务器、移动端）
-rw------- 1 root root  171 Mar  5 07:50 exec-approvals.json # 执行权限审批记录
drwxr-xr-x 3 root root   20 Mar  4 23:00 extensions  # 插件扩展目录，第三方插件的安装目录
drwxr-xr-x 3 root root   19 Mar  4 23:09 feishu      # 飞书集成配置，飞书机器人/消息推送的密钥、回调地址、会话ID，支撑与飞书的联动
drwxr-xr-x 2 root root   49 Mar  4 22:16 identity    # 身份认证信息
drwx------ 2 root root   32 Mar  4 22:15 logs        # 系统日志目录
drwx------ 3 root root   21 Mar  7 08:21 media       # 媒体文件存储
drwxr-xr-x 2 root root   25 Mar  7 23:42 memory             # 智能体记忆数据，Agent 的长期记忆 / 短期记忆存储
-rw------- 1 root root 5.3K Mar  8 11:57 openclaw.json      # 小龙虾核心配置文件
-rw------- 1 root root   49 Mar  8 07:35 update-check.json  # 版本更新检查记录
```

### 2.4. 状态检查和日志查看

当飞书上发送消息后，小龙虾不回复消息时，可能状态存在问题，这时可以使用的一些检查和定位方式。

状态：
* `openclaw status` 总览状态，会包含`Overview`、`Security audit`安全审计、`Channels`（比如飞书频道）、`Sessions`
  * `openclaw gateway status` 网关是否正常（网关负责小龙虾和飞书的交互）
  * `openclaw channels status` 频道状态

日志：
* `openclaw logs --follow` 可以查看当前实时日志

自动诊断和修复：
* `openclaw doctor`、`openclaw doctor --fix`

## 3. 终端命令

1、`openclaw tui` 打开终端，终端里`/`可以选择命令，`/help` 显示支持的命令，支持命令（`Slash commands`）如下：

```sh
Slash commands:                               
/help                                         
/commands                                     
/status                                       
/agent <id> (or /agents)                      
/session <key> (or /sessions)                 
/model <provider/model> (or /models)          
/think <off|minimal|low|medium|high|adaptive> 
/verbose <on|off>                             
/reasoning <on|off>                           
/usage <off|tokens|full>                      
/elevated <on|off|ask|full>                   
/elev <on|off|ask|full>                       
/activation <mention|always>                  
/new or /reset                                
/abort                                        
/settings                                     
/exit                                         
```

比如：`/reasoning on`开启推理后（回车2次），

2、有问题可以使用 doctor 命令修复配置并重启：`openclaw doctor --fix` （善用doctor）

## 4. 建议配置

### 4.1. 配置Skills

找了几篇文章学习经验，一开始不用配置太多Skills，先配置基本的几个Skills
* 初步安装的Skills（优先配置`网页搜索`技能）
  * `tavily-search`，实时检索+结构化输出，AI 原生优化的搜索工具 **建议安装**
    * 官方推荐`Brave Search`，不过貌似使用时要梯子，而且现在要绑VISA卡
  * `exa-web-search-free`，全网检索：实时网络搜索、信息聚合、冷门知识挖掘 **建议安装**
  * `self-improving-agent`，AI自我改进，让AI在犯错或被用户纠正时自动记录下来，下次遇到类似情况避免重蹈覆辙 **建议安装**
  * `multi-search-engine`，元搜索：并行调用多引擎、结果交叉验证、准确率排序
  * `mcporter-1-0-0`，内容生成：结构化文本生成、特定领域模板填充
  * `local-rag-search`，私有知识库，本地文档检索、RAG (检索增强生成)
  * `first-principles-decomposer`，思维建模：第一性原理拆解、复杂问题结构化分析
* [clawhub](https://clawhub.ai/)：OpenClaw 的公共 Skills 注册中心
* 参考的几篇文章
  * [openclaw 新装好，真正值得先装的 10 个 skills，我帮你筛好了](https://mp.weixin.qq.com/s/wFDitFGJUkvklRB2VDbWEw)
  * [这些Skills让OpenClaw把搜索做到极致](https://mp.weixin.qq.com/s/88N4aaOe9__gguQ9wvg4JQ)
  * [安装了72个Skills后，我的OpenClaw无所不能](https://mp.weixin.qq.com/s/VjtLUWo32Huh7Zaa8EIgrA)
  * [OpenClaw 深度使用指南：普通人如何释放 AI Agent 的真正价值](https://mp.weixin.qq.com/s/nbaAYtHFoIxGHigYIkKdow)

### 4.2. 人设配置

以下是每个 agent 工作目录中的核心文件：  

```
 ┌──────────────┬──────────┬─────────────────────────────────────────────────────────────────────────────────────┐
 │      文件     │   用途    │                                       内容说明                                       │
 ├──────────────┼──────────┼─────────────────────────────────────────────────────────────────────────────────────┤
 │ SOUL.md      │ 核心人格  │ 定义 agent 的行为准则、价值观、沟通风格。比如"不要说废话，直接帮忙"、"可以有主见"等              │
 ├──────────────┼──────────┼─────────────────────────────────────────────────────────────────────────────────────┤
 │ IDENTITY.md  │ 身份定义  │ 姓名、物种（AI/机器人等）、气质、emoji、头像                                              │
 ├──────────────┼──────────┼─────────────────────────────────────────────────────────────────────────────────────┤
 │ USER.md      │ 用户信息  │ 用户的名字、称呼、时区、喜好、项目背景等                                                   │
 ├──────────────┼──────────┼─────────────────────────────────────────────────────────────────────────────────────┤
 │ AGENTS.md    │ 使用手册  │ 最重要的文件 - 包含会话初始化流程、记忆系统说明、群组聊天规则、心跳任务、安全准则等               │
 ├──────────────┼──────────┼─────────────────────────────────────────────────────────────────────────────────────┤
 │ BOOTSTRAP.md │ 启动引导  │ 首次运行时的对话脚本，引导用户定义 agent 的身份。完成后应删除                                │
 ├──────────────┼──────────┼─────────────────────────────────────────────────────────────────────────────────────┤
 │ HEARTBEAT.md │ 定期任务  │ 定义周期性检查任务（邮件、日历、天气等）。空表示跳过心跳 API                                  │
 ├──────────────┼──────────┼─────────────────────────────────────────────────────────────────────────────────────┤
 │ TOOLS.md     │ 本地配置  │ 记录本地化配置如摄像头名称、SSH 主机、TTS 声音偏好等                                        │
 └──────────────┴──────────┴─────────────────────────────────────────────────────────────────────────────────────┘
```

多打磨：`SOUL.md`、`AGENTS.md`、`USER.md`
* 社区经验：“在 OpenClaw 中，稳定的规则放 `SOUL.md`，临时的任务放对话，积累的认知放 `MEMORY.md`”。

## 5. 进阶：搭建“一人团队”

`Open Claw` + `Claude Code`互补，针对需要代码理解、架构分析等编程任务，利用`Claude Code`来完成，用小龙虾管理多个智能体。

### 5.1. 分析设计

1、先分析下自己适用的场景：一台机器上部署多个OpenClaw实例，还是一个OpenClaw+多个Agent 更为合理？

结论：多Agent更适合当前使用，多个Agent的方式可以共享资源，通过workspace隔离逻辑；协作性更好，集中维护更便利。
* 多Agent适用场景：复杂、自动化的业务流：如一人开发团队（用`OpenClaw`编排`Claude Code`）、自动化投研、社交媒体运营等
* 多OpenClaw适用场景：安全需求特别高的隔离测试：测试不受信任的插件或代码，且希望一个测试环境的崩溃不影响主环境

2、设计角色：

main：默认agent，飞书角色：`小黑-管家`

新建4个Agent：
* 编程专家：负责架构设计、代码编写、审查、重构
  * 飞书角色：`Dev·技术匠`，agent名：`dev-agent`
* 学习助手：
  * 飞书角色：`Edu·伴学堂`，agent名：`research-agent`
* 写作助手
  * 飞书角色：`Wri·执笔人`，agent名：`writer-agent`
* 理财规划
  * 飞书角色：`Fin·财多多`，agent名：`finance-agent`

```sh
┌─────────────────────────────────────────────────────────────┐
│                        用户（飞书/其他）                       │
│             可以通过 小黑-管家 总机或直接与各 Agent 对话          │
└───────────────────────────┬─────────────────────────────────┘
                            │
                            ▼
┌──────────────────────────────────────────────────────────────────┐
│                         小黑-管家（Main Agent）                    │
│             • 意图识别与统一路由      • 对话管理与全局记忆             │
│             • 多 Agent 协作调度      • 权限控制与操作日志             │
└───────────┬────────────────┬────────────────┬────────────────┬───┘
            │                │                │                │
            ▼                ▼                ▼                ▼
┌──────────────────┐ ┌─────────────────┐ ┌─────────────────┐ ┌─────────────────┐
│   Dev·技术匠      │ │  Edu·伴学堂      │ │  Wri·执笔人      │ │  Fin·财多多      │
│  (编程专家)       │ │ (学习助手)        │ │ (写作助手)       │ │ (理财规划)       │
│ • 架构设计        │ │ • 知识调研        │ │ • 博客撰写       │ │ • 理财建议       │
│ • 代码编写/审查    │ │ • 技术答疑        │ │ • 文章润色       │ │ • 投资分析       │
│ • 重构/调试       │ │ • 学习计划        │ │ • 提纲生成       │ │ • 预算规划       │
│ • 调用Claude Code │ │ • 资料整理       │ │ • 多语言写作      │ │ • 财务报告       │
└──────────────────┘ └─────────────────┘ └─────────────────┘ └─────────────────┘
         │                  │                  │                  │
         └──────────────────┼──────────────────┴──────────────────┘
                            │
                            ▼
                  ┌─────────────────┐
                  │   Claude Code   │
                  │  (代码执行环境)  │
                  │   • 运行/测试代码 │
                  │   • 生成代码片段  │
                  │   • 调试辅助      │
                  └─────────────────┘
```

我做了归档，可见：[一人团队设计](https://github.com/xiaodongQ/ai-playground/blob/main/design/%E4%B8%80%E4%BA%BA%E5%9B%A2%E9%98%9F%E8%AE%BE%E8%AE%A1.md)

### 5.2. 实操搭建

> 可参考：[如何用OpenClaw + 飞书，组建一支"AI团队"](https://mp.weixin.qq.com/s/8FeVltwZYDq7x2Kq5KvunA)

1、创建编程专家agent：`openclaw agents add dev-agent`，按照页面提示操作，先跳过配置模型和IM频道（都选`No`）

会自动创建工作目录和sessions，并自动修改`openclaw.json`

```sh
┌  Add OpenClaw agent
│
◇  Workspace directory
│  /root/.openclaw/workspace-dev-agent
◇  Configure model/auth for this agent now?
│  No
◇  Configure chat channels now?
│  No
Config overwrite: /root/.openclaw/openclaw.json (sha256 9dcc766b666e9e8e0b7fd1b19f83f79ab83aba2f9b7d9fac6e94abd4f3d8648c -> 104771fc42718dc83402aff3f5d91f286d4fe84e620866f3c77e1bff13851253, backup=/root/.openclaw/openclaw.json.bak)
Updated ~/.openclaw/openclaw.json
Workspace OK: ~/.openclaw/workspace-dev-agent
Sessions OK: ~/.openclaw/agents/dev-agent/sessions
```

结果查看：  
1）可看到在`openclaw.json`配置的`"agents"`下面自动增加了`"list"`：
```sh
"list": [
<       {
<         "id": "main"
<       },
<       {
<         "id": "dev-agent",
<         "name": "dev-agent",
<         "workspace": "/root/.openclaw/workspace-dev-agent",
<         "agentDir": "/root/.openclaw/agents/dev-agent/agent"
<       }
<     ]
```

2）新建的agent下面也自动生成了相应的角色描述文件
```sh
[root@xdlinux ➜ .openclaw ]$ ll workspace-dev-agent
total 32K
-rw-r--r-- 1 root root 7.7K Mar  8 15:33 AGENTS.md
-rw-r--r-- 1 root root 1.5K Mar  8 15:33 BOOTSTRAP.md
-rw-r--r-- 1 root root  168 Mar  8 15:33 HEARTBEAT.md
-rw-r--r-- 1 root root  636 Mar  8 15:33 IDENTITY.md
-rw-r--r-- 1 root root 1.7K Mar  8 15:33 SOUL.md
-rw-r--r-- 1 root root  860 Mar  8 15:33 TOOLS.md
-rw-r--r-- 1 root root  477 Mar  8 15:33 USER.md
```

3）到飞书开放平台，进入开发者平台，再创建一个机器人。  
跟初次创建机器人一样的步骤，创建后在飞书上开通权限后（把“通讯录”、“消息与群组”、“云文档”和“多维表格”下面所有权限全开了），再设置事件回调发布（设置回调之前需要先在openclaw上配置好appid）。

4）到配置文件增加账号，配置完成后重启gateway（具体见：[如何用OpenClaw + 飞书，组建一支"AI团队"](https://mp.weixin.qq.com/s/8FeVltwZYDq7x2Kq5KvunA)）

* 由于之前是平铺的，需要增加一级`accounts`，把`appId`和`appSecret`移动过去。并把新账号的appId和密钥加进去，agent名为json对象名称
* 并且在`channels`同级，增加一层`binding`说明
* 并且在`tools`里面，增加`agentToAgent`使能和`sessions`可见

```json
"channels": {
  "feishu": {
    "enabled": true,
    "appId": "cli_xxxxxx",
    "appSecret": "1Rjxxxxxxxxxx"
    ...
  }
}

//  改成
"channels": {
  "feishu": {
    "enabled": true,
    "accounts": {
      "main": {
        "appId": "cli_xxxxxx",
        "appSecret": "1Rjxxxxxxxxxx",
      },
      "dev-agent": {
        "appId": "cli_xxxxxx",
        "appSecret": "1Rjxxxxxxxxxx",
      }
    }
    ...
  }
},
"bindings": [
  {
    "agentId": "main",
    "match": {
      "channel": "feishu",
      "accountId": "main"
    }
  },
  {
    "agentId": "dev-agent",
    "match": {
      "channel": "feishu",
      "accountId": "dev-agent"
    }
  }
],
"tools": {
  ...
  "agentToAgent": {
    "enabled": true,
    "allow": ["main", "dev-agent"]
  },
  "sessions": {
    "visibility": "all"
  }
},
```

2、其他角色类似，在飞书创建机器人后，可以让`OpenClaw`或者`Claude Code`来自动进行配置了

把它们都拉群里来：  
![feishu-openclaw](/images/2026-03-08-feishu-openclaw.png)

3、设置各自的人设：`SOUL.md`、`IDENTITY.md`

