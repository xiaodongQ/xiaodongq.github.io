---
layout: post
title: 学习Linux存储IO栈（二） -- Linux文件系统层次和内核接口
categories: 存储
tags: 存储 IO
---

* content
{:toc}

梳理学习Linux文件系统层次和内核接口。



## 1. 背景

leveldb的学习梳理暂告一段落（还有不少东西没完结），继续看Linux存储IO栈。

上一篇：[学习Linux存储IO栈（一） -- 存储栈全貌图](https://xiaodongq.github.io/2024/07/11/linux-storage-io-stack/) 中，看了一下总体存储协议栈，本篇看下VFS和文件系统相关的内核代码逻辑。

主要参考下面文章，并结合内核代码（5.10.10版本）梳理学习：

* [read 文件一个字节实际会发生多大的磁盘IO？](https://mp.weixin.qq.com/s/vekemOfUHBjZSy3uXb49Rw)
* [7.1 文件系统全家桶](https://www.xiaolincoding.com/os/6_file_system/file_system.html)
* [write文件一个字节后何时发起写磁盘IO？](https://mp.weixin.qq.com/s/qEsK6X_HwthWUbbMGiydBQ)

*说明：本博客作为个人学习实践笔记，可供参考但非系统教程，可能存在错误或遗漏，欢迎指正。若需系统学习，建议参考原链接。*

## 2. 从一个问题开始

问题：read 文件一个字节实际会发生多大的磁盘IO？

### 2.1. IO栈简图

再看下IO栈的简图：

![Linux IO 栈的简化版](/images/2024-08-10-linux-io-stack-simple.png)

典型IO读写流程如下：

* 用户态程序通过`read`/`write`系统调用进行读写时，经过`VFS（Virtual File System，虚拟文件系统）`，
* 然后经过`Page Cache`（不指定`O_DIRECT`时，若指定则跳过），
* 到具体的文件系统（ext/xfs等）实现，而后以`bio`形式到通用块层，
* 经块调度后通过硬盘驱动写到具体硬盘介质（HDD/SSD）上，硬盘自身内部可能有自己的缓存（或者硬盘组RAID时，RAID控制器自身一般也有缓存）

下面看下上述各流程中，在内核中的相关定义。

## 3. VFS 虚拟文件系统

Linux 内核中，虚拟文件系统（VFS）是一个抽象层，提供一种统一的方式来处理不同类型的文件系统。

VFS中的几个核心结构：

* `super_block`：文件系统的超级块，包含文件系统类型、状态、块大小、根目录等信息。
    * 每个文件系统在挂载时都会有一个与之相关联的 `struct super_block`，用于管理文件系统的通用状态信息。
* `inode`：表示文件系统中的一个文件或目录，包含文件类型、权限、所有者信息、大小、时间戳以及指向数据块的指针等。
    * `struct inode` 提供了与文件相关的元数据。
* `dentry`：directory entry，目录中的一个条目，即目录与文件的映射关系，包含文件名和指向相应 `inode` 的指针。
    * `struct dentry` 主要用于路径解析，并实现了一个目录项的缓存机制，以提高访问效率。
* `file`：每个打开的文件在内核空间都有一个和这个数据结构相关的 `struct file`，包含文件偏移量、访问权限、指向 `dentry` 的指针等信息。
    * 该结构体用于跟踪进程打开的文件实例。

上述结构，`super_block`、`inode`、`file`均定义在 include/linux/fs.h 中， `dentry`定义在 include/linux/dcache.h 中。

此外还有`file_system_type`、`vfsmount`、`address_space`等，此处暂不做展开。

### 3.1. super_block

super_block定义如下，截取部分内容：

```cpp
// linux-5.10.10/include/linux/fs.h
struct super_block {
    struct list_head	s_list;		/* Keep this first */
    dev_t			s_dev;		/* search index; _not_ kdev_t */
    ...
    struct file_system_type	*s_type;
    // 超级块的操作接口
    const struct super_operations	*s_op;
    ...
};
```

超级块的操作接口`super_operations`也定义在include/linux/fs.h中，这里都只是函数指针：

```cpp
// linux-5.10.10/include/linux/fs.h
struct super_operations {
       struct inode *(*alloc_inode)(struct super_block *sb);
    ...
       void (*dirty_inode) (struct inode *, int flags);
    int (*write_inode) (struct inode *, struct writeback_control *wbc);
    int (*drop_inode) (struct inode *);
    ...
};
```

### 3.2. inode

inode定义截取部分内容：

```cpp
// linux-5.10.10/include/linux/fs.h
struct inode {
    umode_t			i_mode;
    unsigned short		i_opflags;
    ...
    // inode操作
    const struct inode_operations	*i_op;
    struct super_block	*i_sb;
    ...
```

对应的操作接口`inode_operations`也定义在include/linux/fs.h中：

```cpp
// linux-5.10.10/include/linux/fs.h
struct inode_operations {
    struct dentry * (*lookup) (struct inode *,struct dentry *, unsigned int);
    ...
    int (*create) (struct inode *,struct dentry *, umode_t, bool);
    int (*link) (struct dentry *,struct inode *,struct dentry *);
    int (*mkdir) (struct inode *,struct dentry *,umode_t);
    ...
};
```

### 3.3. file

file定义截取部分内容：

```cpp
// linux-5.10.10/include/linux/fs.h
struct file {
    union {
        struct llist_node	fu_llist;
        struct rcu_head 	fu_rcuhead;
    } f_u;
    struct path		f_path;
    struct inode		*f_inode;	/* cached value */
    // file对应操作
    const struct file_operations	*f_op;
    ...
};
```

file对应的不少操作就比较眼熟了：

```cpp
// linux-5.10.10/include/linux/fs.h
struct file_operations {
    struct module *owner;
    loff_t (*llseek) (struct file *, loff_t, int);
    ssize_t (*read) (struct file *, char __user *, size_t, loff_t *);
    ssize_t (*write) (struct file *, const char __user *, size_t, loff_t *);
    ssize_t (*read_iter) (struct kiocb *, struct iov_iter *);
    ...
    int (*open) (struct inode *, struct file *);
    int (*flush) (struct file *, fl_owner_t id);
    int (*release) (struct inode *, struct file *);
    ...
}
```

### 3.4. dentry

`dentry`则定义在include/linux/dcache.h中，定义截取部分内容如下：

```cpp
// linux-5.10.10/include/linux/dcache.h
struct dentry {
    ...
    struct dentry *d_parent;	/* parent directory */
    struct qstr d_name;
    struct inode *d_inode;
    ...
    // dentry对应操作
    const struct dentry_operations *d_op;
    struct super_block *d_sb;	/* The root of the dentry tree */
    ...
};
```

对应操作定义也在dcache.h中：

```cpp
// linux-5.10.10/include/linux/dcache.h
struct dentry_operations {
    int (*d_revalidate)(struct dentry *, unsigned int);
    int (*d_weak_revalidate)(struct dentry *, unsigned int);
    int (*d_hash)(const struct dentry *, struct qstr *);
    int (*d_compare)(const struct dentry *,
            unsigned int, const char *, const struct qstr *);
    int (*d_delete)(const struct dentry *);
    ...
};
```

## 4. Page Cache 页高速缓存

Page Cache用于加速文件系统访问，通过缓存磁盘数据来减少直接磁盘I/O操作，从而加速文件读取和写入。

我们在 [学习Linux存储IO栈（一） -- 存储栈全貌图](https://xiaodongq.github.io/2024/07/11/linux-storage-io-stack/) 中贴的耗时体感图，磁盘缓存命中时在`100微秒`内，磁盘连续读则在约`1ms`级别，随机读约`8ms`。

在 Linux 内核中，页面缓存由一系列 `struct page` 组成，每个页结构代表一个内存页，页面缓存通过这些页结构来管理和存储缓存的数据。

```cpp
// linux-5.10.10/include/linux/mm_types.h
struct page {
    unsigned long flags;		/* Atomic flags, some possibly updated asynchronously */
    union {
        struct {	/* Page cache and anonymous pages */
            struct list_head lru;
            // 页面缓存的核心结构，用于管理文件内容在内存中的表示。每个文件都拥有一个 `address_space` 结构，用来跟踪文件的数据在页面缓存中的位置。
            // 所属的地址空间
            struct address_space *mapping;
            pgoff_t index;
            unsigned long private;
        };
        struct {	/* page_pool used by netstack */
            dma_addr_t dma_addr;
        };
        struct {	/* slab, slob and slub */
            ...
            struct kmem_cache *slab_cache; /* not slob */
            ...
        }
        ...
    };
    union {		/* This union is 4 bytes in size. */
        atomic_t _mapcount;
        unsigned int page_type;
        unsigned int active;		/* SLAB */
        int units;			/* SLOB */
    };
    ...
};
```

## 5. 小结

学习梳理内核中文件系统相关的结构定义。

## 6. 参考

1、[read 文件一个字节实际会发生多大的磁盘IO？](https://mp.weixin.qq.com/s/vekemOfUHBjZSy3uXb49Rw)

2、[7.1 文件系统全家桶](https://www.xiaolincoding.com/os/6_file_system/file_system.html)

3、[write文件一个字节后何时发起写磁盘IO？](https://mp.weixin.qq.com/s/qEsK6X_HwthWUbbMGiydBQ)

4、GPT
