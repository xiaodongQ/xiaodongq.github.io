---
title: Claude Code系列 -- 手搓coding agent学习Harness工程
description: 手搓coding agent学习Harness工程
categories: [AI, Claude Code系列]
tags: [Claude Code, Harness]
---

## 1. 引言

通过`learn-claude-code`项目，跟着实践学习`Harness`工程。

参考链接：
* [learn-claude-code](https://github.com/shareAI-lab/learn-claude-code)，[fork](https://github.com/xiaodongQ/learn-claude-code)一份便于自己批注修改。
* 仓库对应的[中文文档](https://github.com/xiaodongQ/learn-claude-code/blob/main/README-zh.md)
* [Claude Code核心源码解析 -- 架构设计和工程细节透视Harness最佳实践](http://gk.link/a/12IoB)，极客时间上的直播，讲得很好。（里面的框图挺好，有个思路：把图保存到自己的素材库，让AI生成时就有好的参考了）

> 这篇之前进行了一小半，零零散散看了一些，拖到现在也挺久了，此处进行梳理输出，倒推实践。fork了一个不错的AI相关学习仓库：[AgentGuide](https://github.com/xiaodongQ/AgentGuide)，可参考实践（里面AI生成内容很多，需鉴别后部分参考）。

## 2. 先看看Claude Code架构

Claude Code是AI行业的标杆之一，模型和工程上都是T0级别。从Claude Code前段时间泄漏的代码里能参考学习到很多东西，基于上面的“Claude Code核心源码解析 -- 架构设计和工程细节透视Harness最佳实践”做些笔记记录。

1、`Claude Code`不只是AI Coding工具，而且是`Harness`的一个最佳实践样板。

`Agent = Model + Harness`，除了模型外的周边机制都可以泛化当成`Harness`，比如工具、记忆、安全等等。

2、架构分层（看看包含哪些Harness机制）

![claude-code-overview](/images/claude-code-overview.png)

工具：  
![claude-code-tools](/images/claude-code-tools.png)

3、核心流程（基本是一个通用agent的ReAct流程）

![claude-code-core-loop](/images/claude-code-core-loop.png)

4、上下文管理（**很值得借鉴，如何组织提示词和提高缓存命中**）

静态信息放前面（尽量能缓存住） -> **静态分隔符**（分隔符前的内容优先最大程度缓存）-> 动态信息放后面。

![claude-code-context-memory-prompt](/images/claude-code-context-memory-prompt.png)

5、Agent协作机制（按场景按需使用不同agent）

几种协作模式：  
![claude-code-agents-overview](/images/claude-code-agents-overview.png)

各自模式下的agent协作示意：
* 1、`fork-agent`模式会复制原有上下文，`Prompt Cache`最大化、后台异步。当需要同时处理多个互不干扰的子任务时（例如，同时分析三个不同的文件，或并行运行三个不同的测试用例），系统会“分叉”出多个独立的 Agent 实例。它们共享主任务的初始上下文（利用缓存），然后各自异步执行，最后汇总结果。
* 2、`sub-type-agent`具有特定角色和工具集，上下文是隔离的。系统会预设或动态生成具有特定技能的子代理，比如：`Explore Agent`专门负责搜索和收集信息；`Plan Agent`：专门负责制定任务计划；`Verification Agent`：专门负责验证结果的正确性。通用agent和fork-agent都依赖于主agent执行任务。
* 3、协调者模式(`coordinator`)，大任务拆解，需要多Agent编排。限制主agent只能编排任务而不执行，用XML结构化汇报。
* 4、`team`模式由多角色长期协作，各有独立上下文。每个Agent扮演一个固定角色（如产品经理、前端工程师、后端工程师），拥有自己的“邮箱”（`Mailbox`）用于接收和发送消息，并在独立的“终端窗格”中工作。它们之间可以互相通信、协作，形成一个“虚拟团队”。
* 5、`General Purpose`(通用型)，最基础的模式。普通任务，不需要拆分或委派。适用于简单、线性的任务，比如“帮我写一个 Hello World 程序”

![claude-code-agents-case](/images/claude-code-agents-case.png)

**异步并发执行**（subagent、异步执行shell），触发技巧：`帮我用subagnet并发完成xxx`。

## learn-claude-code

