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

基于5.10内核代码跟踪流程，上下文均基于IPV4，暂不考虑IPV6

## 3. 分析半连接

上篇文章中自己的实验没抓到`SYN`发出后继续重发的情况，先跟着参考文章分析TCP半连接队列流程，再进行实验复现。

### 3.1. 重要前提：先认识几种不同种类的sock结构

网络初始化、处理接口逻辑等过程中，涉及到几种不同的sock结构，前置了解再梳理代码流程会清晰很多。

下述几种sock类型，可以当作是`父类-子类`关系，C语言中结构体里的内存是连续的，将要继承的"父类"，放到结构体的第一位，然后就可以通过强制转换进行继承访问。比如：`struct sock *sk`类型转为`tcp_sock`，可用`(struct tcp_sock *)sk`转换后使用。

![sock种类](/images/2024-06-03-sock_type.png)

* 1、`sock`是最基础的结构，维护一些任何协议都有可能会用到的收发数据缓冲区。

```cpp
// linux-5.10.176\include\net\sock.h
struct sock {
    struct sock_common  __sk_common;
    socket_lock_t       sk_lock;
    atomic_t        sk_drops;
    int         sk_rcvlowat;
    struct sk_buff_head sk_error_queue;
    struct sk_buff      *sk_rx_skb_cache;
    struct sk_buff_head sk_receive_queue;
    ...
    struct proto		*skc_prot;
    ...
}
```

前面也提到过的socket创建流程中，涉及创建`struct sock`结构

`__sys_socket` -> `sock_create` -> `__sock_create` -> (net_proto_family结构)`pf->create`，实际调用到`inet_create`

其中会创建`struct socket *sock`，里面会进行`struct sock`和`struct file`的创建和映射操作

代码逻辑里面涉及的RCU相关解释，辅助代码理解：

* RCU（Read-Copy Update）是一种用于实现高效读取和并发更新数据结构的同步机制。
* 在网络内核中，它允许多个线程或进程同时读取共享数据，而不需要获取锁，从而提高了并发性能。
* 读：允许多个线程或进程同时读取共享数据，而不需要获取锁
* 写：RCU也确保了在写操作进行时，读操作能够访问到一致的数据

应用场景：

1. 路由表：网络内核使用RCU来管理路由表，允许多个线程或进程同时读取路由表信息，而不需要加锁。这可以提高路由查找和转发的效率。
2. 套接字数据结构：在网络协议栈中，RCU被用于管理套接字数据结构，如连接表、监听队列等。这可以确保在多个进程或线程之间共享套接字信息时，不会出现数据不一致或竞争条件。
3. 网络缓冲区：在网络数据包处理过程中，RCU可以用于管理网络缓冲区，允许多个处理线程同时读取和修改数据包。这可以提高数据包处理的吞吐量和效率。

* 2、`inet_sock`，特指用了网络传输功能的`sock`，在sock的基础上还加入了TTL，端口，IP地址这些跟网络传输相关的字段信息。

相对的，有些sock不是用网络传输的，比如Unix domain socket，用于本机进程之间的通信，直接读写文件，不需要经过网络协议栈。

```cpp
// linux-5.10.10/include/net/inet_sock.h
struct inet_sock {
	/* sk and pinet6 has to be the first two members of inet_sock */
	struct sock		sk;
#if IS_ENABLED(CONFIG_IPV6)
	struct ipv6_pinfo	*pinet6;
#endif
	/* Socket demultiplex comparisons on incoming packets. */
#define inet_daddr		sk.__sk_common.skc_daddr
#define inet_rcv_saddr		sk.__sk_common.skc_rcv_saddr
#define inet_dport		sk.__sk_common.skc_dport
#define inet_num		sk.__sk_common.skc_num
    ...
	__u8			min_ttl;
	__u8			mc_ttl;
	...
};
```

* 3、`inet_connection_sock` 是指面向连接的`sock`，在`inet_sock`的基础上加入面向连接的协议里相关字段，比如accept队列，数据包分片大小，握手失败重试次数等。

从其成员变量的命名形式：`icsk_xxx`就可看出其为`inet connection sock`的简写，后续梳理逻辑看变量命名就能知道其所属的sock层级

```cpp
// linux-5.10.10/include/net/inet_connection_sock.h
struct inet_connection_sock {
	/* inet_sock has to be the first member! */
	struct inet_sock	  icsk_inet;
	// 全连接队列，已经 ESTABLISHED 的队列：FIFO of established children
	struct request_sock_queue icsk_accept_queue;
	struct inet_bind_bucket	  *icsk_bind_hash;
	unsigned long		  icsk_timeout;
	...
};
```

* 4、`tcp_sock`就是tcp协议专用的sock结构，在`inet_connection_sock`基础上还加入了tcp特有的滑动窗口、拥塞避免等功能。

该结构中内容很多，近250多行(5.10.10内核)

```cpp
// linux-5.10.10/include/linux/tcp.h
struct tcp_sock {
	/* inet_connection_sock has to be the first member of tcp_sock */
	struct inet_connection_sock	inet_conn;
	u16	tcp_header_len;	/* Bytes of tcp header to send		*/
	u16	gso_segs;	/* Max number of segs per GSO packet	*/
    ...
    u32	snd_wnd;	/* The window we expect to receive	*/
	u32	max_window;	/* Maximal window ever seen from peer	*/
    ...
    u32	snd_cwnd;	/* Sending congestion window		*/
	u32	snd_cwnd_cnt;	/* Linear increase counter		*/
    ...
}
```

### 3.2. SYN接收处理接口是哪个？是何时注册的？

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
    ...
};
```

所以解答小标题问题：初始化网络协议时，注册SYN处理函数为`tcp_v4_conn_request`

### 3.3. tcp_v4_conn_request 逻辑

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

```cpp
// linux-5.10.10/include/net/inet_connection_sock.h
// 判断全连接队列是否已满
static inline int inet_csk_reqsk_queue_is_full(const struct sock *sk)
{
	// sk->sk_max_ack_backlog，之前跟踪listen，可以看到是将 min(backlog,somaxconn) 赋值给了它
	// 全连接队列 >= 最大全连接队列数量
	return inet_csk_reqsk_queue_len(sk) >= sk->sk_max_ack_backlog;
}
```

## 4. 小结

## 5. 参考

1、[从一次线上问题说起，详解 TCP 半连接队列、全连接队列](https://mp.weixin.qq.com/s/YpSlU1yaowTs-pF6R43hMw?poc_token=HKCgSGaji2dgAtvVc7gzTQykh3Aw6neDWcojHyB8)

2、[不为人知的网络编程(十五)：深入操作系统，一文搞懂Socket到底是什么](https://developer.aliyun.com/article/1173904)

3、GPT
