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

### 2.1. 基本介绍

`TC（Traffic Control）`是**Linux内核**中的流量控制子系统，而本文中使用的`tc`是与之对应的**用户态工具**，包含在`iproute2`包中。

`tc`包含如下作用：

* 流量整形(Shaping): 限制网络接口的传输速率，平滑突发流量，避免拥塞，只用于**网络出方向(egress)**。
* 流量调度(Scheduling)：按优先级分配带宽（`reorder`控制优先级），确保关键业务的传输优先级。只用于**网络出方向(egress)**。
* 流量策略(Policing): 根据到达速率决策接收还是丢弃数据包（如限制 DDoS 攻击），用于**网络入方向(ingress)**。
* 流量过滤(Dropping/Filtering): 根据规则（如 IP 地址、端口、协议）对流量分类，并施加不同的策略（如限速、丢弃），可以用于**出入两个方向**。

`tc`的操作依赖 **<mark>3个核心组件</mark>**：

* **`qdisc`（queueing discipline）**，**<mark>队列规则</mark>**，决定了数据包如何排队和发送
    * 支持多种规则，如 `pfifo`（pure First In, First Out queue）、`pfifo_fast`（默认规则）、`htb`（hierarchy token bucket，分层令牌桶）、`tbf`（token buffer filter，令牌桶过滤器）、`fifo`
    * qdisc是一个整流器/整形器（shaper），可以包含多个`class`，不同`class`可以应用不同的策略。
    * qdisc对外暴露两个回调接口`enqueue`和`dequeue`，分别用于数据包入队和数据包出队，而具体的排队算法实现则在qdisc内部隐藏。
        * 不同的`qdisc`实现在Linux内核中实现为不同的**内核模块**，在系统的内核模块目录里可以查看前缀为`sch_`的模块。
        * 确认有哪些模块，可看：`ls -ltrh /usr/lib/modules/5.14.0-503.14.1.el9_5.x86_64/kernel/net/sched/sch_*`。可另外安装`kernel-modules-extra`，其中会包含`sch_netem`模块。
        * 各种qdisc类型说明，可查看<mark>man手册</mark>。
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

`qdisc`和`class`的 **<mark>标识符</mark>**叫做`handle`（下面会用到）, 它是一个32位的整数，分为`major`和`minor`两部分，各占16位，表达方式为`:m:n`, **<mark>m或n省略时，表示0</mark>**。
* `m:0`一般表示`qdisc`
* 对于`class`：`minor`一般从`1`开始，`major`则用它所挂载qdisc的major号
* `root qdisc`的`handle`一般使用`1:0`表示，`ingress`一般使用`ffff:0`表示。

> 下面`tc`用到的`netem`需要先安装加载 `sch_netem` 内核模块（`yum install kernel-modules-extra`确认内核小版本也是一致的、`modprobe sch_netem`）。  
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

这里说明下`netem`，它是一个classless类型的`qdisc`，表示不能包含`class`，只能attach到root根节点上。用于控制 **<mark>出向包</mark>**，可以增加delay、loss、dup等。

```sh
[root@iZbp1dkjrwztxfyf6vufrvZ ~]# man tc
...
CLASSLESS QDISCS
    netem  
        Network Emulator is an enhancement of the Linux traffic control facilities that allow one to add delay, packet  loss,  duplication  and  more other characteristics to packets outgoing from a selected network interface.
```

下面是`netem`网络模拟模块的简单示例，其他模块和层级规则使用，可见：[Linux tc qdisc的使用案例](https://plantegg.github.io/2016/08/24/Linux%20tc%20qdisc%E7%9A%84%E4%BD%BF%E7%94%A8%E6%A1%88%E4%BE%8B/)。

```sh
# 创建qdisc和filter规则，并分配句柄用于其他规则引用
    # root，表示将此队列规则（qdisc）添加到接口的根节点（即所有流量的默认路径）
    # `handle 1:` 为该 qdisc 分配句柄 1:，后续的子规则可通过此句柄引用（例如 parent 1:）
    # netem，使用 netem（网络模拟器）工具，用于模拟网络延迟、丢包、重排序等特性
    # reorder 25% 50%：25% 的数据包会被随机重排序（即数据包的顺序被打乱），50% 表示重排序的最大延迟
tc qdisc add dev bond0 root handle 1: netem delay 10ms reorder 25% 50% loss 0.2%

# 引用上面创建的qdisc规则，并进一步增加控制
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

环境和步骤和上篇一样。起2个阿里云ECS（2核2G）

* 系统：Rocky Linux release 9.5 (Blue Onyx)
* 内核：5.14.0-503.35.1.el9_5.x86_64
* 注意需要`yum install kernel-modules-extra`、`modprobe sch_netem`以使用`netem`
    * 安装的内核小版本不一样，需要`dnf update`升级下内核到`5.14.0-503.40.1.el9_5`，并重启

**步骤说明：**

* 服务端：`python -m http.server`起http服务，监听8000端口
    * `dd`一个2GB文件用于测试：`dd if=/dev/zero of=test.dat bs=1G count=2`
* 客户端：`curl`请求下载文件
    * `curl "http://xxx:8000/test.dat" --output test.dat`
* 抓包：
    * `tcpdump -i any port 8000 -s 100 -w normal_client.cap -v`
    * 先两端都抓包对比下，服务端抓包：`tcpdump -i any port 8000 -s 100 -w normal_server.cap -v`

### 3.2. 用例

**用例：**参考下述博文，里面的场景已经比较充分了，其中的`20%`比例降到`10%`，生产环境`5%`丢包已经算比较严重了。

* [Packet capture experiment 1](https://yishenggong.com/2023/04/11/packet-capture-experiment-1-packet-delay-loss-duplicate-corrupt-out-of-order-and-bandwidth-limit/)
* [Packet capture experiment 2](https://yishenggong.com/2023/04/15/packet-capture-experiment-2-send-receive-buffer/)

**具体用例：**

* 0、基准用例。直接复用上篇默认参数的场景结果即可，不用重复实验
* 1、`tc`叠加客户端延时：`2ms`
    * `tc qdisc add dev enp4s0 root netem delay 2ms`
* 2、`tc`叠加客户端延时：`100ms`
    * `tc qdisc change dev enp4s0 root netem delay 100ms`（之前已有规则，修改参数即可）
* 3、`tc`模拟服务端丢包：`1%`
    * `tc qdisc add dev enp4s0 root netem loss 1%`（需要先清理之前的规则再添加新规则）
* 4、`tc`模拟服务端丢包：`10%`
    * `tc qdisc change dev enp4s0 root netem loss 10%`
* 5、`tc`模拟服务端包重复：`1%`
    * `tc qdisc add dev enp4s0 root netem duplicate 1%`
* 6、`tc`模拟服务端包重复：`10%`
    * `tc qdisc change dev enp4s0 root netem duplicate 10%`
* 7、`tc`模拟服务端包损坏：`1%`
    * `tc qdisc add dev enp4s0 root netem corrupt 1%` 
* 8、`tc`模拟服务端包损坏：`10%`
    * `tc qdisc change dev enp4s0 root netem corrupt 10%`
* 9、`tc`模拟服务端包乱序：`1%`的包比例乱序、delay 100ms、相关性 10%
    * `tc qdisc add dev enp4s0 root netem delay 100ms reorder 99% 10%`
* 10、`tc`模拟服务端包乱序：`20%`的包比例乱序、delay 100ms、相关性 10%
    * `tc qdisc change dev enp4s0 root netem delay 100ms reorder 80% 10%`
* 11、`tc`限制服务端带宽：`50MBps`（即400Mbps）
    * `tc qdisc add dev enX0 root tbf rate 400mbit burst 10mbit latency 10ms`
    * 可以`ll /lib/modules/5.14.0-503.40.1.el9_5.x86_64/kernel/net/sched/sch_*`看到有`sch_tbf.ko.xz`模块
* 12、`tc`限制服务端带宽：`1MBps`
    * `tc qdisc add dev enX0 root tbf rate 8mbit burst 200kbit latency 10ms`

#### 3.2.1. tc reorder用法说明

这里先解释说明上述的`reorder`用法：`tc qdisc add dev enp4s0 root netem delay 100ms reorder 99% 10%`

直接看下`man tc-netem`：
* 用法：`REORDERING := reorder PERCENT [ CORRELATION ] [ gap DISTANCE ]`
    * 且使用reorder时必须指定`delay`选项
* gap参数说明
    * 示例1：`reorder 25% 50% gap 5` （假设指定`delay 10ms`）
        * 前4个（`gap-1`）包**延迟**10ms发送，剩下的一个包有`25%`的概率**立即**发送；每`gap`个包**重复该过程**。（相关性参数见下面的说明）
        * 或者说剩下的那个包有`75%`的概率**延迟**发送
    * 示例2：`reorder 25% 50%`
        * `25%`的包**立即**发送，剩下的包**延迟**10ms发送
        * `gap`默认1，套用上面的逻辑，`gap-1`即0个包延迟发送，（每个包）`25%`的概率**立即**发送，`75%`的概率**延迟**发送。
        * （**和上面用例中给的99%说法情况一致，1%的包乱序**）。
* `CORRELATION`相关系数说明：前一个事件（此处为乱序）和下一个事件的相关性，会影响下一个事件出现相同表现的概率
    * 若前一个包乱序，下一个包的乱序概率会变为 `1% + (100% - 1%) * 10% = 10.9%`
    * 若前一个包未乱序，下一个包的乱序概率会变为 `1% * (1 - 10%) = 0.9%`
    * delay、loss、reorder、corrupt等都支持相关性设置
    * `0%`表示完全独立（默认）；`100%`则跟上一个状态完全相同：概率`1% + (100% - 1%)*100% = 100%`（一般不会设置100%）

```sh
# man tc-netem
SYNOPSIS
        tc qdisc ... dev DEVICE ] add netem OPTIONS

        OPTIONS := [ LIMIT ] [ DELAY ] [ LOSS ] [ CORRUPT ] [ DUPLICATION ] [ REORDERING ] [ RATE ] [ SLOT ]
        REORDERING := reorder PERCENT [ CORRELATION ] [ gap DISTANCE ]
    ...
netem OPTIONS
    reorder
       to use reordering, a delay option must be specified. There are two ways to use this option (assuming 'delay 10ms' in the options list).

       reorder 25% 50% gap 5
       in this first example, the first 4 (gap - 1) packets are delayed by 10ms and subsequent packets are sent immediately with a probability  of  0.25
       (with  correlation  of 50% ) or delayed with a probability of 0.75. After a packet is reordered, the process restarts i.e. the next 4 packets are
       delayed and subsequent packets are sent immediately or delayed based on reordering probability. To cause a repeatable  pattern  where  every  5th
       packet is reordered reliably, a reorder probability of 100% can be used.

       reorder 25% 50%
       in this second example 25% of packets are sent immediately (with correlation of 50%) while the others are delayed by 10 ms.
```

查看参考资料，reorder和delay的组合有2种写法：

* `tc qdisc add dev eth0 root netem reorder 80% delay 50ms`
* `tc qdisc add dev eth0 root netem delay 50ms reorder 80%`

**疑问**：**delay的位置不同会有不同效果吗？**

找一些参考文章，并让DeepSeek、通义给结果，得到的结论有**冲突**。下面进行实验。

#### 3.2.2. tc reorder和delay先后顺序

实验方式：在服务端增加`reorder`对应qdisc，并在客户端ping进行观察。

**先贴下实验结论：**

| 用例                            | 结果                         | ping表现                       |
| ------------------------------- | ---------------------------- | ------------------------------ |
| 1、reorder 80% delay 50ms       | delay 50ms reorder 80% gap 1 | 接近20%概率延迟（10次出现2次） |
| 2、delay 50ms reorder 80%       | delay 50ms reorder 80% gap 1 | 表现同上                       |
| 3、reorder 80% gap 5 delay 50ms | delay 50ms reorder 80% gap 5 | 5次出现4次延迟，1次不延迟      |
| 4、delay 50ms reorder 80% gap 5 | delay 50ms reorder 80% gap 5 | 同上                           |
| 5、reorder 80% gap 8 delay 50ms | delay 50ms reorder 80% gap 8 | 8次出现7次延迟，1次不延迟      |

说明：
* 上述表格，用例列中省略了共同的`tc qdisc add dev eth0 root netem`；结果列中则省略了前面的`qdisc netem 800d: root refcnt 2 limit 1000`
* 可看到不管`reorder`和`delay`的顺序如何，表现相同 (`gap 5`顺序也可以调整) 。并不会出现LLM说的基础延迟再叠加乱序包延迟的情况（乱序包2倍延迟）。
* `gap`非默认值1时，近似会出现固定的`gap-1`次延迟，剩余一次则根据设置的比例作为立即发送的概率。

下面是步骤和部分结果信息，完整信息可见：[tc_reorder_ping_test.md](https://github.com/xiaodongQ/prog-playground/blob/main/network/bdp_tc_experiment/tc_reorder_ping_test.md)。

---

1、case1：delay在reorder后面，gap默认1

```sh
# case1、服务端添加规则1：delay在reorder后面
[root@iZbp1dkjrwztxfyf6vufrvZ ~]# tc qdisc add dev eth0 root netem reorder 80% delay 50ms
# 查看
[root@iZbp1dkjrwztxfyf6vufrvZ ~]# tc qdisc show dev eth0 root
qdisc netem 800d: root refcnt 2 limit 1000 delay 50ms reorder 80% gap 1
```

客户端ping，出现延迟50ms概率是低的，接近20%（10次里有2次）。

```sh
[root@iZbp1dkjrwztxfyf6vufruZ ~]# ping 172.16.58.147
PING 172.16.58.147 (172.16.58.147) 56(84) bytes of data.
64 bytes from 172.16.58.147: icmp_seq=1 ttl=64 time=0.282 ms
64 bytes from 172.16.58.147: icmp_seq=2 ttl=64 time=50.3 ms
64 bytes from 172.16.58.147: icmp_seq=3 ttl=64 time=0.226 ms
64 bytes from 172.16.58.147: icmp_seq=4 ttl=64 time=50.3 ms
64 bytes from 172.16.58.147: icmp_seq=5 ttl=64 time=0.215 ms
64 bytes from 172.16.58.147: icmp_seq=6 ttl=64 time=0.230 ms
64 bytes from 172.16.58.147: icmp_seq=7 ttl=64 time=0.234 ms
64 bytes from 172.16.58.147: icmp_seq=8 ttl=64 time=0.235 ms
64 bytes from 172.16.58.147: icmp_seq=9 ttl=64 time=0.244 ms
64 bytes from 172.16.58.147: icmp_seq=10 ttl=64 time=0.250 ms
64 bytes from 172.16.58.147: icmp_seq=11 ttl=64 time=0.220 ms
64 bytes from 172.16.58.147: icmp_seq=12 ttl=64 time=50.2 ms
64 bytes from 172.16.58.147: icmp_seq=13 ttl=64 time=0.230 ms
64 bytes from 172.16.58.147: icmp_seq=14 ttl=64 time=0.189 ms
64 bytes from 172.16.58.147: icmp_seq=15 ttl=64 time=0.238 ms
64 bytes from 172.16.58.147: icmp_seq=16 ttl=64 time=0.257 ms
64 bytes from 172.16.58.147: icmp_seq=17 ttl=64 time=0.244 ms
```

2、case2：delay在reorder前面，gap默认1

```sh
# 清理规则
[root@iZbp1dkjrwztxfyf6vufrvZ ~]# tc qdisc del dev eth0 root
[root@iZbp1dkjrwztxfyf6vufrvZ ~]# tc qdisc show dev eth0 root
qdisc fq_codel 0: root refcnt 2 limit 10240p flows 1024 quantum 1514 target 5ms interval 100ms memory_limit 32Mb ecn drop_batch 64
# case2、服务端添加规则2：delay在reorder前面
[root@iZbp1dkjrwztxfyf6vufrvZ ~]# tc qdisc add dev eth0 root netem delay 50ms reorder 80%
# 查看
[root@iZbp1dkjrwztxfyf6vufrvZ ~]# tc qdisc show dev eth0 root
qdisc netem 800e: root refcnt 2 limit 1000 delay 50ms reorder 80% gap 1
```

客户端ping，出现延迟50ms概率是低的，接近20%，同上。

3、case3：delay在reorder后面，并设置`gap 5`

```sh
[root@iZbp1dkjrwztxfyf6vufrvZ ~]# tc qdisc del dev eth0 root
[root@iZbp1dkjrwztxfyf6vufrvZ ~]# tc qdisc add dev eth0 root netem reorder 80% gap 5 delay 50ms
[root@iZbp1dkjrwztxfyf6vufrvZ ~]# tc qdisc show dev eth0 root
qdisc netem 8011: root refcnt 2 limit 1000 delay 50ms reorder 80% gap 5
```

客户端看，基本是3~4个50ms延迟后（和`gap-1`对应），而后出现不延迟。按5个icmp统计看，有1次不延迟（20%几率不延迟，即80%几率延迟）。
* tc规则中的`80%`表示剩下那个包有80%几率立即发送或20%几率延迟发送

4、case4：delay在reorder前面，gap 5

```sh
# 清理规则
[root@iZbp1dkjrwztxfyf6vufrvZ ~]# tc qdisc del dev eth0 root
# 添加规则
[root@iZbp1dkjrwztxfyf6vufrvZ ~]# tc qdisc add dev eth0 root netem delay 50ms reorder 80% gap 5
# 查看
[root@iZbp1dkjrwztxfyf6vufrvZ ~]# tc qdisc show dev eth0 root
qdisc netem 800f: root refcnt 2 limit 1000 delay 50ms reorder 80% gap 5
```

客户端看，基本是3~4个50ms延迟后（和`gap-1`对应），出现不延迟的icmp包。按5个icmp看，有1次不延迟（20%几率不延迟，即80%几率延迟）。**且不会出现包有`100ms`延迟**。

5、`tc qdisc add dev eth0 root netem reorder 80% gap 8 delay 50ms`

8次出现7次延迟，1次不延迟。

### 3.3. 测试脚本和使用说明

tc命令和抓包都按脚本选项的形式输入，便于分情况测试。

使用说明：
* 将下述测试脚本在客户端、服务都放一份。
* 手动选择对应的选项、以及抓包选项；而后触发下载，下载结束或者打断后，ctrl+c打断抓包，完成一条用例测试。

1、tc命令输入。完整脚本内容可见：[tc_command.sh](https://github.com/xiaodongQ/prog-playground/blob/main/network/bdp_tc_experiment/tc_command.sh)。

case1、case2在客户端执行；其他在服务端执行。不同规则会先做清理再新增。

```sh
[root@iZbp1dkjrwztxfyf6vufrvZ ~]# sh tc_command.sh 
================= tc 测试工具菜单 =================
1. 添加客户端延时 2ms
2. 修改客户端延时为 100ms
3. 模拟服务端丢包 1%
4. 修改丢包率为 10%
5. 模拟服务端包重复 1%
6. 修改包重复率为 10%
7. 模拟服务端包损坏 1%
8. 修改包损坏率为 10%
9. 模拟服务端包乱序：1% 乱序，延迟 100ms，相关性 10%
10. 修改乱序率为 20%
11. 限制服务端带宽为 400Mbps (50MBps)
12. 限制服务端带宽为 8Mbps (1MBps)
13. 清除所有规则
0. 退出
==================================================
请输入选项编号:
```

tc_command.sh部分内容：

```sh
#!/bin/bash
execute_choice() {
    case $1 in
        1) clear_rules; tc qdisc add dev $DEV root netem delay 2ms;;
        2) tc qdisc change dev $DEV root netem delay 100ms;;
        3) clear_rules; tc qdisc add dev $DEV root netem loss 1%;;
        4) tc qdisc change dev $DEV root netem loss 10%;;
        5) clear_rules; tc qdisc add dev $DEV root netem duplicate 1%;;
        6) tc qdisc change dev $DEV root netem duplicate 10%;;
        7) clear_rules; tc qdisc add dev $DEV root netem corrupt 1%;;
        8) tc qdisc change dev $DEV root netem corrupt 10%;;
        9) clear_rules; tc qdisc add dev $DEV root netem delay 100ms reorder 99% 10%;;
       10) tc qdisc change dev $DEV root netem delay 100ms reorder 80% 10%;;
       11) clear_rules; tc qdisc add dev $DEV root tbf rate 400mbit burst 10mbit latency 10ms;;
       12) clear_rules; tc qdisc add dev $DEV root tbf rate 8mbit burst 200kbit latency 10ms;;
       13) clear_rules;;
        0) echo "退出脚本"; exit 0;;
        *) echo "无效选项" ;;
    esac
}
```

2、抓包命令输入。完整脚本内容可见：[capture.sh](https://github.com/xiaodongQ/prog-playground/blob/main/network/bdp_tc_experiment/capture.sh)。

抓包：客户端执行`sh capture.sh cli 1`、服务端执行`sh capture.sh server 1`。

```sh
[root@iZbp1dkjrwztxfyf6vufrvZ ~]# sh capture.sh 
用法: capture.sh <capture_type> <scenario_number>
capture_type: cli 或 server
scenario_number: 1 到 12 的整数，代表以下场景：
--------------------
1. 客户端延时 2ms
2. 客户端延时 100ms
3. 服务端丢包 1%
4. 服务端丢包 10%
5. 服务端包重复 1%
6. 服务端包重复 10%
7. 服务端包损坏 1%
8. 服务端包损坏 10%
9. 服务端包乱序 1%
10. 服务端包乱序 20%
11. 限制带宽 400Mbps (50MBps)
12. 限制带宽 8Mbps (1MBps)
--------------------
```

capture.sh部分内容：

```sh
#!/bin/bash

# 定义场景与描述的映射关系
declare -A SCENARIOS=(
    [1]="delay-2ms"
    [2]="delay-100ms"
    [3]="loss-1"
    [4]="loss-10"
    [5]="duplicate-1"
    [6]="duplicate-10"
    [7]="corrupt-1"
    [8]="corrupt-10"
    [9]="reorder-1"
    [10]="reorder-20"
    [11]="bd-400mb"
    [12]="bd-8mb"
)

# 执行抓包命令
echo "开始抓包... (请按 Ctrl+C 停止)"
tcpdump -i any port $PORT -s 100 -v -w $CAPTURE_FILE
```

## 4. 实验结果和分析

1、各用例的客户端下载情况，可见：[tc_experiment_result.md](https://github.com/xiaodongQ/prog-playground/blob/main/network/bdp_tc_experiment/tc_experiment_result.md)。

2、抓包文件则可见：[ecs_tc_case](https://github.com/xiaodongQ/assets_archive/tree/main/ecs_tc_case)。

### 4.1. 结果汇总

暂时只统计客户端侧抓包。

![tc-case-statistic](/images/tc-case-statistic.png)

#### 4.1.1. RTT对比

![tc_case-client-rtt](/images/tc_case-client-rtt.svg)

#### 4.1.2. Throughput对比

![tc_case-client-throughput](/images/tc_case-client-throughput.svg)

#### 4.1.3. Time/Sequence对比

![tc_case-client-timeseq](/images/tc_case-client-timeseq.svg)

#### 4.1.4. Window Scaling对比

![tc_case-client-windowscale](/images/tc_case-client-windowscale.svg)

## 5. 小结

通过tc模拟网络异常实验观察TCP性能和窗口、Buffer的关系。

## 6. 参考

* [TCP性能和发送接收窗口、Buffer的关系](https://plantegg.github.io/2019/09/28/%E5%B0%B1%E6%98%AF%E8%A6%81%E4%BD%A0%E6%87%82TCP--%E6%80%A7%E8%83%BD%E5%92%8C%E5%8F%91%E9%80%81%E6%8E%A5%E6%94%B6Buffer%E7%9A%84%E5%85%B3%E7%B3%BB/)
* [Packet capture experiment 1](https://yishenggong.com/2023/04/11/packet-capture-experiment-1-packet-delay-loss-duplicate-corrupt-out-of-order-and-bandwidth-limit/)
* [Packet capture experiment 2](https://yishenggong.com/2023/04/15/packet-capture-experiment-2-send-receive-buffer/)
* [Linux流量控制(Traffic Control)介绍](https://just4coding.com/2022/08/05/tc/)
* [[译] 深入理解 tc ebpf 的 direct-action (da) 模式（2020）](https://arthurchiao.art/blog/understanding-tc-da-mode-zh/)
* [Linux tc qdisc的使用案例](https://plantegg.github.io/2016/08/24/Linux%20tc%20qdisc%E7%9A%84%E4%BD%BF%E7%94%A8%E6%A1%88%E4%BE%8B/)
* LLM
