---
title: 复利工程 -- Obsidian Wiki模板仓库与实用工具分享
description: 打包了自己的Obsidian配置成模板仓库，配合WezTerm等工具链，打造个人高效工程环境。
categories: [AI, 复利工程]
tags: [Obsidian, WezTerm, Draw.io, 知识管理, 工具链]
---

## 1. 引言

搭 Obsidian Wiki 这套系统的时候，顺手把配置打包成了一个[模板仓库](https://github.com/xiaodongq/obsidian_template)，里面的插件和配置可以分享给其他人复用。

另外日常积累的仓库里躺了很多工具配置和快捷键笔记，这次一并整理一下。本文涉及的工具：
- **Obsidian** — 知识库，配合 LLM Wiki 模式管理笔记
- **WezTerm** — 终端，支持分屏、鼠标选中复制
- **Draw.io** — 画架构图、流程图
- **zsh** — 终端配置，补全和智能跳转
- 其他：windterm、Excalidraw、vim插件

一些技巧：
* **给AI提供一手信息源**：开源工具的配置和用法，可以下载原始仓库后让AI分析，并让AI来修改配置。分析其他项目同理。
* **习惯用版本管理一切**：修改配置前，把配置文件用git在本地管理起来（`git init`、`add`、`commit`）。目前我的claude code配置、本地私有笔记、工具配置目录都是按这个方式，很实用。
* **让AI更懂你**：个人知识库、本地版本管理都是除了人看和安全之外，很大一个作用是给AI提供不断进化和沉淀的素材，让它更了解自己的风格和需求，个性化提升个人效率。
* **光想全是问题，做了才有答案**：动手后好和坏都有体感，一样可作为不断迭代的基准素材。

---

## 2. Obsidian Vault 模板

Obsidian的插件是不同知识库目录独立的，可直接下载使用：[obsidian_template](https://github.com/xiaodongQ/obsidian_template) - Obsidian Vault 模板。

### 2.1. 目录结构

```
obsidian_xd/
├── 01_sources/              # 源文档目录（只读）
│   ├── _assets/              # 资源文件（截图等）
│   ├── _clippings/           # 剪藏内容
│   ├── _draft/               # 草稿
│   ├── _excalidraw/          # Excalidraw 绘图
│   └── 知识库设计说明/
│       └── llm_wiki.md       # Karpathy 的原始 gist 内容
├── 02_wiki/                  # AI 生成的 wiki 内容
├── .obsidian/                # Obsidian 配置
│   └── plugins/              # 插件目录
├── CLAUDE.md                 # Wiki 维护指南
└── README.md
```

核心原则：**源文档不可修改，只读；LLM 只写 wiki 层。**

### 2.2. 已打包的插件

到 GitHub 下载插件，基本都是 `main.js`、`manifest.json`、`styles.css` 三个文件，到 `.obsidian/plugins` 目录新增插件名对应的子目录，拷贝进去再启用。

| 插件                         | 用途                                           |
| ---------------------------- | ---------------------------------------------- |
| **Excalidraw**               | 画图，手绘风格，适合画架构图、流程图           |
| **number-headings-obsidian** | 给标题自动编号，配合动态目录                   |
| **open tab setting**         | 默认在新标签页打开 md 笔记，避免重复标签页     |
| **Claudian**                 | 在 Obsidian 里打开 Claude Code                 |
| **terminal**                 | 在 Obsidian 里打开终端（Mac 上挺好用）         |
| **control characters**       | 显示空格和 Tab，避免格式问题                   |
| **obsidian web clipper**     | 浏览器插件(外部安装)，快捷保存网页内容到知识库 |

### 2.3. 使用技巧

**高效编辑**
- **Vim 模式**：普通模式下 `j/k` 上下移动，`i` 进入插入模式
- **显示行号**：便于代码定位和导航
- **手动编号标题**：`Ctrl+P` 打开命令面板，输入 `num` 选择 "Number all headings in document"

**文件管理（手动添加的快捷键，已包含在模板仓库中）**
- `Ctrl+Shift+E` 在文件浏览器中定位当前文件
- `Ctrl+Shift+R` 用默认应用打开当前文件
- 截图或复制图片后直接粘贴，自动保存到 `_assets` 目录

**知识图谱**
- `Ctrl+G` 查看 Graph View，追踪页面间关联
- Graph View 中可显示孤立页面和标签分布

**核心配置**
- **Vim 模式**：已启用
- **拼写检查**：已关闭
- **总是更新链接**：已启用（重命名文件时自动更新引用）
- **Number Headings**：跳过顶层标题，`1.2.3` 格式手动编号

---

## 3. WezTerm 配置

配置拷贝到`~/.config/wezterm`即可使用：[xiaodongQ/wezterm-config](https://github.com/xiaodongQ/wezterm-config)。

### 3.1. 核心快捷键

| 操作             | 快捷键                 |
| ---------------- | ---------------------- |
| 复制             | `⌘+c` / `Ctrl+Shift+C` |
| 粘贴             | `⌘+v` / `Ctrl+Shift+V` |
| 新建标签页       | `⌘+t`                  |
| 关闭标签页       | `⌘+Ctrl+w`             |
| 上/下一个标签    | `⌘+[/]`                |
| 垂直分割（左右） | `⌘+Ctrl+/`             |
| 水平分割（上下） | `⌘+Ctrl+\`             |
| 关闭分屏         | `⌘+w`                  |
| 分屏缩放切换     | `⌘+Ctrl+z`             |
| 切换分屏方向     | `⌘+Ctrl+k/j/h/l`       |
| 调整分屏大小     | `⌘+Ctrl+↑/↓/←/→`       |
| 重命名标签       | `Ctrl+Shift+R`         |
| 增大/减小字体    | `⌘+↑/↓`                |
| 重置字体大小     | `⌘+r`                  |
| 全屏             | `F11`                  |

### 3.2. 鼠标操作

基于AI修改过一些行为：

| 操作               | 快捷键               |
| ------------------ | -------------------- |
| 单击选中并复制     | `Left Click`         |
| 拖拽选择多行       | `Left Drag`          |
| 双击选中单词       | `Double Click`       |
| 三击选中整行       | `Triple Click`       |
| Shift+单击区域选择 | `Shift + Left Click` |
| 右键粘贴           | `Right Click`        |

**原理**：选中即复制到剪贴板，Shift+单击可以在锚点基础上扩展选择区域。

---

## 4. Draw.io 配置

### 4.1. 快捷键

| 快捷键 | 功能     |
| ------ | -------- |
| a      | 文本     |
| d      | 方框     |
| c      | 箭头     |
| f      | 圆       |
| r      | 菱形     |
| x      | 自由绘制 |

### 4.2. 默认样式配置

默认配色感觉不大好看，参考了[博主 sansui233 的配置](https://www.sansui233.com/posts/2024-11-12-%E6%8A%8Adrawio%E8%A3%85%E4%BF%AE%E4%B8%BA%E7%AE%80%E5%8D%95%E7%BE%8E%E8%A7%82%E7%9A%84%E7%99%BD%E6%9D%BF%E5%BA%94%E7%94%A8)，自己也改了一版，见：[draw_io快捷键和修改默认配置.md](https://github.com/xiaodongQ/devNoteBackup/blob/master/%E5%B7%A5%E5%85%B7%E4%BD%BF%E7%94%A8/draw_io%E5%BF%AB%E6%8D%B7%E9%94%AE.md)。

效果1：  
![handy-tools.drawio](/images/handy-tools.drawio.svg)

效果2:  
![sylar_io_coroutine_scheduler](/images/sylar_io_coroutine_scheduler.svg)

**修改方式：** 在 “其他“ -> “配置“ -> 选择JSON，把上面链接里的json配置内容复制后，应用即可。

几个技巧：
- `enableLightDarkColors: false` - 避免导出 svg 时 light-dark 模式影响手机端外观显示
- `flowAnimation` - 流动箭头效果
- 自定义配色方案，导出的图颜色更协调

---

## 5. zsh 配置

Linux/类Unix终端，`zsh + oh my zsh`很好用，基本离不开了

### 5.1. 核心插件

| 插件     | 功能                                  |
| -------- | ------------------------------------- |
| git      | 显示 git 信息，简写命令（gco/gd/gst） |
| autojump | 智能跳转，`j 目录名` 直接跳转         |

### 5.2. 补全技巧

- 按 `tab` 或两下 `tab` 触发补全，会展示可跳转目录而后Tab切换
- `ctrl+n/p/f/b` 用鼠标切换选择展示出来的补全项
- `kill java + tab` 自动替换为进程 pid，同样可用`ctrl+n/p/f/b`来切换选择
- `ssh + 空格 + 两个tab` 列出历史主机和用户名

### 5.3. 性能优化

ssh远程连接时，发现服务端耗时较久，远端zsh进行如下优化可快不少：

```sh
# 禁用 git 未跟踪文件检查，大型 git 仓库中显著提升提示符渲染速度
DISABLE_UNTRACKED_FILES_DIRTY="true"
DISABLE_GIT_AUTO_ADD_STATUS="true"
# 启用补全缓存
zstyle ':completion::complete:*' use-cache on
zstyle ':completion::complete:*' cache-path "$ZSH_CACHE_DIR"
```

一些其他配置，也可见笔记：[zsh.md](https://github.com/xiaodongQ/devNoteBackup/blob/master/%E5%B7%A5%E5%85%B7%E4%BD%BF%E7%94%A8/zsh.md)

---

## 6. 思路：个人AI工具集归档

日常积累的 Claude Code Skills、MCPs、Commands 等工具配置，整理到一个归档仓库，便于不同环境复用。建议每个人都构建自己的市场仓库，换一个机器后可以快速搭建环境。

比如我初步搭建的：[xiaodongQ/xd-self-market](https://github.com/xiaodongQ/xd-self-market) 

```
xd-self-market/
├── skills/      # 统一源格式（Claude Code）
├── openclaw/   # OpenClaw 兼容副本
├── commands/   # slash commands
├── mcps/       # MCP server 配置
└── scripts/    # 公共脚本
```

核心原则：`skills/` 是唯一真实源，OpenClaw 副本由脚本同步或手动维护。

目前已迁移：
- `xd-git-push` — 提交代码前二次确认
- `xd-blog-style` — 基于博客风格写作

---

## 7. 其他

* windterm 终端工具，替换xshell、secureCRT等ssh工具。目前Windows、Mac笔记本都换成了这个，挺好用。默认的横向和纵向分屏功能不大好用，可以让AI来添加快捷键，快捷分屏、快捷移动和关闭。
* Excalidraw的快捷键，之前写了篇博客说明：[Excalidraw白板工具和快捷键](https://xiaodongq.github.io/2024/06/16/excalidraw-cn-font/)
* vim插件，之前记录过：[Vim插件配置](https://xiaodongq.github.io/2015/08/01/vim-plugin-config/)，一直用的这套插件，有点老了不过够用，可以找找其他人的分享。除了插件，一些基本配置可以复用，常用的服务器建议上来就配置下，比如高亮搜索、换行和tab占有、自动语法缩减等。
