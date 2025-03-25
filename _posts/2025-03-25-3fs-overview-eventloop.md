---
layout: post
title: DeepSeek 3FS学习实践（一） -- 事件循环
categories: 存储
tags: 3FS 存储
---

* content
{:toc}

DeepSeek 3FS学习实践，本篇梳理其中的事件循环实现流程。



## 1. 背景

clone了一下 [DeepSeek 3FS](https://github.com/deepseek-ai/3FS) 仓库，看了部分的 [设计文档](https://github.com/deepseek-ai/3FS/blob/main/docs/design_notes.md) 和代码，有很多值得学习的内容。

看到蚂蚁存储团队梳理的文章也很好，可参考学习：

* [DeepSeek 3FS解读与源码分析（1）：高效训练之道](https://mp.weixin.qq.com/s/JbC4YiEj1u1BrBejmiytsA)
* [Deepseek 3FS解读与源码分析（2）：网络通信模块分析](https://mp.weixin.qq.com/s/qzeUL4tqXOBctOOllFqL7A)
* [DeepSeek 3FS解读与源码分析（3）：Storage模块解读](https://mp.weixin.qq.com/s/K8Wn0cop742sxfSdWB5wPg)
* [DeepSeek 3FS解读与源码分析（4）：Meta Service解读](https://mp.weixin.qq.com/s/urzArREaN7wj8UZ9Tx3FKA)
* [DeepSeek 3FS解读与源码分析（5）：客户端解读](https://mp.weixin.qq.com/s/sPkqOdVA3qBAUiMQltveoQ)

本篇梳理其中的事件循环实现流程。

## 2. 3FS简要介绍

3FS是幻方AI自研的高速文件系统，是幻方“萤火二号”计算存储分离后，存储服务中的重要一环，全称是萤火文件系统（Fire-Flyer File System），因为有三个连续的 F，念起来不是很容易，因此被简称为 3FS。

3FS 是一个比较特殊的文件系统，因为它几乎只用在AI训练时**计算节点中的模型批量读取样本数据这个场景上**，通过高速的计算存储交互加快模型训练。这是一个大规模的随机读取任务，而且读上来的数据不会在短时间内再次被用到，因此我们无法使用 **“读取缓存”** 这一最重要的工具来优化文件读取，即使是 **超前读取** 也是毫无用武之地。 因此，3FS的实现也和其他文件系统有着比较大的区别。

参考幻方的博客说明：[幻方力量 -- 高速文件系统 3FS](https://www.high-flyer.cn/blog/3fs/)

## 3. 事件循环流程



## 4. 小结


## 5. 参考

* [幻方力量 -- 高速文件系统 3FS](https://www.high-flyer.cn/blog/3fs/)
* [DeepSeek 3FS](https://github.com/deepseek-ai/3FS) 源码
* [DeepSeek 3FS解读与源码分析（1）：高效训练之道](https://mp.weixin.qq.com/s/JbC4YiEj1u1BrBejmiytsA)
* [Deepseek 3FS解读与源码分析（2）：网络通信模块分析](https://mp.weixin.qq.com/s/qzeUL4tqXOBctOOllFqL7A)
* [DeepSeek 3FS解读与源码分析（3）：Storage模块解读](https://mp.weixin.qq.com/s/K8Wn0cop742sxfSdWB5wPg)
* [DeepSeek 3FS解读与源码分析（4）：Meta Service解读](https://mp.weixin.qq.com/s/urzArREaN7wj8UZ9Tx3FKA)
* [DeepSeek 3FS解读与源码分析（5）：客户端解读](https://mp.weixin.qq.com/s/sPkqOdVA3qBAUiMQltveoQ)