---
title: OpenClaw系列 -- OpenClaw一人团队Multi-Agent系统设计与搭建
categories: [AI, OpenClaw系列]
tags: [AI, OpenClaw, Multi-Agent, 自动化]
---

## 1. 引言

在软件开发和日常工作中，我们常常需要同时扮演多个角色：设计、开发、写作、理财... 一个人的时间和精力有限，如何高效处理这些多样化任务？

本文介绍基于 OpenClaw 框架搭建的**一人团队 Multi-Agent 系统**，通过 5 个专业 Agent 协作，实现自动化处理。

**说明**：
1. 本文是 AI 基于 2026-03-09 的聊天记录自动生成的博客文章
2. 由于是 AI 生成，部分内容可能存在不准确，具体实操请参考：[OpenClaw 实战手记 - 进阶搭建一人团队](https://xiaodongq.github.io/2026/03/05/openclaw-practise/#5-进阶搭建一人团队)

**AI 自动生成博客流程**：
![AI 自动生成博客的完整流程](/images/2026-03-09-blog-generation-flow.png)
*图 1：AI 自动生成博客的完整流程 - 用户下发命令 → AI 生成内容 → 自动插入图片 → Git 提交发布*

---

## 2. 系统架构

### 2.1 整体架构

详细架构图和说明请参考：[一人团队 Multi-Agent 系统设计](https://github.com/xiaodongQ/ai-playground/blob/main/design/一人团队-Multi-Agent-系统设计.md)

![一人团队 Multi-Agent 系统架构图](/images/2026-03-09-multi-agent-architecture.png)
*图 2：一人团队 Multi-Agent 系统架构 - 用户通过小黑 - 管家与 4 个专业 Agent 交互*

**核心设计**：
```
用户 → 小黑 - 管家（路由）
        │
        ├─→ Dev·技术匠（编程、架构）
        ├─→ Edu·伴学堂（学习、研究）
        ├─→ Wri·执笔人（写作、博客）
        └─→ Fin·财多多（理财、投资）
```

### 2.2 Agent 角色

| Agent           | 职责                         | 触发关键词                   |
| --------------- | ---------------------------- | ---------------------------- |
| **小黑 - 管家** | 意图识别、路由编排、全局记忆 | 通用对话、闲聊、简单查询     |
| **Dev·技术匠**  | 编程、架构、代码审查         | 代码、Bug、架构、API、数据库 |
| **Edu·伴学堂**  | 学习辅导、概念讲解           | 学习、研究、教程、概念、入门 |
| **Wri·执笔人**  | 写作、润色、博客创作         | 写博客、文章、润色、写作     |
| **Fin·财多多**  | 理财建议、投资分析           | 理财、投资、股票、基金、预算 |

**详细配置**：参见 [一人团队配置文件归档](https://github.com/xiaodongQ/ai-playground/tree/main/design/一人团队配置文件归档)

**实操步骤**：详见 [OpenClaw 实战手记 - 进阶搭建一人团队](https://xiaodongq.github.io/2026/03/05/openclaw-practise/#5-进阶搭建一人团队)

---

## 3. 路由机制

### 3.1 路由决策树

```
用户输入
   │
   ├─ 显式指定 Agent？（如 @Dev·技术匠） → 直接转交
   │
   ├─ 关键词匹配 ≥2 个？ → 转交对应 Agent
   │
   ├─ 关键词冲突或模糊？ → LLM 意图识别
   │
   ├─ 通用知识/闲聊/简单查询？ → 小黑直接处理
   │
   └─ 混合需求？ → 小黑启动协作流程（串行/并行调度）
```

### 3.2 群聊消息归属规则

**优先级**：
1. 有 @ → 回复指定的人
2. 有引用 → 回复引用的消息
3. 无@无引用 → 智能判断话题连续性
4. 不确定 → 提示用户确认

**实现脚本**：`/root/.openclaw/scripts/message-router.mjs`

**详细说明**：[ROUTING.md](https://github.com/xiaodongQ/ai-playground/blob/main/design/一人团队配置文件归档/小黑 - 管家/ROUTING.md)

---

## 4. 全局规则

全局规则由 AI 自动编写和维护，位于 `~/.openclaw/workspace/RULES.md`：

```markdown
# 全局规则配置中心

| 规则 ID  | 名称                    | 优先级     | 适用 Agent              |
| -------- | ----------------------- | ---------- | ----------------------- |
| RULE-001 | 博客发布评审流程        | P0（强制） | Wri·执笔人、小黑 - 管家 |
| RULE-002 | 群聊消息归属混合模式    | P0（强制） | 所有 Agent              |
| RULE-003 | 多 Agent 协作工作流记录 | P1（重要） | 小黑 - 管家             |
| RULE-004 | 搜索工具优先级策略      | P1（重要） | 所有 Agent              |
| RULE-005 | 挑战式交互原则          | P2（建议） | 所有 Agent              |

**违规处理**:
- P0 违规：立即停止，向用户报告
- P1 违规：记录日志，事后报告
- P2 违规：参考执行
```

**完整规则**：[RULES.md](https://github.com/xiaodongQ/ai-playground/blob/main/design/一人团队配置文件归档/小黑 - 管家/RULES.md)

---

## 5. 记忆系统

### 5.1 记忆分类

| 类型         | 存储位置                    | 内容                             | 访问权限                    |
| ------------ | --------------------------- | -------------------------------- | --------------------------- |
| **全局记忆** | `MEMORY.md`                 | 用户基本信息、项目背景、重要决策 | 所有 Agent 可读，仅小黑可写 |
| **专业记忆** | `workspace-{agent}/memory/` | 领域特定偏好、项目进度           | 仅对应 Agent 可读写         |
| **会话记忆** | `sessions/`                 | 当前对话历史                     | 仅对应 Agent 可访问         |

### 5.2 记忆共享流程

```
子 Agent → 发现重要信息 → 通知小黑 → 小黑确认 → 写入 MEMORY.md
```

**详细说明**：[MEMORY-SHARING.md](https://github.com/xiaodongQ/ai-playground/blob/main/design/一人团队配置文件归档/小黑 - 管家/MEMORY-SHARING.md)

---

## 6. 搭建步骤

### 6.1 设计 Agent 角色

首先设计 5 个 Agent 的角色和职责（见第 2 节表格）。

### 6.2 创建 Agent

设计好方案后，手动创建 Agent 工作区，剩下就让 OpenClaw 自己修改人设文件了。

**实操步骤**：详见 [OpenClaw 实战手记 - 进阶搭建一人团队](https://xiaodongq.github.io/2026/03/05/openclaw-practise/#5-进阶搭建一人团队)

**基本步骤**：
```bash
# 1. 创建工作区
mkdir -p ~/.openclaw/workspace-dev-agent
mkdir -p ~/.openclaw/workspace-research-agent
mkdir -p ~/.openclaw/workspace-writer-agent
mkdir -p ~/.openclaw/workspace-finance-agent

# 2. 复制基础配置
cp -r ~/.openclaw/workspace/* ~/.openclaw/workspace-dev-agent/
# 其他 Agent 同理

# 3. 修改人设（SOUL.md、IDENTITY.md 等）
# OpenClaw 会根据对话自动优化这些人设文件
```

### 6.3 配置飞书通道

参考：[OpenClaw 实战手记 - 飞书通道配置](https://xiaodongq.github.io/2026/03/05/openclaw-practise/#23-飞书通道配置)

**基本步骤**：
1. 在飞书开放平台创建企业自建应用
2. 获取 App ID 和 App Secret
3. 编辑 `~/.openclaw/openclaw.json` 配置飞书通道
4. 配置 `allowFrom` 和 `groupAllowFrom`
5. 重启网关：`openclaw gateway restart`

### 6.4 配置路由规则

路由规则由 AI 自动编写，位于 `~/.openclaw/workspace/ROUTING.md`。

**完整内容**：[ROUTING.md](https://github.com/xiaodongQ/ai-playground/blob/main/design/一人团队配置文件归档/小黑 - 管家/ROUTING.md)

---

## 7. 验证和测试

### 7.1 基础通信测试

**测试命令**：
```bash
# 在飞书群聊中发送
"测试"

# 预期响应
"✅ 测试成功！小黑 - 管家在线待命"
```

### 7.2 路由功能测试

**测试 Dev·技术匠**：
```
用户："我想用 Go 写个 HTTP 服务器"
→ 应路由到 Dev·技术匠
```

**测试 Edu·伴学堂**：
```
用户："帮我解释一下量子计算"
→ 应路由到 Edu·伴学堂
```

**测试 Wri·执笔人**：
```
用户："写一篇关于 Rust 内存安全的博客"
→ 应路由到 Wri·执笔人
```

### 7.3 多 Agent 协作测试

**测试命令**：
```
用户："我想写一篇关于 Python 量化交易的博客"

预期流程：
1. 小黑 → Edu·伴学堂：生成量化交易核心概念笔记
2. 小黑 → Dev·技术匠：基于笔记编写示例代码
3. 小黑 → Wri·执笔人：整合所有材料撰写博客
4. 小黑 → 用户：返回最终博客 + 协作过程摘要
```

---

## 8. 常见问题

### Q1: Agent 无响应？

**可能原因**：
- 用户/群聊不在允许列表中
- Gateway 未运行

**排查步骤**：
```bash
# 1. 检查 Gateway 状态
openclaw gateway status

# 2. 检查允许列表
cat ~/.openclaw/credentials/feishu-*-allowFrom.json

# 3. 查看日志
tail -f ~/.openclaw/logs/*.log
```

### Q2: 路由错误？

**可能原因**：
- 关键词匹配不准确
- 群聊消息归属逻辑问题

**解决方案**：
- 调整 `ROUTING.md` 中的关键词列表
- 检查消息路由器脚本：`/root/.openclaw/scripts/message-router.mjs`

### Q3: 多 Agent 协作失败？

**可能原因**：
- Agent 间通信问题
- 任务依赖关系错误

**解决方案**：
- 检查工作流记录（`~/.openclaw/workspace/memory/workflow-*.md`）
- 查看会话状态：`openclaw sessions list`

---

## 9. 参考链接

### 设计文档
- [一人团队设计文档](https://github.com/xiaodongQ/ai-playground/blob/main/design/一人团队设计.md)
- [一人团队 Multi-Agent 系统设计](https://github.com/xiaodongQ/ai-playground/blob/main/design/一人团队-Multi-Agent-系统设计.md)
- [一人团队配置文件归档](https://github.com/xiaodongQ/ai-playground/tree/main/design/一人团队配置文件归档)

### 实战文档
- [OpenClaw 实战手记](https://xiaodongq.github.io/2026/03/05/openclaw-practise.html)
- [OpenClaw 进阶搭建一人团队](https://xiaodongq.github.io/2026/03/05/openclaw-practise/#5-进阶搭建一人团队) ⭐ **重点参考**
- [CrewAI + LangChain 学习材料包](https://github.com/xiaodongQ/ai-playground/tree/main/learning/crewai-langchain)

---

**说明**：本文是 AI 基于聊天记录自动生成的博客文章，由于是 AI 生成，部分内容可能存在不准确，具体实操请重点参考 [OpenClaw 实战手记 - 进阶搭建一人团队](https://xiaodongq.github.io/2026/03/05/openclaw-practise/#5-进阶搭建一人团队)。
