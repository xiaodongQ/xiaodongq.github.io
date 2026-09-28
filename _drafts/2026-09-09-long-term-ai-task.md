---
title: AI能力集 -- AI长程任务方案分析设计
description: AI长程任务方案分析设计
categories: [AI, AI能力集]
tags: [AI, Agent]
---

## 1. 引言

日常跟AI交互进行开发和学习已经很高频了，但是放手让AI长流程干活还是没有很流畅，不太放心，也没形成一套完备的harness系统。

之前的一些简单尝试：
- 通过openclaw在[xworkbench](https://github.com/xiaodongQ/xworkbench)项目里让它多轮自动迭代，评估不足和新特性开发，由于要求太泛，效果不大好，定位修改问题的效果也不如自己跟claude同步交互
- 本地部署了 [multica](https://xiaodongq.github.io/2026/05/28/multica-deploy/)，目前只用来定期追踪GitHub周榜和推送
- orca的自动编排skill，`/orchestration`，简单使用了下
- 对xworkbench里也加了任务系统：[AI能力集 -- 开发一个任务自动执行系统](https://xiaodongq.github.io/2026/04/19/ai-auto-task-system)，效果一般也没怎么用

本篇中参考一些他人经验，进行设计和实践验证对比。

- [靠这10个优化点，我们把Multi-Agent工作流成本降了50%以上](https://mp.weixin.qq.com/s/TIdXNlrcAOUZWVW1oWnnKQ)
- [任何错误只犯一次：TencentDB Agent Memory 的团队记忆实践](https://mp.weixin.qq.com/s/-ghlUNmB8HvzX9cFYXlDKg)
- [揭秘-如何打造一支凌晨3点还在交付的AI军团](https://mp.weixin.qq.com/s/OV2OqbaDj0hIrBvX1pV_qQ)
- [从Vibe Coding到Harness—— 一套大仓AI工程化实战](https://mp.weixin.qq.com/s/LGo7daiYYRf1r_YY3r-cXw)
- [从AI Coding到Harness Engineering的端到端工程开发实践](https://mp.weixin.qq.com/s/UE-RZH9hnbBd06CVapFGrA)

