---
layout: post
title: Redis学习实践（三） -- 主从复制和集群
categories: Redis
tags: Redis 存储
---

* content
{:toc}

本篇梳理Redis支持的关键特性和机制：主从复制 和 集群。



## 1. 背景

继续梳理Redis支持的关键特性和相关机制，主从复制、哨兵集群、切片集群。

Redis的知识点提纲：

![redis-knowledge-overview](/images/redis-knowledge-overview.jpg)  
[出处](https://time.geekbang.org/column/intro/100056701)

*说明：本博客作为个人学习实践笔记，可供参考但非系统教程，可能存在错误或遗漏，欢迎指正。若需系统学习，建议参考原链接。*

## 2. 主从复制

Redis利用`RDB`和`AOF`能够提升单机系统上历史数据的可靠性，但单机异常时，新数据就无法写入了，也无法对外提供服务。该场景下，**主从集群**能够提升的服务可用性。

* 主从集群通过增加`副本冗余`、使用**主从库模式**并进行`读写分离`：只有主节点（或者称主库）负责**写**操作，主节点和从节点（或者称从库）均可进行**读**操作；
* 主节点和从节点间通过**主从复制**进行集群数据的同步，主机异常时其中一个从节点能成为新的主节点并提供读写服务；
* `主-从-从`模式：从节点也可以有自己的从节点并建立主从**级联关系**，由该节点而不是主节点负责其从节点的写操作同步，来分担主节点上的全量复制压力
    * 主节点`fork`子进程进行`bgsave`的RDB文件异步处理，但是数据量多的话`fork`操作会阻塞主线程
    * 全量复制RDB文件，也会给主节点造成网络压力

示意图如下：

![redis-master-slave](/images/2025-03-30-redis-master-slave.png)

### 2.1. 主从复制流程说明

Redis的主从复制主要包括了：`全量复制`、`增量复制`和`长连接同步`三种情况。

* 全量复制传输 RDB 文件
* 增量复制传输主从断连期间的命令
* 长连接同步则是把主节点正常收到的请求传输给从节点。

Redis基于`状态机`实现主从复制，包含**四大阶段**：

* 1、初始化阶段
    * 当Redis实例 A 设置为另一个实例 B 的从库时，实例 A 会完成初始化操作，主要是获得了主库的 IP 和端口号
    * 该阶段有3种方式设置：
        * 1）在从节点上（此处即A）执行 `replicaof 主库ip 主库port` 的主从复制命令
        * 2）在从节点的redis.conf配置文件中设置 `replicaof 主库ip 主库port`
        * 3）从节点启动时，设置启动参数：`--replicaof [主库ip] [主库port]`
* 2、建立连接阶段
    * 一旦从库 获得了主库 IP 和端口号，该实例就会尝试和主库建立 TCP 网络连接，并且会在建立好的网络连接上，监听是否有主库发送的命令
* 3、主从握手阶段
    * 当从库（此处的实例A） 和主库建立好连接之后，从库就开始和主库进行握手
    * 握手过程就是主从库间相互发送 `PING-PONG` 消息，同时从库根据配置信息向主库进行验证
    * 最后，从库把自己的 IP、端口号，以及对`无盘复制`和 `PSYNC 2` 协议的支持情况发给主库
* 4、复制类型判断与执行阶段
    * 等到主从库之间的握手完成后，从库就会给主库发送 `PSYNC` 命令，有2个参数：`主库id（runID）` 和 `复制进度（offset）`
        * 发送的命令是：`psync ? -1`，第一次不知道主库id，设置为`?`，`-1`则表示第一次复制（逻辑在`slaveTryPartialResynchronization`中）
    * 紧接着，主库会根据从库发送的命令参数作出相应的三种回复，分别是`执行全量复制`、`执行增量复制`、`发生错误`
        * 主库收到 `psync` 命令后，会用 `FULLRESYNC` 响应命令带上两个参数：主库runID 和主库目前的复制进度 offset，返回给从库
            * `FULLRESYNC`响应表示第一次复制采用的全量复制
    * 从库在收到上述回复后，就会根据回复的复制类型，开始执行具体的复制操作
        * 从库收到响应后，会记录下主库runID和offset
        * 主库将所有数据同步给从库：主库执行`bgsave`命令，生成**RDB文件**，接着将文件发给从库。从库接收到RDB文件后，会先清空当前数据库，然后加载RDB文件。
    * 最后，主库会把主从同步执行过程中新收到的写命令，再发送给从库
        * 对于主从同步过程中的实时请求数据，为了保证主从库的数据一致性，主库会在内存中用专门的`replication buffer`，记录RDB文件生成后收到的所有写操作
        * 具体操作：当主库完成RDB文件发送后，就会把此时 `replication buffer` 中的修改操作发给从库，从库再重新执行这些操作

上述流程示意图：

![redis-slave-copy](/images/redis-slave-copy.jpg)  
[出处](https://time.geekbang.org/column/intro/100056701)

### 2.2. 主从复制实现

上述 主从复制状态机 对应`redisServer`实例中的 `repl_state` 变量。

```c
// redis/src/server.h
struct redisServer {
    /* Replication (slave) */
    ...
    // 主库主机名
    char *masterhost;               /* Hostname of master */
    // 主库端口号
    int masterport;                 /* Port of master */
    // 超时时间
    int repl_timeout;               /* Timeout after N seconds of master idle */
    // 从库上用来和主库连接的客户端
    client *master;     /* Client that is master for this slave */
    // 从库上缓存的主库信息
    client *cached_master; /* Cached master to be reused for PSYNC. */
    ...
    // 从库的复制状态机
    int repl_state;          /* Replication status if the instance is a slave */
    ...
};
```

**从库**状态机变化，对照上述4个阶段：

* 1、初始化阶段
    * 1）`initServerConfig`中，初始化为 **REPL_STATE_NONE**状态：`server.repl_state = REPL_STATE_NONE;`
    * 2）从库执行`replicaof ip port`命令后，执行`replicaofCommand`处理函数 -> `replicationSetMaster`，其中设置为 **REPL_STATE_CONNECT**状态
* 2、建立连接阶段
    * 建立连接是在 周期性任务`serverCron` 中进行的， -> `run_with_period(1000) replicationCron();`，1s执行一次，用于重连主库
    * 上面从库初始化后状态机已经是`REPL_STATE_CONNECT`状态了，还未连接，在`replicationCron()`中会进入`connectWithMaster`对应语句块，进行主库连接，连接成功后设置状态机为 **REPL_STATE_CONNECTING**状态，建立连接的阶段就完成了
        * `connectWithMaster`函数会设置连接成功后的回调函数：`syncWithMaster`
* 3、主从握手阶段
    * 连接成功时`syncWithMaster`回调函数被调用，其中判断状态机为`REPL_STATE_CONNECTING`的话，会设置状态为 **REPL_STATE_RECEIVE_PONG**，并通过`sendSynchronousCommand`函数发送`PING`消息
    * 后面的状态机流转处理，也都在`syncWithMaster`函数中，依次会经过 **REPL_STATE_SEND_AUTH** -> **REPL_STATE_SEND_PORT** -> **REPL_STATE_RECEIVE_PORT** -> **REPL_STATE_SEND_IP** -> **REPL_STATE_SEND_CAPA** -> **REPL_STATE_RECEIVE_CAPA**
* 4、复制类型判断与执行阶段
    * 从库和主库完成握手后，从库会读取主库返回的 CAPA 消息响应，状态机为：`REPL_STATE_RECEIVE_CAPA`
    * 紧接着，从库的状态变为 **REPL_STATE_SEND_PSYNC**，表明要开始向主库发送 `PSYNC` 命令，开始实际的数据同步了。此处的处理还是在`syncWithMaster`函数中。
        * 接着通过`slaveTryPartialResynchronization`函数向主库发送`psync`，并将状态机设置为：**REPL_STATE_RECEIVE_PSYNC**
        * 接下来还是一个`slaveTryPartialResynchronization`处理，里面逻辑也很长，负责根据主库的回复消息分别处理（里面也会接收应答），分别对应了全量复制、增量复制，或是不支持 `PSYNC`
    * 最后是将状态机设置为：**REPL_STATE_TRANSFER**

大概跟了下代码，流程还是挺长的，上述状态机变化示意图如下：

![sync-state-machine](/images/redis-slave-sync-state-machine.jpg)  
[出处](https://time.geekbang.org/column/intro/100084301)

上述 `psync`和`replicaof`命令：

```c
// redis/src/server.c
struct redisCommand redisCommandTable[] = {
    ...
    {"psync",syncCommand,3,
     "admin no-script",
     0,NULL,0,0,0,0,0,0},
    ...
    {"replicaof",replicaofCommand,3,
     "admin no-script ok-stale",
     0,NULL,0,0,0,0,0,0},
    ...
};
```

看下`syncCommand`的调用栈，最后调用到`startBgsaveForReplication`进行`bgsave`操作：

![redis-replicaof-call-tree](/images/2025-03-30-redis-replicaof.png)

也可看到其他调用到`startBgsaveForReplication`的场景，比如`serverCron`定期处理中就会进行bgsave的判断操作。

这里推荐下 [calltree.pl](https://zhuanlan.zhihu.com/p/339910341) 工具，作者在该文章中做了介绍。

试了下很好用，有点像用户态的`bpftrace`+`funcgraph`，可以通过mode：0还是1控制查看的调用栈方向。自己也归档了一下并贴了使用结果：[cpp-calltree](https://github.com/xiaodongQ/prog-playground/tree/main/tools/cpp-calltree)。

上述`slaveTryPartialResynchronization`函数中，从库发送`psync`命令并根据应答

```c
// redis/src/replication.c
int slaveTryPartialResynchronization(connection *conn, int read_reply) {
    ...
    // 写部分
    if (!read_reply) {
        server.master_initial_offset = -1;
        if (server.cached_master) {
            psync_replid = server.cached_master->replid;
            snprintf(psync_offset,sizeof(psync_offset),"%lld", server.cached_master->reploff+1);
            serverLog(LL_NOTICE,"Trying a partial resynchronization (request %s:%s).", psync_replid, psync_offset);
        } else {
            serverLog(LL_NOTICE,"Partial resynchronization not possible (no cached master)");
            // 第一次发送psync，命令为：`psync ? -1`
            psync_replid = "?";
            memcpy(psync_offset,"-1",3);
        }
        reply = sendSynchronousCommand(SYNC_CMD_WRITE,conn,"PSYNC",psync_replid,psync_offset,NULL);
        ...
        return PSYNC_WAIT_REPLY;
    }
    // 读部分
    // 接收应答
    reply = sendSynchronousCommand(SYNC_CMD_READ,conn,NULL);
    ...
    // 对应答进行判断处理
    // FULLRESYNC 表示主库响应类型为 全量复制
    if (!strncmp(reply,"+FULLRESYNC",11)) {
        ...
    }
    if (!strncmp(reply,"+CONTINUE",9)) {
        ...
    }
    ...
}
```

### 主库应答处理

来看下主库（主节点）应答`FULLRESYNC`（告知从库类型为全量复制）的处理逻辑，可以搜索看到处理函数为`replicationSetupSlaveForFullResync`

```c
// redis/src/replication.c
int replicationSetupSlaveForFullResync(client *slave, long long offset) {
    char buf[128];
    int buflen;

    slave->psync_initial_offset = offset;
    slave->replstate = SLAVE_STATE_WAIT_BGSAVE_END;
    server.slaveseldb = -1;
    if (!(slave->flags & CLIENT_PRE_PSYNC)) {
        buflen = snprintf(buf,sizeof(buf),"+FULLRESYNC %s %lld\r\n",
                          server.replid,offset);
        if (connWrite(slave->conn,buf,buflen) != buflen) {
            freeClientAsync(slave);
            return C_ERR;
        }
    }
    return C_OK;
}
```

调用链，展开看一下比较直观，后续再跟踪流程：

![reply-FULLRESYNC](/images/2025-03-30-reply-FULLRESYNC.png)

文本也贴一下，便于检索：

```sh
[CentOS-root@xdlinux ➜ redis git:(6.0) ✗ ]$ calltree.pl 'replicationSetupSlaveForFullResync' '' 1 1 10
  
  replicationSetupSlaveForFullResync
  ├── rdbSaveToSlavesSockets	[vim src/rdb.c +2540]
  │   └── startBgsaveForReplication	[vim src/replication.c +638]
  │       ├── syncCommand	[vim src/replication.c +711]
  │       ├── updateSlavesWaitingBgsave	[vim src/replication.c +1221]
  │       │   └── backgroundSaveDoneHandler	[vim src/rdb.c +2505]
  │       │       └── checkChildrenDone	[vim src/server.c +1781]
  │       │           ├── replconfCommand	[vim src/replication.c +863]
  │       │           └── serverCron	[vim src/server.c +1848]
  │       └── replicationCron	[vim src/replication.c +3109]
  │           └── serverCron	[vim src/server.c +1848]
  ├── startBgsaveForReplication	[vim src/replication.c +638]
  │   ├── syncCommand	[vim src/replication.c +711]
  │   ├── updateSlavesWaitingBgsave	[vim src/replication.c +1221]
  │   │   └── backgroundSaveDoneHandler	[vim src/rdb.c +2505]
  │   │       └── checkChildrenDone	[vim src/server.c +1781]
  │   │           ├── replconfCommand	[vim src/replication.c +863]
  │   │           └── serverCron	[vim src/server.c +1848]
  │   └── replicationCron	[vim src/replication.c +3109]
  │       └── serverCron	[vim src/server.c +1848]
  └── syncCommand	[vim src/replication.c +711]
```

## 3. 哨兵机制和Raft选举

## 4. 切片集群

## 5. 小结


## 6. 参考

* [Redis 核心技术与实战](https://time.geekbang.org/column/intro/100056701)
* [Redis 源码剖析与实战](https://time.geekbang.org/column/intro/100084301)
* [图解Redis](https://www.xiaolincoding.com/redis/)
* [Redis系列文章](https://mp.weixin.qq.com/mp/appmsgalbum?action=getalbum&__biz=MzIyOTYxNDI5OA==&scene=1&album_id=1699766580538032128&count=3&uin=&key=&devicetype=iMac+MacBookPro12%2C1+OSX+OSX+12.6.4+build(21G526)&version=13080911&lang=zh_CN&nettype=WIFI&ascene=0&fontScale=100)
