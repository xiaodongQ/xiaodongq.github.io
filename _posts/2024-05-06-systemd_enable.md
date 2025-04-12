---
layout: _post
title: 记一个systemd设置自启动问题
categories: Linux
tags: systemd
---

* content
{:toc}

记一个/etc/init.d下的服务自启动设置失败问题



## 1. 背景

最近碰到一个服务入口脚本(/etc/init.d/下)中误删除了脚本chkconfig注释导致服务没有自启动的问题，并且在CentOS7.7上正常，但是在openEuler上没有正常自启动。

跟踪执行过程和systemd源码定位到了原因，本文进行简单记录。

![两种自启动设置方式](/images/2024-05-12-09-41-36.png)

## 2. 现象模拟

### 2.1. 快速模拟步骤

1、阿里云抢占式ECS

2、借助ChatGPT/文心一言快速模拟环境。(你是一个linux资深开发者->快速创建一个chkconfig服务->通过systemd创建服务，上面的服务换成XD-Service，并且调用的启停脚本为/etc/init.d/XD-Service，调整脚本)

### 2.2. 复现步骤

1、在/etc/init.d下创建满足chkconfig规则的脚本

vi /etc/init.d/XD-Service

```sh
#!/bin/bash  
# chkconfig: 345 99 20  
# description: My Custom Service  
# processname: myservice  

case "$1" in  
  start)  
    echo "Starting myservice"  
    # 这里添加启动服务的命令  
    ;;  
  stop)  
    echo "Stopping myservice"  
    # 这里添加停止服务的命令  
    ;;  
  restart)  
    $0 stop  
    $0 start  
    ;;  
  status)  
    # 这里添加检查服务状态的命令  
    ;;  
  *)  
    echo "Usage: $0 {start|stop|restart|status}"  
    exit 1  
esac  
exit 0
```

2、通过systemd创建服务，用上面的脚本作为启停脚本

vi /etc/systemd/system/XD-Service.service

```sh
[Unit]  
Description=XD-Service  
After=network.target  

[Service]  
Type=forking  
User=yourusername  # 如果需要，指定运行服务的用户  
Group=yourgroupname  # 如果需要，指定运行服务的组  
Environment=PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin  
ExecStart=/etc/init.d/XD-Service start  
ExecStop=/etc/init.d/XD-Service stop  
Restart=on-failure  

[Install]  
WantedBy=multi-user.target
```

3、查看服务状态，`systemctl enable XD-Service.service`设置服务自启动

```sh
# 设置前状态
[root@iZ2zebfcx8h2zfz7ieqaquZ init.d]# systemctl status XD-Service.service 
● XD-Service.service - XD-Service
   Loaded: loaded (/etc/systemd/system/XD-Service.service; disabled; vendor preset: disabled)
   Active: inactive (dead)
# 设置前状态，非自启动
[root@iZ2zebfcx8h2zfz7ieqaquZ init.d]# systemctl is-enabled XD-Service.service 
disabled
# 设置自启动
[root@iZ2zebfcx8h2zfz7ieqaquZ init.d]# systemctl enable XD-Service.service 
Synchronizing state of XD-Service.service with SysV service script with /usr/lib/systemd/systemd-sysv-install.
Executing: /usr/lib/systemd/systemd-sysv-install enable XD-Service
Created symlink /etc/systemd/system/multi-user.target.wants/XD-Service.service → /etc/systemd/system/XD-Service.service.
# 自启动状态
[root@iZ2zebfcx8h2zfz7ieqaquZ init.d]# systemctl is-enabled XD-Service.service 
enabled
[root@iZ2zebfcx8h2zfz7ieqaquZ init.d]# 
```

4、构造场景：先disable去掉自启动，再把入口脚本的chkconfig注释删掉(如下注释)。再设置自启动，设置失败，问题复现。

```sh
# chkconfig: 345 99 20  
# description: My Custom Service 
```

```sh
# 删除上述“注释”后，设置自启动，报错了
[root@iZ2zebfcx8h2zfz7ieqaquZ init.d]# systemctl enable XD-Service.service 
Synchronizing state of XD-Service.service with SysV service script with /usr/lib/systemd/systemd-sysv-install.
Executing: /usr/lib/systemd/systemd-sysv-install enable XD-Service
service XD-Service does not support chkconfig

# 确实没设置成功
[root@iZ2zebfcx8h2zfz7ieqaquZ init.d]# systemctl is-enabled XD-Service.service 
disabled
```

## 3. 问题分析和定位

### 3.1. 提出问题

1、为什么删除了上面的注释，导致服务设置不了自启动？

2、在CentOS7及之上的版本，控制服务自启动的不是systemd吗，为什么此处打印里是走了sysV的处理？

### 3.2. 第一个问题

第一个问题，通过对比脚本变化和网上查询，能快速知道服务脚本要兼容chkconfig的话，必须满足一定格式

> chkconfig 脚本本身并不直接涉及脚本格式，因为 chkconfig 是一个用于管理系统服务启动和停止链接的工具，而不是一个脚本。但是，当你为某个服务编写初始化脚本（通常位于 /etc/init.d/ 或 /usr/lib/systemd/system/，取决于你使用的系统和服务管理工具）时，你可能需要确保该脚本与 chkconfig 兼容。

> 对于传统的 SysV init 脚本（与 chkconfig 配合使用），这些脚本通常遵循以下格式和约定：

1、开头行：指定使用哪种shell来解释脚本。通常是 #!/bin/bash 或其他shell的路径。

2、chkconfig注释：在脚本的顶部，你可以添加一些特殊的注释来告诉 chkconfig 如何在不同的运行级别启动或停止服务。例如：

```bash
#!/bin/bash  
# chkconfig: 345 99 20  
# description: My custom service
```

> 这里，345 表示该服务应在运行级别 3、4 和 5 下启动，99 是启动优先级（数字越大，启动越晚），20 是停止优先级（数字越小，停止越早）。

3、脚本逻辑：接下来是实际的脚本逻辑，用于启动、停止、重新启动或检查服务的状态。通常，你会看到 case 语句来处理不同的操作，如 start、stop、restart 和 status。

4、启动和停止链接：当你使用 chkconfig 将服务添加到系统中时，它会为你创建符号链接在 /etc/rc[0-6].d/ 目录中。这些链接指向你的初始化脚本，并带有特定的前缀（如 S 或 K）和优先级数字。

5、权限和所有权：初始化脚本通常需要具有执行权限，并且通常由 root 用户拥有。

然而，值得注意的是，许多现代Linux发行版已经转向使用 systemd 作为其服务管理工具，而不是传统的 SysV init 和 chkconfig。在 systemd 中，服务配置文件（称为单元文件）位于 /usr/lib/systemd/system/ 或 /etc/systemd/system/ 目录中，并使用不同的语法和约定。

### 3.3. 第二个问题，为什么走了sysV的方式处理自启动

1、和CentOS7.7对比，同样`systemctl enable XD-Service`操作，正常走systemd的流程(没打印sysV)

2、第一反应是strace跟踪对比，对比两者不是太明显。同一个系统上的其他服务正常走systemd处理，以auditd为例进行跟踪

`strace -tt systemctl enable XD-Service.service`

```sh
...
22:40:41.704771 openat(3, "XD-Service.service.d", O_RDONLY|O_NOFOLLOW|O_CLOEXEC|O_PATH) = -1 ENOENT (No such file or directory)
22:40:41.704801 close(3)                = 0
22:40:41.704864 openat(AT_FDCWD, "/etc/systemd/system.control/XD-Service.service.d", O_RDONLY|O_NONBLOCK|O_CLOEXEC|O_DIRECTORY) = -1 ENOENT (No such file or directory)
22:40:41.704995 openat(AT_FDCWD, "/run/systemd/system.control/XD-Service.service.d", O_RDONLY|O_NONBLOCK|O_CLOEXEC|O_DIRECTORY) = -1 ENOENT (No such file or directory)
22:40:41.705122 openat(AT_FDCWD, "/run/systemd/transient/XD-Service.service.d", O_RDONLY|O_NONBLOCK|O_CLOEXEC|O_DIRECTORY) = -1 ENOENT (No such file or directory)
22:40:41.705217 openat(AT_FDCWD, "/etc/systemd/system/XD-Service.service.d", O_RDONLY|O_NONBLOCK|O_CLOEXEC|O_DIRECTORY) = -1 ENOENT (No such file or directory)
22:40:41.705720 openat(AT_FDCWD, "/run/systemd/system/XD-Service.service.d", O_RDONLY|O_NONBLOCK|O_CLOEXEC|O_DIRECTORY) = -1 ENOENT (No such file or directory)
22:40:41.705861 openat(AT_FDCWD, "/usr/local/lib/systemd/system/XD-Service.service.d", O_RDONLY|O_NONBLOCK|O_CLOEXEC|O_DIRECTORY) = -1 ENOENT (No such file or directory)
22:40:41.706002 openat(AT_FDCWD, "/usr/lib/systemd/system/XD-Service.service.d", O_RDONLY|O_NONBLOCK|O_CLOEXEC|O_DIRECTORY) = -1 ENOENT (No such file or directory)
# 此处都会打印
22:40:41.706785 access("/etc/rc.d/init.d/XD-Service", F_OK) = 0
22:40:41.706972 writev(2, [{iov_base="Synchronizing state of XD-Servic"..., iov_len=110}, {iov_base="\n", iov_len=1}], 2Synchronizing state of XD-Service.service with SysV service script with /usr/lib/systemd/systemd-sysv-install.
) = 111
22:40:41.708157 writev(2, [{iov_base="Executing: /usr/lib/systemd/syst"..., iov_len=66}, {iov_base="\n", iov_len=1}], 2Executing: /usr/lib/systemd/systemd-sysv-install enable XD-Service
) = 67
22:40:41.708525 rt_sigprocmask(SIG_SETMASK, ~[RTMIN RT_1], [], 8) = 0
22:40:41.708649 clone(child_stack=NULL, flags=CLONE_CHILD_CLEARTID|CLONE_CHILD_SETTID|SIGCHLD, child_tidptr=0x7f3862525c50) = 3139
22:40:41.709144 rt_sigprocmask(SIG_SETMASK, [], service XD-Service does not support chkconfig
NULL, 8) = 0
22:40:41.711291 --- SIGCHLD {si_signo=SIGCHLD, si_code=CLD_EXITED, si_pid=3139, si_uid=0, si_status=1, si_utime=0, si_stime=0} ---
22:40:41.711376 waitid(P_PID, 3139, {si_signo=SIGCHLD, si_code=CLD_EXITED, si_pid=3139, si_uid=0, si_status=1, si_utime=0, si_stime=0}, WEXITED, NULL) = 0
...
```

`strace -tt systemctl enable auditd.service`

```sh
22:59:07.967786 openat(3, "auditd.service.d", O_RDONLY|O_NOFOLLOW|O_CLOEXEC|O_PATH) = -1 ENOENT (No such file or directory)
22:59:07.967815 close(3)                = 0
22:59:07.967853 openat(AT_FDCWD, "/etc/systemd/system.control/auditd.service.d", O_RDONLY|O_NONBLOCK|O_CLOEXEC|O_DIRECTORY) = -1 ENOENT (No such file or directory)
22:59:07.967906 openat(AT_FDCWD, "/run/systemd/system.control/auditd.service.d", O_RDONLY|O_NONBLOCK|O_CLOEXEC|O_DIRECTORY) = -1 ENOENT (No such file or directory)
22:59:07.967942 openat(AT_FDCWD, "/run/systemd/transient/auditd.service.d", O_RDONLY|O_NONBLOCK|O_CLOEXEC|O_DIRECTORY) = -1 ENOENT (No such file or directory)
22:59:07.967984 openat(AT_FDCWD, "/etc/systemd/system/auditd.service.d", O_RDONLY|O_NONBLOCK|O_CLOEXEC|O_DIRECTORY) = -1 ENOENT (No such file or directory)
22:59:07.968013 openat(AT_FDCWD, "/run/systemd/system/auditd.service.d", O_RDONLY|O_NONBLOCK|O_CLOEXEC|O_DIRECTORY) = -1 ENOENT (No such file or directory)
22:59:07.968052 openat(AT_FDCWD, "/usr/local/lib/systemd/system/auditd.service.d", O_RDONLY|O_NONBLOCK|O_CLOEXEC|O_DIRECTORY) = -1 ENOENT (No such file or directory)
22:59:07.968097 openat(AT_FDCWD, "/usr/lib/systemd/system/auditd.service.d", O_RDONLY|O_NONBLOCK|O_CLOEXEC|O_DIRECTORY) = -1 ENOENT (No such file or directory)
22:59:07.968142 access("/etc/rc.d/init.d/auditd", F_OK) = -1 ENOENT (No such file or directory)
22:59:07.968194 newfstatat(AT_FDCWD, "/proc/1/root", {st_mode=S_IFDIR|0555, st_size=244, ...}, 0) = 0
22:59:07.968247 newfstatat(AT_FDCWD, "/", {st_mode=S_IFDIR|0555, st_size=244, ...}, 0) = 0
22:59:07.968311 newfstatat(AT_FDCWD, "/run/systemd/system/", {st_mode=S_IFDIR|0755, st_size=40, ...}, AT_SYMLINK_NOFOLLOW) = 0
22:59:07.968383 newfstatat(AT_FDCWD, "/run/systemd/system/", {st_mode=S_IFDIR|0755, st_size=40, ...}, AT_SYMLINK_NOFOLLOW) = 0
22:59:07.968426 geteuid()               = 0
22:59:07.968501 socket(AF_UNIX, SOCK_STREAM|SOCK_CLOEXEC|SOCK_NONBLOCK, 0) = 3
```

### 3.4. 源码对比

1、查看当前出问题环境的systemctl版本，下载对应tag的源码

```sh
[root@iZ2zebfcx8h2zfz7ieqaquZ init.d]# systemctl --version
systemd 239 (239-51.el8_5.2)
```

2、上述strace不明显，安装ltrace并结合源码跟踪

跟踪XD-Service服务

```sh
[root@iZ2zebfcx8h2zfz7ieqaquZ init.d]# ltrace -f systemctl enable XD-Service.service 
[pid 30827] setlocale(LC_ALL, "")                                                        = "en_US.UTF-8"
[pid 30827] log_parse_environment_realm(0, 0x7fa8ef19746c, 0, 0)                         = 0
[pid 30827] log_open(0x7fa8eeced157, 1, 0x7fa8eeced157, 23)                              = 0
[pid 30827] sigbus_install(0xffffffff, 0, 0x7fa8eeced157, 0)                             = 0
[pid 30827] isatty(1)                                                                    = 1
[pid 30827] strstr("systemctl", "halt")                                                  = nil
[pid 30827] strstr("systemctl", "poweroff")                                              = nil
[pid 30827] strstr("systemctl", "reboot")                                                = nil
[pid 30827] strstr("systemctl", "shutdown")                                              = nil
[pid 30827] strstr("systemctl", "init")                                                  = nil
[pid 30827] strstr("systemctl", "runlevel")                                              = nil
[pid 30827] getopt_long(3, 0x7ffcf245e3c8, "ht:p:alqfs:H:M:n:o:iTr", 0x55f3e4452740, nil) = -1
[pid 30827] dispatch_verb(3, 0x7ffcf245e3c8, 0x55f3e4451e80, 0 <unfinished ...>
[pid 30827] strv_skip(0x7ffcf245e3d0, 1, 0, 0x55f3e4454088)                              = 0x7ffcf245e3d8
[pid 30827] strv_length(0x7ffcf245e3d8, 0x7ffcf245de58, 0, 0x55f3e4454088)               = 1
[pid 30827] malloc(16)                                                                   = 0x55f3e54a2bf0
[pid 30827] is_path(0x7ffcf24605fa, 0x55f3e54a2c00, 0x55f3e54a2bf0, 0x55f3e54a2bf0)      = 0
[pid 30827] unit_name_mangle_with_suffix(0x7ffcf24605fa, 2, 0x55f3e4244d87, 0x55f3e54a2bf0) = 0
[pid 30827] getenv_bool(0x55f3e4244ff9, 0x55f3e54a2bf0, 19, 0)                           = 0xfffffffa
[pid 30827] strv_find(0x7ffcf245dd70, 0x7ffcf24605f3, 0x55f3e4244ff9, 25)                = 0x55f3e424696e
[pid 30827] lookup_paths_init(0x7ffcf245dd10, 0, 1, 0)                                   = 0
[pid 30827] endswith(0x55f3e54a2c10, 0x55f3e4244d87, 0, 0)                               = 0x55f3e54a2c1a
[pid 30827] path_is_absolute(0x55f3e54a2c10, 0x55f3e4244d87, 8, 7)                       = 0x55f3e54a2c00
[pid 30827] unit_file_exists(0, 0x7ffcf245dd10, 0x55f3e54a2c10, 7)                       = 1
[pid 30827] path_join(0, 0x55f3e4245020, 0x55f3e54a2c10, 10)                             = 0x55f3e54a2c90
[pid 30827] strlen("/etc/rc.d/init.d/XD-Service.serv"...)                                = 35
# 差异点，/etc/rc.d/init.d/下存在服务脚本
[pid 30827] access("/etc/rc.d/init.d/XD-Service", 0)                                     = 0
[pid 30827] log_get_max_level_realm(0, 0, 0x55f3e54a2c90, 0x7fa8ee43971b)                = 6
[pid 30827] log_internal_realm(6, 0, 0x55f3e4244a75, 6140Synchronizing state of XD-Service.service with SysV service script with /usr/lib/systemd/systemd-sysv-install.
)                               = 0
[pid 30827] basename("/etc/rc.d/init.d/XD-Service")                                      = "XD-Service"
[pid 30827] strv_join(0x7ffcf245dd90, 0x55f3e42471f9, 0, 0x8000000)                      = 0x55f3e54a4340
[pid 30827] log_get_max_level_realm(0, 0x55f3e54a2ca1, 10, 0x69767265532d4458)           = 6
[pid 30827] log_internal_realm(6, 0, 0x55f3e4244a75, 6157Executing: /usr/lib/systemd/systemd-sysv-install enable XD-Service
)                               = 0
[pid 30827] safe_fork_full(0x55f3e424503f, 0, 0, 37)                                     = 1
[pid 30827] wait_for_terminate_and_check(0x55f3e424504e, 0x786c, 1, 0 <unfinished ...>
[pid 30828] <... safe_fork_full resumed> )                                               = 0
[pid 30828] execv("/usr/lib/systemd/systemd-sysv-in"..., 0x7ffcf245dd90 <no return ...>
[pid 30828] --- Called exec() ---
[pid 30828] strrchr("/usr/lib/systemd/systemd-sysv-in"..., '/')                          = "/systemd-sysv-install"
[pid 30828] setlocale(LC_ALL, "")                                                        = "en_US.UTF-8"
[pid 30828] bindtextdomain("chkconfig", "/usr/share/locale")                             = "/usr/share/locale"
[pid 30828] textdomain("chkconfig")                                                      = "chkconfig"
[pid 30828] poptGetContext(0x55a3105c80a8, 3, 0x7fff5f51e978, 0x7fff5f51e640)            = 0x55a3116a29c0
```

跟踪auditd服务

```sh
[root@iZ2zebfcx8h2zfz7ieqaquZ init.d]# ltrace -f systemctl enable auditd.service 
[pid 16504] setlocale(LC_ALL, "")                                                        = "en_US.UTF-8"
[pid 16504] log_parse_environment_realm(0, 0x7f000ea5e46c, 0, 0)                         = 0
[pid 16504] log_open(0x7f000e5b4157, 1, 0x7f000e5b4157, 23)                              = 0
[pid 16504] sigbus_install(0xffffffff, 0, 0x7f000e5b4157, 0)                             = 0
[pid 16504] isatty(1)                                                                    = 1
[pid 16504] strstr("systemctl", "halt")                                                  = nil
[pid 16504] strstr("systemctl", "poweroff")                                              = nil
[pid 16504] strstr("systemctl", "reboot")                                                = nil
[pid 16504] strstr("systemctl", "shutdown")                                              = nil
[pid 16504] strstr("systemctl", "init")                                                  = nil
[pid 16504] strstr("systemctl", "runlevel")                                              = nil
[pid 16504] getopt_long(3, 0x7ffc854f2a68, "ht:p:alqfs:H:M:n:o:iTr", 0x5651ab9ce740, nil) = -1
[pid 16504] dispatch_verb(3, 0x7ffc854f2a68, 0x5651ab9cde80, 0 <unfinished ...>
[pid 16504] strv_skip(0x7ffc854f2a70, 1, 0, 0x5651ab9d0088)                              = 0x7ffc854f2a78
[pid 16504] strv_length(0x7ffc854f2a78, 0x7ffc854f24f8, 0, 0x5651ab9d0088)               = 1
[pid 16504] malloc(16)                                                                   = 0x5651ac4efbf0
[pid 16504] is_path(0x7ffc854f45fe, 0x5651ac4efc00, 0x5651ac4efbf0, 0x5651ac4efbf0)      = 0
[pid 16504] unit_name_mangle_with_suffix(0x7ffc854f45fe, 2, 0x5651ab7c0d87, 0x5651ac4efbf0) = 0
[pid 16504] getenv_bool(0x5651ab7c0ff9, 0x5651ac4efbf0, 15, 0)                           = 0xfffffffa
[pid 16504] strv_find(0x7ffc854f2410, 0x7ffc854f45f7, 0x5651ab7c0ff9, 25)                = 0x5651ab7c296e
[pid 16504] lookup_paths_init(0x7ffc854f23b0, 0, 1, 0)                                   = 0
[pid 16504] endswith(0x5651ac4efc10, 0x5651ab7c0d87, 0, 0)                               = 0x5651ac4efc16
[pid 16504] path_is_absolute(0x5651ac4efc10, 0x5651ab7c0d87, 8, 7)                       = 0x5651ac4efc00
[pid 16504] unit_file_exists(0, 0x7ffc854f23b0, 0x5651ac4efc10, 7)                       = 1
[pid 16504] path_join(0, 0x5651ab7c1020, 0x5651ac4efc10, 10)                             = 0x5651ac4f1080
[pid 16504] strlen("/etc/rc.d/init.d/auditd.service")                                    = 31
# 差异点，/etc/rc.d/init.d/下不存在服务脚本
[pid 16504] access("/etc/rc.d/init.d/auditd", 0)                                         = -1
[pid 16504] free(nil)                                                                    = <void>
[pid 16504] free(nil)                                                                    = <void>
[pid 16504] free(0x5651ac4f1080)                                                         = <void>
[pid 16504] lookup_paths_free(0x7ffc854f23b0, 7, 1, 0x5651ac4ea010)                      = 0
[pid 16504] running_in_chroot_or_offline(0x5651ab7c2968, 0x7ffc854f45f8, 0, 4)           = 0
[pid 16504] sd_booted(0xffffff9c, 0x7f000e5b55d8, 0, 0)                                  = 1
[pid 16504] getenv_bool(0x5651ab7c17e7, 0x7f000e5cd132, 0x7ffc854f23b0, 0)               = 0xfffffffa
[pid 16504] strv_find(0x7ffc854f27b0, 0x7ffc854f45f7, 0x5651ab7c17e7, 7)                 = 0
[pid 16504] getenv_bool(0x5651ab7c0a44, 0, 101, 0xfffffffd)                              = 0xfffffffa
[pid 16504] bus_connect_transport_systemd(0, 0, 0, 0x5651ab9d0098)                       = 0
[pid 16504] sd_bus_set_allow_interactive_authorization(0x5651ac4f23b0, 1, 0, 0x7f000dd10f0e) = 0
[pid 16504] polkit_agent_open(0, 1, 0x100040, 0x7f000dd10f0e)                            = 0
[pid 16504] sd_bus_message_new_method_call(0x5651ac4f23b0, 0x7ffc854f2518, 0x5651ab7c0ac7, 0x5651ab7c0aad) = 0
[pid 16504] sd_bus_message_append_strv(0x5651ac4f2c00, 0x5651ac4efbf0, 25, 0)            = 0
[pid 16504] sd_bus_message_append(0x5651ac4f2c00, 0x5651ab7c1a48, 0, 0x5651ac4ea010)     = 1
[pid 16504] sd_bus_message_append(0x5651ac4f2c00, 0x5651ab7c1a48, 0, 0)                  = 1
[pid 16504] sd_bus_call(0x5651ac4f23b0, 0x5651ac4f2c00, 0, 0x7ffc854f2530)               = 1
[pid 16504] sd_bus_message_read(0x5651ac4f32d0, 0x5651ab7c1a48, 0x7ffc854f24f4, 0)       = 1
[pid 16504] bus_deserialize_and_dump_unit_file_changes(0x5651ac4f32d0, 0, 0x7ffc854f2500, 0x7ffc854f2508) = 0
[pid 16504] getenv_bool(0x5651ab7c0a44, 0, 0, 0)                                         = 0xfffffffa
[pid 16504] polkit_agent_open(0x5651ab7c0a44, 0, 0x5651ab9d0090, 4)                      = 0
[pid 16504] sd_bus_message_new_method_call(0x5651ac4f23b0, 0x7ffc854f2440, 0x5651ab7c0ac7, 0x5651ab7c0aad) = 0
[pid 16504] sd_bus_call(0x5651ac4f23b0, 0x5651ac4f3710, 0xaba9500, 0x7ffc854f2450)       = 1
[pid 16504] sd_bus_message_unref(0x5651ac4f3710, 1, 0, 0)                                = 0
[pid 16504] sd_bus_error_free(0x7ffc854f2450, 1, 0, 0x5651ac4ea010)                      = 0
[pid 16504] sd_bus_error_free(0x7ffc854f2530, 1, 0, 0x5651ac4ea010)                      = 0
[pid 16504] sd_bus_message_unref(0x5651ac4f2c00, 1, 0, 0x5651ac4ea010)                   = 0
[pid 16504] sd_bus_message_unref(0x5651ac4f32d0, 2, 0x5651ac4f3710, 0x5651ac4ea010)      = 0
[pid 16504] unit_file_changes_free(0, 0, 0x5651ac5a2300, 0x5651ac4ea010)                 = 0
[pid 16504] strv_free(0x5651ac4efbf0, 0, 0x5651ac5a2300, 0x5651ac4ea010)                 = 0
[pid 16504] <... dispatch_verb resumed> )                                                = 0
[pid 16504] sd_bus_flush_close_unref(0, 4, 0, 0)                                         = 0
[pid 16504] sd_bus_flush_close_unref(0x5651ac4f23b0, 4, 0, 0)                            = 0
[pid 16504] pager_close(0x5651ac4f2ae0, 0, 0x7f000dfd2c20, 273)                          = 0
[pid 16504] ask_password_agent_close(0x5651ac4f2ae0, 0, 0x7f000dfd2c20, 273)             = 0
[pid 16504] polkit_agent_close(0, 0, 0x7f000dfd2c20, 273)                                = 0
[pid 16504] strv_free(0, 0, 0x7f000dfd2c20, 273)                                         = 0
[pid 16504] strv_free(0, 0, 0x7f000dfd2c20, 273)                                         = 0
[pid 16504] strv_free(0, 0, 0x7f000dfd2c20, 273)                                         = 0
[pid 16504] strv_free(0, 0, 0x7f000dfd2c20, 273)                                         = 0
[pid 16504] free(nil)                                                                    = <void>
[pid 16504] __cxa_finalize(0x5651ab9cd040, 0x5651ab9cd038, 1, 1)                         = 0x7f000dfd48f8
[pid 16504] +++ exited (status 0) +++
```

3、通过对比，可以看到最核心区别还是 /etc/init.d/下是否存在服务脚本的判断。其实上一小节的strace也能看到线索，但是不直观。ltrace跟踪库函数并结合源码，基本可以大概定位到源码位置，而后查问题就有头绪了。

根据报错快速找到位置：`with SysV service script`，调用栈：`enable_unit` -> 先调`enable_sysv_units(verb, names)`，再后续处理。里面判断没有sysv脚本或者sysv处理成功则返回0，继续执行；若找到sysv且执行失败，则整体报错退出。

```cpp
static int enable_unit(int argc, char *argv[], void *userdata) {
    ...
    // 先直接尝试sysv方式，里面判断没有sysv脚本或者sysv处理成功则返回0，继续执行；若找到sysv且执行失败，则整体报错退出
    r = enable_sysv_units(verb, names);
    if (r < 0)
        return r;
    
    if (install_client_side()) {
        UnitFileFlags flags;

        flags = args_to_flags();
        if (streq(verb, "enable")) {
                r = unit_file_enable(arg_scope, flags, arg_root, names, &changes, &n_changes);
                carries_install_info = r;
        } else if (streq(verb, "disable"))
        ...
    }
    ...
}

// 内部逻辑，判断
static int enable_sysv_units(const char *verb, char **args) {
    ...
    // 初始化paths里面sysv和systemd uint对应的各自路径
    r = lookup_paths_init(&paths, arg_scope, LOOKUP_PATHS_EXCLUDE_GENERATED, arg_root);
    ...
    while (args[f]) {
        ...
        // 找是否存在服务的systemd uint文件
        // 会遍历判断这些目录下：/etc/systemd/system、/run/systemd/system、/usr/local/lib/systemd/system、/usr/lib/systemd/system
        j = unit_file_exists(arg_scope, &paths, name);
        if (j < 0 && !IN_SET(j, -ELOOP, -ERFKILL, -EADDRNOTAVAIL))
                return log_error_errno(j, "Failed to lookup unit file state: %m");
        found_native = j != 0;

        // 这里是关键，下面对比CentOS7.7和CentOS8默认的systemd实现可以看到原因
        /* If we have both a native unit and a SysV script, enable/disable them both (below); for is-enabled,
         * prefer the native unit */
        if (found_native && streq(verb, "is-enabled"))
            continue;
        ...
        p = path_join(arg_root, SYSTEM_SYSVINIT_PATH, name);
        if (!p)
            return log_oom();

        p[strlen(p) - STRLEN(".service")] = 0;
        // 跟踪可知是/etc/init.d/软链接对应的真实目录下是否有服务脚本，有则当作找到了sysv入口，下面fork子进程进行处理
        found_sysv = access(p, F_OK) >= 0;
        if (!found_sysv)
            continue;

        if (!arg_quiet) {
            if (found_native)
                // 实际走了此处打印：Synchronizing state of XD-Service.service with SysV service script with /usr/lib/systemd/systemd-sysv-install.
                log_info("Synchronizing state of %s with SysV service script with %s.", name, argv[0]);
            else
                log_info("%s is not a native service, redirecting to systemd-sysv-install.", name);
        }

        if (!isempty(arg_root))
            argv[c++] = q = strappend("--root=", arg_root);

        argv[c++] = verb;
        argv[c++] = basename(p);
        argv[c] = NULL;

        l = strv_join((char**)argv, " ");
        if (!l)
            return log_oom();

        if (!arg_quiet)
            // 实际打印：Executing: /usr/lib/systemd/systemd-sysv-install enable XD-Service
            log_info("Executing: %s", l);

        j = safe_fork("(sysv-install)", FORK_RESET_SIGNALS|FORK_DEATHSIG|FORK_LOG, &pid);
        if (j < 0)
                return j;
        if (j == 0) {
            /* Child */
            // 子进程处理上述命令，/usr/lib/systemd/systemd-sysv-install实际是 chkconfig 的软链接
            execv(argv[0], (char**) argv);
            log_error_errno(errno, "Failed to execute %s: %m", argv[0]);
            _exit(EXIT_FAILURE);
        }
        ...
    }
    ...
}
```

4、进一步获取查看CentOS7.7默认的systemd对应源码，其版本为：v219

* 流程类似：`enable_unit`(systemctl.c) ->  `enable_sysv_units`(systemctl.c)，和高版本(V239)区别在于下面的`continue`条件

**streq(verb, "is-enabled")这个条件是v221(2015.6.19)新增的，之前只判断found_native为true就退出，之后版本只有`systemctl is-enabled`才走该`continue`逻辑，`enable/disable`则继续往下判断处理sysV**

所以CentOS7.7上，不管/etc/init.d/下的服务脚本里是否去掉`#chkconfig`标记，`systemctl enable/disable xxx.service`都不会走sysV处理；

而CentOS8或者其他使用>=V221版本systemctl的系统上，当sysV chkconfig脚本(位于/etc/init.d/)和systemd unit共存时，enable/disable都会走sysV处理。

```cpp
// enable_sysv_units函数逻辑

// v220及之前
if (found_native)
    continue;

// v221(2015.6.19)及之后，所以systemctl enabled在此之后会继续判断是否走sysV处理
if (found_native && streq(verb, "is-enabled"))
    continue;
```

5、为佐证上述定位结论，将/etc/init.d/下有问题的脚本移除，`mv /etc/init.d/XD-Service /etc/init.d/XD-Service_bak`

`systemctl enable XD-Service.service`设置自启动成功，且是通过systemd分支处理的。

## 4. 小结

1、为保持兼容性，/etc/init.d/下的服务脚本，必须保持chkconfig兼容性，`#chkconfig: 345 99 20`和`description: xxx`标记并不是可有可无的注释

2、最近用了2次阿里云抢占式ECS，各自1小时2C2G，花费 ¥ 150 - ¥ 149.97 = ¥ 0.03，特别方便

## 5. 参考

1、GPT
