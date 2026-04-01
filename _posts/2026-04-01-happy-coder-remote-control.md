---
title: 用手机远程控制Claude Code
description: 介绍通过`happy-coder`或`hapi`用手机远程控制服务器上的 Claude Code
categories: [AI, Claude Code系列]
tags: [Claude Code, happy-coder]
---

## 1. 引言

介绍通过`happy-coder`或`hapi`用手机远程控制服务器上的 Claude Code

- **happy 官方仓库**: https://github.com/slopus/happy
- **hapi 官方仓库**: https://github.com/tiann/hapi

**说明**：本文的操作都是通过手机聊天让小龙虾远程执行的，如果要具体操作步骤，网上资料很多，可参考这篇：[我用手机玩Claude/Codex，直接控制终端！](https://mp.weixin.qq.com/s/wk5P9PAwj0janrh50ccSxg )。

## 2. 安装步骤

### 2.1. 安装 happy-coder

happy-coder 是连接手机和服务器的桥梁。在服务器上npm安装：`npm i -g happy-coder`。

`happy auth login`启动服务（让小龙虾自动执行了，若手动操作可参考上面链接）

### 2.2. 手机端安装

在手机应用商店搜索 "happy-coder" 或通过官方渠道下载 App。安装完成后打开，会看到扫码连接的界面。

![happy-coder 扫码连接界面](/images/2026-04-01-happy-scan-qr.webp)

## 3. 配置流程

### 3.1. 扫码配对

打开手机端 happy-coder，点击"添加设备"，扫描服务器端生成的二维码。扫码或输入URL成功后，手机会显示设备已连接。（由于我是远程操作，是让小龙虾执行后提供了认证URL）

![happy-coder 设备列表](/images/2026-04-01-happy-device-list.webp)

### 3.2. 设备命名

在设置界面，我给这台服务器命名为 `xdlinux`，方便后续识别。如果你有多台服务器，建议用有意义的名称（如 `home-server`、`work-station`）。


### 3.3. 设置工作目录

在设备详情界面，配置工作目录为 `~/happy_workspace`，不存在会自动创建。这个目录将作为 Claude Code 的默认工作区，所有项目文件都会在这里读写。

![happy-coder 设备详情](/images/2026-04-01-happy-device-detail.webp)

## 4. 使用

happy-coder 支持长连接，即使手机锁屏，任务也会继续在服务器运行。下次打开手机时查看结果即可。

### 4.1. 多会话

![happy-coder 多会话管理](/images/2026-04-01-happy-multi-session.webp)

### 4.2. 命令自动提示

使用时也像命令行里一样会自动提示，使用superpower Skill示例：

![happy-coder 命令提示](/images/2026-04-01-happy-command-prompt.webp)

### 4.3. 修改权限模式

![happy-coder Skill 执行](/images/2026-04-01-happy-skill-execution.webp)

## 5. hapi试用

`hapi`和`happy-code`类似，安全性好一点。但是貌似需要在一个局域网（比如连接wifi），或者配置公网。没有单独的app，但是可以发送文件，感觉下来使用体验不如`happy-code`。

![hapi 聊天界面](/images/2026-04-01-hapi-chat-test.webp)

## 6. 实战案例：通过手机远程分析Claude Code泄漏的源码

有了happy-coder，可以在手机上随时随地让 Claude Code 处理复杂任务。比如最近 Claude Code 源码泄露事件，我用手机让 Claude Code 分析了别人用 Rust 重写的版本：[claw-code](https://github.com/instructkr/claw-code)。

**任务**：分析 https://github.com/instructkr/claw-code 的架构，梳理代码结构。

![Claw Code 架构分析报告](/images/2026-04-01-claw-code-analysis.webp)

**结果**：
- ✅ 识别出项目定位：Claude Code 的 Python/Rust 重构版本
- ✅ 梳理了仓库状态：Rust 分支 (dev/rust) 正在积极开发中
- ✅ 生成了完整的架构与代码梳理报告
- ✅ 待办清单清晰展示分析进度
