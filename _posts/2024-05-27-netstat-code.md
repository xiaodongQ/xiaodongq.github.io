---
title: 分析netstat中的Send-Q和Recv-Q
categories: [网络, TCP半连接全连接]
tags: [Linux, 网络]
---

跟踪分析netstat中`Send-Q`和`Recv-Q`在不同连接状态(listen和非listen)下的含义。

## 1. 背景

[分析某环境中ss结果中Send-Q为0的原因](https://xiaodongq.github.io/2024/05/20/ss-sendq-0/)中，最后没分析`netstat`中为什么不展示全连接队列，本篇博客进行跟踪分析。

## 2. netstat源码

1、环境中执行结果

在ECS中查看netstat

```sh
[root@iZ2zejee6e4h8ysmmjwj1oZ ~]# netstat -antp
Active Internet connections (servers and established)
Proto Recv-Q Send-Q Local Address           Foreign Address         State       PID/Program name
tcp        0      0 0.0.0.0:22              0.0.0.0:*               LISTEN      925/sshd
tcp        0      0 0.0.0.0:5355            0.0.0.0:*               LISTEN      543/systemd-resolve 
tcp        0      0 0.0.0.0:111             0.0.0.0:*               LISTEN      1/systemd
tcp        0      0 172.23.133.141:38268    100.100.18.120:80       TIME_WAIT   -  
tcp        0      0 172.23.133.141:41326    100.100.30.28:80        ESTABLISHED 1152/AliYunDun
tcp        0    232 172.23.133.141:22       100.104.192.136:54940   ESTABLISHED 1343/sshd: root [pr 
tcp6       0      0 :::5355                 :::*                    LISTEN      543/systemd-resolve 
tcp6       0      0 :::111                  :::*                    LISTEN      1/systemd
```

截取/proc/net/tcp部分内容如下

```sh
[root@iZ2zejee6e4h8ysmmjwj1oZ ~]# cat /proc/net/tcp
  sl  local_address rem_address   st tx_queue rx_queue tr tm->when retrnsmt   uid  timeout inode
   0: 00000000:0016 00000000:0000 0A 00000000:00000000 00:00000000 00000000     0        0 22556 1 ffff8a4f35c39480 100 0 0 10 0
   1: 00000000:14EB 00000000:0000 0A 00000000:00000000 00:00000000 00000000   193        0 19185 1 ffff8a4f35c38a40 100 0 0 10 0
   2: 00000000:006F 00000000:0000 0A 00000000:00000000 00:00000000 00000000     0        0 14794 1 ffff8a4f35c38000 100 0 0 10 0
   3: 8D8517AC:E144 78126464:0050 06 00000000:00000000 03:0000014D 00000000     0        0 0 3 ffff8a4f03428e38
   4: 8D8517AC:C8A4 78126464:0050 06 00000000:00000000 03:00001706 00000000     0        0 0 3 ffff8a4f03428c08
```

2、查看`netstat`版本信息，可看到其位于`net-tools`包中，下载net-tools-2.10代码。

```sh
[root@iZ2zejee6e4h8ysmmjwj1oZ ~]# netstat -V
net-tools 2.10-alpha
```

3、其实现代码在netstat.c中

```cpp
// net-tools-2.10/net-tools-2.10/netstat.c
int main(int argc, char *argv[])
{
    ...
    // 解析选项
    case 't':
        flag_tcp++;
        break;
    ...
    if (!flag_arg || flag_tcp) {
        i = tcp_info();
        if (i)
        return (i);
    }
}

static int tcp_info(void)
{
    // #define _PATH_PROCNET_TCP        "/proc/net/tcp"
    // #define _PATH_PROCNET_TCP6       "/proc/net/tcp6"
    // tcp_do_one 是每行内容处理函数，若为tcp v4则解析/proc/net/tcp
    INFO_GUTS6(_PATH_PROCNET_TCP, _PATH_PROCNET_TCP6, "AF INET (tcp)",
           tcp_do_one, "tcp", "tcp6");
}

// sl  local_address rem_address   st tx_queue rx_queue tr tm->when retrnsmt   uid  timeout inode
//  0: 00000000:0016 00000000:0000 0A 00000000:00000000 00:00000000 00000000     0        0 22556 1 ffff8a4f35c39480 100 0 0 10 0
static void tcp_do_one(int lnr, const char *line, const char *prot)
{
    ...
    num = sscanf(line,
    "%d: %64[0-9A-Fa-f]:%X %64[0-9A-Fa-f]:%X %X %lX:%lX %X:%lX %lX %d %d %lu %*s\n",
         &d, local_addr, &local_port, rem_addr, &rem_port, &state,
         &txq, &rxq, &timer_run, &time_len, &retr, &uid, &timeout, &inode);
    ...
    // 对应：Proto Recv-Q Send-Q Local Address           Foreign Address         State
    printf("%-4s  %6ld %6ld %-*s %-*s %-11s",
           prot, rxq, txq, (int)netmax(23,strlen(local_addr)), local_addr, (int)netmax(23,strlen(rem_addr)), rem_addr, _(tcp_state[state]));
    ...
}
```

结论：

netstat展示信息会解析/proc/net/tcp (暂不管tcp6)，`Recv-Q`对应`rx_queue`，`Send-Q`对应`tx_queue`

## 3. /proc/net/tcp文件更新逻辑

这里的/proc/net/tcp，是Linux的一种序列文件(`seq_file`，内核顺序读取和写入的文件)，其更新逻辑在内核代码中查看。

**proc文件系统，只有在读取文件内容时，才动态生成相应的信息**

在内核源码的Documentation中，有其文件内容格式介绍：`Documentation/networking/proc_net_tcp.rst`  

![/proc/net/tcp文件格式](/images/2024-05-27-proc_tcp.png)

里面先展示listen状态的TCP连接，然后展示所有established的连接，然后是其他状态的连接。

### 3.1. 代码流程

* 1、 初始化：`tcp4_proc_init_net()`，里面会创建/proc/net/tcp文件

创建一个`proc_dir_entry*`并注册到/proc/net，其中会初始化对应api： `struct seq_operations tcp4_seq_ops`

```c
// linux-5.10.10/net/ipv4/tcp_ipv4.c
static int __net_init tcp4_proc_init_net(struct net *net)
{
    // 注册 tcp序列文件的操作api： tcp4_seq_ops
    if (!proc_create_net_data("tcp", 0444, net->proc_net, &tcp4_seq_ops,
            sizeof(struct tcp_iter_state), &tcp4_seq_afinfo))
        return -ENOMEM;
    return 0;
}

// 上述要注册的序列顺序操作api，序列文件进行open/read/write等操作时会涉及一系列顺序操作
static const struct seq_operations tcp4_seq_ops = {
    .show       = tcp4_seq_show,
    .start      = tcp_seq_start,
    .next       = tcp_seq_next,
    .stop       = tcp_seq_stop,
};
```

```c
// linux-5.10.10\fs\proc\proc_net.c
struct proc_dir_entry *proc_create_net_data(const char *name, umode_t mode,
        struct proc_dir_entry *parent, const struct seq_operations *ops,
        unsigned int state_size, void *data)
{
    struct proc_dir_entry *p;

    // 针对/proc/net/tcp 创建一个名叫 "tcp"且初始化了的 proc_dir_entry
    p = proc_create_reg(name, mode, &parent, data);
    if (!p)
        return NULL;
    pde_force_lookup(p);
    p->proc_ops = &proc_net_seq_ops;
    p->seq_ops = ops;
    p->state_size = state_size;
    return proc_register(parent, p);
}

// 初始化proc文件的读写操作api
static const struct proc_ops proc_net_seq_ops = {
    .proc_open  = seq_open_net,
    .proc_read  = seq_read,
    .proc_write = proc_simple_write,
    .proc_lseek = seq_lseek,
    .proc_release   = seq_release_net,
};
```

* 2、proc文件读写过程简要说明

上述初始化时，proc文件的`open/read/write`等接口，都注册为了序列文件相关的接口`seq_xxx`

跟踪`seq_read`，里面涉及序列文件的操作流程

可以看到里面流程很复杂，一个vfs层面的`read`操作，就涉及到序列文件的`show`、`next`、`stop`、`start`，包含了上面`tcp4_seq_ops`中的所有操作。

```cpp
// linux-5.10.10/fs/seq_file.c
ssize_t seq_read(struct file *file, char __user *buf, size_t size, loff_t *ppos)
{
    struct iovec iov = { .iov_base = buf, .iov_len = size};
    struct kiocb kiocb;
    struct iov_iter iter;
    ssize_t ret;

    init_sync_kiocb(&kiocb, file);
    iov_iter_init(&iter, READ, &iov, 1, size);

    kiocb.ki_pos = *ppos;
    ret = seq_read_iter(&kiocb, &iter);
    *ppos = kiocb.ki_pos;
    return ret;
}

// 序列操作
ssize_t seq_read_iter(struct kiocb *iocb, struct iov_iter *iter)
{
    struct seq_file *m = iocb->ki_filp->private_data;
    ...
    /* grab buffer if we didn't have one */
    if (!m->buf) {
        m->buf = seq_buf_alloc(m->size = PAGE_SIZE);
        if (!m->buf)
            goto Enomem;
    }
    ...
    // get a non-empty record in the buffer
    p = m->op->start(m, &m->index);
    while (1) {
        err = PTR_ERR(p);
        if (!p || IS_ERR(p))	// EOF or an error
            break;
        err = m->op->show(m, p);
        if (err < 0)		// hard error
            break;
        if (unlikely(err))	// ->show() says "skip it"
            m->count = 0;
        if (unlikely(!m->count)) { // empty record
            p = m->op->next(m, p, &m->index);
            continue;
        }
        if (!seq_has_overflowed(m)) // got it
            goto Fill;
        // need a bigger buffer
        m->op->stop(m, p);
        ...
        p = m->op->start(m, &m->index);
    }
    // EOF or an error
    m->op->stop(m, p);
    m->count = 0;
    goto Done;
Fill:
    while (1) {
        p = m->op->next(m, p, &m->index);
        ...
        err = m->op->show(m, p);
        ...
    }
    m->op->stop(m, p);
    ...
Done:
    ...
    return copied;
Enomem:
    err = -ENOMEM;
    goto Done;
}
```

* 3、文件的更新时机：`tcp4_seq_show`

即上面注册的`.show       = tcp4_seq_show`

```cpp
// linux-5.10.10\net\ipv4\tcp_ipv4.c
static int tcp4_seq_show(struct seq_file *seq, void *v)
{
    struct tcp_iter_state *st;
    struct sock *sk = v;

    seq_setwidth(seq, TMPSZ - 1);
    if (v == SEQ_START_TOKEN) {
        seq_puts(seq, "  sl  local_address rem_address   st tx_queue "
               "rx_queue tr tm->when retrnsmt   uid  timeout "
               "inode");
        goto out;
    }
    st = seq->private;

    if (sk->sk_state == TCP_TIME_WAIT)
        get_timewait4_sock(v, seq, st->num);
    else if (sk->sk_state == TCP_NEW_SYN_RECV)
        get_openreq4(v, seq, st->num);
    else
        get_tcp4_sock(v, seq, st->num);
out:
    seq_pad(seq, '\n');
    return 0;
}
```

```cpp
// linux-5.10.10/net/ipv4/tcp_ipv4.c
static void get_tcp4_sock(struct sock *sk, struct seq_file *f, int i)
{
    ...
    state = inet_sk_state_load(sk);
    if (state == TCP_LISTEN)
        // 监听状态的socket，获取全连接队列当前长度(等待accept处理)
        rx_queue = READ_ONCE(sk->sk_ack_backlog);
    else
        /* Because we don't lock the socket,
         * we might find a transient negative value.
         */
        // 非监听状态的socket，
        rx_queue = max_t(int, READ_ONCE(tp->rcv_nxt) -
                      READ_ONCE(tp->copied_seq), 0);

    // /proc/net/tcp文件中，tx_queue:rx_queue
    seq_printf(f, "%4d: %08X:%04X %08X:%04X %02X %08X:%08X %02X:%08lX "
            "%08X %5u %8d %lu %d %pK %lu %lu %u %u %d",
        i, src, srcp, dest, destp, state,
        READ_ONCE(tp->write_seq) - tp->snd_una,  // 此处对应tx_queue，Send-Q，已发送未收到确认(和ss非监听端口一样)
        rx_queue,   // 此处对应rx_queue，netstat结果中的Recv-Q，监听端口：全连接队列长度；非监听端口：已接收未被读取字节数
        timer_active,
        ...);
}
```

由上面代码可知，/proc/net/tcp文件中的tx_queue:rx_queue有如下关系：

1. `tx_queue`，对应`netstat`结果中的`Send-Q`，已发送未收到确认(和`ss`非监听端口一样)
2. `rx_queue`，对应`netstat`结果中的`Recv-Q`，监听端口：全连接队列长度；非监听端口：已接收未被读取字节数

## 4. 小结

1. `netstat`通过读取`/proc/net/tcp`文件进行结果展示
2. `netstat`结果中
    * `Send-Q`表示已发送未收到确认的字节数 (无论连接是哪种socket状态)
    * `Recv-Q`，对于监听端口，表示全连接队列长度；对于非监听端口，表示已接收未被读取字节数

## 5. 更新

`netstat -s`中，对于监听状态的socket，`Send-Q`里并未和`ss`一样展示**全连接队列的最大长度**，**这是内核的一个bug**。

已经提交了 [patch](https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/commit/?id=e7073830cc8b52ef3df7dd150e4dac7706e0e104)。

信息来自：[知识星球-程序员踩坑案例分享](https://wx.zsxq.com/dweb2/index/group/15552551584552)，推荐一下星主的干货博客：[plantegg](https://plantegg.github.io/)

## 6. 参考

1、[linux /proc/net/tcp 文件分析](https://blog.csdn.net/whatday/article/details/100693051)

2、netstat源码
