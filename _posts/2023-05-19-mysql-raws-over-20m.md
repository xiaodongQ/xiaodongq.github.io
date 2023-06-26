---
layout: post
title: MySQL单表超过2000万后会怎么样
categories: 案例实验
tags: MySQL
---

* content
{:toc}

进行实验学习：MySQL单表超过2000万条记录，分析现象。



## 1. 背景

使用MySQL存数据时，业内有个传言是单表不要超过2000万条记录，若超过则查询效率会显著降低。

本博客对该情况进行实验记录，在实践中加深学习。

## 1. 理论

> 回翻MySQL索引实现的文章：[48 | B+树：MySQL数据库索引是如何实现的？](https://time.geekbang.org/column/article/77830)，结合本文场景加深一下理解。

* InnoDB索引说明

    MySQL 5.1之后的默认存储引擎是`InnoDB`，其索引基于B+树实现。

    虽然内存访问(ns级别)比磁盘访问(ms级别)快很多(万倍甚至几十万倍)，索引存放在内存中查找效率很高，但是随着数据量上升，需要的内存也会很多，相对于磁盘来说内存的成本昂贵得多，服务器上内存上限也比磁盘要低得多。所以InnoDB的索引有一部分是存储在磁盘上的。

    B+树通过二叉查找树演化而来，是一个多叉树(以下假设m叉树)，支持**区间查找**。非叶子结点存储索引值，叶子节点存储数据，数据之间通过双向链表链接，便于区间查找。

    索引设计时使用m叉树的方式来降低树的高度，以减少查找MySQL记录时磁盘的IO操作次数。

    m越大，B+树的高度越低，但也不是越大越好。操作系统按页(`PAGE_SIZE`，一般4096)来读取数据，一次读取的数据量超过一页则会触发多次IO操作，所以一般会尽量让每个节点(m个索引值组成一个节点)大小等于`PAGE_SIZE`，读取一个节点只需要一次IO操作。

    数据插入、删除时会更新索引，为了时刻维持m叉树，会涉及到B+树的`分裂`和`合并`，索引量越大，数据插入、删除会越慢。

* B+树

    1. 先讲讲B树(B-树，B-Tree)。

        `键`：B树中的存储元素是键，是用于指向数据记录的指针。

        `阶`：B树的阶为最大子节点数量，其比键的数量大1。一般称一个B树为M阶的B树，那么该B树最多拥有M个子节点，节点中最多拥有M-1个键

        数据量特别大时，内存中存不下所有数据了，一部分数据就存储在磁盘中。磁盘操作比较耗时（如上所述跟内存差好几个数量级），B树的出现就是为了减少磁盘的IO操作。

        B树在中间节点中存储数据指针（指向包含键值的磁盘文件块的指针），导致节点数据量较大进而导致树层数多，影响查询效率；

    B+树仅在树的叶子结点中存储数据指针，中间节点存储

    [一文详解 B-树，B+树，B*树](https://zhuanlan.zhihu.com/p/98021010)

    [图解：什么是B树？](https://zhuanlan.zhihu.com/p/146252512)
    [什么是B+树，B+树查找、插入、删除](https://zhuanlan.zhihu.com/p/149287061)

## 2. 实验

### 实验说明

* 基础目标：

    - 给出为什么不要超过 2000w 行的数据支持
    - 100、500、1000、2000万他们的查询时间是线性增加的吗？

* 踮踮脚的目标：

    - 从 B+ 树原理结合测试数据分析为什么
    - 以及你自己能想到的验证、结论等都可以——开放式

* 测试表

    ```sql
    CREATE TABLE test(
        id int NOT NULL AUTO_INCREMENT PRIMARY KEY comment '主键',
        person_id tinyint not null comment '用户id',
        person_name VARCHAR(200) comment '用户名称',
        gmt_create datetime comment '创建时间',
        gmt_modified datetime comment '修改时间'
    ) comment '人员信息表';
    ```

    select count(*) from test;  
    select count(*) from test where id=XXX;

### 实验过程

* 环境说明

    MySQL 8.0.26

    Linux配置：16Core，32GB
    ![Linux配置](/images/2023-05-29-22-50-29.png)

* 测试脚本

```sh
#!/bin/bash
# 测试mysql单表超2000万的查询效率

INIT_RAWS=2000
ROUND=20

function op_db() {
    # -N 不要列名，-s不要表格
    mysql -uroot -p123456 -Dxddata -N -s -e "$1" 2>/dev/null
}

function init() {
    op_db "truncate table test;"
    # 建一个非主键索引 person_name 对比
    op_db "CREATE TABLE test(
        id int NOT NULL AUTO_INCREMENT PRIMARY KEY comment '主键',
        person_id int not null comment '用户id',
        person_name VARCHAR(200) comment '用户名称',
        gmt_create datetime comment '创建时间',
        gmt_modified datetime comment '修改时间',
        index(person_name)
    ) comment '人员信息表';"
}

function init_insert() {
    for ((i=1; i<=$INIT_RAWS; i++)); do
        local id=$i
        local name="test_$id"
        op_db "insert into test(person_id, person_name, gmt_create, gmt_modified) values($id, $name, NOW(), NOW());"
    done
}

function double_insert() {
    op_db "insert into test(person_id, person_name, gmt_create, gmt_modified) select person_id, person_name, NOW(), NOW() from test"
}

function main()
{
    if [[ $# -eq 2 ]]; then
        INIT_RAWS=$1
        ROUND=$2
    fi

    local count=0
    for ((i=1; i<=$ROUND; i++)); do
        before=$(( $(date +%s%N)/1000000 ))
        double_insert
        after=$(( $(date +%s%N)/1000000 ))
        insert_cost=$(($after - $before))

        before=$(( $(date +%s%N)/1000000 ))
        count = $(op_db "select count(*) from test;")
        after=$(( $(date +%s%N)/1000000 ))
        select_cost=$(($after - $before))
        
        before=$(( $(date +%s%N)/1000000 ))
        op_db "select count(*) from test where id=999; "
        after=$(( $(date +%s%N)/1000000 ))
        select_where_id_cost=$(($after - $before))

        before=$(( $(date +%s%N)/1000000 ))
        op_db "select count(*) from test where person_name='test_99'; "
        after=$(( $(date +%s%N)/1000000 ))
        select_where_name_cost=$(($after - $before))

        echo "round:$i, count:$count, insert_cost:$insert_cost ms, select_cost:$select_cost ms, select_where_id_cost:$select_where_id_cost ms, select_where_name_cost:$select_where_name_cost ms"
    done
}

main $@
```

## 3. 小结


## 参考

1. [星球：为啥说MySQL单表行数不要超过2000w](https://articles.zsxq.com/id_szzdrtss5t7o.html)
2. [Is 20M of rows still a valid soft limit of MySQL table in 2023?](https://yishenggong.com/2023/05/22/is-20m-of-rows-still-a-valid-soft-limit-of-mysql-table-in-2023/)
