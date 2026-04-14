---
title: AI能力集 -- MiniMax能力补充：MCP和Skills
description: MiniMax能力补充，安装MCP和Skills
categories: [AI, AI能力集]
tags: [AI, Skills]
---

## 1. 引言

最近换了Minimax的token plan，支持生图和语音，这里来补充安装下MiniMax官方提供的`MCP`和`Skills`。

## 2. MiniMax MCP

### 2.1. 安装和使用

使用前把Minimax的MCP安装一下，包括`web_search`和`understand_image`，[图片理解 & 网络搜索 MCP](https://platform.minimaxi.com/docs/token-plan/mcp-guide)。模型会按需使用。

文档写得不好，里面就一行`claude mcp add -s user MiniMax --env MINIMAX_API_KEY=api_key --env MINIMAX_API_HOST=https://api.minimaxi.com -- uvx minimax-coding-plan-mcp -y`，但看网上很多人都安装失败了。

debug模式启动claude code，日志输出在`~/.claude/debug/9d0f3bdf-a880-4206-8894-07122e5c83ba.txt`，`/mcp`查看状态并跟踪日志。错误是没找到`minimax-coding-plan-mcp`和`python`

```sh
# 如果其他环境有问题，也可以开debug查看原因
[MacOS-xd@qxd ➜ tmp_baoyu ]$ claude --debug
  Debug mode enabled
  Logging to: /Users/xd/.claude/debug/9d0f3bdf-a880-4206-8894-07122e5c83ba.txt
❯ /mcp
  ⎿  Failed to reconnect to MiniMax.

# 查看日志
[MacOS-xd@qxd ➜ repo ]$ tail -F /Users/xd/.claude/debug/9d0f3bdf-a880-4206-8894-07122e5c83ba.txt
2026-04-13T23:31:06.186Z [DEBUG] MCP server "MiniMax": Starting connection with timeout of 30000ms
2026-04-13T23:31:06.195Z [DEBUG] High write ratio: blit=0, write=1009 (100.0% writes), screen=26x120
2026-04-13T23:31:06.196Z [DEBUG] Full reset (shrink->below): prevHeight=32, nextHeight=26, viewport=29
2026-04-13T23:31:06.410Z [ERROR] MCP server "MiniMax" Server stderr: /Users/xd/.cache/uv/archive-v0/8E_BBCjaWcPs8z6JjzZHT/bin/minimax-coding-plan-mcp: line 2: realpath: command not found
/Users/xd/.cache/uv/archive-v0/8E_BBCjaWcPs8z6JjzZHT/bin/minimax-coding-plan-mcp: line 2: /Users/xd/Documents/workspace/repo/tmp_baoyu/python: No such file or directory
/Users/xd/.cache/uv/archive-v0/8E_BBCjaWcPs8z6JjzZHT/bin/minimax-coding-plan-mcp: line 2: exec: /Users/xd/Documents/workspace/repo/tmp_baoyu/python: cannot execute: No such file or directory
2026-04-13T23:31:06.410Z [DEBUG] MCP server "MiniMax": Connection failed after 226ms: MCP error -32000: Connection closed
2026-04-13T23:31:06.412Z [ERROR] MCP server "MiniMax" Connection failed: MCP error -32000: Connection closed
```

MCP其实是一个服务程序，自己手动安装下并修改claude配置里的调用路径：

```sh
[MacOS-xd@qxd ➜ local_tool ]$ python -m venv minimax_mcp
[MacOS-xd@qxd ➜ local_tool ]$ cd minimax_mcp
[MacOS-xd@qxd ➜ minimax_mcp ]$ ls
bin        include    lib        pyvenv.cfg
[MacOS-xd@qxd ➜ minimax_mcp ]$ source bin/activate
(minimax_mcp) [MacOS-xd@qxd ➜ minimax_mcp ]$ pip install minimax-coding-plan-mcp
Collecting minimax-coding-plan-mcp
  Downloading minimax_coding_plan_mcp-0.0.4-py3-none-any.whl.metadata (12 kB)
...
[notice] A new release of pip is available: 25.2 -> 26.0.1
[notice] To update, run: pip install --upgrade pip
```

```sh
# vi ~/.claude.json
  "mcpServers": {
    "MiniMax": {
      "type": "stdio",
      "command": "/Users/xd/local_tool/minimax_mcp/bin/minimax-coding-plan-mcp",
      "args": [
        "-y"
      ],
      "env": {
        "MINIMAX_API_KEY": "sk-cp-KgOfCAZKyPH.....kIJk",
        "MINIMAX_API_HOST": "https://api.minimaxi.com"
      }
    }
```

再重新连接就可以了：

```sh
❯ /mcp
──────────────────────────────────────
  Manage MCP servers
  1 server
    User MCPs (/Users/xd/.claude.json)
  ❯ MiniMax · ✔ connected

  https://code.claude.com/docs/en/mcp for help
 ↑↓ to navigate · Enter to confirm · Esc to cancel
```

我的另一个环境报错，ls查看文件不存在，是我路径拷贝错了：

```sh
2026-04-14T15:20:55.475Z [DEBUG] MCP server "MiniMax": Starting connection with timeout of 30000ms
2026-04-14T15:20:55.479Z [DEBUG] MCP server "MiniMax": Connection failed after 5ms: spawn /Users/xd/local_tool/minimap_mcp/bin/minimax-coding-plan-mcp ENOENT
2026-04-14T15:20:55.479Z [ERROR] MCP server "MiniMax" Connection failed: spawn /Users/xd/local_tool/minimap_mcp/bin/minimax-coding-plan-mcp ENOENT
```

### 2.2. MCP实现流程

1、server.py - MCP服务入口

```py
mcp = FastMCP("Minimax", log_level=fastmcp_log_level)
api_client = MinimaxAPIClient(api_key, api_host)
使用 FastMCP 框架注册工具
从环境变量读取 MINIMAX_API_KEY 和 MINIMAX_API_HOST
定义两个 @mcp.tool() 装饰的函数
```

2、client.py - API客户端基类

```py
def _make_request(self, method, endpoint, **kwargs):
    # 1. 根据 files 参数决定 Content-Type
    # 2. 发送请求并检查 raise_for_status()
    # 3. 解析JSON，检查 base_resp.status_code
    #    - 0: 成功
    #    - 1004: 认证错误 → MinimaxAuthError
    #    - 2038: 需实名认证 → MinimaxRequestError
    #    - 其他: 通用错误
```

3、utils.py - 图像处理 (process_image_url)

支持三种输入格式的图像处理流程：

```
输入 image_source
    │
    ├── "@..." 前缀 ──→ 去掉@前缀
    │
    ├── "data:..." ──→ 直接返回 (base64透传)
    │
    ├── "http(s)://..." ──→ requests.get() → base64 → data:image/{format};base64,{data}
    │
    └── 本地路径 ──→ os.path.exists() → 读取文件 → base64 → data:image/{format};base64,{data}
格式检测逻辑：

HTTP图片：通过 content-type 响应头检测
本地文件：通过文件扩展名 (.png/.jpg/.webp) 检测
```

## 3. MiniMax Skills安装和使用

### 3.1. Skills安装

[MiniMax-AI/skills中文说明](https://github.com/MiniMax-AI/skills/blob/main/README_zh.md)

```sh
# clone或者下载minimax的skill仓库
git clone https://github.com/MiniMax-AI/skills.git

# 添加插件市场（此处是下载后解压在minimax-ai_skills-main目录）
claude plugin marketplace add /Users/xd/Documents/workspace/repo/minimax-ai_skills-main

# 安装minimax skills
claude plugin install minimax-skills
```

这些skill很多依赖`mmx-cli`，进行安装：

```sh
# 安装mmx-cli
[MacOS-xd@qxd ➜ _posts ]$ npm install -g mmx-cli
added 5 packages in 2s
1 package is looking for funding
  run `npm fund` for details

# cli登录后可以看到用量情况
[MacOS-xd@qxd ➜ _posts ]$ mmx auth login --api-key sk-cp-KgOfCAZKyPH_o4Gxxxxx
Detecting region... cn
Testing key... MINIMAX ~/.mmx/config.json | Region: global (default) | Key: sk-c...kIJk (flag)
Valid
API key saved to /Users/xd/.mmx/config.json

╭─────────────────────────────────────────────────────────────────────────╮
│ MINIMAX  TokenPlan 配额面板                 周期: 2026-04-12 — 2026-04-19 │
├─────────────────────────────────────────────────────────────────────────┤
│ MiniMax-M*                            20 / 1,500                     1% │
│   └ 每周 346 / 15,000                                       重置于 1h 44m │
├─────────────────────────────────────────────────────────────────────────┤
│ speech-hd                              0 / 4,000                     0% │
│   └ 每周 0 / 28,000                                         重置于 1h 44m │
├─────────────────────────────────────────────────────────────────────────┤
│ MiniMax-Hailuo-2.3-Fast-6s-768p            0 / 0                     0% │
│   └ 每周 0 / 0                                              重置于 1h 44m │
├─────────────────────────────────────────────────────────────────────────┤
│ MiniMax-Hailuo-2.3-6s-768p                 0 / 0                     0% │
│   └ 每周 0 / 0                                              重置于 1h 44m │
├─────────────────────────────────────────────────────────────────────────┤
│ music-2.5                                  0 / 0                     0% │
│   └ 每周 0 / 0                                              重置于 1h 44m │
├─────────────────────────────────────────────────────────────────────────┤
│ music-2.6                                0 / 100                     0% │
│   └ 每周 0 / 700                                            重置于 1h 44m │
├─────────────────────────────────────────────────────────────────────────┤
│ music-cover                              0 / 100                     0% │
│   └ 每周 0 / 700                                            重置于 1h 44m │
├─────────────────────────────────────────────────────────────────────────┤
│ lyrics_generation                        0 / 100                     0% │
│   └ 每周 0 / 700                                            重置于 1h 44m │
├─────────────────────────────────────────────────────────────────────────┤
│ image-01                                  2 / 50                     4% │
│   └ 每周 14 / 350                                           重置于 1h 44m │
├─────────────────────────────────────────────────────────────────────────┤
│ coding-plan-vlm                          0 / 150                     0% │
│   └ 每周 346 / 15,000                                       重置于 1h 44m │
├─────────────────────────────────────────────────────────────────────────┤
│ coding-plan-search                       0 / 150                     0% │
│   └ 每周 346 / 15,000                                       重置于 1h 44m │
╰─────────────────────────────────────────────────────────────────────────╯
```

### 3.2. 生成图片示例效果1（不满意）

基于博客文章：[Claude Code系列 -- CC-Switch和CLIProxyApi组合共享API](https://xiaodongq.github.io/2026/04/12/ai-tools-openrouter-cc-switch/)生成配图

```sh
 /minimax-skills:minimax-multimodal-toolkit 帮我基于 _posts/2026-04-12-ai-tools-openrouter-cc-switch.md 进行配图

⏺ Bash(mmx image generate \
        --prompt "A futuristic tech illustration showing CC-Switch as a central control dashboard/hub, connecting
      multiple AI model icons (Claude…)
  ⎿  images/2026-04-12-ai-tools-openrouter-cc-switch-cover_001.jpg
  ⎿  (timeout 3m)
⏺ 配图已生成！
  文件: images/2026-04-12-ai-tools-openrouter-cc-switch-cover_001.jpg
  使用 mmx + MiniMax image-01 生成，深蓝色渐变背景，展示 CC-Switch 中央控制面板连接多个 AI 模型的整体架构图。

✻ Sautéed for 33s
```

生成封面效果（稍微能看）：  
![ai-tools-openrouter-cc-switch-cover](/images/2026-04-12-ai-tools-openrouter-cc-switch-cover_001.jpg)

### 3.3. 生成图片示例效果2（拉胯）

```sh
_posts/2026-04-12-ai-tools-openrouter-cc-switch.md 生成架构图

⏺ Bash(mmx image generate \
        --prompt "A clean technical architecture diagram for AI model proxy and switch system. Layout from left to
      right:…)
  ⎿  images/2026-04-12-openrouter-cc-switch-architecture_001.jpg
  ⎿  (timeout 3m)
⏺ 架构图已生成：
  文件: images/2026-04-12-openrouter-cc-switch-architecture_001.jpg
  展示整体架构：
  - 左侧: Claude Code、IDE、Codex CLI、Gemini CLI 等应用
  - 中央: CC-Switch 配置管理器 + CLIProxyApi 代理服务器（含故障转移、负载均衡）
  - 右侧: OpenRouter 统一网关连接多个 AI 提供商（Claude、GPT-4、Gemini、DeepSeek、Qwen 等）

  配色：蓝色 CC-Switch、绿色 CPA、紫色 OpenRouter、橙色 AI 提供商。
```

效果如下：看不清字。。。  
![cc-switch-architecture_001](/images/2026-04-12-openrouter-cc-switch-architecture_001.jpg)

### 3.4. 生成图片示例效果3（继续拉胯）

不用他家的skill，用`baoyu-imagine`试下（但模型一样，没办法）

```sh
 用baoyu skill来生成架构图
⏺ Bash(test -f "$HOME/.baoyu-skills/baoyu-imagine/EXTEND.md" && cat "$HOME/.baoyu-skills/baoyu-imagine/EXTEND.md" ||
      echo "EXTEND.md not found")
  ⎿  EXTEND.md not found
⏺ Bash(npx -y bun /Users/xd/Documents/workspace/repo/baoyu-skills-main/skills/baoyu-imagine/scripts/main.ts \
        --prompt "A clean technical architecture diagram for AI…)
  ⎿  Error: Exit code 1
     Using dashscope / qwen-image-2.0-pro for single
     Switch model: --model <id> | EXTEND.md default_model.dashscope | env DASHSCOPE_IMAGE_MODEL
     DASHSCOPE_API_KEY is required
⏺ ...
⏺ baoyu-imagine 没有配置 DASHSCOPE_API_KEY，但我可以用 MiniMax（已配置好）来生成：
⏺ Bash(npx -y bun /Users/xd/Documents/workspace/repo/baoyu-skills-main/skills/baoyu-imagine/scripts/main.ts \
        --prompt "A clean technical architecture diagram for AI…)
  ⎿  Using minimax / image-01 for single
     Switch model: --model <id> | EXTEND.md default_model.minimax | env MINIMAX_IMAGE_MODEL
     {
     … +8 lines (ctrl+o to expand)
  ⎿  (timeout 3m)
⏺ 架构图已生成：
  文件: images/2026-04-12-openrouter-cc-switch-architecture-diagram.png
  Provider: MiniMax / image-01

  使用 baoyu-imagine skill 生成了 CC-Switch + CLIProxyApi + OpenRouter 的技术架构图，白色背景，扁平设计风格。

  如果需要更清晰的文字渲染，可以考虑配置 DashScope API Key（qwen-image-2.0-pro 对中文和文本渲染支持更好）。
```

生成的图片效果（也没法拿出来用）：  
![penrouter-cc-switch-architecture](/images/2026-04-12-openrouter-cc-switch-architecture-diagram.png)

最后也挺有自知之明（一分钱一分货，是我自己想多了，看阿里百炼网站上`qwen-image-2.0-pro`模型`0.5元/每张`）：  
“如果需要更清晰的文字渲染，可以考虑配置 DashScope API Key（qwen-image-2.0-pro 对中文和文本渲染支持更好）”

### 3.5. 其他Skills

可以
```
序号	技能名称	描述
1	android-native-dev	Android 原生应用开发（Kotlin/Compose，Material Design 3）
2	buddy-sings	让 Claude Code 宠物（/buddy）唱歌
3	flutter-dev	Flutter 跨平台开发（Riverpod/Bloc 状态管理，GoRouter 导航）
4	frontend-dev	全栈前端开发，AI 媒体资产、电影级动画
5	fullstack-dev	全栈后端架构与前后端集成开发
6	gif-sticker-maker	将照片（人物/宠物/物体/Logo）转换为 4 帧动画 GIF 贴纸
7	ios-application-dev	iOS 应用开发（UIKit/SnapKit，SwiftUI，安全区域/导航）
8	minimax-docx	专业 DOCX 文档创建与编辑（OpenXML SDK）
9	minimax-multimodal-toolkit	MiniMax 多模态工具包（文本/图像/视频/语音/音乐生成）
10	minimax-music-gen	音乐、歌曲、音频轨道生成
11	minimax-music-playlist	基于用户音乐品味和生成反馈的个性化播放列表
12	minimax-pdf	高质量 PDF 创建，支持设计身份与视觉质量
13	minimax-xlsx	Excel/电子表格处理（.xlsx/.xlsm/.csv/.tsv）
14	pptx-generator	PowerPoint 演示文稿生成（PptxGenJS）
15	react-native-dev	React Native 和 Expo 开发指南
16	shader-dev	GLSL 着色器技术（光线 marching、SDF 建模、流体模拟）
17	vision-analysis	使用 MiniMax 视觉 MCP 工具进行图像分析/描述/信息提取
```
