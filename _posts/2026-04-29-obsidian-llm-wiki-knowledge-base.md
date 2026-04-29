---
title: Obsidian + LLM Wiki 打造个人知识库
description: 基于 Karpathy 的 LLM Wiki 模式，配合 Obsidian 和 Claude Code，构建增量维护的个人知识库。
categories: [工具, 知识管理]
tags: [Obsidian, 知识库, LLM, Claude]
---

## 1. 引言

之前折腾知识管理工具的时候，一直在找一种能"长期积累"而不是"每次查询都从头来"的方式。传统 RAG 大家都懂——上传一堆文档，问问题时检索相关片段。但这个方式有个问题：**每次问问题都要重新找、重新拼凑，没有任何积累**。问一个需要综合五篇文档的深入问题，LLM 每次都得从头发现一遍。

后来看到了 Karpathy 的 [LLM Wiki](https://gist.github.com/karpathy/442a6bf555914893e9891c11519de94f) 这个想法，眼前一亮。他的核心思路是：不只在查询时从原始文档检索，而是让 LLM **增量构建和维护一个持久的 Wiki**——一个位于原始资料和用户之间的结构化、互相链接的 Markdown 文件集合。

简单说就是：**Wiki 是持久积累的工件。交叉引用已经建好，矛盾已经被标记，综合内容反映了你读过的所有材料。** 每加一个源，Wiki 就自动变得更丰富。

这篇文章记录一下我怎么基于 Karpathy 的思路，用 Obsidian + Claude Code 搭建这套系统的。

相关仓库：[obsidian_xd](https://github.com/xiaodongq/obsidian_xd)

---

## 2. 核心理念

### 传统 RAG vs LLM Wiki

|          | 传统 RAG               | LLM Wiki            |
| -------- | ---------------------- | ------------------- |
| 每次查询 | 从原始文档重新检索片段 | 直接读已有的 Wiki   |
| 积累性   | 无，每次重新来         | 有，Wiki 持续变丰富 |
| 交叉引用 | 靠检索时偶然发现       | 提前建好            |
| 矛盾处理 | 每次都可能出现         | 提前标记，用户判断  |

### LLM Wiki 的三层架构

```
┌─────────────────────────────────────┐
│         Schema（CLAUDE.md）           │  ← 告诉 LLM 如何维护 Wiki
├─────────────────────────────────────┤
│         Wiki（02_wiki/）             │  ← LLM 生成的综合内容
├─────────────────────────────────────┤
│      Raw Sources（01_sources/）     │  ← 只读源文档，Immutable
└─────────────────────────────────────┘
```

**Raw Sources**：只读的源文档集合（论文、文章、PDF 等）。LLM 只读不修改，这是真相来源。

**Wiki**：LLM 生成的 Markdown 文件（摘要页、实体页、概念页、对比分析、综合概述）。LLM 全权负责此层。

**Schema**：配置文件（比如 Claude Code 的 CLAUDE.md），告诉 LLM Wiki 的结构、约定和工作流。这是让 LLM 成为一个"有纪律的 Wiki 维护者"而不是"通用聊天机器人"的关键。

---

## 3. Obsidian 搭建

### 3.1 目录结构

我的 Obsidian Vault 大概长这样：

```
obsidian_xd/
├── 01_sources/              # 源文档目录（只读）
│   ├── 知识库设计说明/
│   │   └── llm_wiki.md       # Karpathy 的原始 gist 内容
│   └── _Excalidraw/          # Excalidraw 绘图
├── 02_wiki/                  # AI 生成的 wiki 内容
│   ├── LLM_Wiki_模式.md
│   ├── RAG_对比.md
│   ├── 设计原则.md
│   └── ...
├── .obsidian/                # Obsidian 配置
└── CLAUDE.md                 # Wiki 维护指南（给 Claude Code 用的）
```

核心原则：**源文档不可修改，只读；LLM 只写 wiki 层。**

### 3.2 Obsidian 主题和外观

主题我用的是 **Things**，黑色系看着比较舒服。一级、二级标题颜色可以按自己喜好调，在 `things.css` 里改：

```css
--h1-color: #e87d3e;
--h2-color: #e5b567;
```

其他不错的 Obsidian 主题：Blue Topaz、Obsidian Nord、Shimmering Focus。

---

## 4. 推荐插件

到 GitHub 下载插件，基本都是 `main.js`、`manifest.json`、`styles.css` 三个文件，到 `.obsidian/plugins` 目录新增插件名对应的子目录，拷贝进去再启用。

### 4.1 核心插件

| 插件                         | 用途                                          |
| ---------------------------- | --------------------------------------------- |
| **Excalidraw**               | 画图，手绘风格，适合画架构图、流程图          |
| **Draw.io**                  | 另一种画图工具，UML、流程图                   |
| **number-headings-obsidian** | 给标题自动编号，配合动态目录                  |
| **obsidian-opener**          | 默认在新标签页打开 md 笔记，避免重复标签页    |
| **data-files-editor**        | 支持在 Obsidian 里编辑 .txt、.json、.xml 文件 |

Excalidraw 默认保存位置可以在 `data.json` 里改：

```json
"folder": "01_sources/_Excalidraw"
```

### 4.2 AI 集成插件

| 插件         | 用途                                   |
| ------------ | -------------------------------------- |
| **Claudian** | 在 Obsidian 里打开 Claude Code         |
| **terminal** | 在 Obsidian 里打开终端（Mac 上挺好用） |

Claudian + Claude Code 的组合就是让 LLM 维护 Wiki 的关键——Claude Code 读取 `01_sources/` 中的新文档，然后在 `02_wiki/` 里创建/更新 wiki 页面。

### 4.3 其他实用插件

| 插件                     | 用途                                 |
| ------------------------ | ------------------------------------ |
| **obsidian-opener**      | 新标签页打开笔记，避免重复           |
| **control characters**   | 显示空格和 Tab，避免格式问题         |
| **obsidian web clipper** | 浏览器插件，快捷保存网页内容到知识库 |

浏览器插件 obsidian web clipper 可以设置保存路径，日常收集资料很方便。

---

## 5. CLAUDE.md 配置

这是整个系统的"灵魂文件"——告诉 Claude Code 如何维护 Wiki。以下是我的配置要点：

```markdown
# 知识库维护指南

这是一个基于 LLM Wiki 模式运作的个人知识库。我（AI助手）是 wiki 的维护者，
负责读取源文档、构建和维护 wiki 内容。你（用户）是源材料的提供者和问题的提问者。

## 核心原则

1. **Wiki 是持久积累的工件** - 交叉引用已存在，矛盾已标记
2. **源文档不可修改** - 只读源材料，AI 只写 wiki 层
3. **增量维护** - 新源文档不是简单索引，而是被读取、提取、整合进现有 wiki
```

Wiki 页面格式大概是这样：

```markdown
---
title: 页面标题
tags: [概念, 机器学习]
created: 2026-04-27
source: 来源文档
---

# 标题

## 概述

## 关键概念

## 相关页面

## 争议/矛盾点（如果有）
```

---

## 6. 工作流程演示

### 6.1 摄入新文档

当用户放入新文档到 `01_sources/` 并要求处理时，Claude Code 会：

1. 读取源文档，识别关键实体、概念、主题
2. 与用户讨论要点（关键发现、矛盾点、关联）
3. 创建/更新 wiki 页面：
   - **实体页面**：人物、工具等具体事物
   - **概念页面**：主题、理论、方法论
   - **比较页面**：对比分析
   - **综合页面**：跨文档的综合性结论

### 6.2 实际效果

比如我丢了一篇关于 LLM Wiki 的文章进去，Claude Code 自动生成了这样的 wiki 页面：

```markdown
---
title: LLM Wiki 模式
tags: [概念, 知识管理, LLM]
created: 2026-04-27
source: 01_sources/知识库设计说明/llm_wiki.md
---

# LLM Wiki 模式

## 概述

LLM Wiki 是一种利用 LLM 构建个人知识库的模式...
（LLM 增量维护的内容）
```

Wiki 里已经建好的页面会自动更新，新发现会整合进去，矛盾点会被标记。

---

## 7. 快捷键配置

建议配两个快捷键，用起来会顺手很多：

- **在新窗口打开当前笔记**：Mac 下 `command+shift+r`
- **在标签页打开**：Mac 下 `command+shift+e`

---

## 8. 总结

LLM Wiki 这个模式解决了我之前用知识库工具最大的痛点——**积累不起来**。用 Claude Code + Obsidian 搭这套系统，核心体验就是：

> Claude Code 在一边编辑，Obsidian 在另一边浏览结果。LLM 是程序员，Wiki 是代码库，Obsidian 是 IDE。

现在往 `01_sources/` 丢一篇新文章，告诉 Claude Code "帮我处理一下"，它就会自动读取、提取、整合进 Wiki。不用每次都从零开始检索，交叉引用已经建好，矛盾已经被标记，知识真正积累起来了。
