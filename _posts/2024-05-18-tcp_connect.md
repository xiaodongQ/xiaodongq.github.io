---
layout: post
title: TCP三次握手相关过程
categories: 网络
tags: 网络
---

* content
{:toc}

梳理学习TCP三次握手相关过程，结合相关配置进行实验。



## 1. 背景

最近碰到一个项目上服务端程序处理请求时没有响应的问题，协助尝试定位。初步抓包和`ss`/`netstat`定位是服务端一直没对第一次SYN做响应，也能观察到listen队列溢出了。服务端基于python框架，通过多进程进行监听处理。

在另一个环境进行复现后，发现出问题的子进程有连接一直处于`CLOSE_WAIT`且不响应其他请求，没有出现`CLOSE_WAIT`的子进程还能处理请求，pstack/strace/ltrace一通下来只跟踪到基本都在等条件变量，也没有死锁之类的。

平时都写C++，涉及到python的只是一些胶水脚本，学艺不精所以暂时阻塞在怀疑业务逻辑导致python网络框架卡死。

另一个背景是知识星球里正好有个案例，涉及定位过程中一些知识点和工具，一些概念发现自己还是掌握得不够清晰和深入。

趁此机会，重新全面梳理一下网络相关流程，加之近期也折腾过了一些工具（systemtap/ebpf/packagedrill/scapy），进行一些实验。

本篇先说明TCP三次握手相关过程。

前置说明：

主要基于这篇文章："[从一次线上问题说起，详解 TCP 半连接队列、全连接队列](https://mp.weixin.qq.com/s/YpSlU1yaowTs-pF6R43hMw?poc_token=HKCgSGaji2dgAtvVc7gzTQykh3Aw6neDWcojHyB8)"，进行学习和扩展。

环境：起两个阿里云抢占式实例，CentOS7.7系统

基于5.10内核代码跟踪流程（虽然上面实例是3.10.0-1062.18.1.el7.x86_64）

## 2. 三次握手总体流程

![TCP三次握手及相关控制参数](/images/tcp-connect.png)  
基于[原图出处](https://mp.weixin.qq.com/s/YpSlU1yaowTs-pF6R43hMw?poc_token=HKCgSGaji2dgAtvVc7gzTQykh3Aw6neDWcojHyB8)加工

<!-- 
client                      server
发SYN
`SYN_SENT`              收到后状态：`SYN_RECV`
                   内核把连接存储到半连接队列(SYN Queue)
                     向client回复 SYN+ACK
收到后回复ACK
变成`ESTABLISHED`   收到ACK后，内核把连接从半连接队列取出，添加到全连接队列(Accept Queue)
                        变`ESTABLISHED`
                    `accept()`处理，将连接从全连接队列取出
 -->

## 3. netstat/ss监测实验

### 3.1. `Recv-Q`和`Send-Q`

1. 起一个简单http服务，`python -m SimpleHTTPServer`(python2，python3上用`python -m http.server`)，默认8000端口

2. 观察`netstat`和`ss`展示的各列信息

`netstat -ltnp`：

```sh
[root@iZ2ze76owg090hoj8a5bpqZ ~]# netstat -anpt
Active Internet connections (servers and established)
Proto Recv-Q Send-Q Local Address           Foreign Address         State       PID/Program name    
tcp        0      0 0.0.0.0:22              0.0.0.0:*               LISTEN      1154/sshd           
tcp        0      0 0.0.0.0:8000            0.0.0.0:*               LISTEN      1764/python         
tcp        0      0 172.23.133.137:22       100.104.192.180:54409   ESTABLISHED 1790/sshd: root@not 
tcp        0      0 172.23.133.137:35694    100.100.30.28:80        ESTABLISHED 1382/AliYunDun      
tcp        0     36 172.23.133.137:22       100.104.192.180:54413   ESTABLISHED 1810/sshd: root@pts 
tcp        0      0 172.23.133.137:22       100.104.192.136:48604   ESTABLISHED 1512/sshd: root@pts 
tcp        0      0 172.23.133.137:49200    100.100.18.120:443      TIME_WAIT   - 
```

`ss -ltnp`：

```sh
[root@iZ2ze76owg090hoj8a5bpqZ ~]# ss -atnp
State      Recv-Q Send-Q        Local Address:Port        Peer Address:Port              
LISTEN     0      128           *:22                      *:*                     users:(("sshd",pid=1154,fd=3))
LISTEN     0      5             *:8000                    *:*                     users:(("python",pid=1764,fd=3))
ESTAB      0      0             172.23.133.137:35694      100.100.30.28:80        users:(("AliYunDun",pid=1382,fd=12))
ESTAB      0      36            172.23.133.137:22         100.104.192.180:54413   users:(("sshd",pid=1810,fd=3))
ESTAB      0      0             172.23.133.137:22         100.104.192.136:48604   users:(("sshd",pid=1512,fd=3))
TIME-WAIT  0      0             172.23.133.137:49200      100.100.18.120:443 
```

`netstat`和`ss`里展示的`Recv-Q`和`Send-Q`含义是不一样的，可以看到上述两者的值不同。

1、 在`netstat`中

`Recv-Q`表示收到的数据已经在本地接收缓冲，但是还有多少没有被进程取走（即还没有被应用程序读取）。如果接收队列Recv-Q一直处于阻塞状态，可能是遭受了拒绝服务（denial-of-service）攻击。

`Send-Q`表示对方没有收到的数据或者说没有Ack的，还是本地缓冲区。如果发送队列Send-Q不能很快的清零，可能是有应用向外发送数据包过快，或者是对方接收数据包不够快。

疑问：针对监听和非监听端口，netstat中的`Recv-Q`和`Send-Q`的含义是否有区别？待定，后续分析netstat的源码(TODO)

2、在`ss`中

对于 LISTEN 状态的 socket：  
    `Recv-Q`：当前全连接队列的大小，即已完成三次握手等待应用程序 accept() 的 TCP 链接  
    `Send-Q`：全连接队列的最大长度，即全连接队列的大小  

对于非 LISTEN 状态的 socket：  
    `Recv-Q`：已收到但未被应用程序读取的字节数，表示在接收缓冲区中等待处理的数据量。  
    `Send-Q`：已发送但未收到确认的字节数  

上面SimpleHTTPServer服务的全连接队列最大长度只有5，可以查看其源码：/usr/lib64/python2.7/SimpleHTTPServer.py。一步步跟踪代码可以看到其默认队列长度就是`5`，如下：

```py
# /usr/lib64/python2.7/SocketServer.py
class TCPServer(BaseServer):
    ...
    request_queue_size = 5
    ...
    def __init__(self, server_address, RequestHandlerClass, bind_and_activate=True):
        """Constructor.  May be extended, do not override."""
        BaseServer.__init__(self, server_address, RequestHandlerClass)
        self.socket = socket.socket(self.address_family,
                                    self.socket_type)
        if bind_and_activate:
            self.server_bind()
            self.server_activate()
    ...
    def server_activate(self):
        # 此处listen指定的backlog全连接最大长度默认就是5
        self.socket.listen(self.request_queue_size)
    ...
```

### 3.2. listen队列溢出

另外：`netstat -s`里可以查看listen队列溢出的情况

1、安装`ab`压测工具：`yum install httpd-tools`

2、向上述http服务进行并发请求

`ab -n 1000 -c 10 http://172.23.133.137:8000/`  
    -n 1000 表示总共发送1000个请求。  
    -c 10 表示并发数为10，也就是同时尝试建立1000个连接

3、查看统计情况`netstat -s|grep -i listen`：

```sh
[root@iZ2ze76owg090hoj8a5bpqZ ~]# netstat -s|grep -i listen
    9 times the listen queue of a socket overflowed
    9 SYNs to LISTEN sockets dropped
```

`9 SYNs to LISTEN sockets dropped` 这是半连接队列溢出

`9 times the listen queue of a socket overflowed` 这是全连接队列溢出？

ECS上的对应参数：

```sh
[root@iZ2ze76owg090hoj8a5bpqZ ~]# sysctl -a|grep -E "syn_backlog|somaxconn|syn_retries|synack_retries|syncookies|abort_on_overflow"
net.core.somaxconn = 128
net.ipv4.tcp_abort_on_overflow = 0
net.ipv4.tcp_max_syn_backlog = 1024
net.ipv4.tcp_syn_retries = 6
net.ipv4.tcp_synack_retries = 2
net.ipv4.tcp_syncookies = 1
```

* 修改`sysctl -w net.core.somaxconn=4096`，重新起http服务，全连接队列长度还是5，执行ab后上述溢出变成18(即还是多了9个)
* 备份修改python中`SocketServer.py`里的默认为2048，可看到Send-Q变成了2048

```sh
[root@iZ2ze76owg090hoj8a5bpqZ ~]# ss -anlt
State      Recv-Q Send-Q         Local Address:Port        Peer Address:Port              
LISTEN     0      128            *:22                      *:*                  
LISTEN     0      2048           *:8000
```

而后继续进行一次ab测试，`ab -n 1000 -c 10 http://172.23.133.137:8000/`，查看统计信息后，这次没有再出现队列溢出的情况了。

```sh
[root@iZ2ze76owg090hoj8a5bpqZ ~]# netstat -s|grep -i listen
    18 times the listen queue of a socket overflowed
    18 SYNs to LISTEN sockets dropped
```

所以上述两个溢出打印，是由于服务端处理不过来导致全连接队列满，不去取出半连接队列进而导致半连接队列满？这个待定后续再深究(TODO)

### 3.3. ss中关于监听和非监听端口的区别说明

1、`ss`和`netstat`数据获取的方式不同，`ss`用的是`tcp_diag`模块通过网络获取，而`netstat`是直接解析`/proc/net/tcp`文件，`ltrace`可以大致看出其过程差别。

```sh
[root@iZ2ze76owg090hoj8a5bpqZ ~]# ltrace netstat -ntl
__libc_start_main(0x55bffcd51aa0, 2, 0x7ffed430ef98, 0x55bffcd64340 <unfinished ...>
...
__printf_chk(1, 0x55bffcd65480, 1, 1Active Internet connections (only servers)
)                                                                = 80
putchar(10, 0x7fc9aca9aa00, 80, 0Proto Recv-Q Send-Q Local Address           Foreign Address         State      
)                                                                   = 10
fopen("/proc/net/tcp", "r")                                                                          = 0x55bffe70b390
getpagesize()                                                                                        = 4096
malloc(4096)                                                                                         = 0x55bffe70b5d0
...
```

```sh
[root@iZ2ze76owg090hoj8a5bpqZ ~]# ltrace ss -ntl
__libc_start_main(0x4024d0, 2, 0x7fff6f428268, 0x412d40 <unfinished ...>
...
__printf_chk(1, 0x4138fe, 49, 0x4138f0State      Recv-Q Send-Q                                     Local Address:Port                                                    Peer Address:Port              
)                                                              = 138
fflush(0x7fcdb4e80400)                                                                               = 0
getenv("TCPDIAG_FILE")                                                                               = nil
getenv("PROC_NET_TCP")                                                                               = nil
getenv("PROC_ROOT")                                                                                  = nil
socket(16, 524291, 4)                                                                                = 3
setsockopt(3, 1, 7, 0x7fff6f427e20)                                                                  = 0
setsockopt(3, 1, 8, 0x61b37c)                                                                        = 0
setsockopt(3, 270, 11, 0x7fff6f427e24)                                                               = -1
bind(3, 0x7fff6f427ef4, 12, -384)                                                                    = 0
getsockname(3, 0x7fff6f427ef4, 0x7fff6f427e1c, -1)                                                   = 0
time(nil)                                                                                            = 1716102416
sendmsg(3, 0x7fff6f427f70, 0, 0)                                                                     = 72
recvmsg(3, 0x7fff6f427d80, 34, 0)                                                                    = 192
malloc(192)                                                                                          = 0x1329010
recvmsg(3, 0x7fff6f427d80, 0, 14)                                                                    = 192
memset(0x7fff6f427b40, '\0', 152)                                                                    = 0x7fff6f427b40
```

2、`ss`命令位于`iproute`这个库，若要具体分析过程需要找这个库的源码。

```sh
[root@iZ2ze76owg090hoj8a5bpqZ ~]# rpm -qf /usr/sbin/ss
iproute-4.11.0-25.el7_7.2.x86_64

# netstat位于net-tools中
[root@iZ2ze76owg090hoj8a5bpqZ ~]# rpm -qf /usr/bin/netstat 
net-tools-2.0-0.25.20131004git.el7.x86_64
```

3、tcp_diag中，获取信息的代码位置：`tcp_diag_get_info`(linux-5.10.10/net/ipv4/tcp_diag.c)

```c
// linux-5.10.10/net/ipv4/tcp_diag.c
static void tcp_diag_get_info(struct sock *sk, struct inet_diag_msg *r,
			      void *_info)
{
	struct tcp_info *info = _info;

	if (inet_sk_state_load(sk) == TCP_LISTEN) {
		// socket 状态是 LISTEN 时
		// 当前全连接队列个数 (RECV-Q会用这个)
		r->idiag_rqueue = READ_ONCE(sk->sk_ack_backlog);
		// 当前全连接队列最大个数 (SEND-Q会用这个)
		r->idiag_wqueue = READ_ONCE(sk->sk_max_ack_backlog);
	} else if (sk->sk_type == SOCK_STREAM) {
		// SOCK_STREAM(典型如TCP) socket 状态是其他状态时，
		const struct tcp_sock *tp = tcp_sk(sk);

		// 已收到但未被应用程序读取处理的字节数
		r->idiag_rqueue = max_t(int, READ_ONCE(tp->rcv_nxt) -
					     READ_ONCE(tp->copied_seq), 0);
		// 已发送但未收到确认的字节数
		r->idiag_wqueue = READ_ONCE(tp->write_seq) - tp->snd_una;
	}
	if (info)
		tcp_get_info(sk, info);
}
```

## 4. 源码各阶段流程

### 4.1. listen流程

结合内核源码跟踪流程，具体见：[笔记记录](https://github.com/xiaodongQ/devNoteBackup/blob/master/%E5%90%84%E5%88%86%E7%B1%BB%E8%AE%B0%E5%BD%95/Linux%E5%86%85%E6%A0%B8%E5%AD%A6%E4%B9%A0%E7%AC%94%E8%AE%B0.md)

代码位置：`__sys_listen`，\linux-5.10.176\net\socket.c
（Linux的系统调用在内核中的入口函数都是 `sys_xxx` ，但是如果我们拿着内核源码去搜索的话，就会发现根本找不到 `sys_xxx` 的函数定义，这是因为Linux的系统调用对应的函数全部都是由 `SYSCALL_DEFINE` 相关的宏来定义的。）

```c
// linux-5.10.10/net/socket.c(不同内核版本可能有部分差异，不影响流程)
int __sys_listen(int fd, int backlog)
{
    // socket 定义在 include\linux\net.h
	struct socket *sock;
	int err, fput_needed;
	int somaxconn;

    // 根据fd从fdtable里找到对应struct fd(file.h中定义)，并返回其中的socket相关数据成员(file结构的void* private_data成员)，此处即struct socket结构
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

		fput_light(sock->file, fput_needed);
	}
	return err;
}

// linux-5.10.10/net/ipv4/af_inet.c
int inet_listen(struct socket *sock, int backlog)
{
    
}
```

## 5. 参考

1、[从一次线上问题说起，详解 TCP 半连接队列、全连接队列](https://mp.weixin.qq.com/s/YpSlU1yaowTs-pF6R43hMw?poc_token=HKCgSGaji2dgAtvVc7gzTQykh3Aw6neDWcojHyB8)

2、[图解Linux网络包接收过程](https://mp.weixin.qq.com/s?__biz=MjM5Njg5NDgwNA==&mid=2247484058&idx=1&sn=a2621bc27c74b313528eefbc81ee8c0f&chksm=a6e303a191948ab7d06e574661a905ddb1fae4a5d9eb1d2be9f1c44491c19a82d95957a0ffb6&scene=178&cur_album_id=1532487451997454337#rd)

3、[极客时间：TCP连接的建立和断开受哪些系统配置影响？](https://time.geekbang.org/column/article/284912)

4、[极客时间：如何提升TCP三次握手的性能？](https://time.geekbang.org/column/article/237612)

5、[ss源代码调试&原理分析](https://blog.spoock.com/2019/07/06/ss-learn/)
