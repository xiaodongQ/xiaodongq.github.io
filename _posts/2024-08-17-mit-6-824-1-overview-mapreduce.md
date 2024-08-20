---
layout: post
title: MIT6.824学习笔记（一） -- 课程介绍 及 MapReduce
categories: 6.824
tags: 分布式 MIT6.824 MapReduce
---

* content
{:toc}

MIT6.824（2020）学习笔记，此为第一篇。



## 1. 背景

有几个点促使自己近期行动起来：

* TODO列表里，有一项是把Go和Rust捡起来能熟练使用，之前学过用过但是实践少，久一点不用就生疏了；
* 梳理学习leveldb时，就把 [goleveldb](https://github.com/xiaodongQ/goleveldb) 和 [leveldb-rs](https://github.com/xiaodongQ/leveldb-rs) 放到TODO里了，准备通过工业级项目提升Go和Rust水平。但精力有限，死磕在leveldb上太久的话会有点缺乏正反馈，而且其他TODO会饿死；
* 最近一段时间来在下意识提升英语，当前阶段是先提升听力和阅读。在B站早早收藏过6.824只看了一丢丢，前段时间重看视频1尽量关字幕听原声，这种英语学习效果还可以；
* TODO里本身就有6.824躺着，还有存储、分布式领域的经典论文，趁这个机会串起来。

先收集一些参考资料，作学习参考：

* B站视频：[2020 MIT 6.824 分布式系统](https://www.bilibili.com/video/BV1R7411t71W/?spm_id_from=333.999.0.0&vd_source=477b80445c7c1a81617bbea3bdf9a3c1)
* [CS自学指南-MIT6.824: Distributed System](https://csdiy.wiki/%E5%B9%B6%E8%A1%8C%E4%B8%8E%E5%88%86%E5%B8%83%E5%BC%8F%E7%B3%BB%E7%BB%9F/MIT6.824/)
    * 作者还整理了计算机学科的一些其他名校课程，对应github：[CS 自学指南](https://github.com/PKUFlyingPig/cs-self-learning)
    * “随着欧美众多名校将质量极高的计算机课程全部开源，自学 CS 成了一件可操作性极强的事情。毫不夸张地说，只要你有毅力和兴趣，自学的成果完全不亚于你在国内任何一所大学受到的本科 CS 教育（当然，这里单指计算机专业领域，大学带给你的显然不止是专业知识）。”
* [MIT6.824课程视频中文翻译](https://mit-public-courses-cn-translatio.gitbook.io/mit6-824)
* [MIT 6.824 2020 视频笔记](https://www.qtmuniao.com/2020/02/29/6-824-video-notes-1/)
* [6.824 分布式系统课程学习总结_](https://tanxinyu.work/6-824/)

这里还是先跟着2020版学习，此为第一篇。

*说明：本博客作为个人学习实践笔记，可供参考但非系统教程，可能存在错误或遗漏，欢迎指正。若需系统学习，建议参考原链接。*

## 2. 课程介绍

MIT 6.824: Distributed System，这门课每节课都会精读一篇分布式系统领域的经典论文，并由此传授分布式系统设计与实现的重要原则和关键技术。

主讲老师是 [Robert Tappan Morris](https://en.wikipedia.org/wiki/Robert_Tappan_Morris)，1988年写了互联网上第一个蠕虫病毒Morris，现在是MIT的教授，于2019年当选为美国工程院院士。和 [保罗·格雷厄姆（Paul Graham）](https://zh.wikipedia.org/wiki/%E4%BF%9D%E7%BD%97%C2%B7%E6%A0%BC%E9%9B%B7%E5%8E%84%E5%A7%86)（《黑客与画家》作者） 都是[Viaweb](https://zh.wikipedia.org/wiki/Viaweb)和[Y Combinator](https://zh.wikipedia.org/wiki/Y_Combinator)的共同创办人之一。

课程编号现在是6.5840，这是2024年的课表：[6.5840 Schedule: Spring 2024](https://pdos.csail.mit.edu/6.824/schedule.html)，里面有对应的课件、视频、代码链接。

![6-824_6-5840_schedule-2024](/images/6-824_6-5840_schedule-2024.png)

### 2.1. 课程结构

这门课有几个重要组成部分：

* 课堂授课
    * 授课内容会围绕分布式系统的两个方面：`性能`和`容错`
    * 许多课程我们将会以`案例分析`为主要形式
* 几乎每节课都有论文阅读
    * 这里的论文每周需要读一篇，论文主要是研究论文（有一些最近发布的论文），也有一些经典论文，有的是工业界关于现实问题的解决方案
    * 希望通过这些论文可以让你们弄清楚，什么是`基本的问题`，研究者们`有哪些想法`，这些想法可能会，也可能不会对解决分布式系统的问题有用
    * 有时会讨论这些论文中的一些`实施细节`、我们同样会花一些时间去看人们`对系统的评估`
* 两次考试
    * 一次是随堂期中，大概在春假前最后一节课；并且会在学期期末周迎来期末考试。
* 编程实验
    * 有几节课会介绍一些关于编程实验的内容。
    * 有`四次`编程实验：`简单的MapReduce实验`、`实现Raft算法`、`可容错的KV服务`、`分片式KV服务`
* 可选的项目（与Lab4二选一）

关于论文：

> 希望你们在每次讲课前，都可以完成相关论文的阅读。如果没有`提前阅读`，光是课程本身的内容或许没有那么有意义，因为我们没有足够的时间来解释论文中的所有内容，同时来`反思`论文中一些有意思的地方。

> 我也希望快速高效的读论文会是这堂课的一个收获，比如跳过一些并不太重要的部分，而**关注作者重要的想法**。

## 3. 学习方式说明

以`Lecture 1 - Introduction`为例，说明下暂时的学习方式，后面可参考该流程进行：

* 1、看课程对应的论文：[Google-MapReduce-cn.pdf](https://github.com/xiaodongQ/prog-playground/blob/main/classic_papers/MapReduce/Google-MapReduce-cn.pdf)
* 2、先学习一遍B站视频：[2020 MIT 6.824 分布式系统：Lecture 1 -Introduction](https://www.bilibili.com/video/BV1R7411t71W/?spm_id_from=333.999.0.0&vd_source=477b80445c7c1a81617bbea3bdf9a3c1)
    * 可参考下别人的论文笔记和想法：[MapReduce论文阅读](https://tanxinyu.work/mapreduce-thesis/)
* 3、跟着课程的中文翻译再学习一下：[Lecture 01 - Introduction](https://mit-public-courses-cn-translatio.gitbook.io/mit6-824/lecture-01-introduction)
    * 可参考下别人的学习笔记：[MIT 6.824 2020 视频笔记一：绪论](https://www.qtmuniao.com/2020/02/29/6-824-video-notes-1/)

碰到问题再多回头找找视频、论文、笔记中的对应内容，带着问题学习，动态调整。

## 4. MapReduce 论文（Lecture 1）

为了处理大量的原始数据，比如文档抓取、 Web 请求日志等；也为了计算处理各种类型的衍生数据，比如倒排索引、Web 文档的图结构的各种表示形式、每台主机上网络爬虫抓取的页面数量的汇总、每天被请求的最多的查询的集合等等，Google公司于2004年发表了论文：[MapReduce: Simplified Data Processing on Large Clusters](https://pdos.csail.mit.edu/6.824/papers/mapreduce.pdf)。

另外找了篇中文版作为参考：[Google-MapReduce-cn.pdf](https://github.com/xiaodongQ/prog-playground/blob/main/classic_papers/MapReduce/Google-MapReduce-cn.pdf)

### 4.1. 编程模型

MapReduce 编程模型的原理是：利用一个输入 `key/value pair` 集合来产生一个输出的 `key/value pair` 集合。

MapReduce 库的用户用两个函数表达这个计算： `Map` 和 `Reduce`：

* 用户自定义的`Map` 函数接受一个输入的 `key/value pair` 值，然后产生一个中间 `key/value pair` 值的集合。MapReduce 库把所有具有相同中间 key 值 `I` 的中间 value 值集合在一起后传递给 `Reduce` 函数。
* 用户自定义的`Reduce` 函数接受一个中间 key 的值 `I` 和相关的一个 value 值的集合。`Reduce` 函数合并这些value 值，形成一个较小的 value 值的集合。

类型表示：

* `map(k1,v1) -> list(k2,v2)`。表示由输入得到中间输出，两者的key和value都在不同的域上，所以分别用k1/k2、v1/v2区分了
* `reduce(k2,list(v2)) ->list(v2)`。而reduce输出对应的key和value和上面的中间输出结果的域是相同的，也是用k2、v2表示

示例：论文里有好几个示例，这里选取几个：

* 计算 URL 访问频率：
    * `Map` 函数处理日志中 web 页面请求的记录，然后输出`(URL,1)`。
    * `Reduce` 函数把相同URL的value值都累加起来，产生`(URL,记录总数)` 结果
* 倒排索引：
    * `Map` 函数分析每个文档输出一个`(词,文档号)`的列表
    * `Reduce` 函数的输入是一个给定词的所有`(词，文档号)`，排序所有的文档号，输出`( 词, list(文档号) )`。
* 分布式排序：
    * `Map` 函数从每个记录提取 key，输出`(key,record)`
    * `Reduce` 函数不改变任何的值。这个运算依赖分区机制和排序属性。

### 4.2. 总体执行流程

通过将 `Map` 调用的输入数据自动分割为 `M` 个数据片段的集合， `Map` 调用被分布到多台机器上执行。输入的数据片段能够在不同的机器上并行处理。

使用分区函数将 `Map` 调用产生的中间 key 值分成 `R` 个不同分区（例如 `hash(key) mod R`）， `Reduce` 调用也被分布到多台机器上执行。分区数量（`R`）和分区函数由用户来指定。

总体执行流程示意图：

![总体执行流程](/images/mapreduce-execution-overview.png)

当用户调用 MapReduce 函数时，将发生下面的一系列动作（下面的序号和上图中的序号一一对应）：

1. 用户程序首先调用的 `MapReduce 库`将输入文件分成 `M` 个数据片度，每个数据片段的大小一般从16MB 到 64MB(可以通过可选的参数来控制每个数据片段的大小)。然后用户程序在机群中创建大量的**程序副本**（图中的fork）。
2. 这些程序副本中的有一个特殊的程序– `master`。副本中其它的程序都是 `worker` 程序，由 master 分配任务。有 M 个 `Map` 任务和 R 个 `Reduce` 任务将被分配， master 将一个 Map 任务或 Reduce 任务分配给一个空闲的 worker。
3. 被分配了 `Map` 任务的 `worker` 程序读取相关的输入数据片段，从输入的数据片段中解析出 key/value pair，然后把 key/value pair 传递给用户自定义的 Map 函数，由 Map 函数生成并输出的中间 key/value pair，并**缓存在内存中**。
4. 缓存中的 key/value pair 通过分区函数分成 R 个区域，之后**周期性的写入到本地磁盘上**。缓存的 key/value pair 在本地磁盘上的存储位置将被回传给 master，由 master 负责把这些存储位置再传送给`Reduce` worker。
5. 当 `Reduce` worker 程序接收到 master 程序发来的数据存储位置信息后，使用 `RPC` 从 `Map` worker 所在主机的磁盘上读取这些缓存数据。当 Reduce worker 读取了所有的中间数据后，通过对 key 进行排序后使得具有相同 key 值的数据聚合在一起。 由于许多不同的 key 值会映射到相同的 Reduce 任务上，因此必须进行排序。如果中间数据太大无法在内存中完成排序，那么就要在外部进行排序。
6. `Reduce` worker 程序遍历排序后的中间数据，对于每一个唯一的中间 key 值， Reduce worker 程序将这个 key 值和它相关的中间 value 值的集合传递给用户自定义的 Reduce 函数。 Reduce 函数的输出被追加到所属分区的输出文件。
7. 当所有的 `Map` 和 `Reduce` 任务都完成之后， master 唤醒用户程序。在这个时候，在用户程序里的对`MapReduce 调用`才返回。

在成功完成任务之后， `MapReduce` 的输出存放在 `R` 个输出文件中（对应每个 Reduce 任务产生一个输出文件，文件名由用户指定）。一般情况下，用户不需要将这 R 个输出文件合并成一个文件– 他们经常把这些文件作为**另外一个 MapReduce** 的输入，或者在另外一个可以处理多个分割文件的**分布式应用**中使用。

MapReduce库里面，提供了容错、分布式以及并行计算等的处理，应用只需要专注业务。

### 4.3. 各设计点考虑

**容错：**

* worker故障：master定期检查worker，若超时无应答则标记该worker失效，对应的任务也重新调度给其他worker
* master故障：论文中的实现是master失效则停止`MapReduce`任务。也可考虑通过`checkpoint`快速恢复或启动另一个master，但要考虑到master 失效后再恢复的复杂性。
* 输出结果是原子提交的，如果 master 从一个已经完成的 Map 任务再次接收到一个完成消息， master 将忽略这个消息

**任务就近调度到存储位置附近：**

输入数据(由 `GFS` 管理)存储在集群中机器的本地磁盘上来节省网络带宽，MapReduce 的 `master` 在调度 `Map` 任务时会考虑输入文件的位置信息，尽量将一个 Map 任务调度在包含相关输入数据拷贝的机器上执行；如果上述努力失败了， `master` 将尝试在保存有输入数据拷贝的机器附近的机器上执行 `Map` 任务

GFS 把每个文件按 64MB 一个 Block 分隔，每个 Block 保存在多台机器上，环境中就存放了多份拷贝(一般是 3 个拷贝)。

当在一个足够大的 cluster 集群上运行大型 MapReduce 操作的时候，大部分的输入数据都能从本地机器读取，因此消耗非常少的网络带宽

**任务粒度：**

如前所述，我们把 `Map` 拆分成了 `M` 个片段、把 `Reduce` 拆分成 `R` 个片段执行。理想情况下， M 和 R 应当比集群中 worker 的机器数量要多得多。

但实际上，具体实现中对 `M` 和 `R` 的取值都有一定的客观限制，因为 master 必须执行 `O(M+R)`次调度，并且在内存中保存 `O(M*R)`个状态（对影响内存使用的因素还是比较小的： `O(M*R)`块状态，大概每对 Map 任务/Reduce 任务 1 个字节就可以了）

实现取值参考："我们通常会用这样的比例来执行 MapReduce： M=200000， R=5000，使用 2000 台 worker 机器。"

* 实际使用时我们也倾向于选择合适的 M 值，以使得每一个独立任务都是处理大约 16M 到 64M 的输入数据（以使输入数据本地存储优化策略更有效）
* R 值设置为我们想使用的 worker 机器数量的小的倍数

**备用任务：**

影响一个 `MapReduce` 的总执行时间最通常的因素是`“落伍者”`：在运算过程中，如果有一台机器花了很长的时间才完成最后几个 `Map` 或 `Reduce` 任务，导致 MapReduce 操作总的执行时间超过预期。

我们有一个通用的机制来减少“落伍者”出现的情况：当一个 MapReduce 操作接近完成的时候，master调度**备用（backup）任务进程**来执行剩下的、处于`处理中状态（in-progress）`的任务。无论是最初的执行进程、还是备用（backup）任务进程完成了任务，我们都把这个任务标记成为已经完成。

论文中还有一些很有价值的技巧说明，还有程序实现后运行的环境、结果等说明，具体可参考论文，这里不作记录。

### 4.4. 论文学习小结

论文像一篇精彩的技术博客，涉及到的很多方面比较清晰简明：碰到的问题以及解决方案、设计权衡、异常处理、实验数据分析、经验技巧，自己写博客和文档时可以多参考学习。

## 5. 课程笔记

### 5.1. 课程总体预览

课程主要介绍几种基础架构的类型：主要是`存储`，`通信（网络）`和`计算`。

目标是**抽象**这些基础架构，通过设计一些简单的接口，将`分布式特性`隐藏在系统内。从应用程序的角度看，整个系统是一个`非分布式`的系统，但是实际上又是一个有极高的`性能`和`容错性`的分布式系统。

为了实现这个目标，用到的一些构建分布式系统的工具和手段：

* `RPC（Remote Procedure Call）`
* 线程
* 并发控制（比如 锁）

分布式系统需要的特性：

* 可扩展性（Scalability），希望增加计算机就能实现性能整体提升
    * 我们希望可以通过增加机器的方式来实现扩展，但是现实中这很难实现，需要一些架构设计来将这个可扩展性无限推进下去。
* 可用性（Availability），在特定的错误类型下，系统仍然能够正常运行（`容错`）
    * 另一种容错特性是 自我可恢复性（recoverability），修复后系统可正常运行。是一个比可用性更弱的需求，但也很重要。
    * 为了实现这些特性，有很多工具。其中最重要的有两个：`非易失存储（non-volatile storage）` 和 `复制（replication）`
* 一致性（Consistency），多个副本间的数据一致性。分为 `强一致（Strong Consistency）` 和 `弱一致`
    * 人们常常会使用弱一致系统，弱一致对于应用程序来说很有用，并且它可以用来获取高的性能。

### 5.2. MapReduce

基本是讲了上述论文内容，讲述得更为形象一些，具体细节还是需要进到论文里看下。

Google碰到的问题，以及为了解决问题设计了`MapReduce`分布式框架。一个具象的示例：为了给所有网页（当时`数十TB`级别）建立索引，需要整体做排序，希望将运算任务分布到`几千台机器`运行，以提升运算效率。

工程师只需要实现应用程序的核心，就能将应用程序运行在数千台计算机上，而**不用考虑**如何将运算工作分发到数千台计算机，如何组织这些计算机，如何移动数据，如何处理故障等等这些细节。所以，当时Google需要一种框架，使得**普通工程师**也可以很容易的完成并运行大规模的分布式运算。这就是`MapReduce`出现的背景。

`MapReduce`的思想是，应用程序设计人员和分布式运算的使用者，只需要写简单的`Map`函数和`Reduce`函数，而不需要知道任何有关分布式的事情，MapReduce框架会处理剩下的事情。

术语：

* Job。整个MapReduce计算称为Job
* Task。每一次MapReduce调用称为Task

### 5.3. 问答

问答内容也很有价值，可参考课程翻译这里的问答记录：[课堂：MapReduce的基本框架相关问题和解答](https://mit-public-courses-cn-translatio.gitbook.io/mit6-824/lecture-01-introduction/1.8-mapreduce-han-shu)。

这里放一个教授关于之前和现在（2020）数据读取的对比解答：

`网络通信`（通过网络读取拷贝数据副本）是`2004年`限制MapReduce的瓶颈，受限于之前的网络架构；而在`2020年`现代数据中心中，root交换机比过去快了很多，而且会有很多个root交换机，每个机架交换机都与每个root交换机相连，网络流量在多个root交换机之间做负载分担。所以，现代数据中心网络的吞吐大多了。

> 我认为Google几年前就不再使用MapReduce了，不过在那之前，现代的MapReduce已经不再尝试在GFS数据存储的服务器上运行Map函数了，它乐意从任何地方加载数据，因为网络已经足够快了。

## 6. 小结

启动了6.824课程学习，进行了一部分资料搜集。学习了第一堂课，以及涉及到的MapReduce论文。看经典论文跟看优秀的技术文章差不多，有不少正反馈。

目前主要还是学习并作部分记录输出，不求完整。后续在工作、学习时，碰到对应问题动态补充文章内容。

## 7. 参考

1、[CS自学指南-MIT6.824: Distributed System](https://csdiy.wiki/%E5%B9%B6%E8%A1%8C%E4%B8%8E%E5%88%86%E5%B8%83%E5%BC%8F%E7%B3%BB%E7%BB%9F/MIT6.824/)

2、[MIT6.824中文翻译](https://mit-public-courses-cn-translatio.gitbook.io/mit6-824)

3、[视频：Lecture 1 - Introduction](https://www.bilibili.com/video/BV1R7411t71W/?spm_id_from=333.999.0.0&vd_source=477b80445c7c1a81617bbea3bdf9a3c1)

4、[MapReduce: Simplified Data Processing on Large Clusters](https://pdos.csail.mit.edu/6.824/papers/mapreduce.pdf)

5、[MapReduce论文阅读](https://tanxinyu.work/mapreduce-thesis/)

6、[MIT 6.824 2020 视频笔记一：绪论](https://www.qtmuniao.com/2020/02/29/6-824-video-notes-1/)
