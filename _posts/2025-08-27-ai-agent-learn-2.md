---
title: AI Agent学习实践笔记（二） -- Agent框架：smolagents
description: HuggingFace AI Agents Course学习笔记，unit2 -- Agent框架
categories: [AI, LLM]
tags: [LLM, AI]
---

## 1. 引言

上一篇：[AI Agent学习实践笔记（一） -- Agents介绍](https://xiaodongq.github.io/2025/02/12/ai-agent-learn/) 进行了智能体的基本介绍，间隔比较久了，继续后续的unit学习。

AI发展日新月异，后续还有不少内容可以继续学习，如 [mcp-course](https://huggingface.co/learn/mcp-course/unit0/introduction)，加入TODO List。

## 2. Agent框架介绍

Agentic框架（Agentic Framework）不一定必须，如果只是简单的工作流，则预定义的工作流可能就够了。相对于使用agent框架，开发者能够拥有完全的系统控制权，不需要带着框架的抽象来理解系统。而随着工作流越来越复杂，这些框架的抽象则能带来很大的帮助。

会介绍的几种agent框架：
* `smolagents`，Hugging Face开发的轻量级框架
* `Llama-Index`，端到端工具，处理上下文增强的AI agent
* `LangGraph`，允许有状态地对agent进行编排

## 3. smolagents 框架

本节中使用`smolagents`库来构建AI agent，构建的agent将具备这些功能：搜索数据、执行代码、网页交互，并能学习到如何将多个agents结合起来创建一个更为强大的系统。
* 仓库地址：[huggingface/smolagents](https://github.com/huggingface/smolagents.git)
* 文档地址：[smolagents guided_tour](https://huggingface.co/docs/smolagents/v1.22.0/zh/guided_tour)

本节包含的内容简介：
* `CodeAgents`（代码智能体），`smolagents`里主要的智能体类型，生成Python代码而不是JSON文本来执行操作（使用代码调用工作更高效）。
* `ToolCallingAgents`（工具调用智能体），`smolagents`支持的第二种智能体类型，依赖于系统必须解析和解释以执行操作的 JSON/文本块
* `Retrieval agents`（检索智能体），使模型能访问知识库，从而可以从多个来源搜索、综合和检索信息。
    * 它们利用向量存储（`vector stores`）进行高效检索，并实现 **检索增强生成（`Retrieval-Augmented Generation，RAG`）** 模式。
    * 这些智能体特别适用于将网络搜索与自定义知识库集成，同时通过记忆系统维持对话上下文。
* 工具
    * 在 `smolagents` 中，工具是使用 `@tool`装饰器（`decorator`）包装`Python函数` 或 `Tool类`定义的
* 多智能体系统
* 视觉和浏览器智能体
    * 视觉智能体（`Vision agents`）通过整合 **视觉-语言模型（`Vision-Language Models，VLM`）** 扩展了传统智能体的能力，使其能够处理和解释视觉信息。

两种方式定义工具示例：
* 方式1:`@tool`装饰器方式需要定义包含以下要素的函数：
    * 明确描述性的函数名称：帮助LLM理解其用途
    * 输入输出的类型提示：确保正确使用
    * 详细描述：包含明确描述各参数的Args:部分，这些描述为 LLM 提供关键上下文信息
```py
@tool
def catering_service_tool(query: str) -> str:
    """
    This tool returns the highest-rated catering service in Gotham City.
    
    Args:
        query: A search term for finding catering services.
    """
    ...

agent = CodeAgent(tools=[catering_service_tool], model=InferenceClientModel())
```

* 方式2：通过Python类定义工具（创建`Tool`的子类）。对于复杂工具，可以通过类封装函数及其元数据来帮助LLM理解使用方式，类中需要定义：
    * name: 工具名称
    * description: 用于构建智能体系统提示的描述
    * inputs: 包含type和description的字典，帮助Python解释器处理输入
    * output_type: 指定期望的输出类型
    * forward: 包含执行逻辑的方法
```py
class SuperheroPartyThemeTool(Tool):
    name = "superhero_party_theme_generator"
    description = """ This tool suggests creative superhero-themed party ideas based on a category.xxx """
    inputs = {
        "category": {
            "type": "string",
            "description": "The type of superhero party (e.g., 'classic heroes',xxx",
        }
    }
    output_type = "string"

    def forward(self, category: str):
        themes = {
            "classic heroes": "Justice League Gala: Guests come dressed as their favorite DC heroes.",
            "villain masquerade": "Gotham Rogues' Ball: A mysterious masquerade where xxx.",
        }
        return themes.get(category.lower(), "Themed party idea not found. Try 'classic heroes', 'villain' xxx")

# 实例化工具
party_theme_tool = SuperheroPartyThemeTool()
agent = CodeAgent(tools=[party_theme_tool], model=InferenceClientModel())
```

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

下面进行简单demo实验。

目标：使用`smolagents`为派对选择播放列表。
* 构建一个可以使用`DuckDuckGo`（一个互联网搜索引擎）来搜索网络的智能体

#### 3.1.1. 安装`smolagents`框架

安装：`pip install smolagents -U`
* （MacOS上直接使用pip安装会提示“This environment is externally managed”，这里使用环境管理器创建用于项目隔离的虚拟环境以解决该问题，可了解：[通过brew安装的python无法使用pip安装第三方库](https://25pm-sumio.github.io/posts/2024/09/12/01/)）

```sh
# 创建虚拟环境
[MacOS-xd@qxd ➜ ~ ]$ python3 -m venv ./env
# 后续使用先加载虚拟环境： source /Users/xd/env/bin/activate
[MacOS-xd@qxd ➜ ~ ]$ source ./env/bin/activate 
(env) [MacOS-xd@qxd ➜ ~ ]$ 
# pip安装 smolagents 包
(env) [MacOS-xd@qxd ➜ ~ ]$ pip install smolagents -U
Collecting smolagents
  Downloading smolagents-1.22.0-py3-none-any.whl.metadata (16 kB)
Collecting huggingface-hub>=0.31.2 (from smolagents)
...
Installing collected packages: urllib3, typing-extensions, tqdm, pyyaml, python-dotenv, pygments, pillow, packaging, mdurl, MarkupSafe, idna, hf-xet, fsspec, filelock, charset_normalizer, certifi, requests, markdown-it-py, jinja2, rich, huggingface-hub, smolagents
Successfully installed MarkupSafe-3.0.3 certifi-2025.8.3 charset_normalizer-3.4.3 filelock-3.19.1 fsspec-2025.9.0 hf-xet-1.1.10 huggingface-hub-0.35.3 idna-3.10 jinja2-3.1.6 markdown-it-py-4.0.0 mdurl-0.1.2 packaging-25.0 pillow-11.3.0 pygments-2.19.2 python-dotenv-1.1.1 pyyaml-6.0.3 requests-2.32.5 rich-14.1.0 smolagents-1.22.0 tqdm-4.67.1 typing-extensions-4.15.0 urllib3-2.5.0
```

#### 3.1.2. 编写demo代码并解决依赖

demo内容很简单：
* 其中使用`InferenceClientModel`来访问模型，它提供对`Hugging Face`的无服务器推理模型API的访问（进一步了解可见：[Inference Providers](https://huggingface.co/docs/inference-providers/index)）

```py
# demo.py
from smolagents import CodeAgent, DuckDuckGoSearchTool, InferenceClientModel

agent = CodeAgent(tools=[DuckDuckGoSearchTool()], model=InferenceClientModel())
# 为韦恩的派对寻找最佳音乐推荐
agent.run("Search for the best music recommendations for a party at the Wayne's mansion.")
```

`python demo.py`运行，提示少`ddgs`包，pip安装即可：
```sh
(env) [MacOS-xd@qxd ➜ first_demo git:(main) ✗ ]$ pip install ddgs
...
Installing collected packages: brotli, socksio, sniffio, primp, lxml, hyperframe, hpack, h11, click, httpcore, h2, anyio, httpx, ddgs
Successfully installed anyio-4.11.0 brotli-1.1.0 click-8.3.0 ddgs-9.6.0 h11-0.16.0 h2-4.3.0 hpack-4.1.0 httpcore-1.0.9 httpx-0.28.1 hyperframe-6.1.0 lxml-6.0.2 primp-0.15.0 sniffio-1.3.1 socksio-1.0.0
```

重新运行，**报错**提示需要提供一个`api_key`，或者授权登陆`Hugging Face Hub`：
```sh
(env) [MacOS-xd@qxd ➜ first_demo git:(main) ✗ ]$ python demo.py  
╭───────────────────────────── New run ────────────────────────────────────────╮
│                                                                              │
│ Search for the best music recommendations for a party at the Wayne's ma      │
│                                                                              │
╰─ InferenceClientModel - Qwen/Qwen2.5-Coder-32B-Instruct ─────────────────────╯
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━Step 1━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Error in generating model output:
You must provide an api_key to work with together API or log in with `hf auth login`.
[Step 1: Duration 2.15 seconds]
Traceback (most recent call last):
...
```

新增一个`login.py`，补充登陆hub操作（只需要调一次）
```py
# login.py
from huggingface_hub import login

# 调用登陆接口
login()
```

运行代码，会提示输入登陆token。如果忘记，可登陆[huggingface](https://huggingface.co/)，到“Access Tokens”中重新创建一个。
```sh
# 登陆
(env) [MacOS-xd@qxd ➜ first_demo git:(main) ✗ ]$ python login.py 

    _|    _|  _|    _|    _|_|_|    _|_|_|  _|_|_|  _|      _|    _|_|_|      _|_|_|_|    _|_|      _|_|_|  _|_|_|_|
    _|    _|  _|    _|  _|        _|          _|    _|_|    _|  _|            _|        _|    _|  _|        _|
    _|_|_|_|  _|    _|  _|  _|_|  _|  _|_|    _|    _|  _|  _|  _|  _|_|      _|_|_|    _|_|_|_|  _|        _|_|_|
    _|    _|  _|    _|  _|    _|  _|    _|    _|    _|    _|_|  _|    _|      _|        _|    _|  _|        _|
    _|    _|    _|_|      _|_|_|    _|_|_|  _|_|_|  _|      _|    _|_|_|      _|        _|    _|    _|_|_|  _|_|_|_|

# 输入登陆token
Enter your token (input will not be visible): 
# 输入Y确认
Add token as git credential? (Y/n) Y
```

#### 3.1.3. 查看运行效果

运行时，输出会显示正在执行的工作流步骤的跟踪。

```sh
# 运行demo（省略部分内容）
╭────────────────────────────────────── New run ──────────────────────────────────╮
│                                                                                 │
│ Search for the best music recommendations for a party at the Wayne's mansion.   │
│                                                                                 │
╰─ InferenceClientModel - Qwen/Qwen2.5-Coder-32B-Instruct ─────────────────────────
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━ Step 1 ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 ─ Executing parsed code: ──────────────────────────────────────────────────────────
  search_results = web_search(query="best music for a party at Wayne's mansion")
  print(search_results)
 ──────────────────────────────────────────────────────────────────────────────────
Execution logs:
## Search Results

[The 75 Best Party Songs That Will Get Everyone Dancing](https://www.gear4music.com/blog/best-party-songs/)
May 9, 2024 · So, to keep things simple, we’ve compiled the best party songs of all time, from timeless classics to contemporary hits, giving you a diverse, 
family-friendly playlist that guarantees to bring a great vibe to your gathering.
...

Out: None
[Step 1: Duration 8.63 seconds| Input tokens: 2,090 | Output tokens: 81]
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━ Step 2 ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

# 执行解析
 ─ Executing parsed code: ─────────────────────────────────────────────────────────── 
  # List of recommended songs for a party at Wayne's mansion
  recommended_songs = [
      "Daft Punk - One More Time",
      "Montell Jordan - This Is How We Do It",
      "Rob Base & DJ E-Z Rock - It Takes Two",
      ...
  ]
  # Print the list of recommended songs
  print(recommended_songs)
 ──────────────────────────────────────────────────────────────────────────────────── 
Execution logs:
['Daft Punk - One More Time', 'Montell Jordan - This Is How We Do It', 'Rob Base & DJ E-Z Rock - It Takes Two', 'Billy Idol - Dancing with Myself', 'Beastie Boys - Fight 
...

Out: None
[Step 2: Duration 18.14 seconds| Input tokens: 8,099 | Output tokens: 405]
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━ Step 3 ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 ─ Executing parsed code: ─────────────────────────────────────────────────────────── 
  final_answer(recommended_songs)
 ──────────────────────────────────────────────────────────────────────────────────── 
Final answer: ['Daft Punk - One More Time', 'Montell Jordan - This Is How We Do It', 'Rob Base & DJ E-Z Rock - It Takes Two', 'Billy Idol - Dancing with Myself', 'Beastie
Boys - Fight for Your Right', 'PSY - Gangnam Style', 'Blondie - Heart of Glass', 'Rednex - Cotton Eye Joe', 'Miley Cyrus - Party in the U. S. A.', 'Tech N9ne - Pump Up 
the Jam', 'Uptown Funk - Mark Ronson (feat. Bruno Mars)', 'Bohemian Rhapsody - Queen', 'Dancing Queen - ABBA', 'September - Earth, Wind & Fire', 'Thriller - Michael 
Jackson', 'Hotel California - Eagles', "Sweet Child O' Mine - Guns N' Roses", 'Stairway to Heaven - Led Zeppelin', 'Billie Jean - Michael Jackson', 'Imagine - John 
Lennon']
[Step 3: Duration 6.21 seconds| Input tokens: 14,977 | Output tokens: 477]
```

可看到最终agent输出了一个音乐推荐列表：`Final answer: ['Daft Punk - One More Time', ...`。

#### 3.1.4. 创建自定义工具

导入`tool`包，并使用 `@tool`装饰器 创建一个自定义工具，然后将其包含在`tools`列表中进行使用。
```py
from smolagents import CodeAgent, tool, InferenceClientModel

# 使用@tool来定义工具，根据occasion传入的场合返回不同内容，场合比如casual、formal、superhero
@tool
def suggest_menu(occasion: str) -> str:
    ...

# 创建智能体，其中会使用定义好的suggest_menu工具
agent = CodeAgent(tools=[suggest_menu], model=InferenceClientModel())
# 生成formal场合下的菜单
agent.run("Prepare a formal menu for the party.")
```

#### 3.1.5. 为智能体导入其他Python包

如上所示，在`tools`里指定了agent可以用的工具/包。若想让agent使用一些标准库或者其他包，可通过`additional_authorized_imports`来授权导入（默认情况下预定义列表外的导入是被阻止的）。

```py
from smolagents import CodeAgent, InferenceClientModel
# 除了这里，下面还要additional_authorized_imports来授权额外的导入
import datetime

# additional_authorized_imports来允许导入 datetime 模块
agent = CodeAgent(tools=[], model=InferenceClientModel(), additional_authorized_imports=['datetime'])
agent.run(
    # 可指定多行请求内容
    """
    xxxx
    xxxx
    """
)
```

#### 3.1.6. 追踪和分析agent运行

可利用`Langfuse`来跟踪和分析智能体的行为，`Langfuse`是一个**开源的**可观测性和分析平台，专为由大型语言模型（LLM）驱动的应用而设计。`LLMOps`工具。

### 3.2. 工具调用型智能体（ToolCallingAgent）

工具调用智能体（`ToolCalling Agents`）是`smolagents`中提供的第二种智能体类型。这类智能体**利用LLM提供商的内置工具调用能力**来生成**JSON结构**的工具调用指令（这是 `OpenAI`、`Anthropic` 等主流提供商采用的标准方法）。
* 工具调用智能体会生成 指定工具名称和参数的`JSON`对象，系统随后解析这些指令来执行相应工具

两种agent对比，示例：搜索餐饮服务和派对创意

1、`CodeAgent`会生成并运行如下代码：
```py
for query in [
    "Best catering services in Gotham City", 
    "Party theme ideas for superheroes"
]:
    print(web_search(f"Search for: {query}"))
```

2、`ToolCallingAgent`则会创建JSON结构，该结构随后会被用于执行工具调用：

```json
[
    {"name": "web_search", "arguments": "Best catering services in Gotham City"},
    {"name": "web_search", "arguments": "Party theme ideas for superheroes"}
]
```

两者的交互示意图对比如下，其中文本型需要多轮交互操作：

![smolagents_code_vs_json_actions](/images/smolagents_code_vs_json_actions.png)

#### 3.2.1. demo示例

相对于`CodeAgent`，此处导入`ToolCallingAgent`包，并且实例化一个`ToolCallingAgent`对象。

1、agent代码

```py
from smolagents import ToolCallingAgent, DuckDuckGoSearchTool, InferenceClientModel

agent = ToolCallingAgent(tools=[DuckDuckGoSearchTool()], model=InferenceClientModel())

agent.run("Search for the best music recommendations for a party at the Wayne's mansion.")
```

2、运行，执行并查看结果

可看到`Step 1`中生成的`Calling tool:`内容就是JSON结构：

```sh
(env) [MacOS-xd@qxd ➜ toolcalling_agent git:(main) ✗ ]$ python toolcall.py 
╭──────────────────────────── New run ────────────────────────────────────────────╮
│                                                                                 │
│ Search for the best music recommendations for a party at the Wayne's mansion.   │
│                                                                                 │
╰─ InferenceClientModel - Qwen/Qwen2.5-Coder-32B-Instruct ────────────────────────╯
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━ Step 1 ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
╭───────────────────────────────────────────────────────────────────────────────────────────────────────────────────╮
│ Calling tool: 'web_search' with arguments: {'query': "best music recommendations for a party at Wayne's mansion"} │
╰───────────────────────────────────────────────────────────────────────────────────────────────────────────────────╯
Observations: ## Search Results
|late nights in the wayne manor | a bruce wayne rock/blues playlist](https://www.youtube.com/watch?v=oOdHCjj3jn4)
these are songs that bruce ...
[Step 1: Duration 6.08 seconds| Input tokens: 1,190 | Output tokens: 28]
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━ Step 2 ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
╭───────────────────────────────────────────────────────────────────────────────────────────────────────────────────╮
│ Calling tool: 'final_answer' with arguments: {'answer': "Based on the search results, here are some great music recommendations for a party at Wayne's mansion:\n\n1.    │
**Late Nights in the Wayne Manor | A Bruce Wayne Rock/Blues Playlist** - This playlist features songs that Bruce Wayne might listen to, which could add a unique touch
...
╰───────────────────────────────────────────────────────────────────────────────────────────────────────────────────╯
Observations: Based on the search results, here are some great music recommendations for a party at Wayne's mansion:

1. **Late Nights in the Wayne Manor | A Bruce Wayne Rock/Blues Playlist** - This playlist features songs that Bruce Wayne might listen to, which could add a unique touch 
to your party.
...

Final answer: Based on the search results, here are some great music recommendations for a party at Wayne's mansion:

1. **Late Nights in the Wayne Manor | A Bruce Wayne Rock/Blues Playlist** - This playlist features songs that Bruce Wayne might listen to, which could add a unique touch 
to your party.

2. **The 75 Best Party Songs That Will Get Everyone Dancing** - This list includes timeless classics and contemporary hits to keep your guests dancing all night.
...

7. **50 Songs on Every Event Planner's Playlist** - Eventbrite's list of song suggestions can help you curate the right playlist for your event.
[Step 2: Duration 4.61 seconds| Input tokens: 3,298 | Output tokens: 330]
```

## 4. 小结

从这篇笔记开篇到现在有一个月了，进度停了挺长时间，最近开始需要慢慢调整下节奏了。之前是基于英文来看相应教程内容，想着同时能增强下英语阅读，但也导致学习新内容得到的正反馈断断续续，打击了一些积极性。还是切换成中文来看了，官网上的中文版本表达也不错，顺畅了不少。

本篇先介绍并简单实验`smolagents`框架。

## 5. 参考

* [AI Agents Course -- unit2](https://huggingface.co/learn/agents-course/unit2/introduction)
* [中文版：AI Agents Course -- unit2](https://huggingface.co/learn/agents-course/zh-CN/unit2/introduction)
* [smolagents文档](https://huggingface.co/docs/smolagents/v1.22.0/zh/index)
