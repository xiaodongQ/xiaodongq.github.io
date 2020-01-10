---
layout: post
title: Windows利器Cmder&使用Markdown写博客
categories: 工具
tags: [Markdown,Cmder]
---

* content
{:toc}

介绍cmder、sublime、Markdown



## 工具

### Cmder

右键在当前位置打开终端，操作习惯跟linux终端差不了多少，可以使用大量linux命令，集成了grep、tar、curl等等工具。终于不用再忍受Windows的cmd了。*有一点不足的就是在我电脑上启动后加载比较慢，要等个7、8秒才能操作(之前的笔记了，慢的原因还不确定 20191103注)*(cmder_mini中执行find，与linux下有点差别，e.g. `find . -name "window*"` 执行报`拒绝访问 - .`和 `找不到文件 - -NAME`，要`find "-name" "*.go"`形式才执行正常)

参考：**[Win下必备神器之Cmder](http://www.jeffjade.com/2016/01/13/2016-01-13-windows-software-cmder/)**

* 部分设置
  - 颜色-取消不活动时褪色(个人习惯)
    + 设置方式：外观-滚动条-选择显示
* 终端中文乱码
  - 右下角->Settings(或者快捷键Win+Alt+P)->搜索框搜 chcp，添加`chcp 65001` `set LANG=zh_CN.UTF-8`->保存重启cmder即可
  - [cmder 中文乱码的解决方法](https://blog.csdn.net/lamp_yang_3533/article/details/79841328)

### Markdown

  之前在CSDN写博客的时候看到Markdown，排版格式挺好看的就用来写博客，也没有去看看它的语法，而一直以来都是在网页上选择各个组件拼出来一片博客，现在看之前的自己跟看猴子似的。其语法很直观，十分钟内就能操作熟悉了。

  这篇博客就是用Atom编辑器和Markdown语法来写的。前几天一直在折腾编辑Sublime和Atom编辑神器，在这几天的使用中发现确实很令人愉快。Sublime和Atom都有相关的使用插件，不过Sublime中对Markdown的语法高亮支持得不好，而Atom支持得很好，毕竟github上.md文件普遍；Atom中还支持实时预览，St中要到浏览器中才能够预览，所以还是推荐Atom来使用Markdown写东西。

  简书上这篇指南的图文排版都很好，跟着操作一遍差不多就能用了：  **[Markdown——入门指南](http://www.jianshu.com/p/1e402922ee32/)**

  更全的语法：
  **[Markdown 语法说明 (简体中文版)](http://www.appinn.com/markdown/#p)**

  这一篇比上一个看得舒服一些，直接看后面的Markdown：
  **[atom编辑器的使用和markdown基本语法](http://www.jianshu.com/p/f3fd881548ad)**

  *下面是几篇比较好的sublime和atom的Markdown相关文章*

  * St下Markdown使用：
  **[sublime text 2 下的Markdown写作](http://www.jianshu.com/p/378338f10263)**

#### sublime插件

 SideBarEnhancements     增强侧边栏

 SideBarFolders          标题栏添加管理文件夹功能

 Monokai Extended        比较丰富的markdown语法配色主题

 MarkdownPreview         在浏览器中浏览markdown文件

 Search Stack Overflow   在Sublime中打开浏览器搜索Stackoverflow

 BracketHighlighter      显示当前位置在哪个块中，高亮显示起止位置

 Compare Side-By-Side    文件比较

 terminal                右键在指定文件的路径打开terminal

参考：
 https://www.cnblogs.com/Alisa098/p/7458977.html

  * 若用Atom这几个插件都装上(同步滚动、图片链接管理、格式化表格)：

    **[Atom Markdown 相关插件](https://segmentfault.com/a/1190000004271747)**

***

### 踩过的坑

1. Atom里安装Package时，报编译有问题，有些包的依赖关系没有找到，还是用apm(atom package manager)(非War3概念..)来装插件方便。Atom安装时是自带有apm的，记得添加其路径到path环境变量。**因为环境变量未添加的问题导致一直以为还需要安装其他应用，apm的路径比较深：**

    `xxxxxx\atom\app-1.6.1\resources\app\apm\bin`

2. 今天添加path的时候把原本的path都覆盖掉了，找了一下Windows下面貌似也没有记录剪切板或者更新path的历史记录，后面就一个一个程序的路径给添进去了。

 *本博客介绍建立在操作系统为Windows背景下*
