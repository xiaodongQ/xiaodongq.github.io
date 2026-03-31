---
layout: post
title: "用手机远程控制 Claude Code：happy-coder 实战配置指南"
date: 2026-04-01 07:08:00 +0800
categories: [技术，实战，happy-coder]
tags: [Claude Code, 远程控制，移动开发，Linux]
author: boss
description: "基于真实配置记录的 happy-coder 远程开发环境搭建实战，包含扫码连接、设备配置、守护进程设置等完整流程。"
---

## 引言

作为一个留学全案工作人员，我平时需要处理大量的文书、选校规划和申请流程管理。很多时候灵感来了，但人不一定在电脑前——可能在通勤路上、在会议室、或者临时需要快速处理一些技术任务。

于是我开始琢磨：**能不能用手机远程控制服务器上的 Claude Code？**

答案是肯定的。经过一番折腾，我成功搭建了一套基于 happy-coder 的远程开发环境。这篇文章就是我的实战记录，基于我的真实配置，不啰嗦，直接上干货。

> **说明**：本文的配置是通过手机聊天让小龙虾（OpenClaw 助手）帮忙搭建的，全程语音 + 文字指令，没有手动敲命令。如果你也想这样"动口不动手"，可以参考文末的 OpenClaw 配置教程。

**我的环境**：
- 设备名：`xdlinux`（Linux 服务器）
- 工作目录：`~/happy_workspace`
- 守护进程端口：`42991`
- 状态：在线运行

---

## 安装步骤

### 1. 服务器端准备

首先确保你的 Linux 服务器已经安装了 Node.js（推荐 v24+）和 Claude Code。

```bash
# 检查 Node.js 版本
node -v

# 安装 Claude Code（如果还没装）
npm install -g @anthropic-ai/claude-code
```

### 2. 安装 happy-coder

happy-coder 是连接手机和服务器的桥梁。在服务器上执行：

```bash
# 克隆或下载 happy-coder
git clone https://github.com/slopus/happy-coder.git
cd happy-coder
npm install
```

### 3. 手机端安装

在手机应用商店搜索 "happy-coder" 或通过官方渠道下载 App。安装完成后打开，你会看到扫码连接的界面。

![扫码连接界面](/assets/images/happy-scan-qr.png){: .screenshot-mobile}

> 提示：确保手机和服务器在同一网络，或服务器有公网 IP/内网穿透配置。

---

## 配置流程

### 1. 扫码配对

打开手机端 happy-coder，点击"添加设备"，扫描服务器端生成的二维码。扫码成功后，手机会显示设备已连接。

![设置界面 - 已连接 xdlinux 设备](/assets/images/happy-device-list.png){: .screenshot-mobile}

### 2. 设备命名

在设置界面，我给这台服务器命名为 `xdlinux`，方便后续识别。如果你有多台服务器，建议用有意义的名称（如 `home-server`、`work-station`）。

### 3. 连接测试

配对完成后，点击"测试连接"，确保手机能正常与服务器通信。如果显示"在线"或"likely alive"，说明配置成功。

---

## 工作目录和守护进程配置

### 1. 设置工作目录

在设备详情界面，配置工作目录为 `~/happy_workspace`。这个目录将作为 Claude Code 的默认工作区，所有项目文件都会在这里读写。

```bash
# 服务器上创建工作目录
mkdir -p ~/happy_workspace
cd ~/happy_workspace
```

### 2. 配置守护进程端口

默认端口可能被占用，我自定义为 `42991`。在设备详情中找到"守护进程端口"设置，修改后保存。

![设备详情 - 工作目录、守护进程状态、端口信息](/assets/images/happy-device-detail.png){: .screenshot-mobile}

### 3. 启动守护进程

```bash
# 在服务器上启动 happy-coder 守护进程
cd ~/happy-coder
npm run daemon -- --port 42991 --workdir ~/happy_workspace
```

或者使用 systemd 配置开机自启：

```bash
# 创建 systemd 服务文件
sudo nano /etc/systemd/system/happy-coder.service
```

内容如下：

```ini
[Unit]
Description=Happy-Coder Daemon
After=network.target

[Service]
Type=simple
User=your_username
WorkingDirectory=/home/your_username/happy-coder
ExecStart=/usr/bin/npm run daemon -- --port 42991 --workdir /home/your_username/happy_workspace
Restart=always

[Install]
WantedBy=multi-user.target
```

```bash
# 启用并启动服务
sudo systemctl enable happy-coder
sudo systemctl start happy-coder
sudo systemctl status happy-coder
```

---

## 使用技巧

### 1. 快速启动项目

在手机端选择工作目录后，直接输入：

```
claude 帮我创建一个日本留学选校评估工具
```

Claude Code 会自动在 `~/happy_workspace` 下创建项目结构。

### 2. 代码审查

收到学生文书后，可以手机远程让 Claude Code 帮忙审查：

```
claude 检查这份文书的语法错误和逻辑问题
```

### 3. 批量处理

利用 Claude Code 的批处理能力，一次性处理多个文件：

```
claude 把 docs 目录下所有 markdown 文件转换成 pdf
```

### 4. 会话保持

happy-coder 支持长连接，即使手机锁屏，任务也会继续在服务器运行。下次打开手机时查看结果即可。

![Command 提示 - 命令自动补全](/assets/images/happy-command-prompt.png){: .screenshot-mobile}

### 5. Skill 调用

![Skill 执行 - 权限模式/剩余量](/assets/images/happy-skill-execution.png){: .screenshot-mobile}

### 6. 多会话管理

![多会话管理 - 新建/切换会话](/assets/images/happy-multi-session.png){: .screenshot-mobile}

### 7. 文件传输

通过手机端的文件管理器，可以直接上传/下载 `~/happy_workspace` 中的文件，无需额外配置 FTP 或 SSH。

### 8. 局域网访问

如果服务器在局域网内，可以直接通过内网 IP 访问：

```
http://192.168.1.150:3006
```

![hapi 聊天界面测试](/assets/images/hapi-chat-test.png){: .screenshot-mobile}

---

## 常见问题

### Q1: 扫码后显示"连接超时"

**原因**：网络不通或防火墙阻挡。

**解决**：
```bash
# 检查端口是否开放
netstat -tlnp | grep 42991

# 如果是云服务器，检查安全组规则
# 确保 42991 端口已放行
```

### Q2: 守护进程自动退出

**原因**：内存不足或配置错误。

**解决**：
```bash
# 查看日志
journalctl -u happy-coder -f

# 增加内存或检查工作目录权限
ls -la ~/happy_workspace
```

### Q3: 手机端显示"设备离线"但服务器正常

**原因**：心跳检测失败。

**解决**：
1. 重启手机端 App
2. 在服务器端重启守护进程
3. 检查网络延迟（建议 <200ms）

### Q4: Claude Code 响应慢

**原因**：服务器负载高或模型 API 限流。

**解决**：
```bash
# 检查服务器负载
top
htop

# 检查 API 调用频率
# 考虑升级到更高配服务器或调整调用策略
```

### Q5: 工作目录权限错误

**原因**：用户权限不匹配。

**解决**：
```bash
# 修改目录所有者
chown -R your_username:your_username ~/happy_workspace

# 设置正确权限
chmod -R 755 ~/happy_workspace
```

---

## 参考资源

- **我用手机玩 Claude/Codex，直接控制终端！**  
  https://mp.weixin.qq.com/s/wk5P9PAwj0janrh50ccSxg  
  👈 强烈推荐！这是小龙虾的详细配置教程，手把手教学

- **happy 官方仓库**: https://github.com/slopus/happy
- **hapi 官方仓库**: https://github.com/tiann/hapi
- **Claude Code 官方**: https://docs.anthropic.com/claude-code/

---

## 结语

这套配置我已经稳定运行了两周，日常处理技术任务、写博客、甚至帮学生做选校数据分析都没问题。最大的收获是：**真正的移动开发，不是把 IDE 装到手机上，而是让手机成为远程控制强大算力的终端。**

如果你也在搭建类似的远程开发环境，欢迎交流经验。我的配置不一定是最优的，但绝对是经过实战检验的。

**下一步计划**：
- [ ] 配置自动备份到云存储
- [ ] 集成语音输入，进一步解放双手
- [ ] 探索多设备协同（平板 + 手机 + 电脑）

---

*本文基于真实配置记录，如有疑问欢迎在评论区讨论。*

<style>
.screenshot-mobile {
  max-width: 320px;
  height: auto;
  display: block;
  margin: 20px auto;
  border-radius: 8px;
  box-shadow: 0 2px 8px rgba(0,0,0,0.1);
}
</style>
