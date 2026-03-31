---
title: 用手机远程控制Claude Code
description: 绍通过`happy-coder`或`hapi`用手机远程控制服务器上的 Claude Code
categories: [AI, Claude Code系列]
tags: [Claude Code, happy-coder]
---

## 1. 引言

介绍通过`happy-coder`或`hapi`用手机远程控制服务器上的 Claude Code

- **happy 官方仓库**: https://github.com/slopus/happy
- **hapi 官方仓库**: https://github.com/tiann/hapi

本文的配置是通过手机聊天让小龙虾帮忙搭建的，如果要具体命令操作步骤，网上资料很多，可参考这篇：[我用手机玩Claude/Codex，直接控制终端！](https://mp.weixin.qq.com/s/wk5P9PAwj0janrh50ccSxg )。

## 2. 安装步骤

### 2.1. 安装 happy-coder

happy-coder 是连接手机和服务器的桥梁。在服务器上执行：

```bash
# 克隆或下载 happy-coder
git clone https://github.com/slopus/happy-coder.git
cd happy-coder
npm install
```

### 2.2. 手机端安装

在手机应用商店搜索 "happy-coder" 或通过官方渠道下载 App。安装完成后打开，你会看到扫码连接的界面。

![happy-coder 扫码连接界面](/images/2026-04-01-happy-scan-qr.webp)

> 提示：确保手机和服务器在同一网络，或服务器有公网 IP/内网穿透配置。

---

## 3. 配置流程

### 3.1. 扫码配对

打开手机端 happy-coder，点击"添加设备"，扫描服务器端生成的二维码。扫码成功后，手机会显示设备已连接。

![happy-coder 设备列表](/images/2026-04-01-happy-device-list.webp)

### 3.2. 设备命名

在设置界面，我给这台服务器命名为 `xdlinux`，方便后续识别。如果你有多台服务器，建议用有意义的名称（如 `home-server`、`work-station`）。

### 3.3. 连接测试

配对完成后，点击"测试连接"，确保手机能正常与服务器通信。如果显示"在线"或"likely alive"，说明配置成功。

---

## 4. 工作目录和守护进程配置

### 4.1. 设置工作目录

在设备详情界面，配置工作目录为 `~/happy_workspace`。这个目录将作为 Claude Code 的默认工作区，所有项目文件都会在这里读写。

```bash
# 服务器上创建工作目录
mkdir -p ~/happy_workspace
cd ~/happy_workspace
```

### 4.2. 配置守护进程端口

默认端口可能被占用，我自定义为 `42991`。在设备详情中找到"守护进程端口"设置，修改后保存。

![happy-coder 设备详情](/images/2026-04-01-happy-device-detail.webp)

### 4.3. 启动守护进程

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

## 5. 使用技巧

### 5.1. 快速启动项目

在手机端选择工作目录后，直接输入：

```
claude 帮我创建一个 HTTP 服务器
```

Claude Code 会自动在 `~/happy_workspace` 下创建项目结构。

### 5.2. 代码审查

可以让 Claude Code 帮忙检查代码：

```
claude 检查这个文件的语法错误
```

### 5.3. 批量处理

利用 Claude Code 的批处理能力，一次性处理多个文件：

```
claude 把 docs 目录下所有 markdown 文件转换成 pdf
```

### 5.4. 会话保持

happy-coder 支持长连接，即使手机锁屏，任务也会继续在服务器运行。下次打开手机时查看结果即可。

![happy-coder 命令提示](/images/2026-04-01-happy-command-prompt.webp)

### 5.5. Skill 调用

![happy-coder Skill 执行](/images/2026-04-01-happy-skill-execution.webp)

### 5.6. 多会话管理

![happy-coder 多会话管理](/images/2026-04-01-happy-multi-session.webp)

### 5.7. 文件传输

通过手机端的文件管理器，可以直接上传/下载 `~/happy_workspace` 中的文件，无需额外配置 FTP 或 SSH。

### 5.8. 局域网访问

如果服务器在局域网内，可以直接通过内网 IP 访问：

```
http://192.168.1.150:3006
```

![hapi 聊天界面](/images/2026-04-01-hapi-chat-test.webp)

---

## 6. 常见问题

### 6.1. Q1: 扫码后显示"连接超时"

**原因**：网络不通或防火墙阻挡。

**解决**：
```bash
# 检查端口是否开放
netstat -tlnp | grep 42991

# 如果是云服务器，检查安全组规则
# 确保 42991 端口已放行
```

### 6.2. Q2: 守护进程自动退出

**原因**：内存不足或配置错误。

**解决**：
```bash
# 查看日志
journalctl -u happy-coder -f

# 增加内存或检查工作目录权限
ls -la ~/happy_workspace
```

### 6.3. Q3: 手机端显示"设备离线"但服务器正常

**原因**：心跳检测失败。

**解决**：
1. 重启手机端 App
2. 在服务器端重启守护进程
3. 检查网络延迟（建议 <200ms）

### 6.4. Q4: Claude Code 响应慢

**原因**：服务器负载高或模型 API 限流。

**解决**：
```bash
# 检查服务器负载
top
htop

# 检查 API 调用频率
# 考虑升级到更高配服务器或调整调用策略
```

### 6.5. Q5: 工作目录权限错误

**原因**：用户权限不匹配。

**解决**：
```bash
# 修改目录所有者
chown -R your_username:your_username ~/happy_workspace

# 设置正确权限
chmod -R 755 ~/happy_workspace
```

---

## 7. 参考资源

- **Claude Code 官方**: https://docs.anthropic.com/claude-code/

---

## 8. 结语

这套配置我已经稳定运行了一段时间，日常处理技术任务、写博客、跑脚本都没问题。最大的收获是：**真正的移动开发，不是把 IDE 装到手机上，而是让手机成为远程控制强大算力的终端。**

如果你也在搭建类似的远程开发环境，欢迎交流经验。我的配置不一定是最优的，但绝对是经过实战检验的。

**下一步计划**：
- [ ] 配置自动备份到云存储
- [ ] 集成语音输入，进一步解放双手
- [ ] 探索多设备协同（平板 + 手机 + 电脑）

---

*本文基于真实配置记录，如有疑问欢迎在评论区讨论。*
