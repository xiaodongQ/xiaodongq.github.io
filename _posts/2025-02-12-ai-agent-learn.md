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

当前AI发展日新月异，功能越来越强大。日常只是使用基本问答比较多，之前（[ollama搭建本地个人知识库](https://xiaodongq.github.io/2024/06/20/ollama-ai-models/)）也在本地用ollama部署千问简单体验了一下。近几年AI大模型应用从ChatBot -> Copilot -> Agent，对于软件行业从业者来说相关辅助更为明显，比如火热的cursor编辑器、Devin软件工程师智能体。

技术潮流还是得跟上，正好了解到近期HuggingFace推出了一个免费的AI Agents课程：[AI Agents Course](https://huggingface.co/learn/agents-course/unit0/introduction)，先学习该课程并进行实践。

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

### 2.1. 什么是Agent

**Agent定义**：是一个利用AI模型与其环境进行交互的系统，以实现用户定义的目标。它结合了推理（reason），计划（plan）和执行操作（通常是通过外部工具）来完成任务。

举例：Agent是一个生活助手，告诉他我想要一杯咖啡。而后助手理解了自然语言，推理思考做一杯咖啡需要的步骤，并按步骤行动，过程中他可以使用其了解的工具。

图示：  
![请求咖啡图示](/images/2025-02-12-ai-agent-sample.jpg)

把Agent想象成2个部分：

* 大脑（AI模型）：处理推理和计划
    * Agent中使用的 *最通用* 的AI模型是 `LLM` (Large Language Model，大语言模型)，以**文本**作为输入，并以**文本**作为输出。
        * 也有可能使用其他输入的模型作为核心模型，比如视觉语言模型`Vision Language Model` (VLM)，可以理解图片作为输入
    * 比如来自 OpenAI的`GPT4`、Meta的`LLama`、Google的`Gemini` 等等
* 身体（能力和工具）：代表Agent能做的一切行动，可采取的行动依赖于Agent装配了什么工具

### 2.2. 什么是LLM

`LLM`（Large Language Model，大语言模型） 是一种人工智能模型，擅长理解和生成人类语言。它们接受了大量文本数据的训练，使它们能够学习语言的模式、结构甚至细微差别。这些模型通常由数百万个参数组成。

当前大部分LLM都是建立在`Transformer`架构之上的，这是一种基于 “注意力”（`Attention`） 算法的深度学习架构，自2018年`Google`发布`BERT`以来，该架构引起了人们的极大兴趣。

> `Transformer` 架构是一种基于自注意力机制（Self-Attention）的深度学习模型，广泛应用于自然语言处理（NLP）任务，如机器翻译、文本生成、文本分类等。它由 Vaswani 等人在 2017 年的论文`《Attention is All You Need》`中首次提出，并迅速成为 NLP 领域的核心架构。

> `BERT` 是基于 Transformer 编码器的一种预训练语言模型，通过双向上下文建模和创新的训练任务（如 MLM 和 NSP），在 NLP 领域取得了巨大成功。  
> 它不仅继承了 Transformer 的强大能力，还通过`预训练-微调范式`推动了 NLP 技术的发展。`BERT` 的提出标志着 NLP 进入了预训练语言模型的新时代，后续的许多模型（如 GPT、T5 等）都受到了它的启发。

Transformer 架构有3种类型：

* 编码器（Encoder）
    * 将文本转化为密集表示，用于文本分类、语义搜索等，比如Google的`BERT`
* 解码器（Decoder）
    * 逐一生成新标记以完成序列，用于文本生成、聊天机器人、代码生成等，比如Meta的`Llama`
* 序列到序列（Seq2Seq ）
    * 结合两者，用于翻译、总结、释义等，比如 T5（Google）、BART（Meta）

常见模型：

|模型|公司|
|--|--|
|Deepseek-R1|DeepSeek|
|GPT4|OpenAI|
|Llama 3|Meta (Facebook AI Research)|
|SmolLM2|Hugging Face|
|Gemma|Google|
|Mistral|Mistral|

#### 2.2.1. LLM 的工作原理

大语言模型（LLM）的基本原理简单却极为有效：其目标是在给定前文一系列`token`（词元）的情况下，预测下一个`token`。`token`是大语言模型处理信息的基本单位。可以把 “token” 想象成 “单词”，但出于效率考虑，大语言模型并不使用完整的单词。

每个LLM都有一些特殊的token，LLM使用这些token来标记区分其生成过程中的一些组件，比如用于标记序列/消息/应答的开始和结束，其中最重要的标记是序列结束：End of sequence token (`EOS`)

**预测下一个token**：

LLM是自回归的（`autoregressive`），这意味着一个token的输出作为下一个token的输入，直到预测的下一个token是`EOS`。

* 输入文本被token化（tokenized）后，模型会计算该序列的一种表征（representation），这种表征涵盖了输入序列中每个token的含义及位置信息。
* 这种表征会输入到模型中，模型随后输出`分数`，对其词汇表中每个token作为序列下一个token的可能性进行排序。

**解码策略（decode）**：

基于这些分数，可以有多种`解码`策略来选择哪些token来完成后续的内容。比如简单地总是选取分数最高的标记；更高级的有束搜索，它会探索多个候选序列，找到总分最高的序列

**注意力机制**：

Transformer架构中的`注意力`（Attention）机制至关重要。

在预测下一个单词时，句子中的每个单词重要性并不是相同的，注意力机制能够识别出最相关的单词，从而提高预测的准确性。比如`The capital of France is …`中，`capital`和`France`是最重要的。

**几个概念：**

* `上下文长度`（context length）：指LLM能处理的最大标记数量，也是其注意力的最大跨度
* `提示词`（prompt）：输入给LLM的序列被称为`提示`（prompt），精心设计提示有助于引导LLM生成期望的输出
    * 考虑到LLM的唯一工作是通过查看每个输入token来预测下一个token，并选择哪个token是 “重要的”，因此输入序列的措辞（即prompt）非常重要

#### 2.2.2. LLM 是如何训练的

LLM在大规模文本数据集上进行训练，在此过程中，它们通过`自监督`（self-supervised）或`掩码语言`（masked language）建模目标，来学习预测序列中的下一个单词。

> “masked language” 通常指 “掩码语言”，在自然语言处理领域，尤其是在语言模型的训练中，“掩码语言建模（Masked Language Modeling，MLM）” 是一种常用的技术手段。  
> 原理：在训练数据中随机选择一些单词或词元，并将它们替换为特殊的掩码标记（例如 “[MASK]”）。然后，模型的任务是根据上下文来预测这些被掩码的单词或词元是什么。通过这种方式，模型被迫学习文本中的语言模式和语义信息，以便能够准确地预测被掩码的部分。  
> 作用：增强语言理解能力、提高模型泛化能力

通过这种`无监督学习`（unsupervised learning），模型能够学习语言结构以及文本中的潜在模式，从而使模型能够对未曾见过的数据进行泛化处理。

在完成这一初始`预训练`（pre-training）后，大语言模型（LLM）可以基于`有监督学习目标`（supervised learning objective）进行`微调`（**`fine-tuned`**），以执行特定任务。例如，一些模型针对对话结构或工具使用进行训练，而另一些则专注于分类或代码生成。

> 有监督学习（supervised learning）是指利用标记好的训练数据来训练模型，让模型学习输入特征与输出标签之间的映射关系，从而对未知数据进行预测和分类的机器学习方法。在有监督学习中，训练数据集中的每个样本都由输入特征向量和对应的输出标签组成，模型通过学习这些样本数据，试图找到一种`通用的模式或函数`，使得对于新的输入数据，能够准确地`预测`出相应的输出。

#### 2.2.3. LLM如何使用

有两种主要方式：

* 1、本地运行。需要有足够的硬件支持
* 2、使用云服务或API。比如通过 Hugging Face 的无服务器推理 API，本课程主要采用这种方式

**小结**：LLM 是 AI智能体（AI Agents）的关键组成部分，为智能体理解和生成人类语言提供基础。它能够解释用户指令、在对话中保持上下文连贯、制定行动规划并决定使用哪些工具，是 AI智能体的核心 “大脑”。

### 2.3. 消息与特殊标记

本节介绍LLM如何通过`聊天模板（chat templates）`组织生成的内容。与 ChatGPT 类似，用户通常通过聊天界面与智能体进行交互。因此，我们旨在了解大语言模型是如何管理聊天过程的。

当你与 ChatGPT 或 Hugging Chat 这类系统聊天时，实际上是在`交换消息（exchanging messages）`。在后台，这些消息会被连接并格式化为模型能够理解的`提示（prompt）`

如下例可见 从UI上看到的内容 和 喂给模型的提示内容 的差异：

![UI和后台内容差异](/images/2025-02-16-llm-assistant.jpg)

这里就是`聊天模板（chat templates）`发生作用的地方，它们充当了`对话消息（conversational messages ）`（上图中`用户`和`助手`间的轮次）与所选大语言模型`特定格式要求（the specific formatting requirements）`之间的桥梁。换句话说，聊天模板构建了用户与智能体之间的交流结构，确保每个模型，尽管它们有独特的特殊token，都能收到格式正确的提示（prompt）。

**消息**：大语言模型的底层系统

* `系统消息（System Messages）`，也称为系统提示（System Prompts），定义了模型应有的行为方式。它们作为`持久的指令`（persistent instructions），指导后续的每一次交互。
    * 在使用智能体时，系统消息还会提供有关`可用工具`的信息，向模型说明如何格式化`要采取的行动`（how to format the actions to take），并包含关于`思维过程应如何分段`的指导原则。
* `对话（Conversations）`，用户消息和助手消息
    * `对话`由人类（用户）和大语言模型（助手）之间交替的消息组成。

## 3. 小结

## 4. 参考

* [AI Agents Course](https://huggingface.co/learn/agents-course/unit0/introduction)

* GPT