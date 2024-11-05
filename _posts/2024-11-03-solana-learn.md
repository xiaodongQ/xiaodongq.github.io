---
layout: post
title: Solana开发学习（一）
categories: Solana
tags: Solana
---

* content
{:toc}

Rust项目学习：Solana。



## 1. 背景

继续进一步学习Rust开源项目，后面准备先看下`Solana`和`TiKV`，相关应用和生态发展可了解 [Rust编程第一课--开悟之坡（上）：Rust的现状、机遇与挑战](https://time.geekbang.org/column/article/408400) 和 [2021 年 Rust 行业调研报告](https://www.infoq.cn/article/umqbighceoa81yij7uyg)。

本篇开始学习基于Rust开发的知名项目：Solana，并学习区块链开发相关内容。

先收集部分学习资源：

* [Getting Started with Solana Development](https://solana.com/docs/intro/dev)
    * 中文版：[Solana 开发入门](https://www.solana-cn.com/SolanaDocumention/intro/dev.html)
    * 之前看到的一个资源推荐：[roadmap.sh](https://roadmap.sh/)，其中建议了各类开发相关的学习路线。第一个Solana链接就是此处文档。
* [Solana Documentation](https://solana.com/docs)
* Solana白皮书：[solana-whitepaper](https://solana.com/solana-whitepaper.pdf)
* Solana架构：[Solana Architecture](https://docs.solanalabs.com/architecture)
* [Solana中文开发教程](https://www.solanazh.com/)
* blockchain背景知识：[B站北京大学肖臻老师《区块链技术与应用》公开课](https://www.bilibili.com/video/BV1Vt411X7JF/?vd_source=477b80445c7c1a81617bbea3bdf9a3c1)

关于区块链，之前在《左耳听风》学习过基础的技术原理（笔记：[区块链学习笔记](https://xiaodongq.github.io/2019/10/27/blockchain-note/)），另外当时看《OK区块链60讲》里的应用时还挺受触动（[区块链学习.md](https://github.com/xiaodongQ/devNoteBackup/blob/master/%E5%85%B6%E4%BB%96%E8%AE%B0%E5%BD%95/%E5%8C%BA%E5%9D%97%E9%93%BE%E5%AD%A6%E4%B9%A0.md)），近些年也或多或少参与Crypto的投资或投机（屯大饼二饼；矿机；GTC/ENS/OP/ARB/ZK空投；链游；NFT）。之前看过BTC和以太坊的几本书，但没参与相关开发，趁学Rust的机会拓展下技能栈。

## 2. Solana开发入门

基于上述参考链接浏览对比后，先基于 [Getting Started with Solana Development](https://solana.com/docs/intro/dev)（结合中文版：[Solana 开发入门](https://www.solana-cn.com/SolanaDocumention/intro/dev.html)） 进行学习。

Solana 的开发分两个主要部分：

* 链上程序开发：创建和部署自定义程序到区块链，可基于 `Rust`、`C` 或 `C++`，`Rust`拥有更好的支持
* 客户端开发：编写和链上程序通信的软件（`dApp`），可使用任何语言
    * 客户端通过`RPC`请求向Solana网络通信。用Solana的 [JSON RPC API](https://solana.com/docs/rpc)，通过HTTP和Websocket直接和Solana节点交互，与前端和后端之间的正常开发非常相似

客户端和Solana区块链通信示意图：

![客户端和Solana网络通信](/images/solana-developer_flow.png)


## 3. 小结


## 4. 参考

1、[Getting Started with Solana Development](https://solana.com/docs/intro/dev)

2、[Solana 开发入门](https://www.solana-cn.com/SolanaDocumention/intro/dev.html)

3、[Rust编程第一课--开悟之坡（上）：Rust的现状、机遇与挑战](https://time.geekbang.org/column/article/408400)

4、[2021 年 Rust 行业调研报告](https://www.infoq.cn/article/umqbighceoa81yij7uyg)
