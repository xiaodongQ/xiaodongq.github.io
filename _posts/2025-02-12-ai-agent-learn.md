---
layout: post
title: AI Agent学习实践笔记
categories: 大模型
tags: 大模型 AI
---

* content
{:toc}

HuggingFace AI Agents Course学习笔记



## 1. 背景

当前大模型发展日新月异，功能越来越强大。日常使用基本问答比较多，之前（[ollama搭建本地个人知识库](https://xiaodongq.github.io/2024/06/20/ollama-ai-models/)）也在本地用ollama部署千问简单体验了一下，但其功能不止于此，对于软件行业从业者来说帮助作用更为明显。比如火热的cursor编辑器、比如AI Agent（智能体），包括Devin软件工程师智能体。

看了一些资讯和文章，有提到说大模型经历ChatBot -> Copilot -> Agent几个阶段，觉得挺贴切。另外 关注的 [课代表立正](https://space.bilibili.com/491306902) 的 [2025年，AI最大机会是Agents，如何抓住18个月的窗口期？](https://www.bilibili.com/video/BV1YwfrYfE1s/?spm_id_from=333.1007.top_right_bar_window_history.content.click&vd_source=477b80445c7c1a81617bbea3bdf9a3c1) 、[做这三件事，可以舒服跟上AI发展节奏](https://www.bilibili.com/video/BV1xSknYEEtm/?spm_id_from=333.788.top_right_bar_window_history.content.click&vd_source=477b80445c7c1a81617bbea3bdf9a3c1) 这几期视频（酌情忽略卖课）提的观点和几个例子，联想结合到日常开发中确实能有不小的帮助，技术潮流还是得跟上。

正好了解到近期HuggingFace推出了一个免费的AI Agents课程：[AI Agents Course](https://huggingface.co/learn/agents-course/unit0/introduction)，先学习该课程并进行实践。

* 课程介绍：[AI Agents Course](https://huggingface.co/learn/agents-course/unit0/introduction)
* GitHub：[huggingface/agents-course](https://github.com/huggingface/agents-course)

下面是相应课程单元链接：

You can access the course here 👉 <a href="https://hf.co/learn/agents-course" target="_blank">https://hf.co/learn/agents-course</a>

| Unit | Topic                          | Description                                                                 |
|------|--------------------------------|-----------------------------------------------------------------------------|
| 0    | [Welcome to the Course](https://huggingface.co/learn/agents-course/en/unit0/introduction) | Welcome, guidelines, necessary tools, and course overview.                  |
| 1    | [Introduction to Agents](https://huggingface.co/learn/agents-course/en/unit1/introduction)       | Definition of agents, LLMs, model family tree, and special tokens.          |
| 2    | [2_frameworks](units/en/unit2/README.md)                     | Overview of smolagents, LangChain, LangGraph, and LlamaIndex.               |
| 3    | [3_use_cases](units/en/unit3/README.md)                      | SQL, code, retrieval, and on-device agents using various frameworks.        |
| 4    | [4_final_assignment_with_benchmark](units/en/unit4/README.md) | Automated evaluation of agents and leaderboard with student results.        |

## 2. 单元1：Agents介绍

**Agent定义**：是一个利用AI模型与其环境进行交互的系统，以实现用户定义的目标。它结合了推理，计划和执行操作（通常是通过外部工具）来完成任务。

举例：Agent是一个生活助手，告诉他我想要一杯咖啡。而后助手理解了自然语言，推理思考做一杯咖啡需要的步骤，并按步骤行动，过程中他可以使用其了解的工具。

图示：  
![请求咖啡图示](/images/2025-02-12-ai-agent-sample.jpg)

把Agent想象成2个部分：

* 大脑（AI模型）：处理推理和计划
    * Agent中使用的 *最通用* 的AI模型是 `LLM` (Large Language Model，大语言模型)，以**文本**作为输入，并以**文本**作为输出。
        * 也有可能使用其他输入的模型作为核心模型，比如视觉语言模型`Vision Language Model` (VLM)，可以理解图片作为输入
    * 比如来自 OpenAI的`GPT4`、Meta的`LLama`、Google的`Gemini` 等等
* 身体（能力和工具）：代表Agent能做的一切行动，可采取的行动依赖于Agent装配了什么工具

## 3. 小结

## 4. 参考

* [AI Agents Course](https://huggingface.co/learn/agents-course/unit0/introduction)

