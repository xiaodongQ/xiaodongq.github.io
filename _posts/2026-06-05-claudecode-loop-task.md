---
title: AI能力集 -- /loop 三天就废?如何设置长定时任务
description: Claude Code 里的 /loop、/goal、CronCreate、ScheduleWakeup 等"定时任务"机制对比，并考虑定时任务长期运行
categories: [AI, AI能力集]
tags: [AI, Claude Code, /loop, CronCreate, 定时任务]
---

## 1. 引言

`/loop` 这个东西挺好用,日常用 Claude Code 这种本地 Agent,经常可以用 `/loop` 搞个每日数据统计、任务提醒之类的活。

但有个坑:**`/loop` 创建的定时任务,固定 72 小时自动销毁**,到了时间点直接消失,任务就消失了。

为了能“永久”运行AI相关定时任务，本篇尝试几种方式。

## 2. 几种"续命"方式分析

### 2.1. 单 Loop 单独跑

这种方式显然不可行,3天到点就失效。

### 2.2. 双 Loop 互相续期

调研时看到一种"聪明"的办法:A 是业务 loop,B 是定时去重建 A 的 loop。

听起来挺好?但 B 它**本身也是个 loop**,也是 72 小时寿命。B 一死,A 没人续,整套还是断。这只是把"3 天断"延长到了"6 天断",本质问题没解决。

### 2.3. 三 Loop 环形互保

又看到一个更花哨的:三个 loop 互相重建,故意把创建时间错开,降低同时过期的概率。

太复杂了，也有概率一起失效，paas。

### 2.4. Goal 续 Loop —— 听起来聪明,实际是假象

Claude Code的`goal`功能：`/goal` 的本质是给 Agent 一个**长期目标**,让 Agent 持续往这个方向努力。它**不是定时器**。

- `/goal` 的本质是**会话内的"持续目标"**,跟 Loop 一样,会话一关就死
- 关闭会话 → Goal 立刻失效;重开新会话 → Goal 不会恢复

也有`/loop`一样的问题。

---

## 3. 各种机制的行为

这一节把所有跟"定时"沾边的机制都列出来,按几个维度逐一拆开。

### 3.1. 一张速查表

| 机制                                  | 会话一直开着 | 关闭会话                                  | 重开新会话                            | 多久自动过期                                | 适合"每天做"吗          |
| ------------------------------------- | ------------ | ----------------------------------------- | ------------------------------------- | ------------------------------------------- | ----------------------- |
| `/goal`                               | ✅ 持续生效   | ❌ 立刻失效                                | ❌ 不会恢复                            | 无显式过期,跟随会话生命周期                 | ❌                       |
| `CronCreate (durable: false)`         | ✅ 持续生效   | ❌ 立刻失效                                | ❌ 不会恢复                            | 周期性任务 7 天(但前提是会话要活着)         | ❌                       |
| `CronCreate (durable: true)`          | ✅ 持续生效   | ✅ 持久化在 `.claude/scheduled_tasks.json` | ✅ 自动恢复,遗漏的 one-shot 会被"补跑" | 周期性任务 7 天(到点自动删除最后一次执行后) | 可以持久化，但是最多7天 |
| `/loop` (固定间隔,如 `/loop 5m /foo`) | ✅ 持续生效   | ❌ 立刻失效                                | ❌ 不会恢复                            | 文档未明确 7 天上限,会话一旦结束就死        | ❌                       |
| `/loop` (无间隔动态模式)              | ✅ 持续生效   | ❌ 立刻失效                                | ❌ 不会恢复                            | 同上                                        | ❌                       |
| `ScheduleWakeup`(`/loop` 内部用的)    | ✅ 单次唤醒   | ❌ 唤醒请求随进程消失                      | ❌ 不会恢复                            | 不适用(单次)                                | ❌                       |

**一眼能看出的结论**:跨会话能用的,只有 **`CronCreate (durable: true)`** 一个。其他都是"会话死就死"，但是也只有7天有效期。

### 3.2. CronCreate (durable: false):默认的会话内定时

`CronCreate` 是 Claude Code 提供的定时任务工具,默认 `durable: false`。

真实行为:

- ✅ 会话一直开着 → 持续生效
- ❌ 关闭会话 → 立刻失效,任务当场蒸发
- ❌ 重开新会话 → 不会恢复
- 周期性任务有 7 天过期(但前提是会话要活着,实际根本撑不到 7 天)

**关键细节**:"7 天过期"不是"每 7 天重置",是"会话内最多活 7 天"。一旦关闭 Claude Code,任务当场蒸发,根本撑不到第 7 天。

### 3.3. CronCreate (durable: true):真正跨会话的方案

这是唯一**真能跨会话存活**的方案。`durable: true` 之后,任务会持久化到 `.claude/scheduled_tasks.json`。

真实行为:

- ✅ 会话一直开着 → 持续生效
- ✅ 关闭会话 → 任务还在文件里,不受影响
- ✅ 重开新会话 → 自动恢复,**遗漏的 one-shot 会被"补跑"**(见下)
- 周期性任务有 7 天硬限制(到点自动删除最后一次执行后)
- 一次性任务(`recurring: false`)**没有** 7 天限制

## 4. 操作系统外置定时(唯一能"永远跑"的方案)

这条路是**彻底不依赖 Agent 引擎的调度机制**,把定时这事交给操作系统。

### 4.1. 核心思路

- 操作系统(Windows 任务计划 / Linux cron / macOS launchd):系统级的东西,没 TTL 概念,可以开机自启、崩了自愈
- Claude Code 退化成"执行工具",不负责调度,只负责干活

跨平台落地：不管是 Windows、Linux 还是 macOS，结构都一样。

1. 一个任务指令文件(shell 脚本 / bat / plist)
2. 一个触发器(系统定时)
3. 一个调用 Claude Code CLI 的命令

### 4.2. Windows下示例

**1、第 1 步**：写包装脚本。可选：批处理脚本（最简单）、PowerShell 脚本（更现代、可控性更强）

bat脚本示例：

```bat
@echo off
chcp 65001
:: 任务指令文件路径（单行 prompt，复杂指令用 PowerShell 版更方便）
set TASK_TXT=D:\claude_task\task.txt
:: 日志路径
set LOG=D:\claude_task\run_log.txt

:: 读取任务内容到变量
set /p TASK=<%TASK_TXT%
:: 调用 Claude Code 非交互模式
claude -p "%TASK%" >> %LOG% 2>&1
```

**2、第 2 步**：注册为系统定时任务。可选：PowerShell 注册（推荐，幂等可重跑）、GUI 点点点（最直观，调试方便）

```
1. Win + R → 输入 taskschd.msc → 回车
2. 右侧 "创建基本任务"
3. 名称：Claude Daily Task → 下一步
4. 触发器：每天 → 下一步
5. 时间：填 09:07:00 → 下一步
6. 操作：启动程序 → 下一步
7. 程序：C:\scripts\claude-daily-task.bat → 下一步 → 完成
8. 关键：回到列表里双击新建的任务 → 勾选
  - ☑ "如果任务失败，按以下频率重新启动"
  - ☑ "如果计算机错过计划就尽快运行"
  - "使用最高权限运行"
```

**3、第 3 步**：调试 & 验证

- 先手动跑一次 bat：`D:\claude_task\run.bat`，看 `run_log.txt` 有没有正常输出
- 任务计划程序 → 找到任务 → 看"上次运行结果"和"下次运行时间"对不对
- 勾上"如果任务失败，按以下频率重新启动"让它崩了自愈
- 跑几次确认稳定后，可以把"任务启动方式"改成"仅在用户登录时运行"，省得弹黑窗

### 4.3. Linux下示例

结构和 Windows 一模一样：脚本 + crontab。

**1、第 1 步**：写 shell 脚本

`run.sh` 示例：

```bash
#!/bin/bash
# 任务指令文件路径
TASK_TXT=/home/youruser/claude_task/task.txt
# 日志路径
LOG=/home/youruser/claude_task/run_log.log

TASK=$(cat "$TASK_TXT")
claude -p "$TASK" >> "$LOG" 2>&1
```

加执行权限：`chmod +x /home/youruser/claude_task/run.sh`

**2、第 2 步**：注册为 crontab 定时任务

```bash
crontab -e
```

加一行（每天 09:07 跑）：

```
7 9 * * * /home/youruser/claude_task/run.sh
```

**3、第 3 步**：调试 & 验证

- 手动跑一次：`bash /home/youruser/claude_task/run.sh`，看 `run_log.log` 有没有正常输出
- `crontab -l` 确认定时已注册、表达式没写错
- `grep CRON /var/log/syslog`（部分发行版是 `/var/log/cron`）看 cron 是否正常触发
- 长时间没动静就先改 `* * * * *` 每分钟测一次，确认通了再改回每天


