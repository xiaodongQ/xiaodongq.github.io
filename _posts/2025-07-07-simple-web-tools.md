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

生成项目，业务场景描述：
* MySQL表信息
  * 表A为`buckets`桶，包含如下信息：`bid`、`bname`、`user`、`partition`，其中`partition`范围`00~FF`
  * 子表`bucket_files_00~bucket_files_FF`，根据`partition`对应分区，表示某bucket下的所有file信息都在该子表中，每个子表中的详情包含：`fid`、`fname`、`bid`和A中相同、`fsize`文件大小
  * 此外有个单独的用户表`user`，包含`id`、`name`、用户属性
* 上述表中，A和用户表可自定义修改表名，相关id字段均为`uint64`

需求：
* 基于`Go` + `html/template`实现，选择合适的Go Web框架，页面展示得美观一些。尽量简洁，服务部署时只要一个bin，去除glibc依赖
* 先以用户维度展示
  * 统计每个用户的文件总数和大小，并展示有哪些分区写了数据，对应分区下文件数和大小
  * 分区下的文件数据，我可以点击进去查看具体列表，默认limit 10展示，可输入bid来精确匹配，也可输入fname来like前后模糊匹配
* 支持页面上设置最多3套数据库参数，并可选择连接哪套数据库
  * 每对参数包含：服务端ip、端口、数据库用户、密码、数据库名（默认test）
  * 配置页面默认收起，点击后展开。可点击测试连接是否正常
  * 配置保存在配置文件里，不存在配置文件时，默认生成，页面配置和展示时跟后台配置是一致的

## 3. 代码走读

生成的项目代码在：[simple_web_tool](https://github.com/xiaodongQ/simple_web_tool)。

基于：gin + gorm + html/template，配置文件使用yaml格式。

### 3.1. 代码结构

代码结构如下：

```sh
[MacOS-xd@qxd ➜ simple_web_tool git:(main) ✗ ]$ tree 
.
├── build.sh
├── config
│   ├── database.go
│   └── database.yaml
├── controllers
│   └── database.go
├── go.mod
├── go.sum
├── init_db.sql
├── main.go
├── models
│   └── models.go
├── services
│   └── database.go
├── static
│   ├── css
│   │   └── bootstrap.min.css
│   └── js
│       └── main.js
└── templates
    └── index.html
```

其中：
* 入口：`main.go`
* html和css样式、js控制，在templates和static目录
    * 部署时，需要拷贝这两个相对目录
* models、controllers目录，MVC架构的数据和控制逻辑
* config，配置文件相关加载逻辑
* 测试数据库表和数据初始化：`init_db.sql`

`build.sh`里的编译命令：`CGO_ENABLED=0 go build -ldflags="-s -w" -o simple_web_tool`，其中`CGO_ENABLED=0`可以去掉glibc的动态库依赖（不使用CGO），更便于分发。

### 3.2. 入口函数

```go
package main

import (
	"log"
	"simple_web_tool/controllers"
	"simple_web_tool/services"

	"github.com/gin-gonic/gin"
)

func main() {
	// 初始化数据库连接
	if err := services.InitDatabase(); err != nil {
		log.Fatalf("数据库初始化失败: %v", err)
	}

	r := gin.Default()
	r.Static("/static", "./static")
	r.LoadHTMLGlob("templates/*")

	r.GET("/", controllers.IndexHandler)
	r.GET("/api/users", controllers.GetUserStats)
	r.GET("/api/partitions", controllers.GetPartitionDetails)
	r.GET("/api/configs", controllers.ListDBConfigs)
	r.POST("/api/configure-db", controllers.ConfigureDB)
	r.POST("/api/update-config", controllers.UpdateDBConfig)

	r.Run(":8080")
}
```

## 4. 测试环境部署

### 4.1. MySQL容器环境

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

### 4.2. 测试表和测试数据初始化

初始脚本：`init_db.sql`，在宿主机上执行：`mysql -h 127.0.0.1 -utest -ptest testdb < init_db.sql`

## 5. 程序效果



## 6. 小结

利用AI生成了一个基本的工具项目，并在调试过程中动态调整，结对过程中边学边实践。
