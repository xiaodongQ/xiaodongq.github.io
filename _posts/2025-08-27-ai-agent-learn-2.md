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


## 4. 小结


## 5. 参考

* [AI Agents Course -- unit2](https://huggingface.co/learn/agents-course/unit2/introduction)
