---
layout: post
title: ioserver服务实验（一） -- 借助trae搭建项目
categories: C++
tags: AI C++
---

* content
{:toc}

借助 [trae](https://traeide.com/zh/) 快速搭建项目，实现C++读写服务demo，借此作为场景进行实验。



## 1. 背景

基于C++实现的读写服务demo，借此作为场景温习并深入学习io多路复用、性能调试、MySQL/Redis等开源组件。

本篇借助 [trae](https://traeide.com/zh/) 的`Builder`模式快速搭建项目。[cursor](https://www.cursor.com/cn) 之前只是简单试用了一下，没开Pro后面就一直没用起来，看看之后的体验效果对比再做选择。

trae当前默认使用模型：Claude-3.5-Sonnet

## 2. demo项目思路

demo实验准备涉及的一些技术点，思路：

1、阶段一：

* io复用select/poll/epoll
* 线程池、内存池、
* 缓存Redis、MySQL
* 性能定位和调试：火焰图、上下文切换、cpu亲和性设置、tcp参数调优
* 容器化，dockerfile
* 监测：Prometheus、Grafana，各项指标设计采集
    - 网络，带宽，tcp丢包、重传、rt等指标
    - 内存使用
    - 磁盘io使用率，带宽
    - 服务端的连接数
    * 考虑如何结合`ebpf`进行监测，如何设计指标，可以用USDT手动往程序里埋一些

2、阶段二：改造分布式服务

* 服务端的负载均衡，reuseport、api网关
* redis集群
* grpc框架
* 服务发现etcd/consoul
* 对称式架构，raft选举

3、阶段三：结合场景实践一些算法和机制方案等

* 一致性hash、分布式锁
* 布隆过滤器，过滤异常请求
* 备份、容灾

## 3. trae生成项目

一开始没有特别有条理的要求，只有大概的一些发散思路（上小节实际是项目生成后做了梳理），让AI去发挥吧。

### 3.1. 初次生成

选择`Builder`模式，如下思路：

```
生成c++项目，部署脚本可结合shell，要求如下
1、抽象io复用select/poll/epoll，分别验证读写并发性能
  1）接受到请求后写mysql，以及redis，写缓存再写mysql
  2）客户端测试，给出用例
  结合基准测试
  3）性能测试和优化
  火焰图、上下文切换
  cpu亲和性设置、tcp参数调优
  tcpdump抓包分析
  4）开发环境搭建，制作容器并容器化部署
  5）基于makefile管理

2、DFX需求：
1）可维护性：普罗监测程序服务端、系统资源使用；并支持报表统计
  网络，带宽，tcp丢包、重传、rt等指标
  内存使用
  磁盘io使用率，带宽
  服务端的连接数
2）如何结合ebpf进行监测，如何设计指标

3、分阶段需求：
  1、阶段一：单机服务，mysql和redis均是单机
  2、阶段二：分布式服务
    redis集群
    部署多个分布式服务，增加api网关，reuseport、nginx
    服务发现，etcd consoul
  3、对称式集群架构，raft选举
```

trae builder模式生成项目：

![trae builder模式生成项目](/images/2025-02-23-trae-gen-demo.png)

### 3.2. 过程调整

1、有些内容由于没有给出提示词做限定，比如都是终端打印、逻辑都在main里等，依次进行调整：

* 1）开发基本的工具类，用于日志记录，优化项目里的日志记录
    * 可使用开源的 spdlog header-only C++日志库
* 2）main函数优化一下，逻辑分离到单独线程，支持优雅退出
* 3）连接任务处理调整为线程池
* 4）服务端参数调整为json配置文件，并支持动态加载
* 5）段错误等原因导致core时，日志里记录退出堆栈
* 6）makefile里基于c+14编译
* 7）提供MySQL初始化脚本，init.sql

2、项目里用到的mysql和redis依赖，自动生成的无法使用。手动调整：

```
安装 yum install mysql-devel
下载hiredis（https://github.com/redis/hiredis），手动编译并安装make install
调整pkg-config对应路径，过程中梳理查看ldd脚本流程
```

3、编译问题，复制编译报错，让IDE（下面或称AI）自己去调整

自己在家用的是Mac，IDE/浏览器等都在这台，但Mac的环境开发包有点问题，是scp到一台Linux PC机进行编译的。要不然trae应该能自己进行编译过程和自行修改代码，不用这么拷来拷去了。

4、AI提供学习思路

项目里有mysql、redis，还要编译及运行server和client，环境做隔离，AI建议`Docker Compose`进行组织，之前没用过只是简单用docker，学习一下。

### 3.3. 项目代码及构建

项目代码在：[ioserver_demo](https://github.com/xiaodongQ/prog-playground/tree/main/ioserver_demo)

* 本地编译方式
    * 直接make，调整hiredis库的`.pc`配置路径后，make编译正常
* docker构建方式（TODO）
    - 到docker目录，开始构建 `docker compose up --build`。
    - 问题记录：
        - CentOS已停止维护，yum源部分项失败。跟AI来回捣腾几次，调整为本地下载yum源配置文件，dockerfile里集成，还是失败了
        - 按意见在docker-compose.yml里新增dns、在dockerfile里修改resolv.conf但是只读，均失败，先基于宿主机调试了

### 3.4. 运行

准备：安装redis并启动、初始化MySQL数据：`mysql -uroot -ptest < docker/init.sql`

1、基本运行

![run demo](/images/2025-02-25-run-demo.png)

2、进一步优化和问题修改：调整新增日志、空数据处理、主键冲突调整

结果：

![run demo2](/images/2025-02-25-ioserver-result.png)

3、发送信号动态调整日志等级为info，`kill -HUP 97807`

[CentOS-root@xdlinux ➜ bin git:(main) ✗ ]$ cat ../config/server_config.json

```json
{
    "server": {
        "port": 8080,
        "num_threads": 4
    },
    "database": {
        "mysql": {
            "host": "localhost",
            "user": "root",
            "password": "test",
            "database": "ioserver"
        },
        "redis": {
            "host": "localhost",
            "port": 6379
        }
    },
    "logging": {
        "log_file": "server.log",
        "log_level": "info",
        "console_output": true
    }
}
```

4、客户端上并发就容易出问题，不过简单流程是跑起来了

## 4. 小结

基于AI工具生成项目框架和逻辑，从其中实现可以学习不少东西。**先理解整体代码逻辑后**，再结合手动调整和指示AI优化，效率提升明显。

## 5. 参考

* [AI Agents Course](https://huggingface.co/learn/agents-course/unit0/introduction)

* GPT
