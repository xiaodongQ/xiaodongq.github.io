---
title: 用AI基于Go+Html模板写一个文件统计工具
description: 用AI基于Go+Html模板写一个文件统计工具
categories: [编程语言, Go]
tags: [Go, AI]
---


## 1. 背景

平时定位问题和查看测试环境数据时，经常要连Shell终端（XShell、SecureCRT、[WindTerm](https://github.com/kingToolbox/WindTerm)），连接数据库后再手敲SQL查询。简化后的数据库模型：总表`A`中有一个分区字段，范围`00~FF`共256张子表，需要先到A表找到分区，而后到对应的`A_xx`子表里查看进一步的信息。

有几个痛点：
* 虽然连接数据库、联表等常用命令设置为了快捷按钮，但还是**需要多次点击**以及手动输入数据
* 子表比较多，业务少时很多子表是空的，数据分布不直观
* 多套环境时，需要Shell连接到不同终端，查找不同账号分别登录

基于上述情况，准备写个页面来提高效率，借助LLM快速撸一个能用的程序。简单调研了下：
* 1）基于前端框架（React/Vue），正好之前也准备补下前端技能栈，但结构复杂实现理解有点慢，当前个人需求是短平快
* 2）基于纯静态页面，后端使用Go，程序自带运行时，禁用`CGO_ENABLED`还可以进一步去掉对`glibc`的依赖

基于近期比较热门的`Vibe Coding`（氛围编程），借助`Cursor`或类似平替`trae`、`Zed`直接可以先实现一版需求。此处基于`trae`。

## 2. 需求描述

生成项目，业务场景描述：
* MySQL表信息
  * 用户表`users`，包含`id`、`username`、`status`
  * `buckets`表，包含如下信息：`bid`、`bname`、`user`、`part`
    * 其中 bid为`uint64`类型，16位；`user`对应users表的id字段；`part`为2位字符串，表示分区，范围`00~FF`
  * 子表`bucket_files_00~bucket_files_FF`，包含：`fid`、`fname`、`bid`、`fsize`文件大小、`status`
    * 表名的后缀是buckets中的`part`字段，表示某bucket里的file都在该分区对应的子表中
    * `fid`为`uint64`类型，16位；
* 有多个用户，用户下创建有多个bucket，每个bucket里包含多个文件，bucket里的文件都存在其分区对应的`bucket_files_分区`表里

需求：
* 基于`Go` + `html/template`实现，选择合适的Web框架，页面展示得简洁美观一些，页面按钮简便操作
  * 服务部署时只要一个bin，静态html/css等都都编译到程序里，并去除glibc依赖
* 支持页面上设置最多3套数据库参数，并可选择连接哪套数据库
  * 每对参数包含：服务端ip、端口、数据库用户、密码、数据库名（默认用户test，密码test，数据库testdb）
  * 配置页面默认收起，点击后展开。可从页面上查询和修改参数
  * 配置保存在配置文件里，不存在配置文件时，默认生成
* 以用户维度展示统计信息
  * 展示用户中包含哪些有数据的分区，及各分区里的文件数和大小；并统计用户总文件数和大小。
  * 分区下的文件数据，我可以点击进去查看具体文件详情列表，若数据太多则默认limit 10展示。并可输入fid来精确匹配，也可输入fname来like前后模糊匹配

## 3. 生成项目说明

生成（加上多次调试修改）的项目代码在：[simple_web_tool](https://github.com/xiaodongQ/simple_web_tool)。

生成了2个版本的代码。
* v1版本：基于DeepSeek-V3-0324
    * 实现栈：gin + gorm + html/template，配置文件使用yaml格式。
* v2版本：基于DeepSeek-Reasoner(R1)
    * 实现栈：基于基础的`net/http` + `database/sql`，配置文件基于json

### 3.1. v1版本代码结构说明

第一个版本用了`gin`框架和`gorm`，更复杂一些，本需求的场景逻辑并不复杂，所以逻辑拆分得有点散，不是太有必要。

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
* 入口：main.go
* html和css样式、js控制，在templates和static目录
    * 部署时，需要拷贝这两个相对目录
* models、controllers目录，MVC架构的数据和控制逻辑
* config，配置文件相关加载逻辑
* 测试数据库表和数据初始化：`init_db.sql`

`build.sh`里的编译命令：`CGO_ENABLED=0 go build -ldflags="-s -w" -o simple_web_tool`，其中`CGO_ENABLED=0`可以去掉glibc的动态库依赖（不使用CGO），更便于分发。

### 3.2. v2版本代码结构说明

重新生成更简洁一点的代码逻辑。

代码结构如下：

```sh
[MacOS-xd@qxd ➜ simple_web_tool git:(main) ✗ ]$ tree 
.
├── build.sh
├── config.go
├── db_operations.go
├── go.mod
├── init_db.sql
├── main.go
└── templates
    ├── base.html
    ├── config.html
    ├── files.html
    └── user_stats.html
```

其中：
* 入口 main.go
* 网页和样式都在templates目录
* 数据库操作：db_operations.go
* 配置文件操作：config.go
* 辅助脚本：build.sh编译，init_db.sql初始化数据库表结构和测试数据

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

初始化脚本：`init_db.sql`，在宿主机上执行：`mysql -h 127.0.0.1 -utest -ptest testdb < init_db.sql`

```sql
-- 用户表
CREATE TABLE IF NOT EXISTS users (
    id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    username VARCHAR(50) UNIQUE NOT NULL,
    status TINYINT DEFAULT 1 COMMENT '1-正常, 0-禁用'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Buckets表
CREATE TABLE IF NOT EXISTS buckets (
    bid BIGINT UNSIGNED PRIMARY KEY COMMENT '16位无符号整数',
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    bname VARCHAR(255) NOT NULL COMMENT 'bucket名称',
    user INT UNSIGNED NOT NULL COMMENT '关联users.id',
    part CHAR(2) NOT NULL COMMENT '分区号(00~FF)',
    INDEX idx_user (user),
    INDEX idx_part (part),
    CONSTRAINT fk_bucket_user FOREIGN KEY (user) REFERENCES users(id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 分区文件表模板
CREATE TABLE IF NOT EXISTS `bucket_files_template` (
    fid BIGINT UNSIGNED PRIMARY KEY COMMENT '16位无符号整数',
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    fname VARCHAR(255) NOT NULL COMMENT '文件名',
    bid BIGINT UNSIGNED NOT NULL COMMENT '关联buckets.bid',
    fsize BIGINT UNSIGNED NOT NULL COMMENT '文件大小(字节)',
    status TINYINT DEFAULT 1 COMMENT '1-正常, 0-删除',
    INDEX idx_bid (bid)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='分区表模板结构';

-- 创建所有分区表(00~FF)
DELIMITER $$
CREATE PROCEDURE CreateAllPartitionTables()
BEGIN
    DECLARE i INT DEFAULT 0;
    DECLARE hex_part CHAR(2);
    
    WHILE i < 256 DO
        SET hex_part = LPAD(LOWER(HEX(i)), 2, '0');
        SET @tbl_name = CONCAT('bucket_files_', hex_part);
        SET @sql = CONCAT('CREATE TABLE IF NOT EXISTS `', @tbl_name, '` LIKE bucket_files_template;');
        PREPARE stmt FROM @sql;
        EXECUTE stmt;
        SET i = i + 1;
    END WHILE;
END$$
DELIMITER ;

CALL CreateAllPartitionTables();
DROP PROCEDURE IF EXISTS CreateAllPartitionTables;

-- 测试数据初始化
-- 插入测试用户
INSERT INTO users (username, status) VALUES
('admin', 1),
('tester', 1),
('developer', 1);

-- 插入测试bucket
INSERT INTO buckets (bid, bname, user, part) VALUES
(1000000000000001, 'admin-backup', 1, 'a3'),
(1000000000000002, 'tester-data', 2, 'f0'),
(1000000000000003, 'dev-resources', 3, '7b'),
-- 增加部分空bucket
(1000000000000004, 'xxxxxxxxxxxx', 1, 'b1'),
(1000000000000005, 'yyyyyyyyyyyy', 3, 'c2'),
(1000000000000006, 'zzzzzzzzzzzz', 3, 'd3');

-- 插入测试文件数据
-- 分区a3的文件
INSERT INTO bucket_files_a3 (fid, fname, bid, fsize, status) VALUES
(2000000000000001, 'data.csv', 1000000000000001, 307200, 1),
(2000000000000002, 'backup.zip', 1000000000000001, 15728640, 1);

-- 分区f0的文件
INSERT INTO bucket_files_f0 (fid, fname, bid, fsize, status) VALUES
(2000000000000003, 'profile_picture.png', 1000000000000002, 512000, 1),
(2000000000000004, 'report.docx', 1000000000000002, 1843200, 1),
(2000000000000005, 'archive.rar', 1000000000000002, 10485760, 1);

-- 分区7b的文件
INSERT INTO bucket_files_7b (fid, fname, bid, fsize, status) VALUES
(2000000000000006, 'source_code.tar.gz', 1000000000000003, 5242880, 1),
(2000000000000007, 'database_dump.sql', 1000000000000003, 2097152, 1);
```
 
## 5. 程序实际功能效果

> 说明：仅使用第2个版本，[simple_web_tool/v2](https://github.com/xiaodongQ/simple_web_tool/tree/main/v2)。

功能说明：
* 支持全局统计，统计各个用户下文件分布信息
* 支持配置多个MySQL数据库环境，可切换默认连接的数据库，数据库配置持久化为json配置文件
* 支持用户分区下文件详情查询。并支持进一步根据文件id过滤、文件名称模糊过滤
* 支持bucket名称和id精确查询，并支持跳转到文件详情查询
* 分发和部署
    * 分发便捷，页面基于Go的`embed.FS`特性，HTML直接嵌入在Go程序中，只需要单bin部署
    * 支持`-port xxx`指定监听端口，不指定则默认`8888`
* 其他小细节
    * 日志打印客户端ip
    * 页面显示操作耗时
    * 按钮刷新、查询数据时，基于AJAX（Asynchronous JavaScript and XML）仅加载部分模板，优化性能

部分手动调整的操作：
* html页面和css样式调整，多轮交互（气泡式展示，效果优化）
* go协程优化数据库操作
* 浏览器缓存数据库实例索引，支持多人下拉选择不同数据库实例查询信息（暂禁用了）
* 增减查询条件和预期行为调整

部分功能截图：

1、用户信息统计：`http://localhost:8080/user-stats`

![用户信息统计](/images/2025-07-12-stats.png)

2、分区过滤展示：`http://localhost:8080/files?user=2&part=f0`

![用户信息统计](/images/2025-07-12-filter.png)

---

优化一下HTML和CSS展示，效果如下。

1、用户信息总体统计

![summary](/images/2025-07-16-summary.png)

2、分区详情显示

![partition](/images/2025-07-16-partition.png)

3、数据库配置

![db-config](/images/2025-07-16-db-config.png)

4、文件详情过滤

![files](/images/2025-07-16-files.png)


## 6. 小结

利用AI生成了一个基本的工具项目，并在调试过程中动态调整，结对过程中边学边实践。折腾了一下HTML+CSS的展示和样式，也是一个新的体验。

生成的内容很多细节需要手动做调整，总体来说帮助还是挺大的。
