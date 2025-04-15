---
title: Solana开发学习（一） -- 总体说明
categories: [区块链, Solana]
tags: [Solana, Rust]
---

Rust项目学习：Solana。

## 1. 背景

继续进一步学习Rust开源项目，后面准备先看下`Solana`和`TiKV`，相关应用和生态发展也可了解 [Rust编程第一课--开悟之坡（上）：Rust的现状、机遇与挑战](https://time.geekbang.org/column/article/408400) 和 [2021 年 Rust 行业调研报告](https://www.infoq.cn/article/umqbighceoa81yij7uyg)、[Rust 2022 生态版图调研报告](https://cloud.tencent.com/developer/article/2233690)。

本篇开始学习基于Rust开发的知名项目：[Solana](https://github.com/solana-labs/solana)，并学习区块链开发相关内容。

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

* **链上程序开发**：创建和部署自定义程序到区块链，可基于 `Rust`、`C` 或 `C++`，`Rust`拥有更好的支持
* **客户端开发**：编写和链上程序通信的软件（`dApp`），可使用任何语言
    * 客户端通过`RPC`请求向Solana网络通信。用Solana的 [JSON RPC API](https://solana.com/docs/rpc)，通过HTTP和Websocket直接和Solana节点交互，与前端和后端之间的正常开发非常相似

客户端和Solana区块链通信示意图：

![客户端和Solana网络通信](/images/solana-developer_flow.png)

### 2.1. 客户端开发

可以使用自己熟悉的语言，通过社区贡献的SDK来进行客户端开发，各类SDK，见：[Client-side Development](https://solana.com/docs/intro/dev#client-side-development)，包含RUST、Typescript、Python、Java、C++、Go等等。

### 2.2. 链上程序开发

说明：

* 基于Rust、C 或 C++开发
* 机器上需要安装Rust
* 需要安装`Solana CLI`，用于在本地验证程序，安装后命令工具为 `solana-test-validator`
    * 具体见 [Install the Solana CLI](https://solana.com/docs/intro/installation#install-the-solana-cli)
    * 安装命令：`sh -c "$(curl -sSfL https://release.anza.xyz/stable/install)"`，在Mac上安装后大概要476MB

开发时，可基于原生Rust（不使用框架）开发，也可基于 [Anchor框架](https://www.anchor-lang.com/)，其提供更高等级的API使得开发更简单（类似于`React`替代原生`Javascript`和`HTML`）

测试框架：[solana-program-test](https://docs.rs/solana-program-test/latest/solana_program_test/)

若不想在本地开发程序，也有一个在线IDE：[online IDE Solana Playground](https://beta.solpg.io/)，使用参考：[Solana Quick Start Guide](https://solana.com/docs/intro/quick-start)。

安装Solana CLI：

```sh
[MacOS-xd@qxd ➜ repo ]$ sh -c "$(curl -sSfL https://release.anza.xyz/stable/install)"
downloading stable installer
  ✨ stable commit 7feb24d initialized
Adding
...
export PATH="/Users/xd/.local/share/solana/install/active_release/bin:$PATH"

[MacOS-xd@qxd ➜ repo ]$ cd /Users/xd/.local/share/solana/install/releases/stable-7xxx/solana-release/bin
[MacOS-xd@qxd ➜ bin ]$ ls
agave-install         cargo-test-bpf        solana-dos            solana-stake-accounts
agave-install-init    cargo-test-sbf        solana-faucet         solana-test-validator
agave-ledger-tool     deps                  solana-genesis        solana-tokens
agave-validator       rbpf-cli              solana-gossip         solang
agave-watchtower      sdk                   solana-keygen         spl-token
cargo-build-bpf       solana                solana-log-analyzer
cargo-build-sbf       solana-bench-tps      solana-net-shaper
```

### 2.3. 开发网络环境

Solana上有几种不同的网络环境（也称作集群，`cluster`），注意选择正确环境：

* **主网Beta版（Mainnet Beta）**：生产网络，需要真金白银
* **开发网（Devnet）**：生产模拟环境，用于部署生产环境前，测试保证程序的质量
* **本地（Local）**：在本地使用`solana-test-validator`来测试程序，开发时的首选

### 2.4. 示例参考

有几个资源可以帮助提升Solana开发的学习：

* [Solana Cookbook](https://solana.com/developers/cookbook)，提供了一系列参考和程序片段
* [Solana Program Examples](https://github.com/solana-developers/program-examples)，提供不同操作的程序示例
* [Guides](https://solana.com/developers/guides)，教程和指南

### 2.5. Solana和BPF

特别说明下，Solana基于`eBPF`实现了一个专门用于智能合约的运行时环境，这个运行时环境称为`Solana BPF Loader`。意外地跟前面 [eBPF学习实践系列](https://xiaodongq.github.io/2024/06/06/ebpf_learn/) 联接起来了，后面可以多看下基于Rust编写eBPF程序（相关实际示例参考：[一次使用 ebpf 来解决 k8s 网络通信故障记录](https://mp.weixin.qq.com/s/cK8Ffhr2M6okysu-_iI6jg)、[一次使用 eBPF LSM 来解决系统时间被回调的记录](https://mp.weixin.qq.com/s/6jpXhWpHhGbkz6fHSKckBw)。

Solana 利用`LLVM`编译架构将程序编译成可执行与可链接格式文件(`ELF`)。这些文件包括一个为Solana程序修改过的BPF字节码(`eBPF bytecode`)，称为“Solana Bytecode Format”(`sBPF`)。

LLVM 的使用使Solana能够潜在地支持任何可以编译成 LLVM 的 BPF 后端的编程语言。这大大增强了 Solana 作为开发平台的灵活性。

参考：[Core Concepts -- Berkeley Packet Filter](https://solana.com/docs/core/programs#berkeley-packet-filter-bpf)

## 3. 基本概念

### 3.1. 账户模型

Solana的数据组织方式类似键值存储（`Address: AccountInfo`），其数据库中每个条目都称为`帐户（Account）`

地址是以`Ed25519算法`生成的`32位`的公钥，可视为帐户的唯一标识符。

* 账户最多能存储`10MB`的数据，数据可包含`可执行程序`或`程序状态`
* 账户需要`SOL`代币押金，和存储数据量成正比，押金在账户关闭时可全额退还
* 每个账户都有一个程序所有者，只有程序所有者的程序可修改或扣除余额，不过任何人可增加余额
* 程序（智能合约）是存储（已编译）可执行代码的**无状态**帐户
    * `executable`标志会设置为true
* 数据帐户由程序创建，用于存储和管理程序状态
* `原生程序（Native programs）`是Solana运行时附带的内置程序
* `Sysvar帐户`是存储网络群集状态的特殊帐户
    * 位于预定义地址的特殊账户，随着网路集群数据动态更新

**账户定义：**

见：[AccountInfo](https://github.com/solana-labs/solana/blob/27eff8408b7223bb3c4ab70523f8a8dca3ca6645/sdk/program/src/account_info.rs#L19)

```rust
#[derive(Clone)]
#[repr(C)]
pub struct AccountInfo<'a> {
    /// Public key of the account
    pub key: &'a Pubkey,

    // 账户余额的数字表示，单位为lamports，即 SOL 的最小单位（1 SOL = 10 亿 lamports）
    pub lamports: Rc<RefCell<&'a mut u64>>,
    // 存储帐户状态的字节数组，若账户是一个程序（智能合约），则此处存储可执行程序
    pub data: Rc<RefCell<&'a mut [u8]>>,
    // 指定拥有帐户程序的公钥（程序 ID）
    pub owner: &'a Pubkey,

    /// The epoch at which this account will next owe rent
    pub rent_epoch: Epoch,
    /// Was the transaction signed by this account's public key?
    pub is_signer: bool,
    /// Is the account writable?
    pub is_writable: bool,

    /// This account's data contains a loaded program (and is now read-only)
    // 指示帐户是否为程序
    pub executable: bool,
}
```

**原生程序：**

Solana包含少量原生程序，这些程序是验证器实现的一部分，并为网络提供各种核心功能。

在Solana上开发自定义程序时，通常会与两个原生程序进行交互，即`系统程序`和`BPF加载程序`。

* 系统程序（System Program）
    * 默认情况下，所有新帐户都归`系统程序`所有
    * 负责几个关键任务：创建新账户、空间分配（设置每个账户的数据字段的字节容量）、分配程序所有权（创建账户后，可将程序所有者分配给其他程序账户）
    * 在Solana上，“钱包”只是系统程序拥有的账户，钱包的`lamports`余额是账户所拥有的`SOL`金额
* BPF加载程序（BPFLoader Program）
    * `BPF Loader`程序是Solana网络上除了`原生程序`外所有程序的`所有者`，负责部署、升级和执行自定义程序

**自定义程序：**

`Program Account` 和 `Data Account`：程序账户可理解为程序本身，数据账户可存储其 所有者程序 中定义的任意数据。

数据账户示意图：

![数据账户示意图](/images/solana-data-account.svg)

## 4. 小结

本篇作为开篇，进行基本说明。

## 5. 参考

1、[Getting Started with Solana Development](https://solana.com/docs/intro/dev)

2、[Solana 开发入门](https://www.solana-cn.com/SolanaDocumention/intro/dev.html)

3、[Rust编程第一课--开悟之坡（上）：Rust的现状、机遇与挑战](https://time.geekbang.org/column/article/408400)

4、[2021 年 Rust 行业调研报告](https://www.infoq.cn/article/umqbighceoa81yij7uyg)
