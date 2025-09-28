---
title: AI Agent学习实践笔记（二） -- Agent框架
description: HuggingFace AI Agents Course学习笔记，unit2 -- Agent框架
categories: [AI, LLM]
tags: [LLM, AI]
---

## 1. 引言

上一篇：[AI Agent学习实践笔记（一） -- Agents介绍](https://xiaodongq.github.io/2025/02/12/ai-agent-learn/) 进行了智能体的基本介绍，间隔比较久了，继续后续的unit学习。

AI发展日新月异，后续还有不少内容可以继续学习，如 [mcp-course](https://huggingface.co/learn/mcp-course/unit0/introduction)，加入TODO List。

## 2. Agent框架介绍

Agentic框架（Agentic Framework）不一定必须，如果只是简单的工作流，则预定义的工作流可能就够了。相对于使用agent框架，开发者能够拥有完全的系统控制权，不需要带着框架的抽象来理解系统。而随着工作流越来越复杂，这些框架的抽象则能带来很大的帮助。

本篇的课程中会介绍的几种agent框架：
* `smolagents`，Hugging Face开发的轻量级框架
* `Llama-Index`，端到端工具，处理上下文增强的AI agent
* `LangGraph`，允许有状态地对agent进行编排

## 3. smolagents 框架

本节中使用`smolagents`库来构建AI agent，构建的agent将具备这些功能：搜索数据、执行代码、网页交互，并能学习到如何将多个agents结合起来创建一个更为强大的系统。

本节包含的内容简介：
* `CodeAgents`（代码智能体），`smolagents`里主要的智能体类型，生成Python代码而不是JSON文本来执行操作（使用代码调用工作更高效）。
* `ToolCallingAgents`（工具调用智能体），`smolagents`支持的第二种智能体类型，依赖于系统必须解析和解释以执行操作的 JSON/文本块
* `Retrieval agents`（检索智能体），使模型能访问知识库，从而可以从多个来源搜索、综合和检索信息。
    * 它们利用向量存储（`vector stores`）进行高效检索，并实现 **检索增强生成（`Retrieval-Augmented Generation，RAG`）** 模式。
    * 这些智能体特别适用于将网络搜索与自定义知识库集成，同时通过记忆系统维持对话上下文。
* 工具
    * 在 `smolagents` 中，工具是使用 `@tool`装饰器（`decorator`） 包装`Python函数`或`Tool类`定义的
* 多智能体系统
* 视觉和浏览器智能体
    * 视觉智能体（`Vision agents`）通过整合 **视觉-语言模型（`Vision-Language Models，VLM`）** 扩展了传统智能体的能力，使其能够处理和解释视觉信息。

### 3.1. 构建使用代码的智能体

`CodeAgent`（代码智能体）是`smolagents`中的默认智能体类型，它们生成Python工具调用来执行操作，实现高效、表达力强且准确的操作表示。
* smolagents 提供了一个轻量级框架，用约 `1,000` 行代码实现构建代码智能体（code agents）。

代码智能体工作流程如下：  
![smolagents_codeagent_process](/images/smolagents_codeagent_process.png)

说明：
* smolagents 中智能体的主要抽象是 `MultiStepAgent`
* `CodeAgent`通过一系列步骤执行操作，将 **现有变量** 和 **知识** 整合到智能体的上下文中，这些内容保存在执行日志中。
    * 1、其中 **系统提示** 存储在 `SystemPromptStep` 中，**用户查询** 记录在 `TaskStep` 中
    * 2、而后执行以下循环（调用到`final_answer tool`才结束循环）：
        * 2.1 将智能体的日志写入大语言模型可读的聊天消息列表中
        * 2.2 这些消息发送给 模型（比如`LLM`/`VLM`），模型返回一个字符串结果，其中包含已经被提取出来的代码对象块（`code blob`）
        * 2.3 执行代码对象块，其中的任何工具调用通过函数调用工具后，继续执行后续代码
        * 2.4 将所有执行结果日志记录到 `ActionStep` 中

## 4. 小结

从这篇笔记开篇到现在正好一个月，进度停了挺长时间，最近开始需要慢慢调整下节奏了。之前是基于英文来看相应教程内容，想着同时能增强下英语阅读，但也导致学习新内容得到的正反馈断断续续，打击了一些积极性。还是切换成中文来看了，官网上的中文版本表达也不错，顺畅了不少。

## 5. 参考

* [AI Agents Course -- unit2](https://huggingface.co/learn/agents-course/unit2/introduction)
