---
title: AI Agent学习实践笔记（三） -- RAG系统
description: HuggingFace AI Agents Course学习笔记，RAG系统
categories: [AI, LLM]
tags: [AI, LLM, RAG]
---

## 1. 引言

本篇介绍 **检索增强生成（`Retrieval-Augmented Generation，RAG`）系统**。

`RAG`结合了数据检索和生成模型的能力，以提供上下文感知的响应：
* 1、根据用户查询（利用搜索引擎、LLM）检索到结果
* 2、检索结果和用户查询一起提供给模型
* 3、模型随后根据查询和检索到的信息生成响应

传统的`RAG` VS 智能体驱动的`RAG`（`Agentic RAG`）：
* 智能驱动的`RAG`（Retrieval-Augmented Generation）通过将自主智能体与动态知识检索相结合，**扩展了传统`RAG`系统**
* `传统RAG系统`使用 LLM 根据检索数据回答查询，而`智能驱动的RAG` 实现了对检索和生成流程的智能控制，从而**提高了效率和准确性**
* `传统RAG系统`面临关键限制，例如依赖单次检索步骤、过度关注与用户查询的语义相似性，可能会遗漏相关信息
* 智能驱动的`RAG`通过允许智能体自主制定搜索查询、评估检索结果并进行**多次**检索步骤，以生成**更定制化和全面的输出**

## 2. 小结



## 3. 参考

* [AI Agents课程 -- unit2：检索智能体](https://huggingface.co/learn/agents-course/zh-CN/unit2/smolagents/retrieval_agents)
* [AI Agents课程 -- unit3：Agentic RAG用例](https://huggingface.co/learn/agents-course/zh-CN/unit3/agentic-rag/introduction)
