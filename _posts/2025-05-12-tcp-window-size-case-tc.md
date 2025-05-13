---
title: TCP发送接收过程（三） -- 实验观察TCP性能和窗口、Buffer的关系（下）
description: 通过tc模拟异常实验观察TCP性能和窗口、Buffer的关系。
categories: [网络, TCP]
tags: [TCP, Wireshark, 接收缓冲区]
---


## 1. 引言

上篇进行了基本的TCP发送接收窗口调整实验，实际情况中则可能会碰到网络丢包、网络延迟、乱序等各种情况，本篇借助`tc`进行异常情况模拟，观察TCP发送接收的表现。

## 2. tc说明

几篇不错的`tc`相关介绍和使用参考文章：

* [Linux流量控制(Traffic Control)介绍](https://just4coding.com/2022/08/05/tc/)
* [[译] 深入理解 tc ebpf 的 direct-action (da) 模式（2020）](https://arthurchiao.art/blog/understanding-tc-da-mode-zh/)
* [man手册](https://www.man7.org/linux/man-pages/man8/tc.8.html)
* [Linux tc qdisc的使用案例](https://plantegg.github.io/2016/08/24/Linux%20tc%20qdisc%E7%9A%84%E4%BD%BF%E7%94%A8%E6%A1%88%E4%BE%8B/)
* [Chapter 25. Linux traffic control](https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/10-beta/html/configuring_and_managing_networking/linux-traffic-control)

### 2.1. 基本介绍

`TC（Traffic Control）`是**Linux内核**中的流量控制子系统，而本文中使用的`tc`是与之对应的**用户态工具**，包含在`iproute2`包中。

`tc`包含如下作用：

* 流量整形(Shaping): 限制网络接口的传输速率，平滑突发流量，避免拥塞，只用于**网络出方向(egress)**。
* 流量调度(Scheduling)：按优先级分配带宽（`reorder`），确保关键业务的传输优先级。只用于**网络出方向(egress)**。
* 流量策略(Policing): 根据到达速率决策接收还是丢弃数据包（如限制 DDoS 攻击），用于**网络入方向(ingress)**。
* 流量过滤(Dropping/Filtering): 根据规则（如 IP 地址、端口、协议）对流量分类，并施加不同的策略（如限速、丢弃），可以用于**出入两个方向**。

`tc`的操作依赖 **<mark>3个核心组件</mark>**：

* **`qdisc`（queueing discipline）**，**<mark>队列规则</mark>**，决定了数据包如何排队和发送
    * 支持多种规则，如 `pfifo`（pure First In, First Out queue）、`pfifo_fast`（默认规则）、`htb`、`tbf`（token buffer filter，令牌桶过滤器）、`fifo`
    * qdisc是一个整流器/整形器（shaper），可以包含多个`class`，不同`class`可以应用不同的策略。
    * qdisc对外暴露两个回调接口`enqueue`和`dequeue`，分别用于数据包入队和数据包出队，而具体的排队算法实现则在qdisc内部隐藏。
        * 不同的`qdisc`实现在Linux内核中实现为不同的**内核模块**，在系统的内核模块目录里可以查看前缀为`sch_`的模块。
        * `ls -ltrh /usr/lib/modules/5.14.0-503.14.1.el9_5.x86_64/kernel/net/sched/sch_*`
* **`class`（类别）**，将流量分类，每类流量可分配不同的带宽或优先级
    * 与 htb 等`qdisc`结合使用，实现带宽分级管理
* **`filter`（过滤器）**，根据规则对流量进行分类
    * `filter`也叫**分类器（classifier）**，需要挂载/附着（attach）到class 或 qdisc上
    * 用于对网络设备上的流量进行分类，并将包分发（dispatch）到前面定义的不同 class

**使用步骤：**

* 1、为网络设备 **<mark>创建一个qdisc</mark>**
    * qdisc需要附着（attach）到某个网络接口
* 2、**<mark>创建流量类别（class）</mark>**，并附着（attach）到`qdisc`
* 3、**<mark>创建filter</mark>**，并attach到`qdisc`
* 4、另外 **<mark>可以给filter添加action</mark>**，比如将选中的包丢弃（drop）
    * 大约15年时，`TC`框架加入了`Classifier-Action`机制。
    * `classifier`即上面的`filter`，当数据包匹配到特定`filter`后可执行该`filter`所挂载的`actions`对数据包进行处理。

`class`可以理解为`qdisc`的载体，它还可以包含子`class`与`qdisc`，最终形成的是一个以 root qdisc 为根的 **<mark>树</mark>**。当数据包流入最顶层`qdisc`时，会层层向下递归进行调用。

**简要处理过程说明：**

* 父对象（`qdisc`或`class`）的`enqueue`回调被调用时，其上挂载的`filter`会依次调用，直到一个`filter`匹配成功；
* 然后将数据包入队到`filter`所指向的`class`，具体实现则是调用`class`所配置的`qdisc`的`enqueue`函数；
* 没有成功匹配`filter`的数据包则分类到默认的`class`中。

![tc_qdisc_process](/images/tc_qdisc_process.png)  
[出处](https://just4coding.com/2022/08/05/tc/)

**扩展阅读**：[Linux-Traffic-Control-Classifier-Action-Subsystem-Architecture.pdf](https://people.netfilter.org/pablo/netdev0.1/papers/Linux-Traffic-Control-Classifier-Action-Subsystem-Architecture.pdf)，介绍了`TC Classifier-Action`子系统的架构。

* 可了解到其和`netfilter`的位置关系：数据流入 -> `ingress TC` -> `netfilter` -> `egress TC` -> 数据流出。见下图示意。
* 关于`netfilter`可见 [TCP发送接收过程（三） -- 学习netfilter和iptables](https://xiaodongq.github.io/2024/07/05/netfilter-iptables-learn/) 中的学习梳理。另外看了下当前`Rocky Linux`环境的`firewalld`防火墙后端，也默认`nftables`了（弃用了`iptables`）：`FirewallBackend=nftables`。

![linux-tc-netfilter-datapath](/images/linux-tc-netfilter-datapath.png)  
[出处](https://people.netfilter.org/pablo/netdev0.1/papers/Linux-Traffic-Control-Classifier-Action-Subsystem-Architecture.pdf)

之前看netfilter时的数据流也可以看到`tc qdisc`的位置：  
![netfilter各hook点和控制流](/images/netfilter-packet-flow.svg)  
[出处 Wikipedia](https://upload.wikimedia.org/wikipedia/commons/3/37/Netfilter-packet-flow.svg)

### 2.2. 使用示例

一个网络接口有**两个默认的qdisc锚点（挂载点）**，<mark>入方向</mark>的锚点叫做`ingress`, <mark>出方向</mark>叫做`root`。
* 入方向的`ingress`功能比较有限，不能挂载其他的`class`，只是做为`Classifier-Action`机制的挂载点。

`qdisc`和`class`的 **<mark>标识符</mark>**叫做`handle`, 它是一个32位的整数，分为`major`和`minor`两部分，各占16位，表达方式为`:m:n`, **<mark>m或n省略时，表示0</mark>**。
* `m:0`一般表示`qdisc`
* 对于`class`：`minor`一般从`1`开始，`major`则用它所挂载qdisc的major号
* `root qdisc`的`handle`一般使用`1:0`表示，`ingress`一般使用`ffff:0`表示。

> 下面`tc`用到的`netem`需要先安装 `sch_netem` 内核模块（`yum install kernel-modules-extra`确认内核小版本也是一致的、`modprobe sch_netem`）。  
> [之前](https://xiaodongq.github.io/2024/06/10/bcc-tools-network/#381-tc%E6%A8%A1%E6%8B%9F) 实验bcc网络工具时就踩过坑了，所以本次安装Rocky Linux时/boot分区分的空间足够大。
{: .prompt-warning }

```sh
# 增加规则
    # dev enp4s0，附着到enp4s0网口
    # root，网卡的根级规则
    # netem（Network Emulator），内核的网络模拟模块
    # delay 2ms，延时2ms
tc qdisc add dev enp4s0 root netem delay 2ms
# 修改
tc qdisc change dev enp4s0 root netem delay 3ms
# 查看
tc qdisc show dev enp4s0
# 删除
tc qdisc del dev enp4s0 root

# 一些查看命令
tc qdisc ls
tc class ls
tc filter ls
# 查看统计信息
tc -s qdisc show dev enp4s0
tc -s class show dev enp4s0
```

```sh
# root，表示将此队列规则（qdisc）添加到接口的根节点（即所有流量的默认路径）
# `handle 1:` 为该 qdisc 分配句柄 1:，后续的子规则可通过此句柄引用（例如 parent 1:）
# netem，使用 netem（网络模拟器）工具，用于模拟网络延迟、丢包、重排序等特性
# reorder 25% 50%：25% 的数据包会被随机重排序（即数据包的顺序被打乱），50% 表示重排序的最大延迟
tc qdisc add dev bond0 root handle 1: netem delay 10ms reorder 25% 50% loss 0.2%
# `parent 1:` 表示此 qdisc 是之前 netem qdisc（句柄 1:）的子节点。
    # netem 会先处理流量，再传递给 tbf
# `handle 2:` 为该 qdisc 分配句柄 2:，用于后续管理或调试。
# tbf，使用 tbf（token buffer filter，令牌桶过滤器）算法，用于 限制带宽 和 控制突发流量。
# rate 1mbit，将带宽限制为 1 Mbps
# burst 32kbit，允许突发流量的最大值为 32 Kbit（即短时间内的瞬时流量可超过 1 Mbps，但总和不能超过 rate × latency + burst）。
    # 突发流量的计算公式：burst = rate × (latency + burst_time)
# latency 10ms，设置 最大延迟为 10ms，即数据包在队列中等待的时间不能超过 10ms
    # 该参数与 tbf 的令牌桶机制结合，用于控制流量整形的精度
tc qdisc add dev bond0 parent 1: handle 2: tbf rate 1mbit burst 32kbit latency 10ms
```

## 3. 实验说明

### 3.1. 环境和步骤

**环境：**和上篇一样，起2个阿里云ECS（2核2G）

* 系统：Rocky Linux release 9.5 (Blue Onyx)
* 内核：5.14.0-503.35.1.el9_5.x86_64

**步骤说明：**

* 服务端：`python -m http.server`起http服务，监听8000端口
    * `dd`一个2GB文件用于测试：`dd if=/dev/zero of=test.dat bs=1G count=2`
* 客户端：`curl`请求下载文件
    * `curl "http://xxx:8000/test.dat" --output test.dat`
* 抓包：
    * `tcpdump -i any port 8000 -s 100 -w normal_client.cap -v`
    * 先两端都抓包对比下，服务端抓包：`tcpdump -i any port 8000 -s 100 -w normal_server.cap -v`

### 3.2. 用例

**用例：**参考下述博文，里面的场景已经比较充分了

* [Packet capture experiment 1](https://yishenggong.com/2023/04/11/packet-capture-experiment-1-packet-delay-loss-duplicate-corrupt-out-of-order-and-bandwidth-limit/)
* [Packet capture experiment 2](https://yishenggong.com/2023/04/15/packet-capture-experiment-2-send-receive-buffer/)

**具体用例：**

* 1、基准用例。直接复用上篇默认参数的场景结果即可，不用重复实验
* 2、`tc`叠加延时：`2ms`
* 3、`tc`叠加延时：`100ms`
* 4、`tc`模拟丢包：`1%`
* 5、`tc`模拟丢包：`20%`
* 6、`tc`模拟包重复：`1%`
* 7、`tc`模拟包重复：`20%`
* 8、`tc`模拟包损坏：`1%`
* 9、`tc`模拟包损坏：`20%`
* 10、`tc`模拟包乱序：`1%`、delay 100ms、相关性 10%
* 11、`tc`模拟包乱序：`20%`、delay 100ms、相关性 10%
* 12、`tc`限制带宽：`50Mbps`
* 13、`tc`限制带宽：`1Mbps`


## 4. 小结


## 5. 参考

* [TCP性能和发送接收窗口、Buffer的关系](https://plantegg.github.io/2019/09/28/%E5%B0%B1%E6%98%AF%E8%A6%81%E4%BD%A0%E6%87%82TCP--%E6%80%A7%E8%83%BD%E5%92%8C%E5%8F%91%E9%80%81%E6%8E%A5%E6%94%B6Buffer%E7%9A%84%E5%85%B3%E7%B3%BB/)
* [Packet capture experiment 1](https://yishenggong.com/2023/04/11/packet-capture-experiment-1-packet-delay-loss-duplicate-corrupt-out-of-order-and-bandwidth-limit/)
* [Packet capture experiment 2](https://yishenggong.com/2023/04/15/packet-capture-experiment-2-send-receive-buffer/)
* [Linux tc qdisc的使用案例](https://plantegg.github.io/2016/08/24/Linux%20tc%20qdisc%E7%9A%84%E4%BD%BF%E7%94%A8%E6%A1%88%E4%BE%8B/)
* LLM
