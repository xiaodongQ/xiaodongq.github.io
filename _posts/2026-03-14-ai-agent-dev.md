---
title: AI能力集 -- Agent开发实践
description: Agent开发实践记录
categories: [AI, Agent开发]
tags: [AI, Agent]
---

## 1. 引言

[之前](https://xiaodongq.github.io/2025/08/27/ai-agent-learn-2-framework/) 跟着`Hugging Face`的[AI Agents Course](https://huggingface.co/learn/agents-course/unit0/introduction)简单实践过agent开发，实际使用的话还是应该选择一个比较主流的框架。现在通过IDE或者CLI直接一句话就可以生成了，其中的框架流程和具体逻辑还是有必要去掌握的。

Agent开发实践，相关参考链接：
* [crewai.cn文档](https://docs.crewai.org.cn/en/quickstart)
    * crew：[kruː]，团队的意思，CrewAI就是让你像组建团队一样来编排AI Agent
* AI生成的`CrewAI`和`LangChain`资料：[crewai-langchain-demos](https://github.com/xiaodongQ/ai-playground/tree/main/learning/crewai-langchain/crewai-langchain-demos)
    - 跟着实践的过程中，**发现AI生成的资料有些坑**，比如安装方式是老版本才支持的，**建议还是找官网文档或者他人实践过的文档为准**
* AI生成的`NanoClaw`资料，学习这个微型龙虾项目以了解`OpenClaw`原理：[nanoClaw-study](https://github.com/xiaodongQ/ai-playground/tree/main/nanoClaw-study)
* 他人实践：[从 0 到 1 复刻一个 Claude Code 这样的 Agent](https://plantegg.github.io/2026/03/05/%E4%BB%8E0%E5%88%B01%E5%A4%8D%E5%88%BB%E4%B8%80%E4%B8%AAClaude_Code%E8%BF%99%E6%A0%B7%E7%9A%84Agent/)

智能体开发框架很多，如`LangChain`/`LangGraph`/`AutoGen`/`CrewAI`等等，这里还是基于比较轻量的`CrewAI`框架来进行实践学习。

一般智能体开发框架的**核心：推理 + 行动**。
* `ReAct（Reasoning + Acting）`是目前 Agent 最主流的工作模式，来自 2022 年发表的论文 [ReAct: Synergizing Reasoning and Acting in Language Models](https://arxiv.org/abs/2210.03629)。
* 二者深度协同：
    * **推理轨迹**帮助模型归纳、跟踪、更新行动计划，并处理异常；
    * **行动**让模型与外部环境（知识库、API、交互环境）交互，获取真实信息以修正推理
    * 推理与行动统一为 LLM 的自然语言输出

另外说些题外话：AI发展到现在，会使用和不会使用的人，效率可以差很多倍。[用好AI的第一步：停止使用ChatGPT](https://www.superlinear.academy/c/ai-resources/stop-using-chatgpt) 这篇文章里面说得很好：
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

`CrewAI` 是一个专注于**多Agent协作**的框架，让你能够像组建团队一样编排`AI Agent`。

使用上比较清晰，直接跟着核心组件定义的代码示例看功能和相关属性参数。

### 2.1. 核心组件 之 Agent（智能体）

`Agent` 是 CrewAI 中的基本执行单元，类似于团队中的成员。

核心属性包含下面示例列出来的几个参数（`role`、`goal`等）。
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

核心属性见下面示例。
* 此外还有：`tools`（任务可用的工具，`List[BaseTool]`类型）、`context`（依赖的其他任务输出，`List[Task]`类型）

```py
from crewai import Task

research_task = Task(
    description="对{topic}进行彻底调研，确保找到所有相关信息",       # 任务的清晰描述
    expected_output="包含 10 个要点的列表，涵盖{topic}最重要的信息", # 任务完成的标准描述
    agent=researcher,                  # 负责执行的 Agent，此处用的是上面定义的研究员智能体
    output_file="research_report.md",                          # 输出文件路径
    markdown=True                                              # 是否使用 Markdown 格式输出
)
```

### 2.3. 核心组件 之 Crew（团队）

`Crew` 是 `Agent` 和 `Task` 的集合，定义了协作流程。

参数：`process（执行流程类型）`，可选取值：
* `Sequential`（顺序）：任务按定义顺序依次执行
    * 按照下例中的`tasks`定义的任务列表顺序来执行
* `Hierarchical`（层级）：根据 Agent 角色和专长分配任务
    * 按照下例中的`agents`参数指定的多个智能体的专长来分配任务进行执行

```py
from crewai import Crew, Process

crew = Crew(
    agents=[researcher, analyst],
    tasks=[research_task, analysis_task],
    process=Process.sequential,           # 任务按定义顺序依次执行
    verbose=True
)

# kickoff 执行结果容器
result = crew.kickoff(inputs={"topic": "AI Agents"})
```

### 2.4. 核心组件 之 Process（流程）

流程定义了 Crew 如何协调 Agent 和 Task 的执行。

### 2.5. 推荐的项目结构

CrewAI 推荐使用 `YAML` 配置 + `Python` 代码的混合方式：

```sh
my_crew/
├── src/
│   └── my_crew/
│       ├── __init__.py
│       ├── main.py           # 入口文件
│       ├── crew.py           # Crew 定义
│       └── config/
│           ├── agents.yaml   # Agent 配置
│           └── tasks.yaml    # Task 配置
├── pyproject.toml
└── .env
```

agents.yaml 示例：

```yaml
researcher:
  role: >
    {topic} 高级数据研究员
  goal: >
    发现{topic}领域的前沿发展
  backstory: >
    你是一位经验丰富的研究员，擅长发现最新发展趋势
...
```

tasks.yaml 示例：

```yaml
research_task:
  description: >
    对{topic}进行彻底调研
  expected_output: >
    包含 10 个要点的列表
  agent: researcher
...
```

## 3. 快速入门实践

### 3.1. 安装

暂时先用`pip install "crewai[tools]"`方式，和以前习惯一致。
* 如果要**隔离环境**安装（建议）
    * cd到项目路径后`python -m venv venv1`创建虚拟环境（此处虚拟环境叫`venv1`）
    * 然后激活环境`source venv1/bin/activate`
    * 再`pip install`安装
    * 若要退出则`deactivate`
* 注意老方式不可行了： ~~`pip install crewai crewai-tools`~~，`crewai-tools`已经改名/合并了

```sh
# 方式1
pip install "crewai[tools]"

# 方式2（推荐）
# uv 是 Python 世界里新一代超快的包管理器 + 虚拟环境工具
    # 它能干两件事：1）创建虚拟环境、2）安装 / 卸载 / 更新 Python 包
    # 现代 AI 项目（crewai、llama-index、langchain 都推荐用 uv）
# 等价命令 pip install 包名
uv add "crewai[tools]"
```

执行：`pip install 'crewai[tools]' -i https://mirrors.aliyun.com/pypi/simple/`（下载有点慢，指定国内镜像）
* 参考：[CrewAI 制作智能体](https://www.runoob.com/ai-agent/crewai-agent.html)
  * Python版本要求 必须：Python ≥ 3.10 且 < 3.14 ？这里说不满足版本范围的话，后续问题会非常多，不建议硬扛

听劝，还是让claude帮我升级下python，安装`3.12.0`版本：

```sh
我的python版本是多少，如何升级                        
我来帮你检查当前的 Python 版本。                      
Bash(python --version 2>&1 || python3 --version 2>&1) 
⎿  Python 3.9.21                                      
你当前的 Python 版本是 Python 3.9.21。                
方法 1：使用 pyenv（推荐，可管理多个版本）            
pyenv install 3.12.0
...
```

```sh
# 到项目目录创建隔离的虚拟环境，再安装crewai
[root@xdlinux ➜ python_path ]$ cd crew_ai_agent_test 
[root@xdlinux ➜ crew_ai_agent_test ]$ python -m venv venv1
[root@xdlinux ➜ crew_ai_agent_test ]$ source venv1/bin/activate
(venv1) [root@xdlinux ➜ crew_ai_agent_test ]$ pip install 'crewai[tools]' -i https://mirrors.aliyun.com/pypi/simple/
Collecting crewai[tools]
  Using cached crewai-0.5.0-py3-none-any.whl (27 kB)
WARNING: crewai 0.5.0 does not provide the extra 'tools'
Collecting pydantic<3.0.0,>=2.4.2
  Downloading pydantic-2.12.5-py3-none-any.whl (463 kB)
     |████████████████████████████████| 463 kB 55 kB/s             
...
Collecting SQLAlchemy<3,>=1.4
  Downloading sqlalchemy-2.0.48-cp39-cp39-manylinux2014_x86_64.manylinux_2_17_x86_64.manylinux_2_28_x86_64.whl (3.2 MB)
...
```

CrewAI 的 LLM 对第三方模型（包括 DeepSeek）底层必须通过 `LiteLLM`，使用前我们需要先安装：`pip install -U litellm`
* **LiteLLM介绍**：开源LLM统一网关与调用框架，核心价值在于用OpenAI标准格式一键调用其他主流模型，同时提供成本追踪、故障容错、流量控制等企业级能力
* 可参考 [CrewAI 制作智能体](https://www.runoob.com/ai-agent/crewai-agent.html) 里的说明

```sh
(venv1) [root@xdlinux ➜ crew_ai_agent_test ]$ pip install litellm -i https://mirrors.aliyun.com/pypi/simple/
Looking in indexes: https://mirrors.aliyun.com/pypi/simple/
Collecting litellm
...
```

### 3.2. 开发方式1：手动创建文件

方式1：简单逻辑，可以手动创建文件

前面“修复 sqlite3 版本问题”那段是必要的，要不会报错 `RuntimeError: Your system has an unsupported version of sqlite3. Chroma requires sqlite3 >= 3.35.0.` （另一个方式是把系统的sqlite升级到>=3.35，目前yum安装时我的系统是3.34，需要源码编译安装）

```py
[root@xdlinux ➜ crew_ai_agent_test ]$ cat test.py 
# 修复 sqlite3 版本问题
import pysqlite3 as sqlite3
import sys
sys.modules['sqlite3'] = sqlite3

from dotenv import load_dotenv
import os

# 从 .env 文件加载环境变量
load_dotenv()

from crewai import Agent, Task, Crew, Process
from crewai.llm import LLM

# ==================== 配置 LLM ====================
llm = LLM(
    model=os.getenv("LLM_MODEL", "openai/qwen3.5-plus"),
    api_key=os.getenv("LLM_API_KEY"),
    api_base=os.getenv("LLM_API_BASE"),
    temperature=0.7,
)

# ==================== 1. 定义 Agent ====================

# 研究员 Agent
researcher = Agent(
    role="技术研究员",
    goal="深入调研{topic}领域，找出关键信息和技术要点",
    backstory=(
        "你是一位经验丰富的技术研究员，拥有 10 年技术调研经验。"
        "你擅长从海量信息中筛选出最关键的内容，并用清晰的结构呈现。"
        "你特别关注技术的实用性、性能特点和适用场景。"
    ),
    llm=llm,  # 显式传递 LLM 配置
    verbose=True,
    allow_delegation=False
)

# ==================== 2. 定义 Task ====================
# 调研任务
research_task = Task(
    description=(
        "对{topic}进行彻底调研，重点关注：\n"
        "1. 核心概念和原理\n"
        "2. 主要特点和优势\n"
        "3. 典型使用场景\n"
        "4. 与其他技术的对比\n"
        "5. 学习资源和最佳实践\n\n"
        "确保信息准确、结构清晰，适合有 C++/Go 背景的开发者阅读。"
    ),
    expected_output=(
        "一份包含以下内容的调研报告：\n"
        "- 核心概念（5-7 个要点）\n"
        "- 技术特点（3-5 个要点）\n"
        "- 使用场景（3-5 个场景）\n"
        "- 对比分析（与 1-2 个类似技术对比）\n"
        "- 学习建议（3-5 条建议）"
    ),
    agent=researcher,
    output_file="output/research_report.md"  # 输出到文件
)

# ==================== 3. 创建 Crew ====================
crew = Crew(
    agents=[researcher],
    tasks=[research_task],
    process=Process.sequential,
    verbose=True,
    memory=False  # 禁用记忆功能（需要额外的 embedder 配置）
)

# ==================== 4. 执行 ====================
if __name__ == "__main__":
    print("🚀 启动 CrewAI 基础 Demo - 技术调研团队")
    print("=" * 50)

    # 传入主题参数
    inputs = {
        "topic": "Claude Code使用技巧"  # 可以改成任何你想调研的主题
    }

    print(f"📋 调研主题：{inputs['topic']}")
    print("=" * 50)
    print()

    # 启动执行
    result = crew.kickoff(inputs=inputs)
    print()
    print("=" * 50)
    print("✅ 任务完成！")
    print(f"\n📄 调研报告：output/research_report.md")
```

执行：

```sh
((venv2) ) [root@xdlinux ➜ crew_ai_agent_test ]$ python test.py
🚀 启动 CrewAI 基础 Demo - 技术调研团队
==================================================
📋 调研主题：Claude Code使用技巧
==================================================
...
│  **结语：**    
│  Claude 编程辅助技术并非要取代开发者，而是作为“力倍增器”（Force Multiplier）...
│                     
╰───────────────────────────────────────────────────────────────────────────────────────────────────────────

==================================================
✅ 任务完成！

📄 调研报告：output/research_report.md

╭───────────────────────────────────────────── Tracing Status ───────────────────────────
│                
│  Info: Tracing is disabled.        
│  To enable tracing, do any one of these:                                              
│  • Set tracing=True in your Crew/Flow code                                                
│  • Set CREWAI_TRACING_ENABLED=true in your project's .env file                           
│  • Run: crewai traces enable           
╰─────────────────────────────────────────────────────────────────────────────────────────────────────
```

### 3.3. 开发方式2：创建项目

用`crewai create`命令来自动创建项目层级，基于yaml文件来定义`agent`和`task`：`crewai create crew test_project`（也报错需要`sqlite3 >= 3.35.0`，解决方式见下面的问题记录小节）。

解决依赖问题后创建项目，按照提示进行操作：
* 选择大模型的提供商，这里先选`openai`（`crewai create crew test_project --skip_provider`方式可以跳过这个步骤，可后续手动创建`.env`）
* 模型和key也先随便选一下，走完项目目录结构的创建流程，后面再进行修改

1、`crewai create crew test_project`

```sh
((venv2) ) [root@xdlinux ➜ crew_ai_agent_test ]$ crewai create crew test_create_project
Creating folder test_create_project...
Cache expired or not found. Fetching provider data from the web...
Downloading  [####################################]  1313681/67203
Select a provider to set up:
1. openai
2. anthropic
3. gemini
4. nvidia_nim
5. groq
6. huggingface
7. ollama
8. watson
9. bedrock
10. azure
11. cerebras
12. sambanova
13. other
q. Quit
Enter the number of your choice or 'q' to quit: 
Enter the number of your choice or 'q' to quit: 1
Enter your OPENAI API key (press Enter to skip): 1
API keys and model saved to .env file
Selected model: gpt-4
  - Created test_create_project/.gitignore
  - Created test_create_project/pyproject.toml
  - Created test_create_project/README.md
  - Created test_create_project/knowledge/user_preference.txt
  - Created test_create_project/src/test_create_project/__init__.py
  - Created test_create_project/src/test_create_project/main.py
  - Created test_create_project/src/test_create_project/crew.py
  - Created test_create_project/src/test_create_project/tools/custom_tool.py
  - Created test_create_project/src/test_create_project/tools/__init__.py
  - Created test_create_project/src/test_create_project/config/agents.yaml
  - Created test_create_project/src/test_create_project/config/tasks.yaml
Crew test_create_project created successfully!
```

项目结构如下：

```sh
((venv2) ) [root@xdlinux ➜ crew_ai_agent_test ]$ tree test_create_project 
test_create_project
├── AGENTS.md                  # 一些架构说明和最佳实践示例（可创建crew或flow项目）
├── knowledge
│   └── user_preference.txt
├── pyproject.toml
├── README.md
├── .env                       # 模型提供商和key
├── src
│   └── test_create_project
│       ├── config
│       │   ├── agents.yaml    # Agent配置
│       │   └── tasks.yaml     # Task配置
│       ├── crew.py            # 业务定义
│       ├── __init__.py
│       ├── main.py            # 入口文件
│       └── tools
│           ├── custom_tool.py
│           └── __init__.py
└── tests
```

2、配置模型和API

由于第三方api通过`LiteLLM`(大模型统一接口转换工具)方式接入，所以`.env`里如下方式使用（此处用的千问）
```sh
LLM_API_KEY=sk-sp-0b9521xxxxxxxxxxxxx
LLM_API_BASE=https://coding.dashscope.aliyuncs.com/v1
LLM_MODEL=openai/qwen3.5-plus
```

3、对模版代码进行修改，步骤如下

* 修改agents.yaml
* 修改tasks.yaml
* 修改crew.py
* [可选] 添加团队前后处理函数（使用`@before_kickoff`和`@after_kickoff`装饰器）

4、实际验证

test_create_project/crew.py默认内容：

```sh
researcher:
  role: >
    {topic} Senior Data Researcher
  goal: >
    Uncover cutting-edge developments in {topic}
  backstory: >
    You're a seasoned researcher with a knack for uncovering the latest
    developments in {topic}. Known for your ability to find the most relevant
    information and present it in a clear and concise manner.

reporting_analyst:
  role: >
    {topic} Reporting Analyst
  goal: >
    Create detailed reports based on {topic} data analysis and research findings
  backstory: >
    You're a meticulous analyst with a keen eye for detail. You're known for
    your ability to turn complex data into clear and concise reports, making
    it easy for others to understand and act on the information you provide.
```

#### 3.3.1. 实际运行

**需求丢给AI来修改**：我要修改成一个技术自媒体专家，非常擅长微信小红书抖音运营，并帮我输出可落地的报告

修改后内容可见：[crew_ai_agent_test](https://github.com/xiaodongQ/crew_ai_agent_test.git)

1、agents.yaml：

```yaml
wechat_specialist:
  role: >
    微信运营专家
  goal: >
    制定并执行高效的微信平台内容策略，提升用户互动和粉丝增长
  backstory: >
    您是微信生态运营领域的资深专家，精通公众号、视频号、朋友圈等微信生态内容创作与运营，
    熟悉微信用户的使用习惯和算法推荐机制，能够制定出高传播性的内容策略。

xiaohongshu_specialist:
...
reporting_analyst:
...
```

2、tasks.yaml

```yaml
wechat_strategy_task:
  description: >
    针对人工智能技术主题，制定详细的微信平台运营策略。
    分析微信生态特点，包括公众号、视频号、朋友圈等渠道，
    设计适合微信用户的内容形式、发布频率、互动方式，
    并提供具体的标题、封面图和内容框架建议。
  expected_output: >
    一份完整的微信平台运营策略报告，包含：
    1. 微信生态分析（公众号、视频号、朋友圈）
    2. 内容策略（选题方向、内容形式、发布计划）
    3. 互动策略（用户增长、粉丝维护、社群运营）
    4. 具体执行建议（标题模板、封面设计、内容框架）
  agent: wechat_specialist

xiaohongshu_strategy_task:
...
reporting_task:
...
```

3、crew.py和main.py中也有相关修改，具体见上面仓库链接

4、`python run_crew.py`运行，报告结果在`social_media_report.md`
```sh
((venv2) ) [root@xdlinux ➜ test_create_project git:(main) ✗ ]$ ls
AGENTS.md  pyproject.toml  social_media_report.md  tests
knowledge  README.md       src
```

social_media_report.md部分内容：

```sh
## 1. 各平台对比分析：优劣势、适用场景与用户特征
### 1.1 平台核心属性对比表
...
### 1.2 深度分析与定位建议

*   **微信：信任的基石与变现的终点**
    *   **定位：** 作为“大本营”，承载最深度的内容和服务。
    *   **策略：** 利用公众号建立专业权威，利用视频号突破圈层获取公域流量，最终通过企业微信和社群完成高客单价转化（如课程、咨询、企业服务）。
    *   **关键点：** 必须做好“公域引流 -> 私域沉淀”的路径设计，避免流量浪费。

*   **小红书：精准的搜索引擎与品牌门面**
    *   **定位：** 作为“名片”与“获客渠道”，吸引追求自我提升和实用工具的年轻群体。
    *   **策略：** 侧重“颜值”与“实用”，将高技术门槛降维。利用 SEO 优化获取长尾搜索流量（如"AI 怎么写公文”）。
    *   **关键点：** 封面图决定点击率，干货内容决定收藏率。需注意引流合规性，避免直接导流微信。

*   **抖音：流量的放大器与品牌声量**
    *   **定位：** 作为“扩音器”，最大化品牌曝光，触达泛人群。
    *   **策略：** 侧重“视觉冲击”与“节奏感”。利用 AI 生成的惊艳视觉效果吸引停留，通过通俗语言讲解技术。
    *   **关键点：** 前 3 秒定生死。需高频更新以维持账号权重，适合通过直播进行大规模变现或引流。
...
```

## 4. 问题记录

### 4.1. Chroma依赖的sqlite版本报错：sqlite3 >= 3.35.0

`RuntimeError: Your system has an unsupported version of sqlite3. Chroma requires sqlite3 >= 3.35.0.`

虽然从[sqlite官网](https://www.sqlite.org/download.html)下载了新版本包进行编译安装（**没啥用**），如`sqlite-autoconf-3510300.tar.gz`，但是Python环境里面还是用的旧版。`crewai create`执行还是会报上述错误。

```sh
[root@xdlinux ➜ sqlite-autoconf-3510300 ]$ /usr/local/bin/sqlite3 --version
3.51.3 2026-03-13 10:38:09 737ae4a34738ffa0c3ff7f9bb18df914dd1cad163f28fd6b6e114a344fe6d618 (64-bit)
```

**系统命令行的 sqlite3 ≠ Python 调用的 sqlite3**

解决方式：安装兼容补丁后，自动注入Python环境：

```sh
# 激活虚拟环境（你已经在里面了可以跳过）
source venv2/bin/activate

# 安装兼容补丁（最关键）
pip install pysqlite3-binary

# 自动注入 Python 环境（强制使用新版本）
cat > venv2/lib/python3.12/site-packages/sitecustomize.py << EOF
__import__('pysqlite3')
import sys
sys.modules['sqlite3'] = sys.modules.pop('pysqlite3')
EOF
```
