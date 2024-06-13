---
layout: post
title: 记一次失败的/boot分区扩容
categories: Linux
tags: Linux
---

* content
{:toc}

CentOS的`/boot`分区空间不够用了，记录失败的扩容过程。



## 1. 背景

在“[eBPF学习实践系列（二） -- bcc tools网络工具集](https://xiaodongq.github.io/2024/06/10/bcc-tools-network/)”里，实验`tcpretrans`时想用`tc`构造重传的场景。需要安装`kernel-modules-extra`，提示`/boot`空间不够了，之前装系统只分配了220M左右。

于是准备进行扩容，虽然最终失败，但是熟练了操作，下一次装机能更快。。

## 2. 扩容过程

### 2.1. 扩容前情况

安装`kernel-modules-extra`，提示`/boot`空间不够了

```sh
[root@anonymous ➜ /boot ]$ df -h
Filesystem           Size  Used Avail Use% Mounted on
devtmpfs              16G     0   16G   0% /dev
tmpfs                 16G     0   16G   0% /dev/shm
tmpfs                 16G   17M   16G   1% /run
tmpfs                 16G     0   16G   0% /sys/fs/cgroup
/dev/mapper/cl-root   85G   47G   39G  55% /
/dev/mapper/cl-home   64G  833M   64G   2% /home
/dev/nvme0n1p6       219M  210M  9.1M  96% /boot
/dev/nvme0n1p1       256M   39M  218M  15% /boot/efi
tmpfs                3.1G     0  3.1G   0% /run/user/0
```

lsblk查看分区和LVM情况

```sh
[root@anonymous ➜ /var/crash ]$ lsblk 
NAME        MAJ:MIN RM   SIZE RO TYPE MOUNTPOINT
nvme0n1     259:0    0   477G  0 disk 
|-nvme0n1p1 259:1    0   260M  0 part /boot/efi
|-nvme0n1p2 259:2    0    16M  0 part 
|-nvme0n1p3 259:3    0   200G  0 part 
|-nvme0n1p4 259:4    0 125.7G  0 part 
|-nvme0n1p5 259:5    0  1000M  0 part 
|-nvme0n1p6 259:6    0   224M  0 part /boot
`-nvme0n1p7 259:7    0 149.8G  0 part 
  |-cl-root 253:0    0  84.8G  0 lvm  /
  |-cl-swap 253:1    0     1G  0 lvm  [SWAP]
  `-cl-home 253:2    0    64G  0 lvm  /home
```

fdisk 查看windows和CentOS双系统磁盘(一块512G固态硬盘)使用情况

```sh
[root@anonymous ➜ /boot ]$ fdisk -l
Disk /dev/nvme0n1: 477 GiB, 512110190592 bytes, 1000215216 sectors
Units: sectors of 1 * 512 = 512 bytes
Sector size (logical/physical): 512 bytes / 512 bytes
I/O size (minimum/optimal): 512 bytes / 512 bytes
Disklabel type: gpt
Disk identifier: B95E9484-333C-4235-8051-6D67EF703463

Device             Start        End   Sectors   Size Type
/dev/nvme0n1p1      2048     534527    532480   260M EFI System
/dev/nvme0n1p2    534528     567295     32768    16M Microsoft reserved
/dev/nvme0n1p3    567296  419997695 419430400   200G Microsoft basic data
/dev/nvme0n1p4 419997696  683593727 263596032 125.7G Microsoft basic data
/dev/nvme0n1p5 998166528 1000214527   2048000  1000M Windows recovery environment
/dev/nvme0n1p6 683593728  684052479    458752   224M Linux filesystem
/dev/nvme0n1p7 684052480  998166527 314114048 149.8G Linux LVM
```

### 2.2. 初步想法：/home保留60G，匀4G给/boot

备份数据并清理/home下的数据

```sh
mkdir /home_bak
cp -rf /home/* /home_bak
rm -rf /home/*
umount /home
```

查看LVM的VG，没有空余空间了：`Free  PE / Size       0 / 0`

```sh
[root@anonymous ➜ / ]$ vgdisplay 
  --- Volume group ---
  VG Name               cl
  System ID             
  Format                lvm2
  Metadata Areas        1
  Metadata Sequence No  4
  VG Access             read/write
  VG Status             resizable
  MAX LV                0
  Cur LV                3
  Open LV               2
  Max PV                0
  Cur PV                1
  Act PV                1
  VG Size               <149.78 GiB
  PE Size               4.00 MiB
  Total PE              38343
  Alloc PE / Size       38343 / <149.78 GiB
  Free  PE / Size       0 / 0   
  VG UUID               MuH9jx-91dN-e5Yp-Wddi-vdXy-LCBZ-NrFi4b
```

查看各个逻辑卷`LV`

```sh
[root@anonymous ➜ / ]$ lvdisplay 
  --- Logical volume ---
  LV Path                /dev/cl/swap
  LV Name                swap
  VG Name                cl
  LV UUID                GxDMFv-jqmV-kiY5-tpaw-dRuH-Jmbt-YQiN8k
  LV Write Access        read/write
  LV Creation host, time desktop-mme7h3a, 2023-04-15 15:12:16 +0800
  LV Status              available
  # open                 2
  LV Size                1.00 GiB
  Current LE             256
  Segments               1
  Allocation             inherit
  Read ahead sectors     auto
  - currently set to     8192
  Block device           253:1
   
  --- Logical volume ---
  LV Path                /dev/cl/home
  LV Name                home
  VG Name                cl
  LV UUID                tA30Vo-M6f8-6Sma-vuXb-Ahxr-cwad-RQhxSd
  LV Write Access        read/write
  LV Creation host, time desktop-mme7h3a, 2023-04-15 15:12:16 +0800
  LV Status              available
  # open                 0
  LV Size                63.99 GiB
  Current LE             16382
  Segments               1
  Allocation             inherit
  Read ahead sectors     auto
  - currently set to     8192
  Block device           253:2
   
  --- Logical volume ---
  LV Path                /dev/cl/root
  LV Name                root
  VG Name                cl
  LV UUID                k0MJa0-J1qH-5NTD-002y-PHDa-n0Px-LKa0I9
  LV Write Access        read/write
  LV Creation host, time desktop-mme7h3a, 2023-04-15 15:12:17 +0800
  LV Status              available
  # open                 1
  LV Size                <84.79 GiB
  Current LE             21705
  Segments               1
  Allocation             inherit
  Read ahead sectors     auto
  - currently set to     8192
  Block device           253:0
```

删除`/home`对应的LV

```sh
[root@anonymous ➜ / ]$ lvremove /dev/mapper/cl-home 
Do you really want to remove active logical volume cl/home? [y/n]: y
  Logical volume "home" successfully removed.
```

`lvdisplay`可以看到已经没有这个逻辑卷了

且VG里多了可用空间 `Free  PE / Size       16382 / 63.99 GiB`

```sh
[root@anonymous ➜ / ]$ vgdisplay 
  --- Volume group ---
  VG Name               cl
  System ID             
  Format                lvm2
  Metadata Areas        1
  Metadata Sequence No  5
  VG Access             read/write
  VG Status             resizable
  MAX LV                0
  Cur LV                2
  Open LV               2
  Max PV                0
  Cur PV                1
  Act PV                1
  VG Size               <149.78 GiB
  PE Size               4.00 MiB
  Total PE              38343
  Alloc PE / Size       21961 / <85.79 GiB
  Free  PE / Size       16382 / 63.99 GiB
  VG UUID               MuH9jx-91dN-e5Yp-Wddi-vdXy-LCBZ-NrFi4b
```

创建新的`home`逻辑卷：通过`vgs`查看卷组(`VG`)，并用`lvcreate`创建新的逻辑卷，空间用60G，预留3.99G

```sh
[root@anonymous ➜ / ]$ vgs
  VG #PV #LV #SN Attr   VSize    VFree 
  cl   1   2   0 wz--n- <149.78g 63.99g

[root@anonymous ➜ / ]$ lvcreate -L 60G -n home cl         
WARNING: xfs signature detected on /dev/cl/home at offset 0. Wipe it? [y/n]: y
  Wiping xfs signature on /dev/cl/home.
  Logical volume "home" created.
```

可看到VG里可用只有3.99G了，且多了`/dev/cl/home`这个LV

```sh
[root@anonymous ➜ / ]$ vgs
  VG #PV #LV #SN Attr   VSize    VFree
  cl   1   3   0 wz--n- <149.78g 3.99g
```

格式化LV，并挂载/home

```sh
[root@anonymous ➜ / ]$ mkfs -t xfs /dev/mapper/cl-home 
meta-data=/dev/mapper/cl-home    isize=512    agcount=4, agsize=3932160 blks
         =                       sectsz=512   attr=2, projid32bit=1
         =                       crc=1        finobt=1, sparse=1, rmapbt=0
         =                       reflink=1
data     =                       bsize=4096   blocks=15728640, imaxpct=25
         =                       sunit=0      swidth=0 blks
naming   =version 2              bsize=4096   ascii-ci=0, ftype=1
log      =internal log           bsize=4096   blocks=7680, version=2
         =                       sectsz=512   sunit=0 blks, lazy-count=1
realtime =none                   extsz=4096   blocks=0, rtextents=0
Discarding blocks...Done.

[root@anonymous ➜ / ]$ 
[root@anonymous ➜ / ]$ mount /dev/mapper/cl-home /home
```

可看到已经调整好`/home`的空间了，64G变成了60G。而后把数据还原回来。

```sh
[root@anonymous ➜ / ]$ df -h
Filesystem           Size  Used Avail Use% Mounted on
devtmpfs              16G     0   16G   0% /dev
tmpfs                 16G     0   16G   0% /dev/shm
tmpfs                 16G   17M   16G   1% /run
tmpfs                 16G     0   16G   0% /sys/fs/cgroup
/dev/mapper/cl-root   85G   47G   39G  56% /
/dev/nvme0n1p6       219M  210M  9.1M  96% /boot
/dev/nvme0n1p1       256M   39M  218M  15% /boot/efi
tmpfs                3.1G     0  3.1G   0% /run/user/0
/dev/mapper/cl-home   60G  461M   60G   1% /home

[root@anonymous ➜ / ]$
[root@anonymous ➜ / ]$ mv /home_bak/* /home/
```

### 2.3. Oops! 匀不了

上面多的3.99G，想分配给`/boot`，这是才注意到不在同一个分区的LVM上。。。

来都来了，就分配给`/`吧，用`lvextend`分配剩下的3.99G给`/`对应的VG。

```sh
[root@anonymous ➜ / ]$ lvextend -L +3.99G /dev/mapper/cl-root 
  Rounding size to boundary between physical extents: 3.99 GiB.
  Size of logical volume cl/root changed from <84.79 GiB (21705 extents) to <88.78 GiB (22727 extents).
  Logical volume cl/root successfully resized.
[root@anonymous ➜ / ]$ 
```

上面扩展了LV大小，文件系统是未感知到的。

几个LV分区都是xfs文件系统，用`xfs_growfs`扩展文件系统的空间，`df -h`查看`/`已经从85G变成89G了

```sh
[root@desktop-mme7h3a ➜ /root ]$ cat /etc/fstab 
/dev/mapper/cl-root     /                       xfs     defaults        0 0
UUID=e2dff41b-9fb8-4a28-bc72-e7505c5f291e /boot                   xfs     defaults        0 0
UUID=FE38-DB70          /boot/efi               vfat    umask=0077,shortname=winnt 0 2
/dev/mapper/cl-home     /home                   xfs     defaults        0 0
/dev/mapper/cl-swap     none                    swap    defaults        0 0

[root@anonymous ➜ / ]$ xfs_growfs /
meta-data=/dev/mapper/cl-root    isize=512    agcount=4, agsize=5556480 blks
         =                       sectsz=512   attr=2, projid32bit=1
         =                       crc=1        finobt=1, sparse=1, rmapbt=0
         =                       reflink=1
data     =                       bsize=4096   blocks=22225920, imaxpct=25
         =                       sunit=0      swidth=0 blks
naming   =version 2              bsize=4096   ascii-ci=0, ftype=1
log      =internal log           bsize=4096   blocks=10852, version=2
         =                       sectsz=512   sunit=0 blks, lazy-count=1
realtime =none                   extsz=4096   blocks=0, rtextents=0
data blocks changed from 22225920 to 23272448
[root@anonymous ➜ / ]$ 
[root@anonymous ➜ / ]$ df -h
Filesystem           Size  Used Avail Use% Mounted on
devtmpfs              16G     0   16G   0% /dev
tmpfs                 16G     0   16G   0% /dev/shm
tmpfs                 16G   17M   16G   1% /run
tmpfs                 16G     0   16G   0% /sys/fs/cgroup
/dev/mapper/cl-root   89G   47G   43G  53% /
/dev/nvme0n1p6       219M  210M  9.1M  96% /boot
/dev/nvme0n1p1       256M   39M  218M  15% /boot/efi
tmpfs                3.1G     0  3.1G   0% /run/user/0
/dev/mapper/cl-home   60G  804M   60G   2% /home
```

参考：[LVM----从CentOS7默认安装的/home中转移空间到根目录/](https://www.cnblogs.com/user-sunli/p/15484345.html)

虽然没成功，但上面的操作步骤实操了一把也不算白浪费。小结：

1、从lvm中某个lv释放空间给另一个lv

```sh
# mkdir /backup
# mv /home/* /backup/
# umount /home
# lvremove /dev/centos/home
# lvcreate -L 50G -n home cents
# mkfs -t xfs /dev/centos/home
# mv /backup/* /home/
# lvextend -L +xxxG /dev/centos/root
# xfs_growfs root
# rm -rf /backup
```

2、新盘做LVM，思路---PV----VG---LV

```sh
lsblk
##创建PV         
pvcreate /dev/sdb
##查看当前PV    
pvscan      或者      pvs
##创建VG
vgcreate   datevg   /dev/sdb          （datavg是起的VG名字）
##查看当前VG
vgscan
##加入新的PV到VG datevg
vgextend datevg /dev/sdc
#创建LV    
lvcreate -L 200M -n lv1 datavg     
(-L（指定lv的大小） 指定为200m     lv1为起的LV名字  从datevg里创建)
## 查看LV
lvscan      
/dev/datevg/lv1    200m
##格式化，创建文件系统挂载
mkfs.xfs /dev/datevg/lv1    或者    mkfs.ext4 /dev/datevg/lv1
mkdir /mnt/lv1   
##临时挂载
mount /dev/datevg/lv1  /mnt/lv1
mount -a
df -h    （df-Th）       加上TYPE 类型
LVM完成
```

### 2.4. Windows+CentOS双系统，从Windows匀一下

从windows上压缩空间分配给centos的 /boot (单独分区，没有在LVM里)

问GPT：

```sh
Q：假设你是linux系统专家，磁盘方面特别熟悉
Q：ssd上分了两个分区A和B，其中分区A建了lvm，怎么把lvm剩余的空间分配给B
    备份数据->缩小LVM逻辑卷->删除LVM卷组->重新分区
但是查了下xfs无法缩小卷
Q：lvreduce无法对xfs缩容吗
    lvreduce确实无法直接对XFS文件系统缩容。受限于XFS文件系统特性
    balabala...
Q：ssd上有windows和centos双系统，怎么从windows的分区分配空间给linux的分区
    备份数据->在Windows下缩小分区->在Linux下扩展分区
```

**开始操作：**

重启进入windows -> "此电脑"右键管理，进入"磁盘管理" -> 压缩磁盘，空4G出来

~~重启进入linux，新压缩的空间呢？被GPT坑了!~~ 压缩出来的空间还需要格式化成`NTFS`格式！(创建新卷格式化)

重启进入linux，可以看到4G空间了(`nvme0n1p4`)

```sh
[root@desktop-mme7h3a ➜ /root ]$ fdisk -l
...
Device             Start        End   Sectors   Size Type
/dev/nvme0n1p1      2048     534527    532480   260M EFI System
/dev/nvme0n1p2    534528     567295     32768    16M Microsoft reserved
/dev/nvme0n1p3    567296  411609087 411041792   196G Microsoft basic data
/dev/nvme0n1p4 411609088  419995647   8386560     4G Microsoft basic data
/dev/nvme0n1p5 419997696  683593727 263596032 125.7G Microsoft basic data
/dev/nvme0n1p6 683593728  684052479    458752   224M Linux filesystem
/dev/nvme0n1p7 684052480  998166527 314114048 149.8G Linux LVM
/dev/nvme0n1p8 998166528 1000214527   2048000  1000M Windows recovery environment
```

lsblk也能看到：

```sh
[root@desktop-mme7h3a ➜ /root ]$ lsblk 
NAME        MAJ:MIN RM   SIZE RO TYPE MOUNTPOINT
nvme0n1     259:0    0   477G  0 disk 
|-nvme0n1p1 259:1    0   260M  0 part /boot/efi
|-nvme0n1p2 259:2    0    16M  0 part 
|-nvme0n1p3 259:3    0   196G  0 part 
|-nvme0n1p4 259:4    0     4G  0 part 
|-nvme0n1p5 259:5    0 125.7G  0 part 
|-nvme0n1p6 259:6    0   224M  0 part 
|-nvme0n1p7 259:7    0 149.8G  0 part 
| |-cl-root 253:0    0  88.8G  0 lvm  /
| |-cl-swap 253:1    0     1G  0 lvm  [SWAP]
| `-cl-home 253:2    0    60G  0 lvm  /home
`-nvme0n1p8 259:8    0  1000M  0 part
```

格式化：`mkfs.xfs -f /dev/nvme0n1p4`

备份/boot数据，关闭挂载，重启系统

```sh
/dev/mapper/cl-root     /                       xfs     defaults        0 0
#UUID=e2dff41b-9fb8-4a28-bc72-e7505c5f291e /boot                   xfs     defaults        0 0 
UUID=FE38-DB70          /boot/efi               vfat    umask=0077,shortname=winnt 0 2
/dev/mapper/cl-home     /home                   xfs     defaults        0 0
/dev/mapper/cl-swap     none                    swap    defaults        0 0
```

删除4G分区和原来的/boot分区(224M，按提示的分区号来，此处分别为4和6)

```sh
[root@desktop-mme7h3a ➜ /root ]$ fdisk /dev/nvme0n1
Command (m for help): p
Device             Start        End   Sectors   Size Type
/dev/nvme0n1p1      2048     534527    532480   260M EFI System
/dev/nvme0n1p2    534528     567295     32768    16M Microsoft reserved
/dev/nvme0n1p3    567296  411609087 411041792   196G Microsoft basic data
/dev/nvme0n1p4 411609088  419995647   8386560     4G Microsoft basic data
/dev/nvme0n1p5 419997696  683593727 263596032 125.7G Microsoft basic data
/dev/nvme0n1p6 683593728  684052479    458752   224M Linux filesystem
/dev/nvme0n1p7 684052480  998166527 314114048 149.8G Linux LVM
/dev/nvme0n1p8 998166528 1000214527   2048000  1000M Windows recovery environment

# 删除分区
Command (m for help): d 
Partition number (1-8, default 8): 4

Partition 4 has been deleted.

Command (m for help): p
# 可看到结果里已经没有4G的分区了，略

# 查看空余
Command (m for help): F
Unpartitioned space /dev/nvme0n1: 4 GiB, 4294967296 bytes, 8388608 sectors
Units: sectors of 1 * 512 = 512 bytes
Sector size (logical/physical): 512 bytes / 512 bytes

    Start       End Sectors Size
411609088 419997695 8388608   4G

# 删除分区
Command (m for help): d
Partition number (1-3,5-8, default 8): 6

Partition 6 has been deleted.

# 保存退出
Command (m for help): w
The partition table has been altered.
Syncing disks.
```

创建新分区：

```sh
...
# 创建新分区
Command (m for help): n
Partition number (4,6,9-128, default 4): 6
First sector (411609088-1000215182, default 411609088): 
Last sector, +sectors or +size{K,M,G,T,P} (411609088-419997695, default 419997695): 

Created a new partition 6 of type 'Linux filesystem' and of size 4 GiB.
Partition #6 contains a xfs signature.

# 输y确认
Do you want to remove the signature? [Y]es/[N]o: y

The signature will be removed by a write command.

# 保存退出
Command (m for help): w
The partition table has been altered.
Syncing disks.
```

格式化`mkfs.xfs -f /dev/nvme0n1p6`，并查看lsblk

```sh
[root@desktop-mme7h3a ➜ /root ]$ lsblk -f
NAME        FSTYPE      LABEL     UUID                                   MOUNTPOINT
nvme0n1                                                                  
|-nvme0n1p1 vfat        SYSTEM    FE38-DB70                              /boot/efi
|-nvme0n1p2                                                              
|-nvme0n1p3 ntfs        Windows   2CAC3C7BAC3C419E                       
|-nvme0n1p5 ntfs        DATA1     1C823E3E823E1D28                       
|-nvme0n1p6 xfs                   e2dff41b-9fb8-4a28-bc72-e7505c5f291e   
|-nvme0n1p7 LVM2_member           PfPJxg-ZFLM-YSWj-hEr1-x7Mb-vpii-nlonSB 
| |-cl-root xfs                   564672f7-d5a7-424b-b6a0-5e265113b7d5   /
| |-cl-swap swap                  ca68fa0f-de7e-4645-8afa-5592011d5617   [SWAP]
| `-cl-home xfs                   f69bf04d-529f-47bc-a5aa-7dbce29d8825   /home
`-nvme0n1p8 ntfs        WinRE_DRV 5A783F01783EDB87
```

挂载/boot到新分区，还原数据，设置/etc/fstab自动挂载

```sh
[root@desktop-mme7h3a ➜ /root ]$ mount /dev/nvme0n1p6 /boot 
[root@desktop-mme7h3a ➜ /root ]$ df -h
Filesystem           Size  Used Avail Use% Mounted on
devtmpfs              16G     0   16G   0% /dev
tmpfs                 16G     0   16G   0% /dev/shm
tmpfs                 16G   17M   16G   1% /run
tmpfs                 16G     0   16G   0% /sys/fs/cgroup
/dev/mapper/cl-root   89G   47G   43G  53% /
/dev/mapper/cl-home   60G  804M   60G   2% /home
tmpfs                3.1G     0  3.1G   0% /run/user/0
/dev/nvme0n1p6       4.0G   61M  4.0G   2% /boot

[root@desktop-mme7h3a ➜ /root ]$ cp -rf /home/boot_bak/* /boot
[root@desktop-mme7h3a ➜ /root ]
[root@desktop-mme7h3a ➜ /root ]$ vi /etc/fstab 
[root@desktop-mme7h3a ➜ /root ]
```

重启系统，卧豁没起来。。。 (要去上班了，晚上继续)

## 3. 重装Linux系统

晚上下班回来，看PC已经找不到启动项了，先不折腾了。上次Rufus做的系统U盘还在，重新装CentOS系统。

进Windows把连续的卷空间还原回去(感觉之前不应该从C盘压缩空间，不连续)，删除掉CentOS的几个卷。

![磁盘空间图](/images/windows_centos_disk_volume.jpeg)

半小时左右装完。

1、设置免密登录 `ssh-copy-id -i ~/.ssh/id_rsa.pub root@192.168.1.150`

2、修改yum源为阿里云

/etc/yum.repos.d/下配置都移走

~~`curl -o /etc/yum.repos.d/CentOS-Base.repo http://mirrors.aliyun.com/repo/Centos-8.repo`~~

上面的yum源，下载的内核版本是`4.18.0-348.7.1.el8_5.x86_64`，而系统实际是`4.18.0-348.el8.x86_64`，小版本不一样，修改为下述源

```sh
[root@desktop-mme7h3a ➜ /root ]$ cat /etc/system-release
CentOS Linux release 8.5.2111

[root@desktop-mme7h3a ➜ /root ]wget -O /etc/yum.repos.d/CentOS-Base.repo https://mirrors.aliyun.com/repo/Centos-vault-8.5.2111.repo
```

`yum clean all; yum makecache`

3、安装oh-my-zsh、vim插件

## 4. 安装`kernel-modules-extra`

回归原始需求，把`tc`依赖的`kernel-modules-extra`装起来，看有91M左右

```sh
[root@desktop-mme7h3a ➜ /root ]$ yum install kernel-modules-extra
Failed to set locale, defaulting to C.UTF-8
Last metadata expiration check: 0:00:27 ago on Wed Jun 12 23:19:41 2024.
Dependencies resolved.
===============================================================================================
 Package                      Architecture   Version                        Repository    Size
===============================================================================================
Installing:
 kernel-core                  x86_64         4.18.0-348.7.1.el8_5           base          38 M
 kernel-modules               x86_64         4.18.0-348.7.1.el8_5           base          30 M
 kernel-modules-extra         x86_64         4.18.0-348.7.1.el8_5           base         7.6 M

Transaction Summary
===============================================================================================
Install  3 Packages

Total download size: 75 M
Installed size: 91 M
Is this ok [y/N]: 
```

小版本还是不对应，系统内核为：`4.18.0-348.el8.x86_64`，但是上面是`4.18.0-348.7.1.el8_5`。找了一圈yum源只有这个版本内核了。

```sh
[root@desktop-mme7h3a ➜ /etc/yum.repos.d ]$ uname -a
Linux desktop-mme7h3a 4.18.0-348.el8.x86_64 #1 SMP Tue Oct 19 15:14:17 UTC 2021 x86_64 x86_64 x86_64 GNU/Linux
```

默认内核调整成新装的版本，刚刚yum安装时好像自动就设置了，重启系统，看内核已经是新版本了。

```sh
[root@desktop-mme7h3a ➜ /root ]$ uname -a
Linux desktop-mme7h3a 4.18.0-348.7.1.el8_5.x86_64 #1 SMP Wed Dec 22 13:25:12 UTC 2021 x86_64 x86_64 x86_64 GNU/Linux
```

加载内核模块：`sch_netem`，加载成功。使用`tc`模拟丢包，成功

```sh
[root@desktop-mme7h3a ➜ /root ]$ modprobe sch_netem
[root@desktop-mme7h3a ➜ /root ]$ 
[root@desktop-mme7h3a ➜ /root ]$ tc qdisc add dev enp4s0 root netem loss 10%   
[root@desktop-mme7h3a ➜ /root ]$ tc qdisc show                              
qdisc noqueue 0: dev lo root refcnt 2 
qdisc netem 8002: dev enp4s0 root refcnt 2 limit 1000 loss 10%
[root@desktop-mme7h3a ➜ /root ]$ tc qdisc change dev enp4s0 root netem loss 20%
[root@desktop-mme7h3a ➜ /root ]$ tc qdisc show 
```

## 5. 小结

折腾了一下LVM操作，又重新装了一次机。

## 6. 参考

1、[LVM----从CentOS7默认安装的/home中转移空间到根目录/](https://www.cnblogs.com/user-sunli/p/15484345.html)

2、GPT
