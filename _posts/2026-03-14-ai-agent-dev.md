---
title: AI能力集 -- Agent开发实践
description: Agent开发实践记录
categories: [AI, AI能力集]
tags: [AI, Agent]
---

## 1. 引言

[之前](https://xiaodongq.github.io/2025/08/27/ai-agent-learn-2-framework/) 里跟着`Hugging Face`的[AI Agents Course](https://huggingface.co/learn/agents-course/unit0/introduction)简单实践过agent开发，现在通过IDE或者CLI直接一句话就可以生成了。其中的框架流程和具体逻辑还是有必要去掌握的。

Agent开发实践，相关参考链接：
* AI生成的`CrewAI`和`LangChain`资料：[crewai-langchain-demos](https://github.com/xiaodongQ/ai-playground/tree/main/learning/crewai-langchain/crewai-langchain-demos)
* AI生成的`NanoClaw`资料，学习这个微型龙虾项目以了解`OpenClaw`原理：[nanoClaw-study](https://github.com/xiaodongQ/ai-playground/tree/main/nanoClaw-study)
* 他人实践：[从 0 到 1 复刻一个 Claude Code 这样的 Agent](https://plantegg.github.io/2026/03/05/%E4%BB%8E0%E5%88%B01%E5%A4%8D%E5%88%BB%E4%B8%80%E4%B8%AAClaude_Code%E8%BF%99%E6%A0%B7%E7%9A%84Agent/)

智能体开发框架很多，如`LangChain`/`LangGraph`/`AutoGen`/`CrewAI`等等，这里还是基于比较轻量的`CrewAI`框架来进行实践学习。

一般智能体开发框架的**核心：推理 + 行动**。
* `ReAct（Reasoning + Acting）`是目前 Agent 最主流的工作模式，来自 2022 年发表的论文 [ReAct: Synergizing Reasoning and Acting in Language Models](https://arxiv.org/abs/2210.03629)。
* 二者深度协同：
    * **推理轨迹**帮助模型归纳、跟踪、更新行动计划，并处理异常；
    * **行动**让模型与外部环境（知识库、API、交互环境）交互，获取真实信息以修正推理
    * 推理与行动统一为 LLM 的自然语言输出

另外说些题外话：AI发展到现在，会使用和不会使用的人，效率可以差到10倍多。不是说只是用用AI问答和简单Vibe Coding就是会了，还有很多方面需要在日常边实践边学习。  
[用好AI的第一步：停止使用ChatGPT](https://www.superlinear.academy/c/ai-resources/stop-using-chatgpt) 这篇文章里面说得很好：
* 用好`Cursor`、`Claude Code`、`Codex`等这类`Agentic`工具，除了编程场景，它们**对于几乎所有知识工作都有用**
    * 国内如`Trae`、`Qoder`、`CodeBuddy`等，开源如`OpenCode`
* 好处：
    * 第一层：反馈闭环。工具生成得到的内容，在我们使用时若结果报错或者不满意，可以即时反馈，工具得到反馈及时修改和调整
    * 第二层：上下文供给。可以方便指定内部文档和会议记录等，不像问答场景下需要花功夫梳理描述给AI
    * 第三层：资产积累。问答模式下得到答案用完就没了，而Claude Code这类工具，可以根据实际使用的踩坑情况写一条规则，后续可复用经验，时间一长可以形成**飞轮效应**。
* 改进思路：
    * 日常生活和工作中，做的事情（查资料、设计和开发、定位问题；看过的新闻、时间安排等等）都以`.md`形式沉淀下来（这个步骤也借助AI来自动化），分类作为`Agentic`工具的上下文，沉淀改进，持续“养龙虾”/“养Claude Code”。
    * **可借鉴经验**：
        * 1、**文档沉淀经验**：沉淀下来的md文档，里面**包含成功的标准/好的标准**。尽量让后续的上下文完整，如知道具体有哪些失败模式和原因（分析笔记里有记录）、成功的标准是什么（哪几个case要被修复）。
        * 2、**思维转变 -- AI First**：先让AI生成，再人工调整。“信息先以AI能消费的格式存在（.md文件），AI完成主要工作（生成文档），最后才转成人类可读的版本（Confluence页面）。结果是你花的时间更少，产出的质量更高，而且AI消费的那份原材料还留在你的文件夹里，未来随时可以再用”。
            * “你的价值在于你知道这个算法应该往哪个方向改，你知道什么样的结果才算成功。这种判断力是你作为专业人士最核心的能力，也恰恰是AI最依赖你提供的东西。”
    * “工具会变，但三样东西是持久的：反馈闭环让AI能自我修正，上下文供给让AI能理解你的世界，资产积累让你和AI的协作越来越高效。这是底层的范式，跟具体工具无关。”

## 2. CrewAI简介和核心组件

具体见前面所述的自动内成的资料内容：[CrewAI 核心概念](https://github.com/xiaodongQ/ai-playground/blob/main/learning/crewai-langchain/crewai-langchain-demos/docs/crewai-langchain-research.md#1-crewai-%E6%A0%B8%E5%BF%83%E6%A6%82%E5%BF%B5)

`CrewAI` 是一个专注于**多Agent协作**的框架，让你能够像组建团队一样编排`AI Agent`。

使用上比较清晰，直接跟着核心组件定义的代码示例看功能和相关属性参数。

### 2.1. 核心组件 之 Agent（智能体）

`Agent` 是 CrewAI 中的基本执行单元，类似于团队中的成员。核心属性包含下面示例列出来的几个参数。
* 此外还有`llm`(驱动 Agent 的语言模型)、`memory`(bool, 保持对话历史)、`max_iter`(最大迭代次数，默认 20)等核心参数

```py
from crewai import Agent
from crewai_tools import SerperDevTool

researcher = Agent(
    role="高级数据研究员",            # 定义 Agent 的职责和专业领域
    goal="发现{topic}领域的前沿发展",  # 指导 Agent 决策的个体目标
    backstory="你是一位经验丰富的研究员，擅长发现最新发展趋势", # 提供背景和个性，丰富交互
    tools=[SerperDevTool()],        # Agent 可用的工具/能力，List[BaseTool]类型
    verbose=True,                   # 启用详细执行日志
    allow_delegation=False          # 允许 Agent 委托任务给其他 Agent
)
```

### 2.2. 核心组件 之 Task（任务）

`Task` 是分配给 Agent 的具体工作单元。

```py
from crewai import Task

research_task = Task(
    description="对{topic}进行彻底调研，确保找到所有相关信息",       # 任务的清晰描述
    expected_output="包含 10 个要点的列表，涵盖{topic}最重要的信息", # 
    agent=researcher,
    output_file="research_report.md",
    markdown=True
)
```
