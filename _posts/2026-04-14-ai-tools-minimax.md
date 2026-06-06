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

### 3.5. 生成人物风景等非文字类图片（效果还能看）

效果还可以。

```sh
❯ mmx生成一个风景图，阳光小乡村

● Skill(minimax-skills:minimax-multimodal-toolkit)
  ⎿  Successfully loaded skill
● Bash(mmx image generate --prompt "A sunny small village landscape, warm sunlight shining on rustic cottages with
      thatched roofs, flower-filled meadows, a winding cou…)
  ⎿  /home/workspace/tmpdir/sunny_village_001.jpg
● 图片已生成！
  保存路径: /home/workspace/tmpdir/sunny_village_001.jpg
  Read 1 file (ctrl+o to expand)
● 阳光小乡村风景图已生成完成！
  画面展现了一个宁静祥和的乡村景象：蜿蜒的土路穿过绿意盎然的草地，远山起伏，天空湛蓝带几朵白云，几座古朴的农舍沐浴在温暖
  的晨光中，野花点点——很舒适田园风格。
```

效果：  
[sunny_village_001](/images/sunny_village_001.jpg)

### 3.6. 其他Skills

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

## 4. mmx多模块工具包

上面安装的`minimax-multimodal-toolkit`是`MiniMax`的多模态工具包（文本/图像/视频/语音/音乐生成）。单独实验下效果。

具体可见GitHub仓库：[MiniMax cli -- mmx](https://github.com/MiniMax-AI/cli/blob/main/README_CN.md)。

```sh
[MacOS-xd@qxd ➜ obsidian_xd git:(main) ✗ ]$ mmx -h
Usage: mmx <resource> <command> [flags]
Resources:
  auth       Authentication (login, status, refresh, logout)
  text       Text generation (chat)
  speech     Speech synthesis (synthesize, voices)
  image      Image generation (generate)
  video      Video generation (generate, task get, download)
  music      Music generation (generate, cover)
  search     Web search (query)
  vision     Image understanding (describe)
...
```

### 4.1. 生图：mmx image

`mmx image` 上面已经实验过了，模型文字效果不大好，不过生成动物、风景之类的还行。

上面是通过Claude Code调用的，也可以手动直接触发：

```sh
mmx image "一只穿宇航服的猫"
mmx image generate --prompt "科技感 Logo" --n 3 --aspect-ratio 16:9
mmx image generate --prompt "山水画" --out-dir ./output/
```

### 4.2. 生成音乐：mmx music

安装了Minimax的skills，会自动调用：`mmx music generate`

```sh
# 带歌词生成
mmx music generate --prompt "欢快的流行乐" --lyrics "[主歌] 啦啦啦，阳光照" --out song.mp3
# 自动生成歌词
mmx music generate --prompt "忧郁的独立民谣，雨夜" --lyrics-optimizer --out song.mp3
# 纯音乐（无人声）
mmx music generate --prompt "史诗管弦乐" --instrumental --out bgm.mp3
# Cover — 基于参考音频生成翻唱版本
mmx music cover --prompt "爵士钢琴，慵懒女声" --audio-file original.mp3 --out cover.mp3
mmx music cover --prompt "民谣吉他" --audio https://example.com/song.mp3 --out cover.mp3
```

比如（原来自动支持歌词文件生成，不过播放的进度对应关系有点不准确，需要手动调整下）：

```sh
❯ 帮我生成一首春天的歌曲

⏺ Skill(minimax-skills:minimax-music-gen)
  ⎿  Successfully loaded skill
⏺ 好的，我来帮你生成一首春天的歌曲！
  这是一个人声歌曲，我会为你自动生成歌词。先让我扩展一下描述，然后预览给你确认。
⏺ Bash(command -v mmx && mmx --version || echo "mmx not found")
  ⎿  /Users/xd/.nvm/versions/node/v24.14.1/bin/mmx
     mmx 1.0.7
⏺ Bash(mmx quota show 2>&1 | head -20)
  ⎿  {
       "model_remains": [
         {
     … +17 lines (ctrl+o to expand)
⏺ 好的！我来为你生成一首春天的歌曲。

  歌曲预览：
  - 类型：人声歌曲（中文歌词）
  - 风格：温暖、轻快、民谣风格
  - 描述：关于春天万物复苏、阳光温暖、花朵绽放的喜悦氛围
  - 歌词：自动生成

  确认生成吗？（回车确认，或告诉我你想调整的风格）

⏺ Bash(mmx music generate \
        --prompt "A warm spring song, cheerful folk pop style, about blooming flowers, gentle breeze, sunshine and new beginnings, featuring a sw…)
⏺ Bash(mkdir -p ~/Music/minimax-gen)
  ⎿  Done
⏺ Bash(mmx music generate \
        --prompt "A warm spring song, cheerful folk pop style, about blooming flowers, gentle breeze, sunshine and new beginnings, featuring a sw…)
  ⎿  /Users/xd/Music/minimax-gen/20260418_spring_song.mp3
  ⎿  (timeout 3m)
⏺ 歌曲已生成，现在播放：
⏺ Bash(afplay ~/Music/minimax-gen/20260418_spring_song.mp3 &
      sleep 2…)
  ⎿  正在播放: 20260418_spring_song.mp3
⏺ 春日歌曲已生成完成！
  文件信息：
  - 保存位置：~/Music/minimax-gen/20260418_spring_song.mp3
  - 风格：民谣流行 (folk pop)
  - 情绪：温暖欢快
  - BPM：120
  - 人声：甜美女声
  歌曲主题围绕春天的元素：花开、柔风、阳光和新的开始。
```

生成的歌曲，效果也不错，听不太出和真人有特别明显的区别（非专业的视角）。

同时生成歌词示例，`ctrl+o`展开完整命令：

```sh
歌词写好了，现在用 --lyrics 参数生成歌曲，然后自动生成 LRC 文件。
⏺ 歌词已写好，现在生成歌曲。
  Bash(mmx music generate \
        --prompt "A melancholic indie folk song, rainy night atmosphere, acoustic guitar and gentle piano, heartfelt
      male vocal" \
        --lyrics "[Verse]
      背起行囊离开熟悉的地方
      火车穿过山谷 窗外是未知的天光
      路很长 心跳跟着铁轨声响
      ...
      [Outro]
      旅途无尽 脚步不停
      远方很远 心很近" \
        --genre "folk" --mood "melancholic, nostalgic, warm" --vocals "soft male vocal" \
        --instruments "acoustic guitar, piano" --bpm 80 \
        --out ~/Music/minimax-gen/journey_song_$(date +%Y%m%d_%H%M%S).mp3 \
        --quiet --non-interactive)
```

### 4.3. 生成语音：mmx speech

```sh
# 生成“你好”的音频
mmx speech synthesize --text "你好！" --out hello.mp3
mmx speech synthesize --text "流式输出" --stream | mpv -
mmx speech synthesize --text "Hi" --voice English_magnetic_voiced_man --speed 1.2
echo "头条新闻" | mmx speech synthesize --text-file - --out news.mp3
mmx speech voices
```

### 4.4. 网络搜索：mmx search

```sh
mmx search "MiniMax AI"
mmx search query --q "最新动态" --output json
```

查询示例：  
```sh
[MacOS-xd@qxd ➜ tmp ]$ mmx search 今日AI要闻
MINIMAX ~/.mmx/config.json | Region: cn (file) | Key: sk-c...kIJk (file)
机器人半程马拉松赛开跑,宇树机器人绊到马路牙子摔进草坪;马斯克xAI进军AI智能编程;Cursor即将完成20亿美元融资丨邦早报
  https://so.html5.qq.com/page/real/search_news?docid=70000021_64669e44f9776952
  <p><img src='http://qqpublic.qpic.cn/qq_public/0/28-2037540798-F13998F46757D566AB4FECDDD6077027/0?fmt=jpg&size=98&h=619&w=1080&ppv=1'
  2026-04-19 11:44:23

人工智能产业日报(04.15) : AI经济新活力
  https://so.html5.qq.com/page/real/search_news?docid=70000021_08369e05f1e27652
  类最初未考虑商业化,安全是关键｡L4级自动驾驶需实现全无人驾驶和确保安全,而L2级则不能实现无人驾驶｡    </p><p>中国信通院人工智能所联合发布《大模型推理优化关键技术及应用实践研究报告(2026年)》</p><p>
  2026-04-19 12:00:44

AI驱动科研!紫东太初AI4S大会落幕,OPC社区引爆AI超级个体浪潮
  https://so.html5.qq.com/page/real/search_news?docid=70000021_98869e4244a62452
  以“AI驱动科研·一人智创未来” 为主题,聚焦算力筑基､AI4S大模型赋智､产业数字化转型､OPC社区生态共建四大核心方向,发布多项硬核科技成果,签约一批重点产业项目,为石景山区人工智能产业高质量发展注入新动能｡
  2026-04-19 10:53:26
  ...
```

## 5. 20260606更新：使用MiniMax-M3模型

MiniMax近期发布了`M3`模型，M3 相比 M2.7 核心新增功能
* 上下文：200K → 100 万 Token（1M）
* Agent 智能体迭代：继承 M2.7 自我进化 Harness 框架，新增**Producer+Verifier 自我纠错闭环**、多 Agent 集群协同优化

之前配置的还是`MiniMax-M2.7`，改成`MiniMax-M3`：

Claude Code，`~/.claude/settings.json`：

```sh
  "env": {
    "ANTHROPIC_BASE_URL": "https://api.minimaxi.com/anthropic",
    "ANTHROPIC_AUTH_TOKEN": "sk-cp-KgOfCAZKyPxxxxx",
    "API_TIMEOUT_MS": "3000000",
    "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC": "1",
    "ANTHROPIC_MODEL": "MiniMax-M3",
    "ANTHROPIC_DEFAULT_SONNET_MODEL": "MiniMax-M3",
    "ANTHROPIC_DEFAULT_OPUS_MODEL": "MiniMax-M3",
    "ANTHROPIC_DEFAULT_HAIKU_MODEL": "MiniMax-M3"
  },
```

另外`npm upgrade -g mmx-cli`更新下`mmx` CLI，其页面也有所更新：

```sh
[MacOS-xd@qxd ➜ picoclaw git:(main) ]$ mmx
...
MINIMAX ~/.mmx/config.json | URL: api.minimaxi.com | Key: sk-c...kIJk (file)

╭────────────────────────────────────────────────────────────────────────╮
│ MINIMAX  TokenPlan 配额面板              周期: 2026-05-31 — 2026-06-07   │
├────────────────────────────────────────────────────────────────────────┤
│ 通用    剩余             99%  周剩余             98%  重置 1h 23m         │
├────────────────────────────────────────────────────────────────────────┤
│ 视频    剩余            100%  周剩余            100%  重置 1h 23m         │
╰────────────────────────────────────────────────────────────────────────╯
```
