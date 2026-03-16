---
title: AI能力集 -- Claude Code实战手记
description: Claude Code实战手记，持续更新实践和技巧
categories: [AI, AI能力集]
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

## 3. 快捷键小技巧

可参考（经常翻翻）：[Claude Code 常用技巧](https://docs.bigmodel.cn/cn/coding-plan/best-practice/claude-code)

### 3.1. 权限模式

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

### 3.2. 全局记忆设置

`/memory`设置记忆，可以选择全局级别还是当前项目级别。选择后会自动打开相应的`CLAUDE.md`文件，比如设置中文环境，增加：`与用户交流始终使用中文。`；也可以之间vim编辑相应`CLAUDE.md`文件。

[memory设置](/images/2026-03-06-claude-memory.png)

### 3.3. 常见命令

* `/init`：在项目根目录生成 `CLAUDE.md` 文件，用于定义项目级指令和上下文。
    * 会记录：常用的 bash 命令、核心代码文件、实用函数、代码风格信息
    * 另外可以手动在`CLAUDE.md`里面，用markdown语法增加`项目特定规则`，用不同级别的`#`增加相应小结进行规则说明
* `/status`：查看当前模型、API Key、Base URL 等配置状态
* `/clear`：清除对话历史，开始全新对话
* `/plan`：进入规划模式，仅分析和讨论方案，不修改代码
* `/compact`：压缩对话历史，释放上下文窗口空间
* `/config`：打开配置菜单，可设置语言、主题等

## 4. MCP配置

`MCP (Model Context Protocol) `工具是 `Claude Code` 的扩展功能，可以为其添加各种第三方服务的能力。Claude Code 自带基础联网搜索功能，但通过 MCP 工具可以实现`深度搜索`、`地图服务`、`天气查询`等高级功能。

`Claude Code` 支持通过 `MCP` 和 `Skills` 扩展自身能力，例如调用联网搜索获取实时信息、使用图片理解 Skill 分析图像内容等。
* MCP：安装成熟的 MCP Server，连接外部服务。例如：添加联网搜索MCP。
* Skills：编写详细的 Skill 描述文案。Claude 决定是否调用该工具，取决于对该工具用途的定义。例如：添加视觉理解能力Skill。
* Skills vs MCP：Skills 教会 Claude “怎么做”（工作流知识），MCP 给 Claude“做的工具”（外部接口）。两者互补，Skills 也可集成外部接口。

查看当前已安装的MCP工具：`claude mcp list`

### 4.1. 添加MCP示例

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

### 4.2. 添加Skill示例

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

目录结构如下（我放在了全局里），`claude`重新进入，`/skills`即可看到：`image-analyzer · ~26 description tokens`

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





