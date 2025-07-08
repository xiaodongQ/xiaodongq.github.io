---
title: 基于Go+Html模板写一个简易页面工具
description: 基于Go+Html模板写一个简易页面工具
categories: [编程语言, Go]
tags: [Go]
---


## 1. 背景

平时定位问题和查看测试环境数据时，经常连Shell终端（PS：终端工具也从XShell/SecureCRT切换到[WindTerm](https://github.com/kingToolbox/WindTerm)了），连接数据库后手敲SQL查询。数据库数据模型是：总表`A`中有一个分区字段，范围`00~FF`共256张子表，需要先到A表找到分区，而后到对应的`A_xx`子表里查看进一步的信息。

有几个痛点：
* 虽然连接数据库、联表等常用命令设置为了快捷按钮，但还是**需要多次点击**以及手动输入数据
* 子表比较多，业务少时很多子表是空的，数据分布不直观
* 多套环境时，需要Shell连接到不同终端，查找不同账号分别登录

基于上述情况，准备写个页面来提高效率，借助LLM快速撸一个能用的程序。简单调研了下：
* 1）基于前端框架（React/Vue），正好之前也准备补下前端技能栈，但有点慢，当前个人需求是短平快
* 2）基于纯静态页面，后端使用Go，程序自带运行时，禁用`CGO_ENABLED`还可以进一步去掉对`glibc`的依赖

基于近期比较热门的`Vibe Coding`（氛围编程），借助`Cursor`或类似平替`trae`、`Zed`直接可以先实现一版需求。此时基于`trae`。

## 2. 需求描述

业务场景描述：
* 表A中包含如下信息：`bid`、`bname`、`user`、`partition`，其中`partition`范围`00~FF`
* 子表`A_00~A_FF`，一个bid中对应固定分区，其数据都分区到对应子表中，其中的详情包含：`fid`、`fname`、`bid`和A中相同、`fsize`大小
* 此外有个单独的用户表，`user`、`name`、用户属性

需求：
* 基于`Go` + `html/template`实现，选型合适的Go框架，数据库连接池
* 展示总体统计和每个用户单独统计，每个用户有哪些分区有数据，各自包含多少记录和大小
* 支持页面设置多套数据库参数，并可选择连接哪个数据库，参数包含：服务端ip、端口、数据库用户、密码、数据库默认为test
* 支持输入`bid`或者`bname`，检索展示其下包含的总文件数、大小，以及`fid`、`fname`详情，并可进一步输入`fid`/`fname`过滤检索

## 3. 代码走读

生成的项目代码在：[simple_web_tool](https://github.com/xiaodongQ/simple_web_tool)。

基于：gin + gorm + html/template。



## 4. 测试环境搭建

本地是`Rocky Linux release 9.5 (Blue Onyx)`系统，容器基于`podman`。

1、`podman`更换国内源：修改`/etc/containers/registries.conf`，而后`systemctl restart podman`

```sh
#unqualified-search-registries = ["registry.access.redhat.com", "registry.redhat.io", "docker.io"]
unqualified-search-registries = ["docker.m.daocloud.io"]  
```

2、拉取MySQL镜像：`docker pull mysql:8.0`

3、运行

```sh
podman run -d \
  --name mysql-server \
  -e MYSQL_ROOT_PASSWORD=Demo_123! \
  -e MYSQL_DATABASE=testdb \
  -e MYSQL_USER=test \
  -e MYSQL_PASSWORD=test\
  -p 3306:3306 \
  -v mysql_data:/var/lib/mysql \
  docker.m.daocloud.io/library/mysql:8.0 \
  --character-set-server=utf8mb4 \
  --collation-server=utf8mb4_unicode_ci
```

进容器登录查看：

```sh
# 或 podman ps、podman logs mysql-server
[root@xdlinux ➜ ~ ]$ docker ps   
CONTAINER ID  IMAGE        COMMAND     CREATED       STATUS        PORTS              NAMES
bec5843eb92d  docker.m.daocloud.io/library/mysql:8.0  --character-set-s...  4 minutes ago  Up 4 minutes  0.0.0.0:3306->3306/tcp, 3306/tcp, 33060/tcp  mysql-server

[root@xdlinux ➜ ~ ]$ docker logs mysql-server
Emulate Docker CLI using podman. Create /etc/containers/nodocker to quiet msg.
2025-07-08 14:56:56+00:00 [Note] [Entrypoint]: Entrypoint script for MySQL Server 8.0.42-1.el9 started.
2025-07-08 14:56:56+00:00 [Note] [Entrypoint]: Switching to dedicated user 'mysql'
2025-07-08 14:56:56+00:00 [Note] [Entrypoint]: Entrypoint script for MySQL Server 8.0.42-1.el9 started.
'/var/lib/mysql/mysql.sock' -> '/var/run/mysqld/mysqld.sock'
...

# 进容器
[root@xdlinux ➜ volumes ]$ docker exec -it mysql-server bash
# root用户登录
bash-5.1# mysql -uroot -pDemo_123!
# test用户登录
bash-5.1# mysql -utest -ptest  
```

宿主机登录MySQL，需要调整下`-h`

```sh
[root@xdlinux ➜ ~ ]$ mysql -h 127.0.0.1 -uroot -pDemo_123!
mysql: [Warning] Using a password on the command line interface can be insecure.
...
Type 'help;' or '\h' for help. Type '\c' to clear the current input statement.

mysql> 
```
