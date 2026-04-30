---
title: 基于 Obsidian + LLM Wiki 开始构建个人知识工程
description: 基于 Karpathy 的 LLM Wiki 模式，配合 Obsidian 和 Claude Code，构建增量维护的个人知识库。
categories: [工具, 知识管理]
tags: [Obsidian, 知识库, LLM, Claude]
---

## 1. 引言

最近基于`Andrej Karpathy`（OpenAI联合创始人）的`LLM Wiki`思路构建知识库，在工作环境和家里环境都捣腾了一下。思路是基于`Obsidian`+`LLM`来管理，构建自己的**知识工程/复利工程**，长期积累下来形成飞轮效应。

主要参考链接：
* Karpathy分享的 [LLM Wiki](https://gist.github.com/karpathy/442a6bf555914893e9891c11519de94f)
* [490万浏览量的方案：用 LLM 构建持续更新积累的个人知识库](https://cloud.tencent.com/developer/article/2651812)
* 两个开源项目参考：[graphify](https://github.com/safishamsi/graphify)：把所有内容压缩成一张可查询的知识图谱，每次查询的token量能大大降低；[sage-wiki](https://github.com/xoai/sage-wiki)：也是参考Karpathy做的知识库

之前短暂用过`Obsidian`，当时因为多端同步问题，最后换成了`Notion`。平常记录笔记用的是`Sublime Text`，比较轻量、Markdown效果也挺好。但是用来给别人展示的话效果还是差一些，`Typora`会友好一些，而`Obsidian`则效果更好。

目前使用下来的几个体验：
* `Obsidian`替换`Sublime Text`来记录日常的笔记，开启vim模式后体验差不多（资源占有稍微多了一点，但比`Typora`少些），**大纲**的体验好多了
* 方便集成终端，同一界面开启`Claude Code`方便对话（但有个问题：Claude识别中文目录有时会多个空格，比如`"01_AI相关"`识别成`"01_AI 相关"`导致路径错误。目录和文件名需尽量用全英文）
* 集成`Exclidraw`插件，AI能直接生成草图，体验很好
* 引用自动更新，**银弹特性**。比如引用的文件移动到其他目录，引用它的文件里会自动更新链接
* 插件自定义：插件基本是几个js和json文件，可以很方便地修改

`Obsidian`本身的体验挺好，目前做法是raw层除了外部摄入的信息外，自己历史的笔记记录也一并放过来管理。

但raw层按照 **<mark>AI和人类均友好</mark>**的方式重新组织后，wiki层有点重复显得有些鸡肋，目前还在摸索适合自己的用法。

---

## 2. 核心理念

### 2.1. 传统笔记 vs LLM Wiki

|          | 传统笔记               | LLM Wiki            |
| -------- | ---------------------- | ------------------- |
| 每次查询 | 从原始文档重新检索片段 | 直接读已有的 Wiki   |
| 积累性   | 无，每次重新来         | 有，Wiki 持续变丰富 |
| 交叉引用 | 靠检索时偶然发现       | 提前建好            |
| 矛盾处理 | 每次都可能出现         | 提前标记，用户判断  |

### 2.2. LLM Wiki 的三层架构

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

### 3.1. 目录结构

我的 Obsidian Vault 大概长这样：

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
│   ├── LLM_Wiki_模式.md
│   └── RAG_对比.md
├── .obsidian/                # Obsidian 配置
└── CLAUDE.md                 # Wiki 维护指南（给 Claude Code 用的）
```

核心原则：**源文档不可修改，只读；LLM 只写 wiki 层。**

### 3.2. Obsidian 主题和外观

主题我用的是 **Things**，黑色系看着比较舒服。一级、二级标题颜色可以按自己喜好调，在 `things.css` 里改：

```css
--h1-color: #e87d3e;
--h2-color: #e5b567;
```

效果：  
![obsidian-style](/images/2026-04-29-obsidian-style.png)

其他不错的 Obsidian 主题：Blue Topaz、Obsidian Nord、Shimmering Focus。

---

## 4. 推荐插件

到 GitHub 下载插件，基本都是 `main.js`、`manifest.json`、`styles.css` 三个文件，到 `.obsidian/plugins` 目录新增插件名对应的子目录，拷贝进去再启用。

### 4.1. 核心插件

| 插件                         | 用途                                       |
| ---------------------------- | ------------------------------------------ |
| **Excalidraw**               | 画图，手绘风格，适合画架构图、流程图       |
| **Draw.io**                  | 另一种画图工具，UML、流程图                |
| **number-headings-obsidian** | 给标题自动编号，配合动态目录               |
| **open tab setting**         | 默认在新标签页打开 md 笔记，避免重复标签页 |

Excalidraw 默认保存位置可以在 `data.json` 里改：

```json
"folder": "01_sources/_excalidraw"
```

Excalidraw的保存文件名格式修改：`保存` → `文件名`

### 4.2. AI 集成插件

| 插件         | 用途                                   |
| ------------ | -------------------------------------- |
| **Claudian** | 在 Obsidian 里打开 Claude Code         |
| **terminal** | 在 Obsidian 里打开终端（Mac 上挺好用） |

Claudian + Claude Code 的组合就是让 LLM 维护 Wiki 的关键——Claude Code 读取 `01_sources/` 中的新文档，然后在 `02_wiki/` 里创建/更新 wiki 页面。

### 4.3. 其他实用插件

| 插件                     | 用途                                 |
| ------------------------ | ------------------------------------ |
| **control characters**   | 显示空格和 Tab，避免格式问题         |
| **obsidian web clipper** | 浏览器插件，快捷保存网页内容到知识库 |

浏览器插件 obsidian web clipper 可以设置保存路径，日常收集资料很方便。
* `cmd + shift + o`快捷键（Windows可`ctrl+shift+o`），保存页面内容到obsidian

---

## 5. CLAUDE.md 配置

告诉 Claude Code 如何维护 Wiki。

```
# 知识库维护指南

这是一个基于 LLM Wiki 模式运作的个人知识库。我（AI助手）是 wiki 的维护者，负责读取源文档、构建和维护 wiki 内容。你（用户）是源材料的提供者和问题的提问者。

## 目录结构

obsidian_xd/
├── 01_sources/        # 源文档目录（只读，Immutable）
│   ├── _clippings/    # 外部下载内容（网页、PDF、文档等）→ 需要摄入到 wiki
│   ├── _draft/       # 临时草稿 → 不摄入
│   ├── _excalidraw/  # 画图文件 → 不摄入
│   └── _assets/      # 静态资源 → 不摄入
├── 02_wiki/           # AI 生成的 wiki 内容
└── CLAUDE.md          # 本文件 - AI维护指南

## 核心原则

1. **Wiki 是持久积累的工件** - 交叉引用已存在，矛盾已标记，综合内容反映你读过的所有材料
2. **源文档不可修改** - 只读源材料，AI 只写 wiki 层
3. **增量维护** - 新源文档不是简单索引，而是被读取、提取、整合进现有 wiki

## 工作流程

### 1. 摄入源文档 (Ingest)

当用户放入新文档到 `01_sources/` 并要求处理时：

1. 阅读源文档，识别关键实体、概念、主题
2. 与用户讨论要点（关键发现、矛盾点、与其他知识的关联）
3. 创建/更新 wiki 页面：
   - **实体页面** (Entity pages): 人物、地点、工具等具体事物
   - **概念页面** (Concept pages): 主题、理论、方法论
   - **比较页面**: 对比分析
   - **概述页面**: 某一领域的整体概述
   - **综合页面**: 跨文档的综合性结论

### 2. 回答问题

当用户提问时：

1. 先在 wiki 中查找相关信息
2. 如需引用源文档，注明来源
3. 综合多个页面的信息给出完整答案
4. 发现新联系时，标记并询问是否要更新 wiki

### 3. 维护 Wiki

- 当摄入新文档时，检查现有页面是否需要更新
- 标记矛盾之处（"注意：此观点与 X 文档中的 Y 观点不一致"）
- 维护交叉引用
- 保持页面简洁，互相链接

## 命名规范

- Wiki 页面：使用中文标题，驼峰式，如 `机器学习基础.md`
- 实体页面：使用具体名称，如 `Transformer架构.md`
- 概念页面：描述性标题，如 `注意力机制.md`

## Wiki 页面格式

&#x2D;&#x2D;&#x2D;
title: 页面标题
tags: [概念, 机器学习]
created: 2026-04-27
0.6. source: 来源文档
&#x2D;&#x2D;&#x2D;

# 1. 标题

## 1.1. 概述

## 1.2. 关键概念

## 1.3. 相关页面

## 1.4. 争议/矛盾点（如果有）

## 当前状态

- Wiki 刚初始化，还没有内容
- 用户将逐步添加源文档到 `01_sources/`
- 每次摄入后会更新本文件以反映当前状态

## 注意事项

- Wiki 内容必须来自真实源文档，不可凭空编造。用户添加源材料 → AI处理整合 → Wiki 积累。
- 保持页面精简，每个页面聚焦一个主题
- 主动建议交叉引用和新页面
- 矛盾点要明确标记，供用户判断
```

---

## 6. 快捷键配置

几个建议的快捷键：

- **在资源管理器中打开**：`ctrl+shift+r`（mac：`command+shift+r`）
- **在文件列表中打开**：`ctrl+shift+e`

---

## 7. 问题记录

1、问题：Obsidian is not able to access your clipboard.

解决：常规设置中，启用“传统模式”

## 8. 题外话：AI行为准则建议

[受 Karpathy 启发的 Claude Code 指南](https://github.com/forrestchang/andrej-karpathy-skills/blob/main/README.zh.md) 里建议的行为准则，和平常使用时基本是一致的，很值得参考。

另外看到网络上别人的共享，也可部分参考：  
![其他AI规则](/images/ai-rules.png)

既不要毫无要求又不要太约束AI，综合后自己目前在全局设置的要求（后续按需动态更新）：

```
[MacOS-xd@qxd ➜ obsidian_xd git:(main) ✗ ]$ cat ~/.claude/CLAUDE.md
使用中文问答

## AI 行为准则

> 受 Andrej Karpathy 启发的编码原则

### 1. 编码前思考

- **不要假设** — 如果不确定，询问而不是猜测
- **呈现多种解释** — 当存在歧义时，不要默默选择
- **适时提出异议** — 如果存在更简单的方法，说出来
- **困惑时停下来** — 指出不清楚的地方并要求澄清

### 2. 简洁优先

- 不要添加要求之外的功能
- 不要为一次性代码创建抽象
- 不要添加未要求的"灵活性"或"可配置性"
- 不要为不可能发生的场景做错误处理
- 如果 200 行代码可以写成 50 行，重写它

### 3. 精准修改

- 不要"改进"相邻的代码、注释或格式
- 不要重构没坏的东西
- 如果注意到无关的死代码，提一下 —— 不要删除它
- 删除因你的改动而变得无用的导入/变量/函数
- 不要删除预先存在的死代码，除非被要求

### 4. 目标驱动执行

- 将指令式任务转化为可验证的目标
- 对于多步骤任务，先说明计划再执行
- 定义成功标准，验证直到达成

### 5. 安全准则

- 不要输出或者提交密钥、凭据，若有要求则询问确认
- 删除、迁移、批量重写、权限调整等高影响操作，先明确风险和回退方式，并询问确认
```
