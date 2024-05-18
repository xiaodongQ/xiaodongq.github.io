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

最近碰到一个项目上大模型服务端程序处理请求时没有响应的问题，协助尝试定位(其他项目组，友情支撑)。初步抓包和`ss`/`netstat`定位是服务端一直没对三次握手的第一个SYN做响应，也能观察到listen队列溢出了。在另一个环境中进行复现，发现出问题的子进程连接一直处于`CLOSE_WAIT`且不响应其他请求，没有`CLOSE_WAIT`的子进程还能处理请求，pstack/strace/ltrace一通下来只跟踪到基本都在等条件变量，也没有死锁之类的。

服务端基于python框架，通过多进程进行监听处理。平时都写C++，涉及到python的只是一些胶水脚本，学艺不精所以暂时阻塞在怀疑业务逻辑导致python网络框架卡死。

另一个背景是知识星球里正好有个案例，涉及定位过程中一些知识点和工具，一些概念发现自己还是掌握得不够清晰和深入。

趁此机会，重新全面梳理一下网络相关流程，加之近期也折腾过了一些工具（systemtap/ebpf/packagedrill/scapy），进行一些实验。

本篇先说明TCP三次握手相关过程。

## 2. 前置说明

主要基于这篇文章："[从一次线上问题说起，详解 TCP 半连接队列、全连接队列](https://mp.weixin.qq.com/s/YpSlU1yaowTs-pF6R43hMw?poc_token=HKCgSGaji2dgAtvVc7gzTQykh3Aw6neDWcojHyB8)"，进行学习和扩展。

环境：起两个阿里云抢占式实例，CentOS7.7系统

基于5.10内核代码跟踪流程（虽然上面实例是3.10.0-1062.18.1.el7.x86_64）

## 3. 三次握手总体流程

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

## 4. 简单监测实验

1、起一个简单http服务，`python -m SimpleHTTPServer`(python2，python3上用`python -m http.server`)，默认8000端口

2、观察`netstat`和`ss`展示的各列信息

`netstat -ltnp`：

```sh
[root@iZ2zeariq0ckiibhsrqjp5Z ~]# netstat -ltnp
Active Internet connections (only servers)
Proto Recv-Q Send-Q Local Address           Foreign Address         State       PID/Program name    
tcp        0      0 0.0.0.0:22              0.0.0.0:*               LISTEN      1156/sshd           
tcp        0      0 0.0.0.0:8000            0.0.0.0:*               LISTEN      12364/python 
```

`ss -ltnp`：

```sh
[root@iZ2zeariq0ckiibhsrqjp5Z ~]# ss -ltnp
State      Recv-Q Send-Q        Local Address:Port      Peer Address:Port              
LISTEN     0      128           *:22                    *:*                   users:(("sshd",pid=1156,fd=3))
LISTEN     0      5             *:8000                  *:*                   users:(("python",pid=12364,fd=3))
```

`netstat`和`ss`里展示的`Recv-Q`和`Send-Q`含义是不一样的，可以看到上述两者的值不同。

1、在`netstat`中

`Recv-Q`表示收到的数据已经在本地接收缓冲，但是还有多少没有被进程取走（即还没有被应用程序读取）。如果接收队列Recv-Q一直处于阻塞状态，可能是遭受了拒绝服务（denial-of-service）攻击。

`Send-Q`表示对方没有收到的数据或者说没有Ack的，还是本地缓冲区。如果发送队列Send-Q不能很快的清零，可能是有应用向外发送数据包过快，或者是对方接收数据包不够快。

2、在`ss`中
    对于 LISTEN 状态的 socket  
        Recv-Q：当前全连接队列的大小，即已完成三次握手等待应用程序 accept() 的 TCP 链接  
        Send-Q：全连接队列的最大长度，即全连接队列的大小  
    对于非 LISTEN 状态的 socket  
        Recv-Q：已收到但未被应用程序读取的字节数，表示在接收缓冲区中等待处理的数据量。  
        Send-Q：已发送但未收到确认的字节数  

<!-- `netstat -s | grep "SYNs to LISTEN"` 给出的是队列溢出导致 SYN 被丢弃的个数

```sh
[root@rabbitmq1 ~]# netstat -s | grep -i "listen"
    4794 times the listen queue of a socket overflowed
    4794 SYNs to LISTEN sockets dropped
```


代码位置：`tcp_diag_get_info`(linux-3.10.62\net\ipv4\tcp_diag.c) -->


## 5. 源码各阶段流程

### 5.1. listen流程

结合内核源码跟踪流程，具体见：[笔记记录](https://github.com/xiaodongQ/devNoteBackup/blob/master/%E5%90%84%E5%88%86%E7%B1%BB%E8%AE%B0%E5%BD%95/Linux%E5%86%85%E6%A0%B8%E5%AD%A6%E4%B9%A0%E7%AC%94%E8%AE%B0.md)

代码位置：`__sys_listen`，\linux-5.10.176\net\socket.c
（Linux的系统调用在内核中的入口函数都是 `sys_xxx` ，但是如果我们拿着内核源码去搜索的话，就会发现根本找不到 `sys_xxx` 的函数定义，这是因为Linux的系统调用对应的函数全部都是由 `SYSCALL_DEFINE` 相关的宏来定义的。）

## 6. 参考

1、[从一次线上问题说起，详解 TCP 半连接队列、全连接队列](https://mp.weixin.qq.com/s/YpSlU1yaowTs-pF6R43hMw?poc_token=HKCgSGaji2dgAtvVc7gzTQykh3Aw6neDWcojHyB8)

2、[图解Linux网络包接收过程](https://mp.weixin.qq.com/s?__biz=MjM5Njg5NDgwNA==&mid=2247484058&idx=1&sn=a2621bc27c74b313528eefbc81ee8c0f&chksm=a6e303a191948ab7d06e574661a905ddb1fae4a5d9eb1d2be9f1c44491c19a82d95957a0ffb6&scene=178&cur_album_id=1532487451997454337#rd)

3、[极客时间：TCP连接的建立和断开受哪些系统配置影响？](https://time.geekbang.org/column/article/284912)

4、[极客时间：如何提升TCP三次握手的性能？](https://time.geekbang.org/column/article/237612)