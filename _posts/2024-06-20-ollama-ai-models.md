---
layout: post
title: ollama搭建本地个人知识库
categories: 大模型
tags: 工具 大模型
---

* content
{:toc}

ollama搭建本地个人知识库



## 1. 背景

大模型发展如火如荼，前段时间也打算后面建立自己的知识库，一直没行动。

由于一些因素实在忍受不了了：

1. 最近碰到好几次找之前笔记没找到
2. 而且以前的一些笔记很多都不会去看，看了几个反而不如GPT清晰，其实该更新一波了
3. 自己笔记都用markdown记录，然后全局搜索关键词，辅助自然语言理解更高效

网上资料很多，找了一篇参考：
[利用AI解读本地TXT、WORD、PDF文档](https://www.bilibili.com/read/cv33858702/)

**基于ollama搭建**，最后结构如下：

![ollama-anythingLLM结构](/images/2024-06-20-ollama-anythingLLM.png)

最后的最后：笔记本本地也安装ollama并下载模型，这才是"本地"

## 2. 安装ollama

1、从[ollama官网](https://ollama.com/download/linux)下载ollama：

`curl -fsSL https://ollama.com/install.sh | sh`

除了ollama，里面还会自动判断GPU类型并安装依赖：

```sh
[root@xdlinux ➜ /root ]$ curl -fsSL https://ollama.com/install.sh | sh
>>> Downloading ollama...
######################################################################## 100.0%#=#=-#  #       ######################################################################## 100.0%
>>> Installing ollama to /usr/local/bin...
>>> Creating ollama user...
>>> Adding ollama user to render group...
>>> Adding ollama user to video group...
>>> Adding current user to ollama group...
>>> Creating ollama systemd service...
>>> Enabling and starting ollama service...
Created symlink /etc/systemd/system/default.target.wants/ollama.service → /etc/systemd/system/ollama.service.
>>> Downloading AMD GPU dependencies...
######################################################################## 100.0%##O=#  #        ######################################################################## 100.0%
>>> The Ollama API is now available at 127.0.0.1:11434.
>>> Install complete. Run "ollama" from the command line.
>>> AMD GPU ready.
```

安装后自动起了服务：

```sh
[root@xdlinux ➜ /root ]$ netstat -anp|grep 11434
tcp        0      0 127.0.0.1:11434         0.0.0.0:*               LISTEN      23636/ollama        
[root@xdlinux ➜ /root ]$ 
```

配置局域网内访问：

~~.zshrc里添加，`export OLLAMA_HOST=0.0.0.0:11434`，然后重启服务，貌似没用~~ **失败**

```sh
[root@xdlinux ➜ /root ]$ service ollama restart
Redirecting to /bin/systemctl restart ollama.service
[root@xdlinux ➜ /root ]$ netstat -anp|grep 11434
tcp        0      0 127.0.0.1:11434         0.0.0.0:*               LISTEN      23878/ollama        
[root@xdlinux ➜ /root ]$
```

在unit文件里设置环境变量`OLLAMA_HOST=0.0.0.0:11434`，每个环境变量各自一行（**成功**）

```sh
[root@xdlinux ➜ /root ]$ systemctl cat ollama.service 
# /etc/systemd/system/ollama.service
[Unit]
Description=Ollama Service
After=network-online.target

[Service]
ExecStart=/usr/local/bin/ollama serve
User=ollama
Group=ollama
...

# 在/etc/systemd/system/ollama.service
[root@xdlinux ➜ /root ]$ vim /etc/systemd/system/ollama.service 
[root@xdlinux ➜ /root ]$ cat /etc/systemd/system/ollama.service
[Unit]
Description=Ollama Service
After=network-online.target

[Service]
ExecStart=/usr/local/bin/ollama serve
User=ollama
Group=ollama
Restart=always
RestartSec=3
Environment="PATH=/root/.autojump/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/root/bin"
Environment="OLLAMA_HOST=0.0.0.0:11434"

[Install]
WantedBy=default.target
[root@xdlinux ➜ /root ]$
```

重新加载systemd配置并重启服务

```sh
[root@xdlinux ➜ /root ]$ systemctl daemon-reload
[root@xdlinux ➜ /root ]$ systemctl restart ollama.service
[root@xdlinux ➜ /root ]$ netstat -anp|grep 11434
tcp6       0      0 :::11434                :::*                    LISTEN      24573/ollama        
```

好了，浏览器输入：`http://192.168.1.150:11434/`，可以访问了。提示“Ollama is running"

## 3. 下载模型并使用

到Ollama官网，点击右上角的Models即进入：[ollama library](https://ollama.com/library)。Ollama支持流行的开源大语言模型，包括llama2和它的众多衍生品。

暂时使用阿里的通义千问：`qwen2 1.5b` 实验。

复制网页提示的命令，此处为`ollama run qwen2:1.5b`，到linux终端运行。也可以分两步：`ollama pull qwen2:1.5b`再`ollama pull qwen2:1.5b`

```sh
[root@xdlinux ➜ /root ]$ ollama run qwen2:1.5b
pulling manifest 
pulling manifest 
pulling manifest 
pulling manifest 
pulling 405b56374e02...  81% ▕█████████████████████████      ▏ 760 MB/934 MB   36 KB/s   1h19m
...
```

结束后会出来交互式界面，跟平时用GPT一样问答。后续也可`ollama run qwen2:1.5b`调出来界面。试了下本地还挺快的。

```sh
[root@xdlinux ➜ /root ]$ ollama run qwen2:1.5b
>>> 怎么用大模型搭建个人知识库
使用大型语言模型（如：通义千问、小冰等）来构建自己的知识库，可以分为以下几个步骤：

1. **确定主题范围**：
   - 明确你的目标知识领域。如果是技能学习或专业领域，则可以选择相关的书籍、文章和视频内容作
为参考。
   - 可以根据个人兴趣爱好选择广泛的主题，比如历史、文学、编程语言等。

2. **收集资源**：
...

# 输入 /bye 结束
>>> /bye
[root@xdlinux ➜ /root ]$ 
```

可以用`ollama list`查看下载的模型：

```sh
[root@xdlinux ➜ /root ]$ ollama list    
NAME      	ID          	SIZE  	MODIFIED      
qwen2:1.5b	f6daf2b25194	934 MB	4 minutes ago	
qwen2:0.5b	6f48b936a09f	352 MB	5 minutes ago
```

其他用法：

```sh
[root@xdlinux ➜ /root ]$ ollama -h  
Large language model runner

Usage:
  ollama [flags]
  ollama [command]

Available Commands:
  serve       Start ollama
  create      Create a model from a Modelfile
  show        Show information for a model
  run         Run a model
  pull        Pull a model from a registry
  push        Push a model to a registry
  list        List models
  ps          List running models
  cp          Copy a model
  rm          Remove a model
  help        Help about any command

Flags:
  -h, --help      help for ollama
  -v, --version   Show version information

Use "ollama [command] --help" for more information about a command.
```

## 4. 下载向量模型

向量模型是用来将Word和PDF文档转化成向量数据库的工具。通过向量模型转换之后，我们的大语言模型就可以更高效得理解文档内容。

在这里我们使用 `nomic-embed-text`

```sh
[root@xdlinux ➜ /root ]$ ollama pull nomic-embed-text
pulling manifest 
pulling 970aa74c0a90... 100% ▕███████████████████████████████▏ 274 MB                         
pulling c71d239df917... 100% ▕███████████████████████████████▏  11 KB                         
pulling ce4a164fc046... 100% ▕███████████████████████████████▏   17 B                         
pulling 31df23ea7daa... 100% ▕███████████████████████████████▏  420 B                         
verifying sha256 digest 
writing manifest 
removing any unused layers 
success 
[root@xdlinux ➜ /root ]$ ollama list
NAME                   	ID          	SIZE  	MODIFIED       
nomic-embed-text:latest	0a109f422b47	274 MB	47 seconds ago	
qwen2:1.5b             	f6daf2b25194	934 MB	17 minutes ago	
qwen2:0.5b             	6f48b936a09f	352 MB	18 minutes ago	
[root@xdlinux ➜ /root ]$ 
```

## 5. 利用Langchain处理文档

> Langchain是一套利用大语言模型处理向量数据的工具。以前，搭建LLM+Langchain的运行环境比较复杂。现在我们使用AnythingLLM可以非常方便的完成这个过程，因为AnythingLLM已经内置了Langchain组件。

> AnythingLLM是一个集成度非常高的大语言模型整合包。它包括了图形化对话界面、内置大语言模型、内置语音识别模型、内置向量模型、内置向量数据库、内置图形分析库。

> 可惜的是，AnythingLLM目前的易用性和稳定性仍有所欠缺。因此，在本教程中，我们仅使用AnythingLLM的向量数据库和对话界面。LLM模型和向量模型仍然委托给Ollama来管理

> AnythingLLM本身对Ollama的支持也非常完善。只需要通过图形界面，点击几下鼠标，我们就可以轻松完成配置。

下载Mac端程序(300MB左右)，安装后进行配置。

### 5.1. 配置LLM

1、按提示进行必要设置，设置邮箱、工作空间名等

2、进入workspace后，左下角有配置按钮，选择`LLM Preference`选项卡

3、在`LLM Provider`的下拉中，选择`Ollama`，并进行配置后保存

* Ollama Base URL：`http://192.168.1.150:11434`
* Chat Model Selection：`qwen2:1.5b`
* Token context window：`8192`

### 5.2. 配置embedding模式

1、选择`Embedding Preference`选项卡

2、在`Embedding Provider`下拉中，选择`Ollama`，进行配置后保存

* Ollama Base URL：`http://192.168.1.150:11434`
* Embedding Model Selection：`nomic-embed-text:latest`
* Max embedding chunk length：`512`

> 注意：这个Max embedding chunk length数值会影响文档回答的质量，推荐设置成128-512中的某个数值。  
> 从512往下逐级降低，测试效果。太低也不好，对电脑性能消耗大。

### 5.3. 选择LanceDB向量数据库

1、选择`Vector Database`选项卡

2、在`Vector Database Provider`下拉中，选择LanceDB作为后端。这是一个内置的向量数据库。

## 6. 使用AnythingLLM上传文档和问答

1、基本问答：可以直接开始问答

效果有点差，哪里配置还要优化下。

直接使用命令行效果还不错。

2、上传文档

![上传文档](/images/2024-06-21-anythingLLM-upload-file.png)

上传完成后，选中相应的文档，并点击 Move to Workspcae。

```sh
Q：提炼文档里的网络知识
A：根据提供的文档内容，我们可以总结出以下关于网络的知识点：

1. 网络性能的实现：文档提到了如何实现网络性能，包括使用Nginx等服务器程序来提高网络性能。Nginx是一个流行的HTTP和反向代理Web服务器软件。

2. TCP/IP协议：文档中提到了TCP/IP协议，这是一个广泛使用的通信协议，用于在网络之间传输数据包。

3. 网络管理：文档还涉及了系统级别的网络配置、监控以及性能优化等方面的知识。例如，提供了如何设置安全限制（如fs.file-max和sysctl）的示例。

4. 网络接口和地址：文档也提到了网络接口（如eth0, wlan0等）及其对应的IP地址。这通常用于网络设备上配置特定端口或接口的通信服务。

5. 服务器进程：文档中提到如何使用epoll来提高Nginx处理并发请求的能力，这可能涉及如何在多线程环境中管理事件和资源。

6. 网络编程和异步编程：文档提到了异步编程的概念，例如通过epoll_wait函数进行网络事件的实时处理。异步编程通常用于提高效率和减少系统阻塞现象。

7. 模块化开发：文档中还涉及了模块化的编码实践，即在代码中分组不同的功能，并使用类或对象来组织这些功能。这有助于提高代码的可读性、复用性和扩展性。

8. 网络测试和监控：文档中的部分内容可能涉及到网络测试工具（如Wireshark）的使用，以及如何通过监控系统性能指标（如CPU使用率、内存使用情况等）来发现潜在的问题。这些知识对于确保系统的稳定运行非常重要。
```

`Show Citations`里可以看到引用的数据。

```sh
Hide Citations
理解了实现再谈网络性能_202202更新.pdf
```

切换为`Query`模式（不过上面没切换也能参考到文档）：

点击齿轮图标，打开对应workspace的设置选项。选择Chat Settings，将对话模式更改为Query（默认是Chat）

Query模式能够确保仅采用上传文档中的信息进行回答（而不会采用大模型本身的信息）。

## 7. 构建"本地"应用

最后发现有点不对，笔记本带出去就没法用了，于是本地再安装一下，流程一样：

1. Mac上安装一下Ollama（会下载Ollama.app，440MB左右）
2. 下载模型和向量模型（`qwen2:1.5b`和`nomic-embed-text`）
3. 配置AnythingLLM到本机（上面各URL地址改成127.0.0.1）

```sh
➜  /Users/xd ollama list
NAME                   	ID          	SIZE  	MODIFIED       
nomic-embed-text:latest	0a109f422b47	274 MB	34 seconds ago	
qwen2:1.5b             	f6daf2b25194	934 MB	6 minutes ago 
```

不过试了下效果，风扇呼呼的转，还是算了，改成了指向PC机。

## 8. 小结

基于Ollama+AnythingLLM搭建了简单的文档知识库。不过总体效果还没达到预期。

## 9. 参考

1、[利用AI解读本地TXT、WORD、PDF文档](https://www.bilibili.com/read/cv33858702/)

2、[基于Ollama+AnythingLLM轻松打造本地大模型知识库](https://developer.aliyun.com/article/1490578)

3、GPT
