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

  ```sql
    create table [if not exists] table_name (
    column_name data_type,
    ...
    );
  ```

  ```sql
    create table tb1(
      username VARCHAR(20),
      age tinyint unsigned,
      salary float(8,2) unsigned
      );
  ```

  **查看表是否存在: show tables [from db_name];**

  **查看表结构: show columns from tbl_name;**

  **DESC 表名**

* 插入记录

  `insert [into] tbl_name [(col_name,...)] values(val,...);`

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

    show indexes from 表名\G; (\G表示以网格的形式显示)

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

    `ALTER TABLE tbl_name ADD [COLUMN] col_name column_definition [FIRST|AFTER col_name]`

  * 添加多列 (不可指定位置，添加在最后)

    `ALTER TALBE tbl_name ADD [COLUMN] (col_name column_definition, ...)`

  * 删除列

    `ALTER TABLE tbl_name DROP col_name`

    *也可删除多列，或同时添加列，使用 , 分隔 (e.g. drop col1,drop col2,add col3 int)*

  * 添加主键约束

    `ALTER TABLE tbl_name ADD [CONSTRAINT [symbol]] PRIMARY KEY [index_type] (index_col_name,...)`

  * 添加唯一约束

    `ALTER TABLE tbl_name ADD [CONSTRAINT [symbol]] UNIQUE [INDEX|KEY] [index_name] [index_type] (index_col_name, ...)`

  * 添加外键约束

    `ALTER TABLE tbl_name ADD [CONSTRAINT [symbol]] FOREIGN KEY [index_name] (index_col_name, ...) reference_definition`

    e.g. `ALTER TABLE users1 ADD FOREIGN KEY (pid) REFERENCES provinces(id)`

  * 添加/删除默认约束

    `ALTER TABLE tbl_name ALTER [COLUMN] col_name {SET DEFAULT iteral | DROP DEFAULT}`

    e.g. `ALTER TABLE users1 ALTER age SET DEFAULT 10;`

    e.g. `ALTER TABLE users1 ALTER age DROP DEFAULT;`

  * 删除主键约束

    `ALTER TABLE tbl_name DROP PRIMARY KEY;`

  * 删除唯一约束

    `ALTER TABLE tbl_name DROP {KEY|INDEX} index_name`

  * 删除外键约束

    `ALTER TABLE tbl_name DROP FOREIGN KEY fk_symbol (fk_symbol需知道名字, show create table 表名)`

  * 修改列定义 (只能改类型)

    `ALTER TABLE tbl_name MODIFY [COLUMN] col_name column_definition [FIRST|AFTER col_name]`

  * 修改列名称

    `ALTER TABLE tbl_name CHANGE [COLUMN] old_col_name new col_name column_definition [FIRST|AFTER col_name]`

  * 数据表更名

      1. `ALTER TABLE tbl_name RENAME [TO|AS] new_tbl_name`

      2. `RENAME TABLE tbl_name TO new_tbl_name [,tbl_name2 TO new_tbl_name2]...`

  **数据列和数据表名尽量不去修改**

## 操作数据表中的记录

### 插入记录

  **三种形式:**

  1. 可一次插入多条记录

      `INSERT [INTO] tbl_name [(col_name,...)] {VALUES | VALUE} ({expr | DEFAULT},...),(...),...`

        e.g. `INSERT users VALUES (DEFAULT, 'Tom', 3*3+1), (NULL, 'Cat', 3);`

        > 对AUTO_INCREMENT可赋值为NULL,DEFAULT；  含有默认值的列也可以赋DEFAULT

  2. 可使用子查询,一次性仅能插入一条记录

      `INSERT [INTO] tbl_name SET col_name={expr|DEFAULT},...`

  3. 将查询结果插入到指定表

      `INSERT [INTO] tbl_name [(col_name,...)] SELECT...`

### 更新记录(单表更新)

```sql
  UPDATE [LOW_PRIORITY] [IGNORE] table_reference
  SET col_name1={expr1|DEFAULT}[,col_name2={expr2|DEFAULT}]... 
  [WHERE where_condition]
```

  e.g. `UPDATE student SET age=age-id where id%2=0;`

### 删除记录(单表删除)

  `DELETE FROM tbl_name [WHERE where_condition]`

### 查询表达式

```sql
  SELECT select_expr [,select_expr ...]
  [
    FROM table_reference
    [WHERE where_condition]
    [GROUP BY {col_name|position} [ASC|DESC], ...]
    [HAVING where_condition]
    [ORDER BY {col_name|expr|position} [ASC|DESC], ...]
    [LIMIT {[offset,]row_count|row_count OFFSET offset}]
  ]
```

  可使用别名 [AS]可使用，也可不使用，建议使用。

  e.g. `SELECT id AS no,studentname AS name FROM student WHERE id=3;`

* 分组条件

  GROUP BY 子句 HAVING 条件

  **HAVING中的列需保证在SELECT中 或 该列位于聚合函数**

  e.g. `SELECT id,age FROM student GROUP BY id HAVING age > 4;`

* 排序

  `[ORDER BY {col_name|expr|position} [DESC|ASC]]`

* 限制查询结果返回的数量 LIMIT子句

  `[LIMIT {[offset,] row_count|row_count OFFSET offset}]`

  e.g. 前两条记录 `SELECT * FROM student LIMIT 2`

  e.g. 从第2条(0,1,2)开始的两条记录 `SELECT * FROM student LIMIT 2,2`

## 子查询与连接

### 子查询

  Subquery指出现在其他SQL语句内的SELECT子句。嵌套在查询内部，必须始终出现在圆括号内。

  比较运算符 >, >=, <, <=, =, <>, != 注意不等

  (操作数 比较运算符 子查询)

  `operand comparison_operator ANY (subquery)`

  `operand comparison_operator SOME (subquery)`

  `operand comparison_operator ALL (subquery)`

  `operand comparison_operator [NOT] IN (subquery)` (相当于 = ANY)

  `operand comparison_operator [NOT] EXISTS (subquery)` (返回TRUE或FALSE)

### 多表更新

  多表更新: 参照其他表更新本表记录

```sql
  UPDATE table_references
  SET col_name1={exp1|DEFAULT}[,col_name2={expr2|DEFAULT}] ...
  [WHERE where_condition]
```

* 连接

  1. INNER JOIN, 内连接

      *MySQL中,JOIN,CROSS JOIN和INNER JOIN是等价的。*

  2. LEFT [OUTER] JOIN, 左外连接
  3. RIGHT [OUTER] JOIN, 右外连接

  ```sql
  table_reference {[INNER|CROSS] JOIN|{LEFT|RIGHT} [OUTER] JOIN}
  table_reference
  ON conditionl_expr
  ```

  e.g. `UPDATE tdb_goods AS a INNER JOIN tdb_goods_cates as b on a.goods_cate=b.cate_name SET a.goods_cate=cate_id;`

### 多表删除

e.g. 删除重复的记录(自身连接)
  ```sql
    DELETE t1 FROM tdb_goods AS t1 LEFT JOIN (SELECT
    goods_name,goods_id FROM tdb_goods GROUP BY goods_name HAVING
    count(goods_name) >= 2) AS t2 ON t1.goods_name = t2.goods_name
    WHERE t1.goods_id > t2.goods_id;
  ```
