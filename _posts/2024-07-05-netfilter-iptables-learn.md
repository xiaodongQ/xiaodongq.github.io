---
layout: post
title: 深入学习netfilter和iptables
categories: 网络
tags: TCP netfilter iptables
---

* content
{:toc}

深入学习netfilter和iptables，深入理解TCP发送接收过程



## 1. 背景

在[追踪内核网络堆栈的几种方式](https://xiaodongq.github.io/2024/07/03/strace-kernel-network-stack)里记录了一下iptables设置日志跟踪的实践过程，CentOS8下为什么实验失败还没有定论。

平常工作中设置iptables防火墙规则，基本只是浮于表面记住，不清楚为什么这么设置，规则也经常混淆。

[TCP半连接全连接（一） -- 全连接队列相关过程](https://xiaodongq.github.io/2024/05/18/tcp_connect/)里面的TODO项：“内核drop包的时机，以及跟抓包的关系。哪些情况可能会抓不到drop的包？”，在系列文章里分析了源码里全连接、半连接溢出时drop的位置，给了个tcpdump能抓到drop原始请求包的现象结论，但没有理清楚流程。

这些问题都或多或少，或直接或间接跟**内核中的netfilter框架**有关系。

基于上述几个原因，深入学习一下`netfilter`框架和基于其实现的`iptables`，以及tcpdump抓包跟`netfilter`的关系。

主要参考学习以下文章：

* [[译] 深入理解 iptables 和 netfilter 架构](https://arthurchiao.art/blog/deep-dive-into-iptables-and-netfilter-arch-zh)
* [用户态 tcpdump 如何实现抓到内核网络包的?](https://mp.weixin.qq.com/s?__biz=MjM5Njg5NDgwNA==&mid=2247486315&idx=1&sn=ce3a85a531447873e02ccef17198e8fe&chksm=a6e30a509194834693bb7ee50cdd3868ab1f686a3a0807e2d1a514253ba1579d1246b99bf35d&scene=178&cur_album_id=1532487451997454337#rd)
* [来，今天飞哥带你理解 iptables 原理！](https://mp.weixin.qq.com/s?__biz=MjM5Njg5NDgwNA==&mid=2247487465&idx=1&sn=aace79dcb4edb011cf69e7cd9f7331f9&chksm=a6e30ed2919487c402f20fdda822bc63f057a334e81e8d26e48194f5b679882c627311205bbe&scene=178&cur_album_id=1532487451997454337#rd)
* [iptable 的基石：netfilter 原理与实战](https://juejin.cn/book/6844733794801418253/section/7355436057355583528)

*说明：本博客作为个人学习实践笔记，可供参考但非系统教程，可能存在错误或遗漏，欢迎指正。若需系统学习，建议参考原链接。*

## 2. netfilter基本介绍

官网：[netfilter](https://netfilter.org/)，上面可看到netfilter相关项目的动态，如iptables、nftables、conntrack-tools等。

netfilter是Linux内核中一个非常关键的子系统，它负责在网络协议栈的不同层级处理数据包，提供了一系列强大的网络数据包处理功能，包括但不限于数据包过滤、网络地址转换（NAT）以及连接跟踪。

netfilter框架由Linux内核防火墙和网络维护者 Rusty Russell 所提出和实现。这个作者还基于 netfilter 开发了大名鼎鼎的 iptables，用于在用户空间管理这些复杂的 netfilter 规则。（番外：这位大佬18年宣布退出并投入到比特币闪电网络的原型开发中了，大佬的[博客](https://rusty.ozlabs.org/)）

* netfilter最初在Linux 2.4.x内核系列中引入，作为继`IPchains`之后的新一代Linux防火墙框架。它至今仍是Linux系统中实现网络数据包处理的核心机制。
* netfilter的设计遵循高度模块化的原则，这意味着它的功能可以通过加载或卸载内核模块来动态扩展，从而实现了极高的灵活性和可扩展性。
* netfilter的核心在于其hook机制。它在Linux网络堆栈的关键位置定义了多个挂载点（hook points），比如在数据包流入（PREROUTING）、流出（POSTROUTING）、进入本地进程（INPUT）和转发（FORWARD）时。当数据包经过这些点时，预先注册的hook函数会被调用，执行相应的处理逻辑，如过滤、修改或丢弃数据包。
* netfilter通常与用户空间工具`iptables`一起提及。netfilter作为内核部分，负责实际的数据包处理；而`iptables`则是一个高级命令行工具，允许管理员定义复杂的规则集来控制netfilter的行为，比如设置过滤规则、NAT规则等。

**nftables**：（之前比较陌生，上面netfilter官网上也有nftables介绍）

* 也是一个netfilter项目，旨在替换现有的 {ip,ip6,arp,eb}tables 框架，为 {ip,ip6}tables 提供一个新的包过滤框架、一个新的用户空间实用程序（nft）和一个兼容层。
* 虽然`iptables`长期以来是与netfilter交互的主要方式，但随着`nftables`的引入，它提供了一种更现代、更灵活的方式来配置netfilter规则。`nftables`支持更丰富的表达能力和更高效的内部实现。
* CentOS8里，就用 `nftables` 框架替代了 `iptables` 框架作为默认的网络包过滤工具。（**难道这就是之前日志跟踪实验没成功的原因？ TODO**）

疑问：既然`nftables`旨在替换`iptables`，现在的使用情况怎么样？

> 实际上目前各大 Linux 发行版都已经不建议使用 iptables 了，甚至把 iptables 重命名为了 iptables-legacy
>
> 目前 opensuse/debian/opensuse 都已经预装了并且推荐使用 nftables，而且 firewalld 已经默认使用 nftables 作为它的后端了。
>
> **但是现在 kubernetes/docker 都还是用的 iptables**
>
> 参考自：[iptables 及 docker 容器网络分析](https://thiscute.world/posts/iptables-and-container-networks/)

查看自己当前CentOS8.5的环境，firewalld的配置文件：/etc/firewalld/firewalld.conf，看配的是iptables

```sh
# FirewallBackend                                                                                                                                             
# Selects the firewall backend implementation.
# Choices are:
#   - nftables (default)
#   - iptables (iptables, ip6tables, ebtables and ipset)
#FirewallBackend=nftables
FirewallBackend=iptables
```

## 3. netfilter hooks

netfilter提供了`5`个hook点，这些在内核协议栈中已经定义好了（之前学习eBPF时可了解到内核提供了各种类型hook钩子）

*注意：下面列的hook类型是IPv4的宏，IPv6则为`NF_IP6_PRE_ROUTING`形式，枚举值是一样的。具体见下面**ip_rcv逻辑**小节的分析说明。*

* `NF_IP_PRE_ROUTING`：接收到的包进入协议栈后立即触发此 hook，在进行任何路由判断（将包发往哪里）之前
* `NF_IP_LOCAL_IN`：接收到的包经过路由判断，如果目的是本机，将触发此 hook
* `NF_IP_FORWARD`：接收到的包经过路由判断，如果目的是其他机器，将触发此 hook
* `NF_IP_LOCAL_OUT`：本机产生的准备发送的包，在进入协议栈后立即触发此 hook
* `NF_IP_POST_ROUTING`：本机产生的准备发送的包或者转发的包，在经过路由判断之后， 将触发此 hook

内核协议栈各hook点位置和控制流如下图所示（来自[Wikipedia](https://upload.wikimedia.org/wikipedia/commons/3/37/netfilter-packet-flow.svg)）：

![netfilter各hook点和控制流](/images/netfilter-packet-flow.svg)

为了理解上面这张图，还需要了解 **`chain`** 和 **`table`**的概念。

* iptables 使用 `table` 来组织规则，根据用来做什么类型的判断标准，将规则分为不同 `table`。
* 在每个 `table` 内部，规则被进一步组织成 `chain`，内置的 `chain` 是由内置的 `hook` 触发 的。

**chain：**

chain基本上能决定规则是何时被匹配的。内置的 chain 名字和 netfilter hook 名字是一一对应的：

* `PREROUTING`：由 `NF_IP_PRE_ROUTING` hook 触发
* `INPUT`：由 `NF_IP_LOCAL_IN` hook 触发
* `FORWARD`：由 `NF_IP_FORWARD` hook 触发
* `OUTPUT`：由 `NF_IP_LOCAL_OUT` hook 触发
* `POSTROUTING`：由 `NF_IP_POST_ROUTING` hook 触发

**table：**

iptables 提供的 table 类型如下：

* `filter`：过滤（放行/拒绝），判断是否允许一个包通过，这个 table 提供了防火墙 的一些常见功能
* `nat`：网络地址转换，通常用于将包路由到无法直接访问的网络
* `mangle`：修改 IP 头
* `raw`：conntrack 相关，其唯一目的就是提供一个让包绕过连接跟踪的框架
* `security`：打 SELinux 标记

## 4. 内核代码跟踪

这里先找一个TCP相关追踪点获取一个堆栈，再根据堆栈去找代码分析。

说明：本篇环境基于CentOS8.5，内核：4.18.0-348.7.1.el8_5.x86_64

### 4.1. 先获取一份网络堆栈

有多种方式获取堆栈，可按之前[追踪内核网络堆栈的几种方式](https://xiaodongq.github.io/2024/07/03/strace-kernel-network-stack/)里的方法，这里用bpftrace来获取。

```sh
# TCP相关追踪点
[root@xdlinux ➜ ~ ]$ bpftrace -l |grep -E ':tcp:|sock:inet|skb:'
tracepoint:skb:consume_skb
tracepoint:skb:kfree_skb
tracepoint:skb:skb_copy_datagram_iovec
tracepoint:sock:inet_sock_set_state
tracepoint:tcp:tcp_destroy_sock
tracepoint:tcp:tcp_probe
tracepoint:tcp:tcp_rcv_space_adjust
tracepoint:tcp:tcp_receive_reset
tracepoint:tcp:tcp_retransmit_skb
tracepoint:tcp:tcp_retransmit_synack
tracepoint:tcp:tcp_send_reset
```

先选取跟TCP状态变化有关的 `tracepoint:sock:inet_sock_set_state`进行跟踪，并打印内核堆栈

方法：用bpftrace启动eBPF跟踪，服务端`python -m http.server`起一个服务，并通过客户端`curl 192.168.1.150:8000`。

截取一个网络接收的堆栈如下：

```sh
[root@xdlinux ➜ ~ ]$ bpftrace -e 'tracepoint:sock:inet_sock_set_state { printf("comm:%s, stack:%s\n", comm, kstack); }'
...
comm:swapper/9, stack:
        inet_sk_state_store+132
        # linux-4.18/net/ipv4/af_inet.c
        inet_sk_state_store+132
        # linux-4.18/net/ipv4/tcp.c
        tcp_set_state+148
        # linux-4.18/net/ipv4/tcp.c
        tcp_done+54
        tcp_rcv_state_process+3421
        # linux-4.18/net/ipv4/tcp_input.c
        tcp_v4_do_rcv+180
        # 传输层，TCP协议初始化时.handler注册为该函数
        # linux-4.18/net/ipv4/tcp_ipv4.c
        tcp_v4_rcv+2883
        ip_protocol_deliver_rcu+44
        # linux-4.18/net/ipv4/ip_input.c
        ip_local_deliver_finish+77
        ip_local_deliver+224
        # IP层
        # linux-4.18/net/ipv4/ip_input.c
        ip_rcv+635
        # 网络协议栈收到skb，依次向上面的各协议调用栈传递
        # linux-4.18/net/core/dev.c
        __netif_receive_skb_core+2963
        # 数据包将被送到协议栈中
        # linux-4.18/net/core/dev.c
        netif_receive_skb_internal+61
        # 网卡GRO特性，理解成把相关的小包合并成一个大包，目的是减少传送给网络栈的包数
        # linux-4.18/net/core/dev.c
        napi_gro_receive+186
        # 网卡驱动注册的poll
        # linux-4.18/drivers/net/ethernet/realtek/r8169.c
        rtl8169_poll+667
        __napi_poll+45
        # net_dev_init(void)时注册的 NET_RX_SOFTIRQ软中断 处理函数
        # linux-4.18/net/core/dev.c
        net_rx_action+595
        # 软中断
        __softirqentry_text_start+215
        irq_exit+247
        # 硬中断
        do_IRQ+127
        ret_from_intr+0
        cpuidle_enter_state+219
        cpuidle_enter+44
        do_idle+564
        cpu_startup_entry+111
        start_secondary+411
        secondary_startup_64_no_verify+194
...
```

### 4.2. 接收数据前置处理

有上面的堆栈后，选取几个关键过程分析，直接参考[图解Linux网络包接收过程](https://mp.weixin.qq.com/s?__biz=MjM5Njg5NDgwNA==&mid=2247484058&idx=1&sn=a2621bc27c74b313528eefbc81ee8c0f&chksm=a6e303a191948ab7d06e574661a905ddb1fae4a5d9eb1d2be9f1c44491c19a82d95957a0ffb6&scene=21#wechat_redirect)里的梳理，过程大体是对应的。

```c
// linux-4.18/net/core/dev.c
static int __netif_receive_skb_core(struct sk_buff *skb, bool pfmemalloc)
{
    struct packet_type *ptype, *pt_prev;
    rx_handler_func_t *rx_handler;
    struct net_device *orig_dev;
    bool deliver_exact = false;
    int ret = NET_RX_DROP;
    __be16 type;

    net_timestamp_check(!netdev_tstamp_prequeue, skb);

    // 定义 tracepoint:net:netif_receive_skb，可以通过eBPF追踪
    trace_netif_receive_skb(skb);
    ...

    // pcap逻辑，&ptype_all、&skb->dev->ptype_all 这里会将数据送入抓包点。tcpdump就是从这个入口获取包的
    list_for_each_entry_rcu(ptype, &ptype_all, list) {
        if (pt_prev)
            // 从数据包中取出协议信息，然后遍历注册在这个协议上的回调函数列表
            ret = deliver_skb(skb, pt_prev, orig_dev);
        pt_prev = ptype;
    }

    list_for_each_entry_rcu(ptype, &skb->dev->ptype_all, list) {
        if (pt_prev)
            // 从数据包中取出协议信息，然后遍历注册在这个协议上的回调函数列表
            ret = deliver_skb(skb, pt_prev, orig_dev);
        pt_prev = ptype;
    }
    ...
}
```

```c
// linux-4.18/net/core/dev.c
static inline int deliver_skb(struct sk_buff *skb,
                  struct packet_type *pt_prev,
                  struct net_device *orig_dev)
{
    if (unlikely(skb_orphan_frags_rx(skb, GFP_ATOMIC)))
        return -ENOMEM;
    refcount_inc(&skb->users);
    // 协议层注册的处理函数，对于ip包来讲，就会进入到ip_rcv（如果是arp包的话，会进入到arp_rcv）
    return pt_prev->func(skb, skb->dev, pt_prev, orig_dev);
}
```

贴一下pt_prev对应的`packet_type`结构：

```c
// linux-4.18/include/linux/netdevice.h
struct packet_type {
    __be16			type;	/* This is really htons(ether_type). */
    struct net_device	*dev;	/* NULL is wildcarded here	     */
    int			(*func) (struct sk_buff *,
                     struct net_device *,
                     struct packet_type *,
                     struct net_device *);
    bool			(*id_match)(struct packet_type *ptype,
                        struct sock *sk);
    void			*af_packet_priv;
    struct list_head	list;
};
```

### 4.3. IP网络层

#### 4.3.1. ip_rcv注册时机

上面`deliver_skb(xxx)`中调用的`pt_prev->func()`，其中的`func`就是网络子系统`inet_init()`初始化时，注册的IP网络层处理函数

```c
// linux-4.18/net/ipv4/af_inet.c
static int __init inet_init(void)
{
    ...
    rc = proto_register(&tcp_prot, 1);
    if (rc)
        goto out;

    rc = proto_register(&udp_prot, 1);
    if (rc)
        goto out_unregister_tcp_proto;
    ...
    // 注册ip网络层的处理函数为 ip_rcv
    dev_add_pack(&ip_packet_type);
    ...
}

// ip_packet_type结构如下
static struct packet_type ip_packet_type __read_mostly = {
    .type = cpu_to_be16(ETH_P_IP),
    .func = ip_rcv,
};
```

#### 4.3.2. ip_rcv逻辑

继续看一下IP层的处理逻辑 `ip_rcv`，可看到`NF_INET_PRE_ROUTING`这个hook

```c
// linux-4.18/net/ipv4/ip_input.c
int ip_rcv(struct sk_buff *skb, struct net_device *dev, struct packet_type *pt, struct net_device *orig_dev)
{
    const struct iphdr *iph;
    struct net *net;
    u32 len;
    ...

    // 这里就是一个 netfilter 的hook了，类型为 NF_INET_PRE_ROUTING
    return NF_HOOK(NFPROTO_IPV4, NF_INET_PRE_ROUTING,
               net, NULL, skb, dev, NULL,
               ip_rcv_finish);

csum_error:
    __IP_INC_STATS(net, IPSTATS_MIB_CSUMERRORS);
inhdr_error:
    __IP_INC_STATS(net, IPSTATS_MIB_INHDRERRORS);
drop:
    kfree_skb(skb);
out:
    return NET_RX_DROP;
}

hook类型看起来和上面netfilter介绍时的没完全对应起来。检索下可知是IPv4和IPv6各自定义了宏跟hook枚举值对应，实际是一样的。  
而上面介绍时也只是放了IPv4的hook。

```c
// linux-4.18/include/uapi/linux/netfilter.h
enum nf_inet_hooks {
    NF_INET_PRE_ROUTING,
    NF_INET_LOCAL_IN,
    NF_INET_FORWARD,
    NF_INET_LOCAL_OUT,
    NF_INET_POST_ROUTING,
    NF_INET_NUMHOOKS
};
```

IPv4的netfilter hooks：

```c
// linux-4.18/include/uapi/linux/netfilter_ipv4.h
/* IP Hooks */
/* After promisc drops, checksum checks. */
#define NF_IP_PRE_ROUTING	0
/* If the packet is destined for this box. */
#define NF_IP_LOCAL_IN		1
/* If the packet is destined for another interface. */
#define NF_IP_FORWARD		2
/* Packets coming from a local process. */
#define NF_IP_LOCAL_OUT		3
/* Packets about to hit the wire. */
#define NF_IP_POST_ROUTING	4
#define NF_IP_NUMHOOKS		5
```

IPv6的netfilter hooks：

```c
// linux-4.18/include/uapi/linux/netfilter_ipv6.h
/* IP6 Hooks */
/* After promisc drops, checksum checks. */
#define NF_IP6_PRE_ROUTING	0
/* If the packet is destined for this box. */
#define NF_IP6_LOCAL_IN		1
/* If the packet is destined for another interface. */
#define NF_IP6_FORWARD		2
/* Packets coming from a local process. */
#define NF_IP6_LOCAL_OUT		3
/* Packets about to hit the wire. */
#define NF_IP6_POST_ROUTING	4
#define NF_IP6_NUMHOOKS		5
```

## 5. 小结


## 6. 参考

1、[[译] 深入理解 iptables 和 netfilter 架构](https://arthurchiao.art/blog/deep-dive-into-iptables-and-netfilter-arch-zh)

2、[用户态 tcpdump 如何实现抓到内核网络包的?](https://mp.weixin.qq.com/s?__biz=MjM5Njg5NDgwNA==&mid=2247486315&idx=1&sn=ce3a85a531447873e02ccef17198e8fe&chksm=a6e30a509194834693bb7ee50cdd3868ab1f686a3a0807e2d1a514253ba1579d1246b99bf35d&scene=178&cur_album_id=1532487451997454337#rd)

3、[来，今天飞哥带你理解 iptables 原理！](https://mp.weixin.qq.com/s?__biz=MjM5Njg5NDgwNA==&mid=2247487465&idx=1&sn=aace79dcb4edb011cf69e7cd9f7331f9&chksm=a6e30ed2919487c402f20fdda822bc63f057a334e81e8d26e48194f5b679882c627311205bbe&scene=178&cur_album_id=1532487451997454337#rd)

4、[iptable 的基石：netfilter 原理与实战](https://juejin.cn/book/6844733794801418253/section/7355436057355583528)

5、[iptables 及 docker 容器网络分析](https://thiscute.world/posts/iptables-and-container-networks/)

6、[图解Linux网络包接收过程](https://mp.weixin.qq.com/s?__biz=MjM5Njg5NDgwNA==&mid=2247484058&idx=1&sn=a2621bc27c74b313528eefbc81ee8c0f&chksm=a6e303a191948ab7d06e574661a905ddb1fae4a5d9eb1d2be9f1c44491c19a82d95957a0ffb6&scene=21#wechat_redirect)

7、GPT
