---
layout: post
title: 从1万空文件占用空间大小看Linux文件系统结构
categories: 案例实验
tags: 存储
---

* content
{:toc}

当一个目录中包含1万个空文件时，目录会占用多大的空间？



## 1. 背景

项目中使用空文件来标记模块数量，正常情况下模块不会太多。但由于误用和边界限制不完备，标记空文件生成了1000万个而导致这个目录很大，且主备间会rsync同步该目录，进而导致系统资源异常。

本文结合实验和Linux文件系统的结构代码进行对照验证，小结以加深理解。

## 2. 相关知识

Linux 文件系统会为每个文件分配两个数据结构：索引节点（index node） 和 目录项（directory entry），它们主要用来记录文件的元信息和目录层次结构。

* 索引节点，也就是inode

    用来记录文件的元信息，比如 inode 编号、文件大小、访问权限、创建时间、修改时间、数据在磁盘的位置等等。索引节点是文件的唯一标识，它们之间一一对应，也同样都会被存储在硬盘中，所以索引节点同样占用磁盘空间。

* 目录项，也就是dentry

    用来记录文件的名字、索引节点指针以及与其他目录项的层级关联关系。多个目录项关联起来，就会形成目录结构，但它与索引节点不同的是，目录项是由内核维护的一个数据结构，不存放于磁盘，而是缓存在内存。

### 2.1. 查看inode使用

查看inode使用和空闲数量：

```sh
[root@localhost xd]# df -i
Filesystem                       Inodes IUsed     IFree IUse% Mounted on
/dev/mapper/VolGroup-lv_root   55304192 80470  55223722    1% /
```

创建一个目录dir_0_file(ext4文件系统)，在目录下创建10000个空文件后查看，占用了10001个inode(创建一个文件会消耗一个inode，创建一个目录也是占用1个inode)：

```sh
[root@localhost xd]# df -i
Filesystem                       Inodes IUsed     IFree IUse% Mounted on
/dev/mapper/VolGroup-lv_root   55304192 90471  55213721    1% /
```

查看该目录占用大小，占用159744：

```sh
[root@localhost xd]# ll
drwxr-xr-x. 2 root root 159744 Sep 12 11:29 dir_0_file
```

* 链接相关操作查看

    1、当一个文件拥有多个硬链接时，对文件内容修改，会影响到所有文件名

    2、删除一个文件名，不影响另一个文件名的访问，只会使得inode中的链接数减1

    3、不能对目录做硬链接

硬链接示例：

```sh
# ln对test.dat创建2个硬链接
[root@localhost xd]# ll
-rw-r--r--. 3 root root     20 Sep 12 11:23 test.dat
-rw-r--r--. 3 root root     20 Sep 12 11:23 test.link1
-rw-r--r--. 3 root root     20 Sep 12 11:23 test.link2

# stat查看，其Links为3
[root@localhost xd]# stat test.dat 
  File: ‘test.dat’
  Size: 20              Blocks: 8          IO Block: 4096   regular file
Device: fd01h/64769d    Inode: 22282244    Links: 3
Access: (0644/-rw-r--r--)  Uid: (    0/    root)   Gid: (    0/    root)
Context: system_u:object_r:home_root_t:s0
Access: 2023-09-12 11:23:26.461508472 +0800
Modify: 2023-09-12 11:23:17.601509000 +0800
Change: 2023-09-12 11:37:35.538457863 +0800
 Birth: -
```

### 2.2. ext文件系统

#### 2.2.1. ext4中inode和entry结构

基于linux-5.10内核代码查看相关定义。

```c
// fs/ext4/ext4.h
struct ext4_inode {
	__le16	i_mode;		/* File mode */
	__le16	i_uid;		/* Low 16 bits of Owner Uid */
	__le32	i_size_lo;	/* Size in bytes */
	__le32	i_atime;	/* Access time */
	__le32	i_ctime;	/* Inode Change time */
	__le32	i_mtime;	/* Modification time */
	__le32	i_dtime;	/* Deletion Time */
	__le16	i_gid;		/* Low 16 bits of Group Id */
	__le16	i_links_count;	/* Links count */
	...
	__le32	i_block[EXT4_N_BLOCKS];/* Pointers to blocks */
	__le32	i_generation;	/* File version (for NFS) */
	...
	__le32  i_version_hi;	/* high 32 bits for 64-bit version */
	__le32	i_projid;	/* Project ID */
};
```

* inode中不定义文件名，是在目录项结构(entry)中定义的

```c
// fs/ext4/ext4.h
#define EXT4_NAME_LEN 255

struct ext4_dir_entry {
    __le32  inode;          /* Inode number */
    __le16  rec_len;        /* Directory entry length */
    __le16  name_len;       /* Name length */
    char    name[EXT4_NAME_LEN];    /* File name */
};
```

* ext4里面文件长度宏定义最大长度为255，touch文件名最长只能255，超出会报错 "File name too long"

查看ext2里文件长度也是255

```c
// fs/ext2/ext2.h
// ext2_fs.h里定义了 #define EXT2_NAME_LEN 255，也是8字节+文件名
struct ext2_dir_entry_2 {
    __le32  inode;          /* Inode number */
    __le16  rec_len;        /* Directory entry length */
    __u8    name_len;       /* Name length */
    __u8    file_type;
    char    name[];         /* File name, up to EXT2_NAME_LEN */
};
```

#### 2.2.2. ext4下inode实验

* 当前目录：/log (mount查看为ext4文件系统：/dev/mapper/VolGroup-lv_log on /log type ext4)

    1) 空目录 ll查看大小： 4096 Sep 22 14:36 tmp (和xfs不同，在xfs上看空目录只占用了6字节)

    2) touch tmp/1，大小不变，还是4096

    3) touch tmp/222，大小不变，还是4096

    4) echo "xxx">tmp/3，还是4096

    5) touch 空文件，文件名128字节，还是4096

    6) 批量实验：touch 40个空文件，每文件名为100字节，从4096跳到12288(3个blocksize)(此时父目录ll看是不占空间的)

可用`dumpe2fs`查看ext2/3/4文件系统上的超级块和block组的信息(XFS族用 `xfs_info` 查看信息)

```sh
// blocksize:4096
[root@localhost xd]# dumpe2fs -h /dev/mapper/VolGroup-lv_log
dumpe2fs 1.42.9 (28-Dec-2013)
Filesystem volume name:   <none>
Last mounted on:          /log
Filesystem features:      has_journal ext_attr resize_inode dir_index filetype needs_recovery extent 64bit flex_bg sparse_super large_file huge_file uninit_bg dir_nlink extra_isize
Filesystem flags:         signed_directory_hash 
Default mount options:    user_xattr acl
Filesystem state:         clean
。。。
Inode count:              5996544
Block count:              23963648
Reserved block count:     1198182
Free blocks:              22636259
Free inodes:              5996151
First block:              0
Block size:               4096
```

### 2.3. xfs文件系统

#### 2.3.1. xfs下inode实验

查看xfs超级块信息

```sh
[root@localhost xd]# xfs_info /home
meta-data=/dev/mapper/centos-home isize=512    agcount=4, agsize=55582208 blks
         =                       sectsz=512   attr=2, projid32bit=1
         =                       crc=1        finobt=0 spinodes=0
data     =                       bsize=4096   blocks=222328832, imaxpct=25
         =                       sunit=0      swidth=0 blks
naming   =version 2              bsize=4096   ascii-ci=0 ftype=1
log      =internal               bsize=4096   blocks=108559, version=2
         =                       sectsz=512   sunit=0 blks, lazy-count=1
realtime =none                   extsz=4096   blocks=0, rtextents=0
```

* inode实验：当前目录为xfs文件系统(mount可查看，/dev/mapper/centos-home on /home type xfs)

    1) 空目录 ll查看大小： 6 Sep 21 10:34 tmp

    2) touch tmp/1，15 Sep 21 10:34 tmp (新增9字节：上述结构体中，8字节+1字节文件名)

    3) touch tmp/222，26 Sep 21 10:36 tmp (新增11字节：8字节+3字节文件名)

    4) echo "xxx">tmp/3，35 Sep 21 10:37 tmp (新增9字节，说明和文件内容无关，查看的目录大小只跟文件名长度有关系)

    5) touch 空文件，文件名128字节 (目录新增136字节：8字节+128文件名)

    6) 批量实验：touch 9个空文件，每文件名为10字节，理论新增长度 (8+10)*9 = 162字节 (查看目录大小，由35 -> 197，和理论一致)

#### 2.3.2. xfs on-disk结构

参考这个系列下的文章，跟着操作查看：[XFS的on-disk组织结构(2)——SuperBlock](https://zhuanlan.zhihu.com/p/352722394)

`xxd`是一个十六进制dump工具，可以将二进制文件转换为十六进制表示，并以可读的形式显示。xxd命令可用于显示文件内容、编辑文件等用途

```sh
[root@localhost xd]# echo "ab123" >xdtmp
[root@localhost xd]# xxd xdtmp 
0000000: 6162 3132 330a                           ab123.
```

* 获取磁盘上前面部分信息，`xxd -l $((8*4096)) -g 1 -a /dev/vdisk/vdisk0008 > xdtmp_xfs`

    此处只获取了AG部分长度数据

    `-l len` 输出<len>个字符后停止

    `-g bytes` 每<bytes>个字符(每两个十六进制字符或者八个二进制数字)之间用一个空格隔开

    `-a` 打开/关闭 autoskip: 用一个单独的 '*' 来代替空行。默认关闭

```sh
# xdtmp_xfs开始部分内容
0000000: 58 46 53 42    00 00 10 00    00 00 00 00 74 6c 25 56  XFSB........tl%V
0000010: 00 00 00 00    00 00 00 00    00 00 00 00 00 00 00 00  ................
0000020: 96 f6 5e 64    f1 6b 4b 17    a4 80 93 3f e4 f0 09 c0  ..^d.kK....?....
0000030: 00 00 00 00    40 00 00 07    00 00 00 00 00 00 00 60  ....@..........`
0000040: 00 00 00 00    00 00 00 61    00 00 00 00 00 00 00 62  .......a.......b
0000050: 00 00 00 01    0f ff ff ff    00 00 00 08 00 00 00 00  ................
0000060: 00 00 20 00    bc b5 10 00    02 00 00 08 00 00 00 00  .. .............
0000070: 00 00 00 00    00 00 00 00    0c 0c 09 03 1c 00 00 05  ................
0000080: 00 00 00 00    00 02 89 00    00 00 00 00 00 00 00 c0  ................
0000090: 00 00 00 00    45 e9 f1 ee    00 00 00 00 00 00 00 00  ....E...........
00000a0: ff ff ff ff    ff ff ff ff    ff ff ff ff ff ff ff ff  ................
00000b0: 00 00 00 00    00 00 00 04    00 00 00 00 00 00 00 00  ................
00000c0: 00 0c 10 00    00 00 10 00    00 00 01 8a 00 00 01 8a  ................
00000d0: 00 00 00 00    00 00 00 00    00 00 00 01 00 00 00 00  ................
00000e0: 73 02 d6 02    00 00 00 00    ff ff ff ff ff ff ff ff  s...............
00000f0: 00 00 00 8d    00 00 38 f8    00 00 00 00 00 00 00 00  ......8.........
0000100: 00 00 00 00    00 00 00 00    00 00 00 00 00 00 00 00  ................
*      
0001000: 58 41 47 46    00 00 00 01    00 00 00 00 0f ff ff ff  XAGF............
0001010: 00 00 00 04    00 00 00 05    00 00 00 00 00 00 00 01  ................
0001020: 00 00 00 01    00 00 00 00    00 00 00 00 00 00 00 03  ................
0001030: 00 00 00 04    0f fd bd 70    0e ff fe f8 00 00 00 00  .......p........
0001040: 96 f6 5e 64    f1 6b 4b 17    a4 80 93 3f e4 f0 09 c0  ..^d.kK....?....
```

xfs超级块结构定义：

```c
// fs/xfs/libxfs/xfs_format.h
typedef struct xfs_sb {
	uint32_t	sb_magicnum;	/* magic number == XFS_SB_MAGIC */
	uint32_t	sb_blocksize;	/* logical block size, bytes */
	xfs_rfsblock_t	sb_dblocks;	/* number of data blocks */
	xfs_rfsblock_t	sb_rblocks;	/* number of realtime blocks */
	xfs_rtblock_t	sb_rextents;	/* number of realtime extents */
	uuid_t		sb_uuid;	/* user-visible file system unique id */
	xfs_fsblock_t	sb_logstart;	/* starting block of log if internal */
	...
	uuid_t		sb_meta_uuid;	/* metadata file system unique id */
	/* must be padded to 64 bit alignment */
} xfs_sb_t;
```

* 对照代码和上述数据查看

    sb_magicnum `58 46 53 42`  XFSB (magic number，ASCII值为88 70 83 66)

    sb_blocksize `00 00 10 00` block大小4096字节

    sb_dblocks `00 00 00 00 74 6c 25 56` 当前的XFS的总大小，单位是block(十进制是：1953244502)

> 实际查看XFS的Superblock结构并不需要像上面那样，自己对着RAW格式的硬盘内容挨个对照，这里只是为了给读者一个硬盘如何存储文件系统数据的直观印象。实际上我们在调试时直接使用专业工具即可，如xfs_db。获取主superblock的内容只需要下述命令即可：

* `xfs_db -c "sb 0" -c "p" $your_xfs_dev` (注意要在没mount的时候才能查看)

    `-c`用于指定执行命令，可指定多个，依次执行后结束

    `-c "sb [agno]"` 查看指定AG(allocation group)里的超级块信息

    `-c "p/print"` 打印指定字段的值，未指定则打印当前结构中所有字段

* 也可以`xfs_db /dev/sdb`后进入交互式界面

```sh
[root@localhost ~]# xfs_db /dev/sdb
xfs_db> sb 0
xfs_db> p
magicnum = 0x58465342
blocksize = 4096
dblocks = 244190646
rblocks = 0
...
```

xfs相关初始化，相关概念后续深入：

```c
// fs/xfs/libxfs/xfs_ag.c
int xfs_ag_init_headers(
	struct xfs_mount	*mp,
	struct aghdr_init_data	*id)
{
    /* SB */
    /* AGF */
    /* AGFL */
    /* AGI */
    /* BNO root block */
    /* CNT root block */
    /* INO root block */
    /* FINO root block */
    ...
}
```

## 3. 小结

1. 实验对照了ext4和xfs文件系统的inode、dentry结构和空间占用(很早占坑最近重新实验了下)
2. 学习了xfs在磁盘上的结构，有点硬。。以后再深入

## 4. 参考

1. [新建一个空文件占用多少磁盘空间？](https://mp.weixin.qq.com/s/9YeUEnRnegplftpKlW4ZCA)
2. [说说文件系统](https://www.zhihu.com/column/zorrolang)
3. [XFS的on-disk组织结构(2)——SuperBlock](https://zhuanlan.zhihu.com/p/352722394)
