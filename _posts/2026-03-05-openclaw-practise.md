---
title: AI能力集 -- Open Claude实战手记
description: Open Claude实战手记，持续更新实践和技巧
categories: [AI, AI能力集]
tags: [AI, Open Claude]
---

## 1. 引言

Open Claude实战手记，持续更新实践和技巧。

几个不错的参考链接：
* 玩转OpenClaw：[awesome-openclaw-tutorial](https://github.com/xianyu110/awesome-openclaw-tutorial)
  * 开始可跟着这里实践：[OpenClaw 7天学习路径](https://github.com/xianyu110/awesome-openclaw-tutorial/blob/main/LEARNING-PATH.md)
* [OpenClaw 深度使用指南：普通人如何释放 AI Agent 的真正价值](https://mp.weixin.qq.com/s/nbaAYtHFoIxGHigYIkKdow)
* [awesome-openclaw-usecases](https://github.com/hesamsheikh/awesome-openclaw-usecases)
* [awesome-openclaw-skills](https://github.com/VoltAgent/awesome-openclaw-skills)

## 2. 安装和基本说明

### 2.1. 安装和配置

基本步骤：通过`npm`安装（可设置一下国内镜像源） -> 初始化OpenClaw并配置API -> 而后可以接入飞书（也有开源项目可以接入微信的），步骤可见：[Open Claw安装和配置](https://github.com/xiaodongQ/devNoteBackup/blob/master/%E5%90%84%E5%88%86%E7%B1%BB%E8%AE%B0%E5%BD%95/AI%E5%A4%A7%E6%A8%A1%E5%9E%8B%E5%AD%A6%E4%B9%A0%E7%AC%94%E8%AE%B0.md#%E5%AE%89%E8%A3%85-1)。

执行`openclaw tui`即可启动终端页面，也可用`openclaw dashboard`启动web页面（其他机器上访问，可以在机器上起SSH隧道来转发请求：`ssh -N -L 18789:127.0.0.1:18789 root@192.168.1.150`，而后仍用`http://localhost:18789/`访问）

```sh
[root@xdlinux ➜ ~ ]$ openclaw -v
2026.3.2
```

修改配置文件`~/.openclaw/openclaw.json`后，要重启网关服务：`openclaw gateway restart`。
* Gateway网关：负责连接各个聊天平台，管理会话和消息路由
* 默认地址：`http://127.0.0.1:18789/`

### 2.2. 安装目录说明

由于我的环境是`-g`全局安装的，安装在node的目录里：`/home/workspace/local/node-v24.13.0-linux-x64/lib/node_modules/openclaw/`。

```sh
[root@xdlinux ➜ ~ ]$ ll /home/workspace/local/node-v24.13.0-linux-x64/lib/node_modules/openclaw/
total 772K
drwxr-xr-x   3 root root  118 Mar  4 22:43 assets
-rw-r--r--   1 root root 549K Mar  4 22:43 CHANGELOG.md
drwxr-xr-x   8 root root  32K Mar  4 22:43 dist
drwxr-xr-x  28 root root 4.0K Mar  4 22:43 docs
drwxr-xr-x  43 root root 4.0K Mar  4 22:43 extensions
-rw-r--r--   1 root root 1.1K Mar  4 22:43 LICENSE
drwxr-xr-x 438 root root  12K Mar  4 22:43 node_modules
-rwxr-xr-x   1 root root 2.3K Mar  4 22:43 openclaw.mjs
-rw-r--r--   1 root root  15K Mar  4 22:43 package.json
-rw-r--r--   1 root root 120K Mar  4 22:43 README.md
drwxr-xr-x  54 root root 4.0K Mar  4 22:43 skills
```

相关说明：
| 目录/文件       | 说明                                                                            |
| --------------- | ------------------------------------------------------------------------------- |
| `openclaw.mjs`  | ⚙️ CLI 入口脚本（可执行），运行`openclaw`命令时执行的脚本                        |
| `package.json`  | 📦 包配置、依赖、脚本                                                            |
| `README.md`     | 📖 项目说明文档（122KB）                                                         |
| `CHANGELOG.md`  | 📝 版本更新日志（561KB）                                                         |
| `LICENSE`       | 📜 MIT 许可证                                                                    |
| `dist/`         | 🏗️ 编译后的 JavaScript 代码                                                      |
| `docs/`         | 📚 官方文档（28 个子目录）                                                       |
| `extensions/`   | 🔌 渠道/平台集成插件（43 个），Discord、电报、飞书等                             |
| `skills/`       | 🛠️ 内置的技能模块（54 个），比如Notion集成、代码开发代理、GitHub集成、天气查询等 |
| `node_modules/` | 📦 依赖包（438 个）                                                              |
| `assets/`       | 🎨 静态资源文件                                                                  |

## 3. 终端命令

1、`openclaw tui` 打开终端，终端里`/`可以选择命令，`/help` 显示支持的命令，支持命令（`Slash commands`）如下：

```sh
Slash commands:                               
/help                                         
/commands                                     
/status                                       
/agent <id> (or /agents)                      
/session <key> (or /sessions)                 
/model <provider/model> (or /models)          
/think <off|minimal|low|medium|high|adaptive> 
/verbose <on|off>                             
/reasoning <on|off>                           
/usage <off|tokens|full>                      
/elevated <on|off|ask|full>                   
/elev <on|off|ask|full>                       
/activation <mention|always>                  
/new or /reset                                
/abort                                        
/settings                                     
/exit                                         
```

比如：`/reasoning on`开启推理后（回车2次），

2、有问题可以使用 doctor 命令修复配置并重启：`openclaw doctor --fix` （善用doctor）

## 4. 必备配置

### 4.1. 配置Skills

优先配置 `网页搜索`：官方推荐`Brave Search`，配置方式：
* 步骤 1: 获取 API Key
  * 访问 Brave Search API 官网 `https://brave.com/search/api/` 注册账号,~~免费计划每月提供 2000 次搜索请求~~（貌似取消免费模式了）。
* 步骤 2: 配置 OpenClaw
  * 运行配置向导进行交互式设置:`openclaw configure --section web`
  * 向导会提示你输入 Brave Search API Key,配置完成后会自动保存到 tools.web.search.apiKey

### 4.2. 人设配置



