---
title: Ceph学习笔记（一） -- 总体架构和流程
description: Ceph梳理实践，介绍总体架构和流程。
categories: [存储和数据库, Ceph]
tags: [存储, Ceph]
---


## 1. 引言

开始梳理`Ceph`，结合分布式存储的工作经验，加深并补充技能树。`Ceph`用`RocksDB`作为存储引擎，趁此机会也看下`RocksDB`在工业级项目中的实践和调优效果。

**说明**：基于版本 **<mark>17.2.8</mark>（`Quincy`）**，自己的仓库fork了一份代码 [ceph-v17.2.8)](https://github.com/xiaodongQ/ceph/tree/ceph-v17.2.8) 用于标注学习。

参考链接：

* [Ceph Document -- quincy](https://docs.ceph.com/en/quincy/)
    * [Intro to Ceph](https://docs.ceph.com/en/quincy/start/)
    * [Architecture](https://docs.ceph.com/en/quincy/architecture/)
* [ceph-v17.2.8)](https://github.com/xiaodongQ/ceph/tree/ceph-v17.2.8)
* 各版本时间线说明：[ceph-releases-index](https://docs.ceph.com/en/latest/releases/#ceph-releases-index)

## 2. 总体介绍

`Ceph`始于 [Sage Weil](https://en.wikipedia.org/wiki/Sage_Weil) 的博士论文（目前Weil在`Red Hat`工作，是Ceph项目的首席架构师），代码编写则开始于`2004`年。2010年3月，Linus Torvalds将`Ceph Client`合入Linux内核`2.6.34`版本。

具体可见：[Ceph History](https://en.wikipedia.org/wiki/Ceph_(software)#History)。

### 2.1. 版本说明

**版本格式**：`x.y.z`

* `x.0.z` 开发版（早期测试）
* `x.1.z` 候选版（测试集群适用）
* `x.2.z` 稳定版（用户生成环境推荐）

稳定发布版本（stable release）的维护生命周期，近似24个月，具体见[ceph-releases-index](https://docs.ceph.com/en/latest/releases/#ceph-releases-index)给出的时间线。

LLM提供的各个版本代号和部分关键特性，下面也贴一下作了解（也可了解wikipedia：[Release_history](https://en.wikipedia.org/wiki/Ceph_(software)#Release_history)）。

**代号命名**：按**字母顺序**命名（单词中的 **<mark>首字母</mark>**）

* 更早期版本
    * `Argonaut` (0.48版本, LTS)，2012年6月发布，是长期支持版本（LTS）。
    * `Bobtail` (0.56版本, LTS)，2013年5月发布，同样是LTS版本，带来了显著的性能改进和新的功能。
    * `Cuttlefish` (0.61版本)，2013年1月发布，引入了新功能并提升了系统的稳定性。
    * `Dumpling` (0.67版本, LTS)，2013年8月发布，专注于提高稳定性和修复bug。
    * `Emperor`，0.72.2, 2013-11-01
    * `Firefly` 0.80.11, 2014-05-01
    * `Giant` 0.87.2, 2014-10-01
    * `Hammer` 0.94.10, 2015-04-01
    * `Infernalis` 9.2.1, 2015-11-01
* `Jewel` (`10.2.z`)，`J`
    * 发布时间：2016年4月
    * 首个支持CRUSH Tunables优化算法的版本。
    * 引入RGW（对象存储网关）的S3多对象复制API。
    * 默认使用AsyncMessenger提升网络性能。
* `Kraken` (`11.2.z`)，`K`
    * 发布时间：2017年10月
    * 改进OSD故障检测机制，优化心跳超时。
    * 支持RGW元数据离线重塑。
* `Luminous` (`12.2.z`)，`L`，第12个大版本
    * 2017年10月（**<mark>首个LTS版本</mark>**）
    * **<mark>BlueStore</mark>**：默认的OSD后端存储，直接管理裸盘，支持数据校验与压缩（zlib/snappy/LZ4）。
    * ceph-mgr：新增管理守护进程，提供REST API、Prometheus/Zabbix监控插件。
    * 支持10,000 OSD的大规模集群，优化CRUSH规则自动化。
* `Mimic` (`13.2.z`)，`M`
    * 2018年5月（LTS）
    * 增强BlueStore的稳定性和性能。
    * 支持RBD镜像延迟删除（Trash功能）。
* `Nautilus` (`14.2.z`)，`N`
    * 2019年2月
    * 引入**Cephadm**工具，简化集群部署与管理。
    * 支持**纠删码**存储池（Erasure Code）优化存储效率。
* `Octopus` (`15.2.z`)，`O`
    * 2020年4月
    * 增强**容器化**部署（如Kubernetes集成）。
    * 改进RGW多站点同步的稳定性。
* `Pacific` (`16.2.z`)，`P`
    * 2021年3月
    * 引入RGW的服务器端加密（SSE-KMS支持）。
    * 优化CephFS元数据分片性能。
* `Quincy` (`17.2.z`)，`Q`
    * 2022年4月
    * 增强安全性，支持TLS 1.3。
    * 改进OSD的自动故障恢复机制。
* `Reef` (`18.2.z`)，`R`
    * v18.2.6（截至2025年4月）
    * 支持Zstandard（zstd）压缩算法优化性能。
    * 引入**AI**驱动的负载均衡策略。
* 未来版本，重点关注AI集成与边缘计算场景支持。

### 2.2. Ceph集群构成

具体见：[Intro to Ceph](https://docs.ceph.com/en/quincy/start/)

一个Ceph存储集群中需要：

* 1、至少一个`Ceph Monitor daemon`（Monitor）
    * **`ceph-mon` daemon服务**，维护集群状态的map信息，包括`monitor map`、`manager map`、`OSD map`、`MDS map` 和 `CRUSH map`，这些map状态是后台服务（daemon）间相互通信的关键信息。Monitor还负责管理daemon和客户端之间的身份验证。
    * 一般至少需要<mark>3</mark>个`ceph-mon`来保持冗余和**高可用**
* 2、至少一个`Ceph Manager daemon`（Manager）
    * **`ceph-mgr` daemon服务**，负责跟踪运行时指标（metrics）和集群的当前状态，包括存储利用率、性能指标和系统负载。
    * Manager服务还提供了基于python的模块，包括一个`web面板`（Ceph Dashboard）和`REST API`
        * 可见：[Ceph Dashboard](https://docs.ceph.com/en/quincy/mgr/dashboard/#mgr-dashboard)
    * 一般至少需要<mark>2</mark>个`ceph-mgr`来保持高可用
        * 最佳实践：对于每个`Monitor`，都运行一个`Manager`，但这不是必须的
* 3、大于等于副本个数的`OSD（Ceph Object Storage Daemon）`
    * **`ceph-osd` daemon服务**，负责数据存储，处理数据复制、恢复和重新负载，并提供一些监控信息给Monitor和Manager
        * OSD除了会检查自己的状态，还会通过心跳检查其他OSD的状态，并上报给Monitor。
    * 一般至少需要<mark>3</mark>个`ceph-osd`来保持冗余和高可用
* 4、另外，如果要使用`文件存储`（Ceph File System），则还需要`MDS（Ceph Metadata Server）`
    * **`ceph-mds` daemon服务**，存储文件系统需要的元数据信息，MDS服务允许CephFS用户运行基本命令，如`ls`、`find`等等。

### 2.3. 架构示意

具体见：[Architecture](https://docs.ceph.com/en/quincy/architecture/)

Ceph可以在一个单一系统中同时提供**对象**、**块** 和 **文件存储**。

架构如下：

![ceph-architecture](/images/ceph-architecture.png)

#### RADOS

底层存储引擎称作`RADOS（Relaible Autonomic Distributed Object Store）`（意译：可靠自管理分布式对象存储），负责数据存储、复制和故障恢复。Ceph基于`RADOS`提供<mark>可无限扩展（infinitely scalable）</mark>的存储集群。

`RADOS`了解可见：
* 作者`Sage Weil`对`RADOS`简要介绍的博客：[The RADOS distributed object store](https://ceph.io/en/news/blog/2009/the-rados-distributed-object-store/)。
* 详尽解释则可见 **<mark>RADOS论文</mark>**：[RADOS: A Scalable, Reliable Storage Service for Petabyte-scale Storage Clusters](https://ceph.io/assets/pdfs/weil-rados-pdsw07.pdf)。

2、Ceph的上层特性则基于`librados`来访问Ceph存储集群。

#### CRUSH

3、Ceph以 **<mark>对象（object）</mark>**的形式将数据存储在**逻辑存储池**（logical storage pools）中。

存储集群的 **客户端** 和 **OSD** 通过 **`CRUSH（Controlled Replication Under Scalable Hashing）`** 算法（意译：可扩展哈希控制下的数据分布算法），计算数据的位置信息：哪个`PG（placement group，放置组）`应该包含object，哪个`OSD`应该用于存储该`PG`。`CRUSH`算法使Ceph存储集群能够动态扩展、重新平衡和动态恢复。

* 客户端和OSD使用`CRUSH`算法计算数据位置，意味着不存在中心化查找的瓶颈。
* **<mark>CRUSH论文</mark>**：[CRUSH: Controlled, Scalable, Decentralized Placement of Replicated Data](https://ceph.com/assets/pdfs/weil-crush-sc06.pdf)

## 3. 小结


## 4. 参考

* [Ceph Document](https://docs.ceph.com/en/reef/)
* [Ceph Git仓库](https://github.com/ceph/ceph)
* LLM