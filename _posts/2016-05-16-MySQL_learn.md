---
layout: post
title: MySQL学习实践笔记
categories: MySQL
tags: MySQL SQL 数据库
---

* content
{:toc}

## 基本命令

默认端口: 3306 默认用户: root
登录: mysql -uroot -p密码 -P端口 -hIP地址
退出: exit; quit; \q
prompt mysql> 改描述符

## 语句规范：

* 关键字与函数名称全部大写；
* 数据库名称、表名称、字段名称全部小写；
* SQL语句必须以分好结尾。

## 操作数据库

create database [if not exists] 名字 character set 编码;
alter database 名字 character set 编码;
drop database [if exists] 名字;
show warnings;
show errors;

## 数据类型及表操作

### 数据类型

* 整型: 有符无符 unsigned
  TINYINT    1
  SMALLINT   2
  MEDIUMINT  3
  INT        4
  BIGINT     8
* 浮点型
  FLOAT[(M,D)]
  DOUBLE
* 日期时间型
  YEAR 1
  TIME 3
  DATE 3
  DATETIME 8 用的少
  TIMESTAMP 4
* 字符型
  CHAR(M) 0<= M <= 255 定长
  VARCHAR(M) 65535
  TINYTEXT  8字节
  TEXT      16字节
  MEDIUMTEXT 24
  LONGTEXT   32
  ENUM ('value1','value2',...)
  SET(‘value1’,'value2',...)

### 数据表

USE 数据库名称
select database() 查看打开的数据库

* 建表
  create table [if not exists] table_name (
    column_name data_type,
    ...
    )

    ``` SQL
    create table tb1(
      username VARCHAR(20),
      age tinyint unsigned,
      salary float(8,2) unsigned );
    ```

    **查看表是否存在: show tables [from db_name];**

    **查看表结构: show columns from tbl_name;**

* 插入记录
  insert [into] tbl_name [(col_name,...)] values(val,...);
* 查找记录
  select * from tbl_name;

  *空值与非空*
  建表 column_name data_type not null,
* 主键
  primary key,

**自动编号**
  auto_increment
  必须与主键组合使用;
  默认情况下，起始值为1，每次增量为1
* 唯一约束
  UNIQUE KEY
  保证记录的唯一性;
  唯一约束的字段可为空值(NULL);
  每张表可存在多个唯一约束。
* 默认值
  enum('1','2','3') default '3'

## 约束及修改数据表

### 约束

  * 保证数据的完整性和一致性；
  * 分为表级约束和列级约束
  * 约束类型包括：
    非空、主键约束(PRIMARY KEY)、唯一约束(UNIQUE KEY)、默认约束(DEFAULT)、外键约束(FOREIGN KEY)

* 外键约束
  父表，子表: 有外键的表称作子表；
  默认存储引擎: InnoDB;
  外键列，参照列: (是否有符要一致，外键列和参照列必须创建索引)；
  主键创建时会自动创建索引。
    show indexes from 表名\G; (\G排版清晰)

    **外键约束的参照操作**
    1. CASCADE: 从父表 删除 或 更新 会自动删除或更新子表中匹配的行
    2. SET NULL: 从父表删除或更新行，设置子表中得外键列为NULL(须保证子表中未设为NOT NULL)
    3. RESTRICT: 拒绝对父表的删除或更新操作
    4. NO ACTION: 标准SQL的关键字，MySQL中与上者相同

* 表级约束和列级约束
  对一个数据列建立的约束，称为列级约束；(NOT NULL,default只有列级约束)
  对多个数据列建立的约束，称为表级约束；
  列级约束可在列定义时声明，也可在列定以后声明；表级约束只能在列定义后声明。

### 修改数据表

  * 添加单列 (可指定列的位置)
    ALTER TABLE tbl_name ADD [COLUMN] col_name column_definition [FIRST|AFTER col_name]
  * 添加多列 (不可指定位置，添加在最后)
    ALTER TALBE tbl_name ADD [COLUMN] (col_name column_definition, ...)
  * 删除列
    ALTER TABLE tbl_name DROP col_name
    *也可删除多列，或同时添加列，使用 , 分隔 (e.g. drop col1,drop col2,add col3 int)*

  * 添加主键约束
    ALTER TABLE tbl_name ADD [CONSTRAINT [symbol]] PRIMARY KEY [index_type] (index_col_name,...)
  * 添加唯一约束
    ALTER TABLE tbl_name ADD [CONSTRAINT [symbol]] UNIQUE [INDEX|KEY] [index_name] [index_type] (index_col_name, ...)
  * 添加外键约束
    ALTER TABLE tbl_name ADD [CONSTRAINT [symbol]] FOREIGN KEY [index_name] (index_col_name, ...) reference_definition
      e.g. ALTER TABLE users1 ADD FOREIGN KEY (pid) REFERENCES provinces(id)

  * 添加/删除默认约束
    ALTER TABLE tbl_name ALTER [COLUMN] col_name {SET DEFAULT iteral | DROP DEFAULT}
      e.g. ALTER TABLE users1 ALTER age SET DEFAULT 10;
           ALTER TABLE users1 ALTER age DROP DEFAULT;

  * 删除主键约束
    ALTER TABLE tbl_name DROP PRIMARY KEY;
  * 删除唯一约束
    ALTER TABLE tbl_name DROP {KEY|INDEX} index_name
  * 删除外键约束
    ALTER TABLE tbl_name DROP FOREIGN KEY fk_symbol (fk_symbol需知道名字, show create table 表名)

  * 修改列定义 (只能改类型)
    ALTER TABLE tbl_name MODIFY [COLUMN] col_name column_definition [FIRST|AFTER col_name]
  * 修改列名称
    ALTER TABLE tbl_name CHANGE [COLUMN] old_col_name new col_name column_definition [FIRST|AFTER col_name]
  * 数据表更名
    1. ALTER TABLE tbl_name RENAME [TO|AS] new_tbl_name
    2. RENAME TABLE tbl_name TO new_tbl_name [,tbl_name2 TO new_tbl_name2]...

    **数据列和数据表名尽量不去修改**
