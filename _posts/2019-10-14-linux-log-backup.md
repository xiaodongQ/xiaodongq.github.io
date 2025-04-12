---
title: Linux构建自动化过期日志备份
categories: C/C++
tags: [crontab, Shell]
---

Linux下使用crontab和shell脚本实现过期日志移动备份到备份路径

## 缘由

针对某类文件做一个通用的运维demo，一个是便于复用，一个是温习加深印象

之前就整理过crontab使用：[crontab学习使用笔记](https://xiaodongq.github.io/2015/08/18/crontab%E5%AD%A6%E4%B9%A0%E7%AC%94%E8%AE%B0/)

### 前提

日志保存在：`/home/xd/log`

备份日志路径： `/home/xd/log/backup`

日志命名以 `xxx_log_2019-10-12.txt` 方式命名，每日假设会重新生成对应日期的文件

备份功能实现的脚本 `log_daily_backup.sh` 和 `crontab.xd` 存放路径：`/home/xd/auto_ops`

## 实现

实现功能：

1. 将以日期命名的文件进行移动，备份到指定备份路径
2. 定期每日00:00执行移动备份
3. 脚本执行过程记录日志文件，日志文件大小有100MB限制处理，超过100MB清空重新记录

不完善功能：

1. 日志备份路径，文件总大小没有控制

    不管不顾可能最后会将磁盘占满。 应根据实际需求，超额进行报警或者自动删除部分规则的文件。

2. 会重新生成对应日期的日志文件只是前提假设

    若为7*24小时程序，删除日志文件可能不会重新生成，移动日志后后续日志则记不到文件中。 脚本中应进行保护判断。

### 日志清理脚本

```sh
#log_daily_backup.sh

#!/bin/bash

LOG_DIR=/home/xd/log
LOG_DIR_BACKUP=backup

AUTO_OPS_LOG_FILE="/home/xd/auto_ops/ops.log"

# 2019-10-14形式
CUR_DATE=`date "+%Y-%m-%d"`
echo -e "\n`date`, check backup log start...\n" >> $AUTO_OPS_LOG_FILE

# 添加必要保护，有该日志路径才继续，防止变量为空导致的非预期目录操作
if [ ! -d ${LOG_DIR} ]; then
    echo "`date`, $LOG_DIR not exist, exit!" >> $AUTO_OPS_LOG_FILE
    exit -1
fi

cd ${LOG_DIR}
if [ ! -d $LOG_DIR_BACKUP ]; then
    echo "`date`, $LOG_DIR_BACKUP not exist! create..." >> $AUTO_OPS_LOG_FILE
    mkdir $LOG_DIR_BACKUP
fi

# 命名格式都是xxx_log_2019-10-12.txt形式
function log_backup()
{
    for file in `ls`
    do
        if [ ${file} != "${LOG_DIR_BACKUP}" ] && [[ ${file} != *_${CUR_DATE}.txt ]]; then
            echo "`date`, matched file[$file], not like *_${CUR_DATE}.txt, mv to backup" >> $AUTO_OPS_LOG_FILE
            mv ${file} ${LOG_DIR_BACKUP}/ -f 2>&1 | tee -a $AUTO_OPS_LOG_FILE
        fi
    done
}

function check_log_size()
{
    OPS_LOG_FILE_SIZE=`ls -l ${AUTO_OPS_LOG_FILE} | awk -F' ' '{ print $5}'`
    MAX_LOG_SIZE=$((1024*1024*100))
    echo "`date`, file[${AUTO_OPS_LOG_FILE}] size:${OPS_LOG_FILE_SIZE}" >> $AUTO_OPS_LOG_FILE
    # 大于100M则重新生成
    if [ $OPS_LOG_FILE_SIZE -gt $MAX_LOG_SIZE ]; then
        echo "`date`, file[${AUTO_OPS_LOG_FILE}] size:${OPS_LOG_FILE_SIZE} over $((${MAX_LOG_SIZE}/1024/1024)) MB, recover" > $AUTO_OPS_LOG_FILE
    fi
}

log_backup
check_log_size

echo "`date`, end" >> $AUTO_OPS_LOG_FILE
```

### crontab文件

关于crontab，参考前面贴出来的 [crontab学习使用笔记](https://xiaodongq.github.io/2015/08/18/crontab%E5%AD%A6%E4%B9%A0%E7%AC%94%E8%AE%B0/)

```sh
#crontab.xd

# Example of job definition:
# .---------------- minute (0 - 59)
# |  .------------- hour (0 - 23)
# |  |  .---------- day of month (1 - 31)
# |  |  |  .------- month (1 - 12) OR jan,feb,mar,apr ...
# |  |  |  |  .---- day of week (0 - 6) (Sunday=0 or 7) OR sun,mon,tue,wed,thu,fri,sat
# |  |  |  |  |
  0  0  *  *  * sh /home/xd/auto_ops/log_daily_backup.sh
```

用 `crontab crontab.xd` 进行定期任务安装加载；

`crontab -r` 进行该用户的定期任务移除；

`crontab -l` 查看当前用户已安装的crontab定期任务
