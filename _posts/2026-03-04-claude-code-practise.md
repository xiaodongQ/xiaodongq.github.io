---
title: Claude Code系列 -- Claude Code实战手记
description: Claude Code实战手记，持续更新实践和技巧
categories: [AI, Claude Code系列]
tags: [AI, Claude Code]
pin: true
---

## 1. 引言

记录一些日常使用Claude Code的一些实用功能和小技巧，比如很实用的`/loop`循环，`Superpowers`、`claude-hud`插件，利用Hook机制来进行自动消息通知等。

## 2. 安装和基本使用

基本安装和配置就不单独说了，基本步骤：通过`npm install -g @anthropic-ai/claude-code`安装（可设置一下国内镜像源） -> 配置API。

## 3. 常用快捷键和操作

### 3.1. 快捷键和命令

快捷键：
* `Shift + Tab`快捷键循环切换`权限模式`
* `↑ / ↓` 浏览命令历史
* `Ctrl + A`	跳转到行首
* `Ctrl + E`	跳转到行尾
* `\` 行尾输入`\`后可多行输入，回车才发送所有消息
* 输入`!` 执行命令

命令：
* `/init`：在项目根目录生成 `CLAUDE.md` 文件，用于定义项目级指令和上下文。
* `/vim` 切换vim模式编辑
* `/status`：查看当前模型、API Key、Base URL 等配置状态
* `/clear`：清除对话历史，开始全新对话
* `/plan`：进入规划模式，仅分析和讨论方案，不修改代码（shift+tab快捷键更快）
* `/compact`：压缩对话历史，释放上下文窗口空间
* `/config`：打开配置菜单，可设置语言、主题等

### 3.2. 权限模式

跟Claude Code对话时，可以用`Shift + Tab`快捷键来循环切换`权限模式`：计划模式、自动接受模式。

也可以在配置文件`.claude/settings.json`里永久设置为默认，这里自动开启`接受编辑模式`：  
```sh
"permissions": {
    "defaultMode": "acceptEdits"
}
```

启用自动权限模式，则可：`claude --dangerously-skip-permissions`，为了方便可以在bashrc里设置一个别名：`alias claudecc="claude --dangerously-skip-permissions"`，但基于安全考虑，root用户下还是会提示是否接受。

![权限模式](/images/2026-03-06-claude-code-permission.png)

**精细控制权限**：我不想每次人工来点击一次接受修改，所以权限进行了下述修改，并安装了开源社区的`cc-safety-net`插件：`npm install -g cc-safety-net`，然后在 `.claude/settings.json` 中启用。
* 内置数百种危险模式识别
* 会区分rm -rf /tmp/cache（允许）vs rm -rf /（阻止）

```sh
{
  "permissions": {
    "mode": "acceptEdits",
    "allow": ["Bash(*)", "Edit(*)", "Write(*)"],
    "deny": [
      "Bash(rm -rf / *)",
      "Bash(git push --force)"
    ]
  },
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "npx -y cc-safety-net",
            "timeoutSec": 15
          }
        ]
      }
    ]
  }
}
```

### 3.3. 全局记忆设置

`/memory`设置记忆，可以选择全局级别还是当前项目级别。选择后会自动打开相应的`CLAUDE.md`文件，比如设置中文环境，增加：`与用户交流始终使用中文。`；也可以之间vim编辑相应`CLAUDE.md`文件。

![memory设置](/images/2026-03-06-claude-memory.png)

## 4. MCP、Skill和插件

### 4.1. 基本说明

`MCP (Model Context Protocol) `工具是 `Claude Code` 的扩展功能，可以为其添加各种第三方服务的能力。Claude Code 自带基础联网搜索功能，但通过 MCP 工具可以实现`深度搜索`、`地图服务`、`天气查询`等高级功能。

`Claude Code` 支持通过 `MCP` 和 `Skills` 扩展自身能力，例如调用联网搜索获取实时信息、使用图片理解 Skill 分析图像内容等。
* MCP：安装成熟的 MCP Server，连接外部服务。例如：添加联网搜索MCP。
* Skills：编写详细的 Skill 描述文案。Claude 决定是否调用该工具，取决于对该工具用途的定义。例如：添加视觉理解能力Skill。
* Skills vs MCP：Skills 教会 Claude “怎么做”（工作流知识），MCP 给 Claude“做的工具”（外部接口）。两者互补，Skills 也可集成外部接口。

### 4.2. Skills

Agent Skills（智能体技能）是将专业知识、工作流规范固化为可复用资产的核心工具。本质上是一个模块化的 Markdown 文件，能教会 AI 工具 （如 Claude、GitHub Copilot、Cursor 等） 执行特定任务，且支持自动触发、团队共享与工程化管理，彻底告别重复的提示词输入。

Agent Skills 的关键是**渐进式披露**，分三层加载：
* 层级 1：技能发现 -- AI 先读取所有技能的元数据（name 和 description），判断任务是否相关，这些元数据始终在系统提示中
* 层级 2：加载核心指令 -- 如果相关，AI 自动读取 SKILL.md 的正文内容，获取详细指导
* 层级 3：加载资源文件 -- 只在需要时读取额外文件（如脚本、示例），或通过工具执行脚本

#### 4.2.1. 手动添加Skill示例

借用阿里百炼的一个示例，添加一份Skill，添加视觉理解能力（部分模型可能已经默认具备视觉能力了，如`qwen3.5-plus`，这里假设切换的模型不支持）。

1、在项目目录（按需看是否要全局目录）的`.claude`目录中，新建`skills/image-analyzer`目录，`image-analyzer`即Skill名  
2、在该目录下创建`SKILL.md`文件，并写入下述内容

```yaml
---
name: image-analyzer
description: 帮助没有视觉能力的模型进行图像理解。当需要分析图像内容、提取图片中的信息、文字、界面元素，或理解截图、图表、架构图等任何视觉内容时，使用此技能，传入图片路径即可获得描述信息。
model: qwen3.5-plus
---
qwen3.5-plus具有视觉理解能力，请直接使用qwen3.5-plus模型进行图片理解。
```

目录结构如下（或放全局里），`claude`重新进入，`/skills`命令即可看到：`image-analyzer · ~26 description tokens`。直接在目录`~/.claude/skills`查看也可。

```sh
[root@xdlinux ➜ skills ]$ pwd
/root/.claude/skills
[root@xdlinux ➜ skills ]$ tree
.
└── image-analyzer
    └── SKILL.md
```

删除Skills：直接删除相应文件，`rm -rf /root/.claude/skills/<skill-name>`

#### 4.2.2. Skills编写最佳实践

为避免上下文膨胀，**推荐目录结构**：

* 核心规则 → SKILL.md。在 SKILL.md 中引用其他文件或者目录，比如md里说明：查看示例 `./examples/good-commit.txt`；运行脚本：使用工具执行 `./scripts/process.py`
* 详细资料 → 单独文件
* 实用逻辑 → 脚本执行（不加载）

```sh
my-skill/
├── SKILL.md
├── reference.md   # 存放参考文档，也可以增加一个 references 目录
├── examples.md    # 存放示例文件，也可以增加一个 examples 目录
└── scripts/
    └── helper.py
```

Skills 存放在 `~/.claude/skills/`（个人全局）或项目目录下的 `.claude/skills/`（项目专用）。

创建Skill后，Claude执行任务就会扫描已安装的 Skills，发现你的请求有涉及就会调用。

### 4.3. MCP

MCP可以是一个服务程序或者工具，在配置中告诉Claude Code可以使用它来扩展能力，比如联网、比如自定义一些私有的工具功能。

查看当前已安装的MCP工具：`claude mcp list`

添加：`claude mcp add <name> <command>`，（移除MCP：`claude mcp remove <name>`）

1、示例1，我实际用的MiniMax联网MCP，添加命令：`claude mcp add -s user MiniMax --env MINIMAX_API_KEY=xxxx --env MINIMAX_API_HOST=https://api.minimaxi.com -- uvx minimax-coding-plan-mcp -y`

而由于网络问题没自动安装成功，我是`pip install`安装工具后手动维护了MCP和配置，可见记录：[MiniMax MCP安装](https://xiaodongq.github.io/2026/04/14/ai-tools-minimax/)。原理一样的。

```sh
# vi ~/.claude.json
  "mcpServers": {
    "MiniMax": {
      "command": "/Users/xd/local_tool/minimax_mcp/bin/minimax-coding-plan-mcp",
      "type": "stdio",
      "args": [
        "-y"
      ],
      "env": {
        "MINIMAX_API_KEY": "sk-cp-KgOfCAZKyPH.....kIJk",
        "MINIMAX_API_HOST": "https://api.minimaxi.com"
      }
    }
```

2、示例2，自定义工具作为MCP：
* 第一步：本地写一个MCP服务器脚本（需要满足MCP协议要求的接口和交互方式），比如叫 my_tool.py
* 第二步：添加到 Claude Code，`claude mcp add my_tool python3 ~/my_mcp_tools/my_tool.py`

#### 4.3.1. 添加MCP：github CLI

1、从官方仓库`claude-plugins-official`里安装github MCP

2、安装CLI，见 [cli#installation](https://github.com/cli/cli#installation)

可以手动下载assets里面的bin程序，而后加到PATH。

```sh
[MacOS-xd@qxd ➜ tools ]$ gh version
gh version 2.92.0 (2026-04-28)
https://github.com/cli/cli/releases/tag/v2.92.0

# 一些操作（认证后可查看）
# 查看仓库信息
gh repo view                                     # 查看当前仓库 README
gh pr list                                       # 列出 PR
gh pr review 123 --approve                       # 批准 PR
gh issue list                                    # 列出 Issue
gh issue create                                  # 交互式创建
```

3、认证 `gh auth login`

```sh
[root@xdlinux ➜ repo ]$ gh auth login
? Where do you use GitHub? GitHub.com
? What is your preferred protocol for Git operations on this host? HTTPS
? How would you like to authenticate GitHub CLI? Paste an authentication token
Tip: you can generate a Personal Access Token here https://github.com/settings/tokens
The minimum required scopes are 'repo', 'read:org', 'workflow'.
? Paste your authentication token: *************************************************************************************- gh config set -h github.com git_protocol https
✓ Configured git protocol
! Authentication credentials saved in plain text
✓ Logged in as xiaodongQ
! You were already logged in to this account
```

**到GitHub创建token的方式**：

```
根据 GitHub 官方文档，以下是创建个人授权 Token 的步骤：

创建细粒度个人访问令牌（推荐）
GitHub 推荐使用细粒度个人访问令牌，更安全且权限控制更细：

进入设置：在 GitHub 右上角点击头像，选择 Settings（设置）

进入开发者设置：在左侧边栏点击 Developer settings（开发者设置）

选择令牌类型：在左侧边栏的 Personal access tokens（个人访问令牌） 下，点击 Fine-grained tokens（细粒度令牌）

生成新令牌：点击 Generate new token（生成新令牌）

配置令牌：

Token name：输入令牌名称
Expiration：设置过期时间
Description：（可选）添加说明
Resource owner：选择资源所有者（个人或组织）
Repository access：选择令牌可以访问的仓库
Permissions：选择具体权限（建议按最小权限原则设置）
生成：点击 Generate token（生成令牌） 后，立即复制并保存令牌（之后无法再查看）
```

### 4.4. 插件

**插件（Plugin）**是 Claude Code 中最高级别的扩展机制，用于将`command`、`agent`、`Skills`、`钩子`、`MCP`、`LSP` 等能力打包、版本化、共享和分发。

**插件 = 一组可复用的 Claude Code 扩展能力集合**

> 插件的核心目标只有一个：让 Claude Code 的能力像工具箱"一样被复用，而不是每个项目重复配置。**实现 "一次打包，多环境使用"**

* 什么时候用独立配置？个人使用、单项目、快速实验、想要简短命令名（如 /review）
* 什么时候用插件？团队共享、跨项目、版本化控制
* **最佳实践**：先在 `.claude/` 中迭代 → 稳定后打包为插件

可见：[Claude Code插件](https://www.runoob.com/claude-code/claude-code-plugins.html)

#### 4.4.1. 插件管理命令

```sh
/plugin                # 打开插件管理器
/plugin install         # 安装插件
/plugin uninstall       # 卸载
/plugin enable/disable  # 启用 / 禁用（回车后会进入选择页面）
/plugin marketplace add # 添加市场
/plugin marketplace rm  # 移除市场
```

添加插件：

在线方式：`/plugin marketplace add xxx`，而后`/plugin install xxx`

离线方式：以`claude-hud`为例

* 1、克隆 claude-hud 仓库，`git clone https://github.com/jarrodwatts/claude-hud.git`
* 2、添加仓库：`/plugin marketplace add 本地路径/claude-hud`
* 3、安装：`/plugin install claude-hud`

下面是几个推荐插件。

#### 4.4.2. 添加 Superpowers 插件

Superpowers 是一个 Claude Code 增强插件，安装后 AI 会自动获得一套完整的工作流技能——从需求分析、方案设计、代码编写到测试验证，全程自主完成。具体见：[Superpowers 插件](https://claude-zh.cn/guide/superpowers#superpowers-%E6%8F%92%E4%BB%B6)

```sh
# 1. 注册插件市场
/plugin marketplace add obra/superpowers-marketplace

# 2. 从市场安装 Superpowers
/plugin install superpowers@superpowers-marketplace
```

使用方式示例：
* `/brainstorming 描述你想做的事情`

Superpowers 会自动：
* 分析需求 — 和你确认功能细节和技术选型
* 制定计划 — 拆分任务，设计实现方案
* 编写代码 — 逐步实现每个功能模块
* 测试验证 — 运行测试确保代码正确
* 代码审查 — 自动检查代码质量

整个过程中 AI 会在关键节点询问你的意见，你只需要回答即可。

#### 4.4.3. 添加 claude-hud

提供实时会话状态监控（Token 用量、上下文进度、工具调用状态等）

> 除了在线安装，这里也补充下离线方式，见 [claude-hud-offline-install](https://github.com/xiaodongQ/ai-playground/blob/main/docs/claude-hud-offline-install.md)

```sh
# 1. 添加插件市场源（首次安装）
# 作用：将 claude-hud 的 GitHub 仓库添加为插件市场源
/plugin marketplace add jarrodwatts/claude-hud

# 2. 安装插件
/plugin install claude-hud

# 3. 初始化 HUD 配置
# 自动配置状态栏，启用 HUD 显示
/claude-hud:setup
# 会自动进行配置，执行后如下：
    # 我来帮你配置 claude-hud。首先让我检测一下当前的安装状态。
    # ● Bash(CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"   CACHE_EXISTS=$(ls -d "$CLAUDE_DIR/plugins/cache/claude-hud" 2>/dev/null && echo "YES" || echo "NO")…)
    #   ⎿  (eval):4: no matches found: /root/.claude/plugins/cache/temp_local_*  
    #      Cache: /root/.claude/plugins/cache/claude-hud
    #      YES | Registry: YES | Temp: none     
    # ...
    
```

安装成功验证：应显示 HUD 界面（底部状态栏）

观察会话底部出现：
* Token 计数器：显示当前上下文占用 Token 数
* 上下文进度条：直观显示上下文接近上限程度
* 工具调用状态：显示正在执行的工具及进度
* 任务进度：多步骤任务时显示完成百分比

状态显示项先都启用，效果如下：
* 能实时展示coding plan的进度情况，还是很方便的

![claude-hud状态栏效果](/images/2026-03-29-claude-code-hud.png)

另外，Claude Code的`/buddy`宠物展示，要取消的话，执行：`/buddy off`。

## 5. Claude Code 几个被低估的功能

实践一下这篇文章中，涉及的其中几个功能：[Claude Code 15 个被低估的功能，创建者亲述](https://mp.weixin.qq.com/s/dxIFKYaKhoCDcPaCn3x6MA)。

关于创始人`Boris Cherny`，可了解 [Claude Code 一周年：Boris Cherny 访谈中最值得开发者深思的 5 件事](https://www.ginonotes.com/posts/boris-cherny-insights-for-developers)。

### 5.1. 会话远程切换功能、Cowork Dispatch远程操控桌面端

自己用`happy-coder`，貌似不需要了。可见：[用手机远程控制Claude Code](https://xiaodongq.github.io/2026/04/01/happy-coder-remote-control/)

### 5.2. 定时自动化：`/loop` 和 `/schedule`

**（创始人说这是 Claude Code **<mark>最强大的两个功能</mark>**）

**Boris 的建议：把工作流变成 skill + loop 的组合**
* 这可能是整个帖子里最有想象力的部分，把 Claude 从“你问它答”变成了后台持续运行的自动化工人。
* 但有几个限制要注意：终端必须保持开启，`/loop` 任务最长跑三天（一周是通过桌面端的 /schedule 实现的）
* 另外，这种自动处理审查并推到生产的做法，前提是你有充分的测试覆盖，不建议在测试薄弱的项目里照搬。

```sh
 /loop 30s 随机提示                                                                                      
 我将设置一个每 30 秒执行的随机提示任务。                                                                
 根据规则，30s 需要向上取整到最近 1 分钟（cron 的最小粒度是 1 分钟）。所以我将其设置为每 1 分钟执行一次。
 CronCreate(* * * * *: 随机提示)                                                                         
 ⎿  Scheduled 58228574 (* * * * *)                                                                       
 已安排周期性任务：                                                                                      
 - Job ID: 58228574                                                         
 - Cron 表达式: * * * * *（每分钟）                                                                      
 - 说明: 原始间隔 30s 已向上取整到 1 分钟（cron 最小粒度）                                               
 - 过期时间: 7 天后自动删除                                                                              
 - 取消方式: 使用 CronDelete 并提供 Job ID 可提前取消                                                    
 现在执行提示：                                                                                          
─────────────────────────────────────────────────────────────────────────────────────────────────────────
✻ Running scheduled task (Apr 6 10:51pm)             
● 🎲 随机提示                                        
  尝试这个：重构一个你最近写过的函数，让它更简洁     
  ...
```

### 5.3. `Hooks`（钩子）：在代理生命周期中插入确定性逻辑

`SessionStart`：每次启动时动态加载上下文

`PreToolUse`：每次执行 bash 命令（工具）前记录日志

`PermissionRequest`：把权限请求发到IM，远程批准或拒绝

`Stop`：Claude 停下来时自动催它继续

只是说说没什么体感，可以见下面的应用小节：[主动通知](#74-主动通知)

### 5.4. 会话分叉

两种方式：在当前会话里运行 `/branch`，或从命令行运行 `claude --resume <session-id> --fork-session`

场景：探索不同方案时有用。让 Claude 做到一半，想试另一个方向，分叉出去两边互不影响。

```sh
❯ /branch 
  ⎿  Branched conversation. You are now in the branch.
     To resume the original: claude -r 4bc1ad63-b6e8-4835-b1a1-525247070857
❯ 你的上下文 （ =========== 说明：此处是问问题）
● 当前上下文：                                                              
  - 会话状态：已创建新分支 4bc1ad63-b6e8-4835-b1a1-525247070857             
  - 之前的工作：                                                            
    - 设置了一个每 30 秒（实际为每分钟）的随机提示循环任务                  
    - 执行了约 15 次随机提示（编码建议、重构提示、测试提示等）              
    - 你已取消该循环任务（Job ID: 58228574）                                
  - 当前目录：/root                                                         
  - 项目状态：非 git 仓库                                                   
  有什么想继续做的吗？                                                      
────────────────────────────────────────────────────────────────────────────
❯                                                                       
────────────────────────────────────────────────────────────────────────────
```

另外，在shell终端执行 `claude -r 4bc1ad63-b6e8-4835-b1a1-525247070857`，可恢复`/branch`之前会话的记录

### 5.5. `/btw`（即by the way）：边工作边问问题 

（这个平时用得多些）

Claude 执行任务的过程中，用 /btw 可以插入快速问题，不打断正在进行的工作。单轮问答，不会调用工具，但能看到当前会话的完整上下文。

### 5.6. `Git Worktrees`：并行开发的基础设施

Git 工作树（worktrees）允许你在同一个仓库里同时检出多个分支到不同目录，互不干扰。Claude Code 对工作树有深度支持。

### 5.7. `/batch`：大规模并行修改

`/batch` 先和你沟通需求，然后把任务扇出给多个工作树代理并行执行，数量可以是几十个、几百个甚至上千个。适用于大规模代码迁移和其他可并行化的工作。
* 前提是你的任务确实可以并行化，而且有足够的测试来验证批量修改没出问题。

未指定指令时会交互提示：

```sh
❯ /batch                                                                      
         
● 我需要了解您想要执行的批量更改。请提供具体的指令，描述您想要进行的批量修改。
                                                                              
  例如：                                                                      
  - 将项目中所有 .forEach 循环迁移到 for...of 语法                            
  - 将所有 var 声明替换为 const 或 let                                        
  - 为所有函数添加 JSDoc 注释                                                 
  - 将所有 CommonJS require 迁移到 ES6 import                                 
                                                                              
  您想要执行什么样的批量更改？                                                
                                                                              
──────────────────────────────────────────────────────────────────────────────
❯ /batch  <instruction>                                                       
```

### 5.8. `--bare`：SDK 启动提速最多 10 倍

写自动化脚本和 CI/CD 集成的人注意这条。加上 `--bare` 跳过不必要的配置加载，速度提升明显。

下面的 [headless模式](#71-headless模式) 小节里就可以用上该选项。

### 5.9. `--add-dir`：跨仓库工作

在一个仓库启动 Claude，用 `--add-dir`（或 `/add-dir`）让它看到并操作另一个仓库。

### 5.10. `--agent`：自定义代理

在 `.claude/agents` 目录下定义代理，用 `claude --agent=<名字>` 启动。可以给代理设定专属的系统提示词和工具集。

自定义代理的价值在于专业化。与其让一个通用 Claude 处理所有事，不如为代码审查、写测试、写文档各创建一个专用代理，每个加载不同的上下文和工具。这和前面 skill + loop 的思路是一脉相承的。

## 6. agent teams（智能体团队）

协调多个 Claude Code 实例作为一个团队一起工作，具有共享任务、代理间消息传递和集中管理。
* Agent teams 需要 Claude Code `v2.1.32` 或更高版本。使用 `claude --version` 检查版本。
* 本地版本：`2.1.97 (Claude Code)`

> Agent teams 是实验性功能，默认禁用。通过将 CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS 添加到你的 settings.json 或环境变量来启用它们。

### 6.1. 使用场景

Agent teams最适合用于并行探索能增加真实价值的任务：
* 研究和审查：多个队友同时调查问题的**不同方面**，然后**分享和质疑彼此的发现**
* 新模块或功能：各自拥有一个**独立**的部分
* **并行测试不同的理论**，更快地收敛到答案
* 跨层协调：**跨越前端、后端和测试**的更改，每个由不同的队友负责

注意：Agent teams 增加了协调开销，使用的token数量明显多于单个会话。

* **建议场景**：当队友可以**独立运作**时，它们效果最好。
* **不建议场景**：对于**顺序任务**、同一文件编辑或有许多**依赖关系**的工作，单个会话或 `subagents` 更有效。

Agent teams 和 subagents的对比可见：[协调 Claude Code 会话团队](https://code.claude.com/docs/zh-CN/agent-teams)
* Subagents 仅向主代理报告结果，彼此不交谈
* 在 agent teams 中，队友共享任务列表、认领工作并直接相互通信

### 6.2. 使用方式

配置文件`~/.claude/settings.json`中，设置环境变量。

```json
{
  "env": {
    "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1"
  }
}
```

对话直接让Claude Code创建团队即可，比如：`帮我创建一个团队各自分析当前仓库下的不同目录内容`，比顺序分析速度快很多

![agent teams示例](/images/2026-04-09-agent-teams.png)

### 6.3. 多agent各自显示窗格

这个功能比较酷炫，见上面参考链接的“选择显示模式”章节。

Agent teams 支持两种显示模式：
* `in-process`：所有队友在你的主终端内运行。使用 `Shift+Down` 循环浏览队友并输入以直接向他们发送消息。（试了笔记本上，用`上下键`即可，不用`shift`，状态栏会提示按键作用）
* `split panes`，每个队友获得自己的窗格。可以同时看到每个人的输出，并点击窗格直接交互。可以设置`tmux` 或 `iTerm2`。默认值是 "auto"，如果已经在 `tmux` 会话中运行，则使用分割窗格，否则使用 `in-process`。

配置文件里，注意是`~/.claude.json`，这里设置`tmux`（系统先安装）：

```json
{
  "teammateMode": "tmux"
}
```

主窗口会提示： view teammates: `tmux -L claude-swarm-1001179 a`

开一个新终端执行`tmux -L claude-swarm-1001179 a`，效果如下：  
![agent-teams-tmux](/images/2026-04-09-agent-teams-tmux.png)

## 7. 常见工作流技巧（202604更新）

具体参考官方文档：[常见工作流程](https://code.claude.com/docs/zh-CN/common-workflows)

列出并使用了几个，都是很实用的功能。

### 7.1. headless模式

headless模式（无头模式）：`claude -p xxx`，进一步信息可见官网文档：[headless模式](https://code.claude.com/docs/zh-CN/headless)
* 在 Plan Mode 中运行”无头”查询，`claude --permission-mode plan -p "Analyze the authentication system and suggest improvements"`
* **脚本集成**，如：`cat build-error.txt | claude -p 'concisely explain the root cause of this build error' > output.txt`

临时性的工作，headless方式很方便，可简化这个操作：`claude`启动后->信任目录->临时工作 -> `/exit`退出Claude Code。

```sh
[root@xdlinux ➜ ~ ]$ claude -p 查看当前npm安装了哪些包 --allowedTools "Bash,Read,Edit"
当前 `/root` 目录下没有安装任何npm包（目录是空的）。
如果你想在其他位置查看，可以告诉我具体路径，或者如果你是想查看全局安装的包，可以运行：
npm list -g --depth=0
```

#### 7.1.1. 自动批准工具：`--allowedTools`参数

可以`--allowedTools`指定自动批准工具，让Claude Code使用某些工具而无需提示：  
```sh
[root@xdlinux ➜ ~ ]$ claude -p 查看当前npm安装了哪些包 --allowedTools "Bash,Read,Edit"
**当前目录**：没有本地安装的npm包

**全局安装的包**（共15个）：

| 包名                      | 版本    |
| ------------------------- | ------- |
| @anthropic-ai/claude-code | 2.1.101 |
| @tarojs/cli               | 4.1.11  |
| @twsxtd/hapi              | 0.16.5  |
...

如果需要查看特定包的详细信息或依赖树，可以告诉我。
```

#### 7.1.2. 继续对话： `-c`/`--continue`参数

```sh
[root@xdlinux ➜ ~ ]$ claude -p 查看当前npm安装了哪些包 --allowedTools "Bash,Read,Edit"
当前环境：
- 无 `package.json` 文件
- 无任何 npm 全局包
...

[root@xdlinux ➜ ~ ]$ claude -p 你记得上一步做了什么吗
这是我们对话的开始，我还没有执行过任何操作。请问有什么我可以帮你的吗？
```

而加了`-c`或者`--continue`，可以连续性对话：  
```sh
[root@xdlinux ➜ ~ ]$ claude -p 你记得上一步做了什么吗 -c
是的，记得上一步：

1. 你问"查看当前npm安装了哪些包"
2. 我执行了 `npm list --depth=0` 命令
...
```

### 7.2. Thinking Mode（思考/努力级别）

思考默认启用，可输入`/effort`来调整思考级别，复杂任务可以调高一点，也可设置自动调整：

```sh
❯ /effort  [low|medium|high|max|auto]
─────────────────────────────────────────────
```

### 7.3. 在git仓库目录并行独立任务：`--worktree`

同一个git仓库目录，各自启动任务，修改是在不同分支：
* 若不指定分支名则会自动生成一个随机名称

```sh
# 在名为 "feature-auth" 的 worktree 中启动 Claude
# 创建 .claude/worktrees/feature-auth/ 和新分支
claude --worktree feature-auth

# 在单独的 worktree 中启动另一个会话
claude --worktree bugfix-123
```

### 7.4. 主动通知

> 具体可见：[在 Claude 需要您的注意时获得通知](https://code.claude.com/docs/zh-CN/common-workflows#%E5%9C%A8-claude-%E9%9C%80%E8%A6%81%E6%82%A8%E7%9A%84%E6%B3%A8%E6%84%8F%E6%97%B6%E8%8E%B7%E5%BE%97%E9%80%9A%E7%9F%A5)。

在工作环境中，基于全局记忆 + 钉钉的通知MCP，实现了完成任务或者需要我确认时发送钉钉通知，但是触发是基于LLM来判断的，有时并不准确。Claude Code提供的hook机制，可以指定**匹配到固定规则**时触发动作。

1、方式1：手动在`.claude/settings.json` 里增加通知机制：
* MacOS用`osascript`通知
* Linux用`notify-send`通知
* Windows下用`powershell`来调用`MessageBox`进行通知

```sh
# ~/.claude/settings.json
{
  ...
  "hooks": {
    "Notification": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "command": "osascript -e 'display notification \"Claude Code needs your attention\" with title \"Claude Code\"'"
          }
        ]
      }
    ]
  }
}
```

Notification的matcher可指定（保留为空则不匹配，都会进行通知。不同hook的matcher是不同的）：  
```sh
匹配器              触发时机
permission_prompt  Claude 需要您批准工具使用
idle_prompt        Claude 完成并等待您的下一个提示
auth_success       身份验证完成
elicitation_dialog Claude 在问您一个问题
```

2、方式2：也可以描述想要的内容来要求Claude自动编写 hook）

#### 7.4.1. Notification hook实验和通知效果

`hooks`里添加`Notification`规则（Claude Code里支持的Hook事件之一），里面又可以设置多个hooks规则，下面添加了2个hook，并且各自匹配不同场景：`idle_prompt`空闲情况、`permission_prompt`需批准权限的情况。通知的标题可以按需自行定义。

```sh
# ~/.claude/settings.json
  "permissions": {
    "defaultMode": "acceptEdits",
    # 临时删除这句
    # "allow": ["Bash(*)", "Edit(*)", "Write(*)"],
    "deny": [
      "Bash(rm -rf / *)",
      "Bash(git push --force)"
    ]
  },
  ...
  "hooks": {
    "Notification": [
      {
        "matcher": "idle_prompt",
        "hooks": [
          {
            "type": "command",
            "command": "osascript -e 'display notification \"Claude 完成并等待您的下一个提示\" with title \"Claude Code完成通知\"'"
          }
        ]
      },
      {
        "matcher": "permission_prompt",
        "hooks": [
          {
            "type": "command",
            "command": "osascript -e 'display notification \"Claude Code需要批准权限\" with title \"Claude Code需要批准权限\"'"
          }
        ]
      }
    ]
  }
```

当需要批准权限时，就会有系统通知：  
![claude-hook-notify](/images/2026-04-19-claude-hook-notify.png)

当需要完成任务时，就通知完成：  
![claude-done-notify](/images/2026-04-19-claude-done-notify.png)

#### 7.4.2. Claude支持的Hooks事件

上面的通知Hook是Claude Code支持的Hooks事件之一，所有支持的事件具体可见：[Hooks事件参考](https://code.claude.com/docs/zh-CN/hooks)。用法原理跟`Notification`是类似的，不同hook事件的参数有所区别，结合起来使用非常强大，每类事件具体说明和用法见参考链接。

Claude Code会话周期各个阶段支持的hooks事件，示意图：  
![hooks-lifecycle](/images/hooks-lifecycle.svg)

`/hooks`命令可以查看当前支持和配置的hooks事件

```sh
 /hooks
─────────────────────────────────────────────────────────
  Hooks
  1 hook configured

  ℹ This menu is read-only. To add or modify hooks, edit settings.json directly or ask Claude. Learn more

  ❯ 1.  PreToolUse          Before tool execution
    2.  PostToolUse         After tool execution
    3.  PostToolUseFailure  After tool execution fails
    4.  PermissionDenied    After auto mode classifier denies a tool call
  ↓ 5.  Notification (1)    When notifications are sent

  Enter to confirm · Esc to cancel
```
