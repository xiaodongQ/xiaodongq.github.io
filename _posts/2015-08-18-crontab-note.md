---
title: crontab学习使用笔记
categories: Linux
tags: Shell
---

crontab命令常见于Unix和类Unix的操作系统之中，用于设置周期性被执行的指令。

## 1. crond简介及crontab文件

部分参考：

[crontab命令](https://man.linuxde.net/crontab)

[每天一个linux命令（50）：crontab命令](https://www.cnblogs.com/peida/archive/2013/01/08/2850483.html)

linux系统由 cron (crond) 这个系守护进程服务来控制循环运行的例行性计划任务

crond进程每分钟会定期检查是否有要执行的任务，如果有要执行的任务，则自动执行该任务。

Linux下的任务调度分为两类，系统任务调度和用户任务调度。

  * 系统任务调度：系统周期性所要执行的工作，比如写缓存数据到硬盘、日志清理等。在/etc目录下有一个crontab文件，这个就是系统任务调度的配置文件。
  * 用户任务调度：用户定期要执行的工作，比如用户数据备份、定时邮件提醒等。用户可以使用 crontab 工具来定制自己的计划任务。所有用户定义的crontab 文件都被保存在 /var/spool/cron目录中。其文件名与用户名一致。

/etc/crontab文件：

```sh
# 前四行是用来配置crond任务运行的环境变量
# 第一行SHELL变量指定了系统要使用哪个shell，这里是bash，第二行PATH变量指定了系统执行命令的路径，第三行MAILTO变量指定了crond的任务执行信息将通过电子邮件发送给root用户，如果MAILTO变量的值为空，则表示不发送任务执行信息给用户，第四行的HOME变量指定了在执行命令或者脚本时使用的主目录。
SHELL=/bin/bash
PATH=/sbin:/bin:/usr/sbin:/usr/bin
MAILTO=root

# For details see man 4 crontabs

# Example of job definition:
# .---------------- minute (0 - 59)
# |  .------------- hour (0 - 23)
# |  |  .---------- day of month (1 - 31)
# |  |  |  .------- month (1 - 12) OR jan,feb,mar,apr ...
# |  |  |  |  .---- day of week (0 - 6) (Sunday=0 or 7) OR sun,mon,tue,wed,thu,fri,sat
# |  |  |  |  |
# *  *  *  *  * user-name  command to be executed
```

在以上各个字段中，还可以使用以下特殊字符：

- 星号（*）：代表所有可能的值，例如month字段如果是星号，则表示在满足其它字段的制约条件后每月都执行该命令操作。
- 逗号（,）：可以用逗号隔开的值指定一个列表范围，例如，“1,2,5,7,8,9”
- 中杠（-）：可以用整数之间的中杠表示一个整数范围，例如“2-6”表示“2,3,4,5,6”
- 正斜线（/）：可以用正斜线指定时间的间隔频率，例如“0-23/2”表示每两小时执行一次。同时正斜线可以和星号一起使用，例如*/10，如果用在minute字段，表示每十分钟执行一次。

对于命名：如果是自己新建的crontab文件，命名成 "crontab", "crontab.xd"，用vim打开都能显示语法高亮;
而"crontab_xd", "xd_crontab", "crontab_xd.xd"则不行。 使用crontab.用户名方式命名

### 1.1. 部分用法示例：

更多实例查看上面的链接

* 每隔两分钟执行

  `*/2 * * * * cmd`

* 每小时的奇数分钟执行，（0不执行，1执行）

  `1-59/2 * * * * cmd`

* 每天18:00至23:00间每隔30分钟

  `0,30 18-23 * * * cmd`

  `0-59/30 18-23 * * * cmd`

> * `A,B,C` A或B或C
* `A-B` A到B之间
* `*/A` 每A分钟（小时等）

* 两小时运行一次，注意分钟要设置值

  `* */2 * * * cmd （错误）`
  `0 */2 * * * cmd （正确）`

## 2. crontab 命令

通过crontab 命令，我们可以在固定的间隔时间执行指定的系统指令或 shell script脚本。

```sh
crontab [-u user] file
crontab [-u user] [ -e | -l | -r ]

-u user：用来设定某个用户的crontab服务
-e：编辑某个用户的crontab文件内容。如果不指定用户，则表示编辑当前用户的crontab文件。
-l：显示某个用户的crontab文件内容，如果不指定用户，则表示显示当前用户的crontab文件内容。
-r：从/var/spool/cron目录中删除某个用户的crontab文件，如果不指定用户，则默认删除当前用户的crontab文件。
-i：在删除用户的crontab文件时给确认提示。
```

## 3. 注意事项

### 3.1. 环境变量问题

不要假定cron知道所需要的特殊环境，它其实并不知道。所以你要保证在shelll脚本中提供所有必要的路径和环境变量，除了一些自动设置的全局变量。所以注意如下3点：

1）脚本中涉及文件路径时写全局路径；

2）脚本执行要用到java或其他环境变量时，通过source命令引入环境变量，如：

```sh
cat start_cbp.sh

#!/bin/sh
source /etc/profile
export RUN_CONF=/home/d139/conf/platform/cbp/cbp_jboss.conf
/usr/local/jboss-4.0.5/bin/run.sh -c mev &
```

3）当手动执行脚本OK，但是crontab死活不执行时。这时必须大胆怀疑是环境变量惹的祸，并可以尝试在crontab中直接引入环境变量解决问题。如：

```
0 * * * * . /etc/profile;/bin/sh /var/www/java/audit_no_count/bin/restart_audit.sh
```

### 3.2. 日志清理问题

每条任务调度执行完毕，系统都会将任务输出信息通过电子邮件的形式发送给当前系统用户(/var/mail/用户, /var/log/messages)等系统日志文件，这样日积月累，日志信息会非常大，可能会影响系统的正常运行，因此，将每条任务进行重定向处理非常重要。

例如，可以在crontab文件中设置如下形式，忽略日志输出：

```sh
0 */3 * * * /usr/local/apache2/apachectl restart >/dev/null 2>&1

#“/dev/null 2>&1”表示先将标准输出重定向到/dev/null，然后将标准错误重定向到标准输出，由于标准输出已经重定向到了/dev/null，因此标准错误也会重定向到/dev/null，这样日志输出问题就解决了。
```

也可以有单独的脚本来维护日志 serviceDog.sh，定期检查文件大小，超出限制则备份或者删除

使用linux系统自带的logrotate工具来管理：
[日常运维中的相关日志切割处理方法总结](https://www.cnblogs.com/kevingrace/p/6307298.html)
