---
layout: post
title: TCP半连接队列溢出实验及分析
categories: 网络
tags: 网络
---

* content
{:toc}

半连接队列溢出分析及实验，并用工具跟踪



## 1. 背景

在“[TCP建立连接相关过程](https://xiaodongq.github.io/2024/05/18/tcp_connect/)”这篇文章中，进行了全连接队列溢出的实验，并且遗留了几个问题。

本博客实验分析半连接队列溢出情况，并探究上述文章中的遗留问题。

1. 半连接队列溢出情况分析，服务端接收具体处理逻辑
2. 内核drop包的时机，以及跟抓包的关系。哪些情况可能会抓不到drop的包？
3. systemtap/ebpf跟踪TCP状态变化，跟踪上述drop事件
4. 上述全连接实验case1中，2MSL内没观察到客户端连接`FIN_WAIT2`状态，为什么？

## 2. 前置说明

主要基于这篇文章："[从一次线上问题说起，详解 TCP 半连接队列、全连接队列](https://mp.weixin.qq.com/s/YpSlU1yaowTs-pF6R43hMw?poc_token=HKCgSGaji2dgAtvVc7gzTQykh3Aw6neDWcojHyB8)"，进行学习和扩展。

环境：起两个阿里云抢占式实例，Alibaba Cloud Linux 3.2104 LTS 64位（内核版本：5.10.134-16.1.al8.x86_64）

基于5.10内核代码跟踪流程

## 分析半连接

上篇文章中自己的实验没抓到`SYN`发出后继续重发的情况，先跟着参考文章分析TCP半连接队列流程，再进行实验复现。

对于TCP，第一次接收处理时即处理三次握手的第一次`SYN`，先梳理其注册的处理接口

`inet_init`初始化网络协议->注册TCP协议(`struct proto tcp_prot`)

注册的init接口为： `.init = tcp_v4_init_sock,`，其中会指定tcp协议socket连接的处理接口`ipv4_specific`

```c
// linux-5.10.10/net/ipv4/tcp_ipv4.c
static int tcp_v4_init_sock(struct sock *sk)
{
    struct inet_connection_sock *icsk = inet_csk(sk);

    tcp_init_sock(sk);

    icsk->icsk_af_ops = &ipv4_specific;

#ifdef CONFIG_TCP_MD5SIG
    tcp_sk(sk)->af_specific = &tcp_sock_ipv4_specific;
#endif

    return 0;
}
```

```cpp
// linux-5.10.10/net/ipv4/tcp_ipv4.c
const struct inet_connection_sock_af_ops ipv4_specific = {
    // 发送数据的函数。用于将数据从传输层（TCP）发送到网络层（IP）
    .queue_xmit	   = ip_queue_xmit,
    // 用于计算校验和的函数
    .send_check	   = tcp_v4_send_check,
    .rebuild_header	   = inet_sk_rebuild_header,
    .sk_rx_dst_set	   = inet_sk_rx_dst_set,
    // 处理SYN段的函数。在TCP三次握手的开始阶段被调用，用于处理来自客户端的SYN包
    .conn_request	   = tcp_v4_conn_request,
    // 创建和初始化新socket的函数。在TCP三次握手完成后被调用，用于为新的连接创建一个传输控制块（TCB）并初始化它
    .syn_recv_sock	   = tcp_v4_syn_recv_sock,
    .net_header_len	   = sizeof(struct iphdr),
    .setsockopt	   = ip_setsockopt,
    .getsockopt	   = ip_getsockopt,
    .addr2sockaddr	   = inet_csk_addr2sockaddr,
    .sockaddr_len	   = sizeof(struct sockaddr_in),
    .mtu_reduced	   = tcp_v4_mtu_reduced,
};
```

然后就可以看下处理握手时第一次请求`SYN`的处理：

```cpp
// linux-5.10.10/net/ipv4/tcp_ipv4.c
// 初始化时注册的处理第一次SYN的函数
int tcp_v4_conn_request(struct sock *sk, struct sk_buff *skb)
{
    // 如果是广播或者组播的SYN请求包，直接drop
    /* Never answer to SYNs send to broadcast or multicast */
    if (skb_rtable(skb)->rt_flags & (RTCF_BROADCAST | RTCF_MULTICAST))
        goto drop;

    // 处理请求，处理类通过参数传入(结构体指针模拟多态) tcp_request_sock_ops 和 tcp_request_sock_ipv4_ops
    // 具体初始化分别为：`struct request_sock_ops tcp_request_sock_ops` 和 `const struct tcp_request_sock_ops tcp_request_sock_ipv4_ops`
    return tcp_conn_request(&tcp_request_sock_ops,
                &tcp_request_sock_ipv4_ops, sk, skb);

drop:
    tcp_listendrop(sk);
    return 0;
}

// request_sock_ops是用于定义连接请求（request socket）操作的结构体
/* 
 在 TCP/IP 协议栈中，当一个连接请求（如 SYN 包）到达时，内核不会立即创建一个完整的套接字（socket），
 而是先创建一个连接请求套接字（request socket），这个套接字只包含建立连接所需的最少信息。
 一旦连接被确认（如收到 SYN/ACK 和 ACK），这个连接请求套接字就会被转换为一个完整的套接字。 
*/
struct request_sock_ops tcp_request_sock_ops __read_mostly = {
    .family		=	PF_INET,
    .obj_size	=	sizeof(struct tcp_request_sock),
    // 当需要重传 SYN/ACK 响应时调用的函数
    .rtx_syn_ack	=	tcp_rtx_synack,
    // 发送ACK响应的函数
    .send_ack	=	tcp_v4_reqsk_send_ack,
    // 当请求套接字不再需要时调用的析构函数，用于释放资源
    .destructor	=	tcp_v4_reqsk_destructor,
    // 发送RST响应的函数，即拒绝连接请求
    .send_reset	=	tcp_v4_send_reset,
    // 当SYN/ACK超时时调用
    .syn_ack_timeout =	tcp_syn_ack_timeout,
};

// 虽然跟上面全局变量重名，但这里是一个结构体
/*
 该结构是 TCP 协议栈用于扩展 struct request_sock_ops 结构体以处理 TCP 特定的连接请求操作的结构体。
 由于 TCP 连接建立过程比一些其他协议（如 UDP）更复杂，因此 TCP 需要额外的函数和逻辑来处理 SYN 包的接收、确认、超时等情况。
*/
const struct tcp_request_sock_ops tcp_request_sock_ipv4_ops = {
    .mss_clamp	=	TCP_MSS_DEFAULT,
#ifdef CONFIG_TCP_MD5SIG
    .req_md5_lookup	=	tcp_v4_md5_lookup,
    .calc_md5_hash	=	tcp_v4_md5_hash_skb,
#endif
    // 初始化TCP请求套接字的函数
    .init_req	=	tcp_v4_init_req,
#ifdef CONFIG_SYN_COOKIES
    .cookie_init_seq =	cookie_v4_init_sequence,
#endif
    .route_req	=	tcp_v4_route_req,
    // 初始化TCP序列号的函数
    .init_seq	=	tcp_v4_init_seq,
    // 初始化TCP时间戳偏移的函数，时间戳用于计算往返时间（RTT）和防止被包裹的序列号
    .init_ts_off	=	tcp_v4_init_ts_off,
    // 发送SYN/ACK响应的函数
    .send_synack	=	tcp_v4_send_synack,
};
```

具体处理逻辑：

```cpp
// linux-5.10.10/net/ipv4/tcp_input.c
// 处理第一次SYN请求
int tcp_conn_request(struct request_sock_ops *rsk_ops,
             const struct tcp_request_sock_ops *af_ops,
             struct sock *sk, struct sk_buff *skb)
{
    ...
    // tcp_syncookies：1表示当半连接队列满时才开启；2表示无条件开启功能，此处可看到就算半连接队列满了也不drop
    // inet_csk_reqsk_queue_is_full：判断accept队列(全连接队列)是否满
    if ((net->ipv4.sysctl_tcp_syncookies == 2 ||
         inet_csk_reqsk_queue_is_full(sk)) && !isn) {
        want_cookie = tcp_syn_flood_action(sk, rsk_ops->slab_name);
        if (!want_cookie)
            goto drop;
    }
    ...
}
```

## 小结

## 参考

1、[从一次线上问题说起，详解 TCP 半连接队列、全连接队列](https://mp.weixin.qq.com/s/YpSlU1yaowTs-pF6R43hMw?poc_token=HKCgSGaji2dgAtvVc7gzTQykh3Aw6neDWcojHyB8)

2、GPT
