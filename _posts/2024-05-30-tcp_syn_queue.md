---
layout: post
title: TCP半连接队列相关过程系列（一） -- 半连接队列代码逻辑
categories: 网络
tags: 网络
---

* content
{:toc}

半连接队列相关过程分析及实验，并用工具跟踪。本文先分析半连接相关代码逻辑。



## 1. 背景

在“[TCP建立连接相关过程](https://xiaodongq.github.io/2024/05/18/tcp_connect/)”这篇文章中，进行了全连接队列溢出的实验，并且遗留了几个问题。

本博客跟踪分析半连接队列相关过程，并探究上述文章中的遗留问题。

1. 半连接队列溢出情况分析，服务端接收具体处理逻辑
2. 内核drop包的时机，以及跟抓包的关系。哪些情况可能会抓不到drop的包？
3. systemtap/ebpf跟踪TCP状态变化，跟踪上述drop事件
4. 上述全连接实验case1中，2MSL内没观察到客户端连接`FIN_WAIT2`状态，为什么？

本文先分析梳理代码逻辑。

## 2. 前置说明

主要基于这篇文章："[从一次线上问题说起，详解 TCP 半连接队列、全连接队列](https://mp.weixin.qq.com/s/YpSlU1yaowTs-pF6R43hMw?poc_token=HKCgSGaji2dgAtvVc7gzTQykh3Aw6neDWcojHyB8)"，进行学习和扩展。

环境：起两个阿里云抢占式实例，Alibaba Cloud Linux 3.2104 LTS 64位（内核版本：5.10.134-16.1.al8.x86_64）

基于5.10内核代码跟踪流程，上下文均基于IPV4，暂不考虑IPV6

## 3. 前提：先认识几种不同种类的sock结构

网络初始化、处理接口逻辑等过程中，涉及到几种不同的sock结构，前置了解再梳理代码流程会清晰很多。

下述几种sock类型，可以当作是`父类-子类`关系，C语言中结构体里的内存是连续的，将要继承的"父类"，放到结构体的第一位，然后就可以通过强制转换进行继承访问。

![sock种类](/images/2024-06-03-sock_type.png)

对于TCP的`socket`来说，`sock`对象实际上是一个`tcp_sock`。因此TCP中的`sock`对象随时可以强制类型转化为`tcp_sock`（`(struct tcp_sock *)sk`形式）、`inet_connection_sock`、`inet_sock`来使用。

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
    // 全连接队列？，已经 ESTABLISHED 的队列：FIFO of established children
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

## 4. inet_listen服务端监听流程进一步分析

在说明全连接队列最大长度时，简单提到过`listen`系统调用，会调用到TCP协议注册的`inet_listen`，此处进一步分析其逻辑。

```c
// linux-5.10.10/net/socket.c(不同内核版本可能有部分差异，不影响流程)
int __sys_listen(int fd, int backlog)
{
    ...
    sock = sockfd_lookup_light(fd, &err, &fput_needed);
    if (sock) {
        // 获取sysctl配置的 net.core.somaxconn 参数
        somaxconn = sock_net(sock->sk)->core.sysctl_somaxconn;
        // 取min(传入的backlog, 系统net.core.somaxconn)
        if ((unsigned int)backlog > somaxconn)
            backlog = somaxconn;

        err = security_socket_listen(sock, backlog);
        if (!err)
            // ops里是一系列socket操作的函数指针(如bind/accept)，inet_init(void)网络协议初始化时会设置
            // 其中，tcp协议的结构是 inet_stream_ops，里面的listen函数指针赋值为：inet_listen
            err = sock->ops->listen(sock, backlog);
        ...
    }
    ...
}

// linux-5.10.10/net/ipv4/af_inet.c
int inet_listen(struct socket *sock, int backlog)
{
    struct sock *sk = sock->sk;
    lock_sock(sk);
    ...
    // __sys_listen(linux-5.10.176\net\socket.c)调用时，传进来的的backlog值是`min(调__sys_listen传入的backlog, 系统net.core.somaxconn)`
    // 此处设置到struct socket中struct sock相应成员中： sk_max_ack_backlog
    WRITE_ONCE(sk->sk_max_ack_backlog, backlog);

    if (old_state != TCP_LISTEN) {
        ...
        // 监听操作的核心逻辑
        err = inet_csk_listen_start(sk, backlog);
        if (err)
            goto out;
        ...
    }
    ...
}
```

下面具体分析调用到的`inet_csk_listen_start`函数

```cpp
// linux-5.10.10/net/ipv4/inet_connection_sock.c
int inet_csk_listen_start(struct sock *sk, int backlog)
{
    // 转换成面向连接的sock
    struct inet_connection_sock *icsk = inet_csk(sk);
    // 转换成基于网络的sock
    struct inet_sock *inet = inet_sk(sk);
    int err = -EADDRINUSE;
    ...
}
```

5.10内核的`request_sock_queue`结构里，只有全连接队列（网络上的文章很多是3.10内核，注意版本对应）

和3.10内核的对比，见下面3.10的单独章节。

```cpp
// linux-5.10.10/include/net/request_sock.h
struct request_sock_queue {
    spinlock_t		rskq_lock;
    u8			rskq_defer_accept;

    u32			synflood_warned;
    atomic_t		qlen;
    atomic_t		young;

    struct request_sock	*rskq_accept_head;
    struct request_sock	*rskq_accept_tail;
    struct fastopen_queue	fastopenq;
};
```

## 5. 分析TCP请求处理

### 5.1. SYN接收处理接口是哪个？是何时注册的？

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

### 5.2. tcp_v4_conn_request 逻辑

然后就可以看下处理握手时第一次请求`SYN`的处理：

```cpp
// linux-5.10.10/net/ipv4/tcp_ipv4.c
// 初始化时注册的处理第一次SYN的函数
// sk是socket， skb是请求？
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
    // 全连接队列 >= 最大全连接队列数量，半连接队列？？？ TODO
    return inet_csk_reqsk_queue_len(sk) >= sk->sk_max_ack_backlog;
}
```

## 6. 3.10内核对比

### 6.1. 概要说明

网上很多文章关于半连接都是基于3.x的内核，跟踪上述5.10内核过程中一直疑惑`icsk_accept_queue`算是全连接还是半连接队列。

对比3.10内核中`request_sock_queue`里既有全连接又有半连接，5.10内核里似乎没有单独的半连接，而是通过引用计数加1减1，共享同一个队列（类似享元模式？）。

带着怀疑在技术讨论群搜半连接队列，碰巧历史记录里有人提到：4.4之后的内核改了syn_queue半连接队列逻辑，半连接队列成为一个概念没有了，统一保存到`ehash table` 中，维护半连接长度就放到`icsk_accept_queue->qlen`，并附了一篇陈硕大佬的文章链接：[Linux 4.4 之后 TCP 三路握手的新流程](https://zhuanlan.zhihu.com/p/25313903)

### 6.2. inet_listen流程

下述逻辑可用下图概括：

![icsk_accept_queue](/images/2024-06-05-3.10-icsk_accept_queue.png)

图片出处：[为什么服务端程序都需要先 listen 一下？](https://mp.weixin.qq.com/s?__biz=MjM5Njg5NDgwNA==&mid=2247485737&idx=1&sn=baba45ad4fb98afe543bdfb06a5720b8&scene=21#wechat_redirect)

```cpp
// linux-3.10.89/net/ipv4/af_inet.c
int inet_listen(struct socket *sock, int backlog)
{
    struct sock *sk = sock->sk;
    unsigned char old_state;
    int err;
    ...
    if (old_state != TCP_LISTEN) {
        ...
        // 初始化半连接队列和
        err = inet_csk_listen_start(sk, backlog);
        if (err)
            goto out;
    }
    sk->sk_max_ack_backlog = backlog;
    err = 0;
    ...
}
```

```cpp
// linux-3.10.89/net/ipv4/inet_connection_sock.c
// nr_table_entries传入的是 backlog
int inet_csk_listen_start(struct sock *sk, const int nr_table_entries)
{
    struct inet_sock *inet = inet_sk(sk);
    struct inet_connection_sock *icsk = inet_csk(sk);
    // 申请半连接队列的空间，初始化全连接队列为NULL
    int rc = reqsk_queue_alloc(&icsk->icsk_accept_queue, nr_table_entries);
    ...
    // 设置socket状态为 LISTEN
    sk->sk_state = TCP_LISTEN;
    // TCP协议初始化时指定了： inet_csk_get_port
    // 用来处理TCP端口绑定操作，里面逻辑比较复杂，本文先不涉及
    if (!sk->sk_prot->get_port(sk, inet->inet_num)) {
        inet->inet_sport = htons(inet->inet_num);

        sk_dst_reset(sk);
        // inet_hash
        sk->sk_prot->hash(sk);

        return 0;
    }
    ...
}
```

先说明下上述`icsk->icsk_accept_queue`队列，其定义为：`struct request_sock_queue icsk_accept_queue;`队列结构，里面包含了全连接和半连接队列：

```cpp
// linux-3.10.89/include/net/request_sock.h
struct request_sock_queue {
    // 全连接队列，是一个先进先出(FIFO)的链表结构
    struct request_sock	*rskq_accept_head;
    struct request_sock	*rskq_accept_tail;
    rwlock_t		syn_wait_lock;
    u8			rskq_defer_accept;
    /* 3 bytes hole, try to pack */
    // 里面包含了半连接队列
    struct listen_sock	*listen_opt;
    struct fastopen_queue	*fastopenq; 
};

struct listen_sock {
    // 半连接队列长度的log2对数
    u8			max_qlen_log;
    u8			synflood_warned;
    /* 2 bytes hole, try to use */
    int			qlen;
    int			qlen_young;
    int			clock_hand;
    u32			hash_rnd;
    // 半连接队列长度
    u32			nr_table_entries;
    // 此处实际以hash表方式管理，用于第三次握手时快速地查找出来第一次握手时留存的`request_sock`对象
    struct request_sock	*syn_table[0];
};
```

继续看上面`inet_csk_listen_start`里初始化半连接队列的具体操作：

```cpp
// linux-3.10.89/net/core/request_sock.c
// nr_table_entries传入的是 backlog(listen时传入的参数)
int reqsk_queue_alloc(struct request_sock_queue *queue,
              unsigned int nr_table_entries)
{
    size_t lopt_size = sizeof(struct listen_sock);
    struct listen_sock *lopt;

    // min(backlog, tcp_max_syn_backlog)
    nr_table_entries = min_t(u32, nr_table_entries, sysctl_max_syn_backlog);
    // 取 max(8, nr_table_entries)
    nr_table_entries = max_t(u32, nr_table_entries, 8);
    // 2倍（结果按2^n取整)
    nr_table_entries = roundup_pow_of_two(nr_table_entries + 1);
    // 申请空间
    lopt_size += nr_table_entries * sizeof(struct request_sock *);
    if (lopt_size > PAGE_SIZE)
        lopt = vzalloc(lopt_size);
    else
        lopt = kzalloc(lopt_size, GFP_KERNEL);
    if (lopt == NULL)
        return -ENOMEM;

    // 此处含义：取 max( 3, log2(nr_table_entries) )
    // 每次 1<<max_qlen_log即乘2，直到>=nr_table_entries，即nr_table_entries以2为底
    for (lopt->max_qlen_log = 3;
         (1 << lopt->max_qlen_log) < nr_table_entries;
         lopt->max_qlen_log++);

    get_random_bytes(&lopt->hash_rnd, sizeof(lopt->hash_rnd));
    rwlock_init(&queue->syn_wait_lock);
    // 全连接队列 头
    queue->rskq_accept_head = NULL;
    // 上述计算的半连接长度限制
    lopt->nr_table_entries = nr_table_entries;

    write_lock_bh(&queue->syn_wait_lock);
    // struct listen_sock *lopt; 即我们常说的 半连接队列
    queue->listen_opt = lopt;
    write_unlock_bh(&queue->syn_wait_lock);

    return 0;
}
```

可看到，相比于5.10内核，此处额外申请了一个半连接队列的空间。

上面计算描述有点抽象，举个例子（来自参考链接里的：[为什么服务端程序都需要先 listen 一下？](https://mp.weixin.qq.com/s?__biz=MjM5Njg5NDgwNA==&mid=2247485737&idx=1&sn=baba45ad4fb98afe543bdfb06a5720b8&scene=21#wechat_redirect)）：

* 假设：某服务器上内核参数 `net.core.somaxconn` 为 128， `net.ipv4.tcp_max_syn_backlog` 为 8192。那么当用户 backlog 传入 5 时，半连接队列到底是多长呢？

和代码一样，我们还把计算分为四步，最终结果为 16。

```c
min (backlog, somaxconn)  = min (5, 128) = 5
min (5, tcp_max_syn_backlog) = min (5, 8192) = 5
max (5, 8) = 8
roundup_pow_of_two (8 + 1) = 16
```

* somaxconn 和 `tcp_max_syn_backlog` 保持不变，listen 时的 backlog 加大到 `512`，再算一遍，结果为 `256`。

```c
min (backlog, somaxconn)  = min (512, 128) = 128
min (128, tcp_max_syn_backlog) = min (128, 8192) = 128
max (128, 8) = 128
roundup_pow_of_two (128 + 1) = 256
```

> **把半连接队列长度的计算归纳成一句话，半连接队列的长度是 `min(backlog, somaxconn, tcp_max_syn_backlog) + 1 再上取整到 2 的幂次`，但最小不能小于`16`。**

## 7. 小结

## 8. 参考

1、[从一次线上问题说起，详解 TCP 半连接队列、全连接队列](https://mp.weixin.qq.com/s/YpSlU1yaowTs-pF6R43hMw?poc_token=HKCgSGaji2dgAtvVc7gzTQykh3Aw6neDWcojHyB8)

2、[不为人知的网络编程(十五)：深入操作系统，一文搞懂Socket到底是什么](https://developer.aliyun.com/article/1173904)

3、[为什么服务端程序都需要先 listen 一下？](https://mp.weixin.qq.com/s?__biz=MjM5Njg5NDgwNA==&mid=2247485737&idx=1&sn=baba45ad4fb98afe543bdfb06a5720b8&scene=21#wechat_redirect)

4、[能将三次握手理解到这个深度，面试官拍案叫绝！](https://mp.weixin.qq.com/s?__biz=MjM5Njg5NDgwNA==&mid=2247485862&idx=1&sn=1f3a92b8fd5fbc14c4d073d04c6d44ed&chksm=a6e3089d9194818bbd9ab3582bd7e7b7f2d83892833d088d8d1c514cbf145b9ee8f0f3b4be81&scene=178&cur_album_id=1532487451997454337#rd)

5、[Linux 4.4 之后 TCP 三路握手的新流程](https://zhuanlan.zhihu.com/p/25313903)

6、GPT
