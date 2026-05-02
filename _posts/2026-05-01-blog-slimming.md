---
title: 利用图片压缩、LFS和BFG对Git仓库进行瘦身
description: 通过图片压缩、Git LFS管理大文件、BFG清理Git历史，对博客Git仓库进行瘦身
categories: [工具和命令, Blog]
tags: [Git, GitHub, 博客]
---

## 1. 背景

博客用了几年下来，`images` 和 `.git` 越来越膨胀，克隆一次要好久，还占硬盘空间。这是当前仓库大小，已经370MB了。。

```sh
[MacOS-xd@qxd ➜ xiaodongQ.github.io git:(master) ✗ ]$ du -h -d1|sort -h
4.0K    ./.claude
4.0K    ./.github
4.0K    ./_draft
4.0K    ./_plugins
8.0K    ./.devcontainer
8.0K    ./_includes
8.0K    ./tools
 12K    ./.vscode
 16K    ./_tabs
 72K    ./_data
1.8M    ./assets
3.1M    ./_posts
166M    ./images
200M    ./.git
371M    .
```

主要问题在两个地方：
* `images/` 占了 166MB，积累下来的图片越来越多
* `.git/` 占了 200MB，历史里积累了很多大文件

折腾了下，把整个仓库从`371MB`瘦了下来，记录下措施和过程，其他大仓库理论上也可以进行操作参考。几个措施：
* PNG图片压缩：使用 `pngquant`，缩减png图片大小。效果：`90MB -> 28MB`。
* LFS图片存储：使用 `Git LFS` 追踪所有图片，clone时设置`GIT_LFS_SKIP_SMUDGE=1`。效果：图片`166MB -> 2.8M`（只保留了文件指针）
* Git历史清理：使用 `BFG Repo-Cleaner` 清理git历史中的大对象。效果：`171MB -> 94MB`

**先放结论：**

实践操作下来走了些弯路，其实使用LFS一项措施即可：设置LFS规则后，利用`git lfs migrate`配合`--everything`选项，对LFS所追踪文件的历史记录进行迁移，然后用`GIT_LFS_SKIP_SMUDGE=1 git clone`方式重新克隆仓库（LFS解决了图片管理问题后，图片压缩不是太必要；BFG也没必要）。

---

## 2. png图片压缩

`images` 里的图片占用比较大，用 [pngquant](https://pngquant.org/) 工具对PNG进行压缩。

```sh
  for f in images/*.png; do
      pngquant --quality=65-80 --force --output "$f" "$f"
  done

# 问题记录：
# 执行失败：pngquant --quality=65-80 --force images/2023-05-13-20230513075237.png
# 执行成功：pngquant --quality=65-80 --force --output images/2023-05-13-20230513075237.png images/2023-05-13-20230513075237.png
# 因此上面用`--output`指定路径
```

压缩png前后：

```sh
  ┌─────────┬───────┬────────────────┐
  │  指标    │ 之前  │      现在      │
  ├─────────┼───────┼────────────────┤
  │ images/ │ 166MB │ 102MB          │
  ├─────────┼───────┼────────────────┤
  │ 节省     │ -     │ 64MB (38%)     │
  ├─────────┼───────┼────────────────┤
  │ PNG     │ 90MB  │ ~28MB (压缩后) │
  └─────────┴───────┴────────────────┘

  # 压缩后的各部分大小：
  ┌──────────────┬────────┐
  │     类型      │  大小  │
  ├──────────────┼────────┤
  │ JPG/JPEG     │ ~2.3MB │
  ├──────────────┼────────┤
  │ SVG          │ ~72MB  │
  ├──────────────┼────────┤
  │ PNG (已压缩)  │ ~28MB  │
  ├──────────────┼────────┤
  │ 总计          │ ~102MB │
  └──────────────┴────────┘
```

---

## 3. 用Git LFS管理图片等大文件

`Git LFS`（`Large File Storage`，大文件存储），是Git官方出的工具，**专门解决：Git仓库因为图片、视频、压缩包等大文件，越用越大、克隆慢、卡死 的问题**。让大文件不塞进Git历史里，只存一个"链接"，仓库瞬间变轻。

**作用**：图片、抓包、压缩包等大文件不存入 Git 版本历史，仓库只存几行文本指针，真实大文件托管在 LFS 专属存储，从根源避免仓库膨胀、克隆变慢。

注意事项：
- GitHub 免费账户有 1GB LFS 存储额度
- 超过部分按量收费
- `.gitattributes` 必须推送到远程才能让所有协作者生效

### 3.1. 增加LFS追踪规则

```sh
# 1、添加LFS追踪规则
[root@xdlinux ➜ xiaodongq.github.io git:(master) ]$ git lfs track "*.png" "*.jpg" "*.jpeg" "*.gif" "*.svg" "*.cap" "*.pcap"
# 2、查看并确认内容
[root@xdlinux ➜ xiaodongq.github.io git:(master) ✗ ]$ cat .gitattributes
...
*.png filter=lfs diff=lfs merge=lfs -text
*.jpg filter=lfs diff=lfs merge=lfs -text
*.ico binary
*.jpeg filter=lfs diff=lfs merge=lfs -text
*.gif filter=lfs diff=lfs merge=lfs -text
*.svg filter=lfs diff=lfs merge=lfs -text
*.cap filter=lfs diff=lfs merge=lfs -text
*.pcap filter=lfs diff=lfs merge=lfs -text

# 3、添加并提交
git add .gitattributes
git commit -m "添加git lfs追踪类型，lfs管理图片"

# 4、推送到远程
git push

**LFS相关命令**：
* 查看LFS追踪的文件：`git lfs ls-files`
* 查看LFS存储量：`git lfs status`
* 查看LFS追踪规则：`git lfs track`

```sh
[root@xdlinux ➜ xiaodongq.github.io git:(master) ✗ ]$ git lfs track
Listing tracked patterns
    *.png (.gitattributes)
    *.jpg (.gitattributes)
    *.jpeg (.gitattributes)
    *.gif (.gitattributes)
    *.svg (.gitattributes)
    *.cap (.gitattributes)
    *.pcap (.gitattributes)
Listing excluded patterns
```

### 3.2. 历史图片迁移到LFS

操作步骤如下。

#### 3.2.1. git lfs migrate迁移

上面添加LFS追踪规则后，只影响后续新增或者修改的文件。已有的图片如果不做修改，需要主动迁移才能转到LFS管理。
* `git lfs track` 只对 **「发生变化的文件」**生效（如果修改的文件匹配到了追踪规则，则文件会自动变成LFS）
* 注意：若不加`--everything`参数，可能有些历史图片不会管理在LFS里

`git lfs migrate import --include="*.png,*.jpg,*.jpeg,*.gif,*.svg,*.cap,*.pcap" --everything`

迁移后，本地`.git`会膨胀，文件会修改：

```sh
[root@xdlinux ➜ xiaodongq.github.io git:(master) ✗ ]$ git status
Changes not staged for commit:
  (use "git add <file>..." to update what will be committed)
  (use "git restore <file>..." to discard changes in working directory)
        modified:   assets/img/favicons/favicon.svg
        modified:   images/2024-07-03-tcp-graph-tcptrace-detail.jpeg
        ...
[root@xdlinux ➜ xiaodongq.github.io git:(master) ✗ ]$ du -h -d1
# 之前是90MB左右
155M    ./.git
101M    ./images
...
261M    .
```

需要提交这些"修改"，步骤如下。

#### 3.2.2. git add -A添加所有文件

添加所有文件（这会用 LFS 指针替换实际文件）

```sh
# 该步不能缺少，在此之前，git lfs ls-files看不到LFS管理的文件
[root@xdlinux ➜ xiaodongq.github.io git:(master) ✗ ]$ git add -A

# 然后就可查看到LFS管理的文件了
[root@xdlinux ➜ xiaodongq.github.io git:(master) ✗ ]$ git lfs ls-files
4b15f617f5 * assets/img/favicons/favicon.svg
e63de17933 * images/2024-07-03-tcp-graph-tcptrace-detail.jpeg
24a1d5e5e0 * images/2024-07-21-leveldb-class-graph.svg

# 历史还是没变
[root@xdlinux ➜ xiaodongq.github.io git:(master) ✗ ]$ du -h -d1
155M    ./.git
101M    ./images
...
```

#### 3.2.3. git commit提交

```sh
[root@xdlinux ➜ xiaodongq.github.io git:(master) ✗ ]$ git commit -m "迁移现有图片到git LFS"
[master d58ec63] 迁移现有图片到git LFS
 95 files changed, 195 insertions(+), 62615 deletions(-)

# 历史还是没变
[root@xdlinux ➜ xiaodongq.github.io git:(master) ✗ ]$ du -h -d1
155M    ./.git
101M    ./images
...

# 查看LFS状态，有待push的对象
[root@xdlinux ➜ xiaodongq.github.io git:(master) ]$ git lfs status
On branch master
Objects to be pushed to origin/master:
    assets/img/favicons/favicon.svg (4b15f617f57b868da21f4bfadaca140542667a851d960e98e0230a4a1ea4e6d0)
    images/2024-07-03-tcp-graph-tcptrace-detail.jpeg (e63de179335389b6b8ba434d10fc9a5713ffbcee469429407afceaf4cf08cd4e)
    ...
```

#### 3.2.4. git push强制推送到远程

强制推送到远程，`git push --force-with-lease`

由于 `git lfs migrate import` 重写了 Git 历史（`commit hash` 全都变了），所以本地和远程已经"分叉"了，**必须force提交**。

`--force-with-lease` 是安全的强制推送，比 `--force` 更安全。（如果确定只有你一个人在用这个仓库，用 `--force` 也可以，效果一样）

```sh
  ┌────────────────────┬──────────────────────────────────────┬────────────────────┐
  │        参数         │                 行为                 │        风险         │
  ├────────────────────┼──────────────────────────────────────┼────────────────────┤
  │ --force            │ 无条件覆盖远程                         │ 可能丢失他人的提交    │
  ├────────────────────┼──────────────────────────────────────┼────────────────────┤
  │ --force-with-lease │ 检查远程是否有人更新过，没更新才推送       │ 避免覆盖他人提交      │
  └────────────────────┴──────────────────────────────────────┴────────────────────┘
```

```sh
[root@xdlinux ➜ xiaodongq.github.io git:(master) ]$ git push --force-with-lease
Uploading LFS objects: 100% (95/95), 78 MB | 4.0 MB/s, done.
Enumerating objects: 198, done.
Counting objects: 100% (198/198), done.
Delta compression using up to 16 threads
Compressing objects: 100% (101/101), done.
Writing objects: 100% (102/102), 14.26 KiB | 2.38 MiB/s, done.
Total 102 (delta 5), reused 0 (delta 0), pack-reused 0 (from 0)
remote: Resolving deltas: 100% (5/5), completed with 5 local objects.
To github.com:xiaodongQ/xiaodongq.github.io.git
   a56e390..d58ec63  master -> master
```

```sh
# 历史还是没变
[root@xdlinux ➜ xiaodongq.github.io git:(master) ✗ ]$ du -h -d1
155M    ./.git
101M    ./images
...

# LFS状态，已经没有待处理数据了
[root@xdlinux ➜ xiaodongq.github.io git:(master) ]$ git lfs status
On branch master
Objects to be pushed to origin/master:
Objects to be committed:
Objects not staged for commit:
[root@xdlinux ➜ xiaodongq.github.io git:(master) ]$

# 查看被LFS管理的文件
[root@xdlinux ➜ xiaodongq.github.io git:(master) ]$ git lfs ls-files
4b15f617f5 * assets/img/favicons/favicon.svg
e63de17933 * images/2024-07-03-tcp-graph-tcptrace-detail.jpeg
24a1d5e5e0 * images/2024-07-21-leveldb-class-graph.svg
...
```

#### 3.2.5. 重新git clone仓库，指定GIT_LFS_SKIP_SMUDGE=1

到新目录里重新git clone仓库，注意clone时设置下`GIT_LFS_SKIP_SMUDGE=1`，否则默认情况会下载lfs图片缓存。

如上一步`git push --force/--force-with-lease`所示，LFS 对象已经推送到了远程，但本地 `.git` 还有旧的悬空对象，需要重新clone仓库。

~~**试了下git gc，大小还是没变，需要重新clone项目。**~~
* ~~git reflog expire --expire=now --all~~
* ~~git gc --prune=now --aggressive~~

```sh
# 下面方式只给当前这一条git clone命令临时设置环境变量，克隆完就失效，不影响以后的Git操作。
# 不能分成2条分别执行（否则只定义了一个本地变量，git clone拿不到这个值）
[root@xdlinux ➜ workspace ]$ GIT_LFS_SKIP_SMUDGE=1 git clone git@github.com:xiaodongQ/xiaodongq.github.io.git
Cloning into 'xiaodongq.github.io'...
remote: Enumerating objects: 7049, done.
remote: Counting objects: 100% (3817/3817), done.
remote: Compressing objects: 100% (1892/1892), done.
remote: Total 7049 (delta 2052), reused 3574 (delta 1915), pack-reused 3232 (from 1)
Receiving objects: 100% (7049/7049), 3.58 MiB | 75.00 KiB/s, done.
Resolving deltas: 100% (4373/4373), done.
```

**大小只有11MB了**，`images`里只保留了图片的LFS的指针。

```sh
[root@xdlinux ➜ xiaodongq.github.io git:(master) ]$ du -h -d1
4.2M    ./.git
3.1M    ./_posts
2.8M    ./images
...
11M     .
```

查看其中的一张图片内容，里面只有一些元数据，包含lfs的地址、oid和大小：

```sh
[root@xdlinux ➜ images git:(master) ]$ cat wireshark-tcp-sack.svg
version https://git-lfs.github.com/spec/v1
oid sha256:6987f55fb8af61c99f9c9c74df586a18a23d364762ab2e95fe6b88ab0a0e0026
size 995001
```

后续若要下载LFS真实文件，则使用 `git lfs pull`

```sh
# images里可从大小看出来，文件指针还原为真实图片数据了
[root@xdlinux ➜ xiaodongq.github.io git:(master) ]$ du -h -d1
105M    ./.git
101M    ./images
...
211M    .

# .git里面可看到lfs缓存变大了
[root@xdlinux ➜ xiaodongq.github.io git:(master) ]$ du -h -d1 .git
101M    .git/lfs
...
105M    .git
```

### 3.3. 让GitHub Pages支持LFS

**问题**：查看我博客里面的文章，web页面上查看不了LFS管理的图片，但是在Git仓库里看图片是能正常访问的。

**原因**：`GitHub Actions` 工作流用的是 `actions/checkout@v4`（只是我当前的博客），但没有开启 LFS 支持，所以 CI 构建时把 LFS 指针文件当成了实际图片上传到 Pages。

**解决**：需要启用LFS，在`workflow`里加一行`lfs: true`。而后博客上访问图片正常了。

```sh
# .github/workflows/pages-deploy.yml
jobs:
  build:
    runs-on: ubuntu-latest

    steps:
      - name: Checkout
        uses: actions/checkout@v4
        with:
          fetch-depth: 0
          lfs: true
  ...
```

### 3.4. 问题答疑：开启LFS后，图片还在我的仓库里吗

文件目录结构、文件名都还在，本地正常预览、编辑；

只是 Git 仓库不存大图本体，只存指针，真实文件放在 LFS 后端存储，不会丢失、不影响使用。

### 3.5. 问题答疑：用了LFS，Markdown引用图片路径要改吗？

**完全不用改**。依旧用原有相对路径写法：`![](/images/xxx.png)`，LFS 只底层改存储逻辑，不改变项目文件路径、不影响博客图片渲染。

### 3.6. GIT_LFS_SKIP_SMUDGE变量说明和验证

`GIT_LFS_SKIP_SMUDGE=1` 是 Git LFS 的环境变量，作用是关闭 LFS 的 `smudge` 拉取行为。
* 默认情况下`git clone`时会将LFS的文件指针还原成真实文件，这个过程叫`smudge`濡染。
* 而`GIT_LFS_SKIP_SMUDGE=1`开启该变量时，克隆/切换分支只拉取LFS指针，不下载真实大文件。
* 单次生效：`GIT_LFS_SKIP_SMUDGE=1 git clone git@github.com:xxxxx`（不要分2条命令设置）

1、启用`GIT_LFS_SKIP_SMUDGE=1`的表现：

```sh
# `.git/lfs`目录里是LFS缓存，关闭smudge时里面只有文件地址
[root@xdlinux ➜ xiaodongq.github.io git:(master) ]$ du -h -d1 .git
0       .git/branches
84K     .git/hooks
4.0K    .git/info
3.9M    .git/objects
8.0K    .git/refs
12K     .git/logs
252K    .git/lfs
4.3M    .git
```

2、作为对比，clone时不指定`GIT_LFS_SKIP_SMUDGE=1`，默认会下载图片。可看到不加参数的话`images`和`.git`里还是很大：

```sh
[root@xdlinux ➜ xiaodongq.github.io_1508 git:(master) ]$ du -h -d1
107M    ./.git
101M    ./images
...
213M    .

# `.git/lfs`下面是LFS的缓存，不关闭smudge时里面有真实图片
[root@xdlinux ➜ xiaodongq.github.io_1508 git:(master) ]$ du -h -d1 .git
0       .git/branches
84K     .git/hooks
4.0K    .git/info
5.5M    .git/objects
8.0K    .git/refs
12K     .git/logs
101M    .git/lfs
107M    .git
```

若要一直关闭，可在`.bashrc`/`.zshrc`里设置变量：`export GIT_LFS_SKIP_SMUDGE=1`。
* 但是**不建议**，否则可能有坑：别人clone仓库后大文件正常，而自己只拉取下来了文件指针影响使用，还需要手动`git lfs pull`拉取一把。
* 一般只要在第一次`git clone`时临时指定即可，有需要可以主动拉取，让lfs还原成真实文件

典型使用场景：
* 内网 / 网速差环境：只需要代码逻辑，不需要大二进制资源，加速克隆
* CI / 编译构建：编译代码无需完整大素材，减小构建镜像体积
* 批量拉取多仓库：避免一次性下载海量 LFS 文件，节省磁盘与带宽

**其他一些变量：**
* `GIT_LFS_SKIP_PUSH=1`，关闭LFS文件上传，提交时只会把指针存入Git，禁止将大文件推送到LFS远端存储。即**只推 Git 指针，真实大文件永远留在本地，不上云端**。（感觉除了测试场景，一般不需要设置该参数）
* `GIT_LFS_CACHE_DIR`，自定义LFS本地缓存目录，默认在 `.git/lfs`。使用场景：多仓库共用一份LFS缓存，节省磁盘空间。（原理：LFS不是按仓库分文件，而是按 **文件哈希（SHA256）** 存储真实文件，**只要两个仓库里的文件内容完全一样**，它们的哈希就一模一样，只会**在全局缓存里存唯一一份**）

### 3.7. 问题答疑：不开启smudge克隆，提交新图片是自动到LFS里吗

是的，新图片一定会提交到 LFS，不会提交到 Git。

`GIT_LFS_SKIP_SMUDGE=1`只影响「下载」，不影响「上传」。LFS上传不是靠环境变量控制，而是靠`.gitattributes`文件控制，只要出现在列表里 = 100% 进 LFS，不会进 Git。

---

## 4. 利用BFG对.git历史瘦身

### 4.1. BFG工具介绍

利用`BFG`工具：[BFG Repo-Cleaner](https://rtyley.github.io/bfg-repo-cleaner/) 来处理git提交历史。

* git提供的`git filter-branch`命令，也可以批量重写 Git 仓库的提交历史；
* 而`BFG`更高效，官方介绍说要比 `git filter-branch` 快上`10~720`倍。
* 可了解：[清理.git文件夹过大出现臃肿问题-filter-branch和BFG工具 ](https://www.cnblogs.com/mq0036/p/17551073.html)。

用法：
* 1）到上述官网下载`bfg.jar`（java版本>=11，此处安装下java21）
* 2）而后`--mirror`拉取自己项目的`.git`文件, `--mirror`参数只拉取`.git`文件不克隆代码，防止操作失误修改项目代码。
* 3）`java -jar bfg.jar xxx`进行相应处理，可进行指向性查询和删除（**实用命令**：`git ls-tree -r -l HEAD | sort -k4 -rn | head -30`可以查看git历史里最大的30个历史对象）
* 4）`git push`推送到远程

### 4.2. 实际操作

实际操作：（**特别注意：先备份一份原仓库到其他目录，以便处理有问题时可以提交恢复**）

```sh
# 1. 克隆镜像
git clone --mirror git@github.com:xiaodongQ/xiaodongq.github.io.git /home/xd_blog_mirror

[root@xdlinux ➜ xd_blog_mirror git:(master) ]$ du -sh /home/xd_blog_mirror
171M    /home/xd_blog_mirror
# cp /home/workspace/local/bfg-1.15.0.jar bfg.jar
# [root@xdlinux ➜ xd_blog_mirror git:(master) ]$ du -sh
# 185M    .

# 2. 删除历史中大于 100KB 的文件
# （BFG 开始扫描并删除Git里的commit历史，此时大小还不会变）（只删历史，不删当前最新的文件）
java -jar bfg.jar --strip-blobs-bigger-than 100K /home/xd_blog_mirror
# 执行很快，执行后会生成报告
# In total, 2648 object ids were changed. Full details are logged here:
#     /home/xd_blog_mirror.bfg-report/2026-05-01/19-20-14
# [root@xdlinux ➜ xd_blog_mirror git:(master) ]$ du -sh /home/xd_blog_mirror
# 198M    /home/xd_blog_mirror

# 3. 进入镜像目录清理
cd /home/xd_blog_mirror

# 4. 清理悬空引用（把BFG删掉的文件真正从磁盘上清除，让仓库体积变小。这步是真正物理删除、压缩仓库）
# 清空 Git 的操作日志（reflog），让被删除的文件 / 历史彻底失去引用，变成无人指向的垃圾数据
git reflog expire --expire=now --all
# Git 垃圾回收，真正从磁盘上删除垃圾数据，并强力压缩仓库，让仓库体积真正变小
git gc --prune=now --aggressive

# 5. 查看清理后大小
[root@xdlinux ➜ xd_blog_mirror git:(master) ]$ du -sh /home/xd_blog_mirror
94M     /home/xd_blog_mirror

# 6. 确认无误后强制推送
git push --force
```

**注意**：需要重新clone下仓库。

### 4.3. 问题答疑：BFG清理Git历史后，大文件还在吗？

BFG **只清理Git历史版本**（`.git`）里的大文件，**当前分支最新代码里的图片 / 文件完全保留**；

清理后再配合 `git reflog expire + git gc`，才能真正回收磁盘空间、缩小仓库体积。

示例说明：
* BFG 清理 `>100KB` 图片后，BFG不会删除你现在工作区里的文件，你现在能看到的 `.png/.jpg` 完全不受影响。只是无法从`.git`旧版本还原那些大图片。
* 注意区分：正常删除文件（`git rm + commit`），历史可见，也是**可以回退**的，只有把历史记录删除才回退不了。

### 4.4. 问题答疑：mirror仓库里清理force push了，本地仓库pull后为什么还是很大

`git gc` 只能清理无用文件，不能删除旧历史，**需要重新clone项目**。

---

## 5. 最终效果和建议

瘦身前：

```sh
[MacOS-xd@qxd ➜ xiaodongQ.github.io git:(master) ✗ ]$ du -h -d1|sort -h
3.1M    ./_posts
166M    ./images
200M    ./.git
371M    .
```

瘦身后：

```sh
[root@xdlinux ➜ xiaodongq.github.io git:(master) ]$ du -h -d1
4.2M    ./.git
3.1M    ./_posts
2.8M    ./images
...
11M     .
```

仓库从原来的`371MB`变成了`11MB`（LFS所管理的文件只clone文件指针），克隆和更新都飞快。若本地需要使用图片，`git lfs pull`进行拉取即可（下面是lfs pull之后，`211M`相对之前也还是下降不少）。

```sh
[root@xdlinux ➜ xiaodongq.github.io git:(master) ]$ du -h -d1
105M    ./.git
101M    ./images
...
211M    .
```

针对我自己的个人博客场景，只需要博客主页能访问图片即可，本地不需要历史的那些原始图片。`GitHub Actions`工作流使用的`actions/checkout@v4`里，加一行`lfs: true`启用LFS支持，就可以上传LFS对应的实际图片到Pages了。
