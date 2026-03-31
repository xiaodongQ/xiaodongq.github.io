---
title: Claude Code系列 -- Claude Code实战手记
description: Claude Code实战手记，持续更新实践和技巧
categories: [AI, Claude Code系列]
tags: [AI, Claude Code]
---

## 1. 引言

Claude Code实战手记，持续更新实践和技巧。

## 2. 安装和基本使用

基本安装和配置就不单独说了，基本步骤：通过`npm`安装（可设置一下国内镜像源） -> 配置API。具体步骤可见：[Claude Code安装和使用](https://github.com/xiaodongQ/devNoteBackup/blob/master/%E5%90%84%E5%88%86%E7%B1%BB%E8%AE%B0%E5%BD%95/AI%E5%A4%A7%E6%A8%A1%E5%9E%8B%E5%AD%A6%E4%B9%A0%E7%AC%94%E8%AE%B0.md#%E5%AE%89%E8%A3%85)。

执行`claude`即可执行：

```sh
╭─── Claude Code v2.1.63 ──────────────────────────────────────────────────────────────────────────────────╮
│                                      │ Tips for getting started                                          │
│             Welcome back!            │ Run /init to create a CLAUDE.md file with instructions for Claude │
│                                      │ ───────────────────────────────────────────────────────────────── │
│                ▐▛███▜▌               │ Recent activity                                                   │
│               ▝▜█████▛▘              │ No recent activity                                                │
│                 ▘▘ ▝▝                │                                                                   │
│                                      │                                                                   │
│   qwen3.5-plus · API Usage Billing   │                                                                   │
│                /home                 │                                                                   │
╰──────────────────────────────────────────────────────────────────────────────────────────────────────────╯

  /model to try Opus 4.6

──────────────────────────────────────────────────────────────────────────────────────────
❯  
```

## 3. 快捷键和技巧

可参考（经常翻翻）：[Claude Code 常用技巧](https://docs.bigmodel.cn/cn/coding-plan/best-practice/claude-code)

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
    * 会记录：常用的 bash 命令、核心代码文件、实用函数、代码风格信息
    * 另外可以手动在`CLAUDE.md`里面，用markdown语法增加`项目特定规则`，用不同级别的`#`增加相应小结进行规则说明
* `/vim` 切换vim模式编辑
* `/status`：查看当前模型、API Key、Base URL 等配置状态
* `/clear`：清除对话历史，开始全新对话
* `/plan`：进入规划模式，仅分析和讨论方案，不修改代码
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

[memory设置](/images/2026-03-06-claude-memory.png)

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

这里添加一份Skill，添加视觉理解能力（部分模型可能已经默认具备视觉能力了，如`qwen3.5-plus`，这里假设切换的模型不支持）。

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

目录结构如下（或放全局里），`claude`重新进入，`/skills`即可看到：`image-analyzer · ~26 description tokens`

```sh
[root@xdlinux ➜ skills ]$ pwd
/root/.claude/skills
[root@xdlinux ➜ skills ]$ tree
.
└── image-analyzer
    └── SKILL.md
```

删除Skills：直接删除相应文件，`rm -rf /root/.claude/skills/<skill-name>`

参考自：[百炼 -- 添加视觉理解能力](https://help.aliyun.com/zh/model-studio/add-vision-skill?spm=a2c4g.11186623.help-menu-2400256.d_0_2_3_1.51165152hkJMsy&scm=20140722.H_3023166._.OR_help-T_cn~zh-V_1)

#### 4.2.2. Skills编写最佳实践

为避免上下文膨胀，**推荐目录结构**：

* 核心规则 → SKILL.md
  * 在 SKILL.md 中引用其他文件或者目录，比如md里说明：
    * 查看示例 commit：./examples/good-commit.txt
    * 运行脚本：使用工具执行 ./scripts/process.py
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

查看当前已安装的MCP工具：`claude mcp list`

**手动添加MCP示例：**

在MCP广场找到MCP（暂时用阿里百炼里的MCP），开通并添加：
`claude mcp add WebSearch https://dashscope.aliyuncs.com/api/v1/mcps/WebSearch/mcp -t http -H "Authorization: Bearer sk-sp-xxxxxxxxxxxx(相应的API Key)"`

```sh
[root@xdlinux ➜ tmpdir ]$ claude mcp add WebSearch https://dashscope.aliyuncs.com/api/v1/mcps/WebSearch/mcp -t http -H "Authorization: Bearer sk-sp-1xxxxxxxxxxxxxxxxxxxx"
Added HTTP MCP server WebSearch with URL: https://dashscope.aliyuncs.com/api/v1/mcps/WebSearch/mcp to local config
Headers: {
  "Authorization": "Bearer sk-sp-1xxxxxxxxxxxxxxxxxxxxx"
}
File modified: /root/.claude.json [project: /home/workspace/tmpdir]
```

`/root/.claude.json`文件里，可以看到：  
```sh
    "/home/workspace/tmpdir": {
      "allowedTools": [],
      "mcpContextUris": [],
      "mcpServers": {
        "WebSearch": {
          "type": "http",
          "url": "https://dashscope.aliyuncs.com/api/v1/mcps/WebSearch/mcp",
          "headers": {
            "Authorization": "Bearer sk-sp-1xxxxxxxxxxxxxxxxxxx"
          }
        }
      },
```

删除MCP：`claude mcp remove WebSearch`

参考自：[百炼 -- 添加联网搜索MCP](https://help.aliyun.com/zh/model-studio/web-search-for-coding-plan?spm=a2c4g.11186623.help-menu-2400256.d_0_2_3_0.52807719hn0Yus)

### 4.4. 插件

**插件（Plugin）**是 Claude Code 中最高级别的扩展机制，用于将`command`、`agent`、`Skills`、`钩子`、`MCP`、`LSP` 等能力打包、版本化、共享和分发。

**插件 = 一组可复用的 Claude Code 扩展能力集合**

> 插件的核心目标只有一个：让 Claude Code 的能力像工具箱"一样被复用，而不是每个项目重复配置。**实现 "一次打包，多环境使用"**

* 什么时候用独立配置？
  * 个人使用、单项目、快速实验、想要简短命令名（如 /review）
* 什么时候用插件？
  * 团队共享、跨项目、版本化控制
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
* 在线方式：`/plugin marketplace add xxx`，而后`/plugin install xxx`
* 离线方式：以`claude-hud`为例
  * 1、克隆 claude-hud 仓库
    * `git clone https://github.com/jarrodwatts/claude-hud.git`
  * 2、添加仓库：`/plugin marketplace add 本地路径/claude-hud`
  * 3、安装：`/plugin install claude-hud`

下面是几个推荐插件。

#### 4.4.2. Superpowers 插件

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

#### 4.4.3. claude-hud

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


## 参考

* [菜鸟教程 -- Agent Skills（智能体技能）](https://www.runoob.com/claude-code/claude-agent-skills.html)