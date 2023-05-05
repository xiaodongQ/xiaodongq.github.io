---
layout: post
title: Vim插件配置
categories: Linux
tags: Vim
---

* content
{:toc}


## Vim

[Vim插件及配置](https://github.com/xiaodongQ/dot-vimrc)

自己用的配置，基于[humiaozuzu/dot-vimrc](https://github.com/humiaozuzu/dot-vimrc)的配置根据需要做了少量修改。

截图：
![Vim效果截图](http://7xsl51.com1.z0.glb.clouddn.com/Vim_screenshot.png)

截图中展示了Nerdtree, Tagbar, Tabbar, Ack。另外还有多种插件：代码编辑时补全代码及代码段、语法检查、快速跳转、快速注释、文件模糊查找、状态栏等等功能。配合快捷键特别好用。

在新机器配置时，步骤：

1. 下载配置

    `git clone https://github.com/xiaodongQ/dot-vimrc.git ~/.vim`

2. 下载配置管理插件Vundle

    `git clone https://github.com/gmarik/vundle.git ~/.vim/bundle/vundle`

3. 打开Vim窗口执行安装插件命令

    `:BundleInstall`

4. 已经可以用了，不过有些插件依赖于ack和ctags，进行安装(本人是Mac OS X系统)

    `brew install ack ctags               # OS X`


以下对插件做部分说明。

---

## 代码补全

* vim-snipmate和vim-snippets 生成代码片段

  [Vim的snipMate插件](http://ccvita.com/481.html)

  ```
  Bundle 'garbas/vim-snipmate'
  Bundle 'honza/vim-snippets'    
  "------ snipmate dependencies -------                                                          
  Bundle 'MarcWeber/vim-addon-mw-utils'
  Bundle 'tomtom/tlib_vim'
  ```

  (vim-snippets为代码块合集)
  vim-snipmate这个插件只用了一个键，就是TAB键，比如对一个C/C++文件，输入inc，再按TAB键，就会填充为#include <stdio.h>，同时stdio被选中，以备修改。还有其他的，如main+TAB, wh+TAB,do+TAB,for+TAB,forr+TAB,if+TAB……具体可以看snippets文件夹下的那些文件，比如c.snippets

* delimitMate 符号自动补全
    [VIM插件: DELIMITMATE[符号自动补全](http://www.wklken.me/posts/2015/06/07/vim-plugin-delimitmate.html)
* emmet-vim HTML代码简写
    [vim插件--emmet-vim](http://www.jianshu.com/p/ad8a6a786054)

* YouCompleteMe
  - Vim代码补全插件，支持基于语义的代码跳转，比ctags精确。可以基于clang为C/C+＋代码提供代码提示
* SuperTab
  - SuperTab使Tab快捷键具有更快捷的上下文提示功能。 也就是一种自动补全插件
* neocomplete
  - neocomplcache的下一代(fork的项目中用的是这个)
  - 需要 Vim 7.3.885+，编译vim时加上lua使能./configure --enable-luainterp=yes，再make && make install
    + 系统自带的lua没看到.h信息，./configure看lua相关的依赖项还是缺失的，make出来的程序看lua模块还是不可用
    + 手动安装一个lua程序，并指定路径
      * `wget http://www.lua.org/ftp/lua-5.3.4.tar.gz`，`make linux test`
      * [centos7源码编译安装lua:lua5.1升级lua5.3](https://blog.csdn.net/feinifi/article/details/80078721)
    + `./configure --enable-luainterp --enable-gui=no --without-x --enable-multibyte --with-lua-prefix=/usr/local`

## 快速跳转

* vim-matchit 标签跳转

    [VIM插件: MATCHIT[成对标签跳转]](http://www.wklken.me/posts/2015/06/07/vim-plugin-matchit.html)

    %跳转到匹配的标签(html,xml)

* vim-easymotion 快速跳转

    [VIM插件: EASYMOTION[快速跳转]](http://www.wklken.me/posts/2015/06/07/vim-plugin-easymotion.html)

    <leader>全局映射为,  用法<leader>j 根据出现的标号选择，进行向下跳转(另还有：,k ,w ,b)

## 快速编辑

* vim-surround 处理成对出现的“包围结构”

    [vim插件surround介绍](http://blog.codepiano.com/2013/08/12/vim-surround/)

* nerdcommenter 快速注释

    [VIM插件: NERDCOMMENTER[快速注释]](http://www.wklken.me/posts/2015/06/07/vim-plugin-nerdcommenter.html)

    <leader>cc   加注释
    <leader>cu   解开注释
    <leader>cs   优雅的添加注释。有一定格式的多行注释

    <leader>c<space>  加上/解开注释, 智能判断
    <leader>cy   先复制, 再注解(p可以进行黏贴)

* gundo.vim 查看文件历史内容

    [VIM插件: GUNDO[时光机]](http://www.wklken.me/posts/2015/06/13/vim-plugin-gundo.html)

* tabular 排版插件

    [Tabular: 在 Vim 中对齐文本](https://linuxtoy.org/archives/tabular.html)

    若想让其中的两行按等号对齐，则将光标定位到有等号的那行，执行 :Tab /= 即可。(Tab是手输不是tab键)
    :Tab /| 按|对齐

* vim-indent-guides 缩进显示，高亮缩进

    [每日vim插件--缩进显示vim-indent-guides](http://foocoder.com/2014/04/11/mei-ri-vimcha-jian-suo-jin-xian-shi-vim-indent-guides/)

    默认的快捷键是<Leader>ig,开关插件。若需启动就开启,只要设置：

    `let g:indent_guides_enable_on_vim_startup = 1`

    `let g:indent_guides_guide_size = 1 ` 设置宽度

## IDE特性

* nerdtree 树形目录
* TabBar buffer选项卡
* tagbar 大纲式导航
* ack.vim 全局搜索词

    比grep快很多

* ctrlp.vim 模糊查询定位文件
* vim-fugitive 在vim中直接使用git
* vim-go go语言插件(需要手动触发安装关联工具，如下)
  - 打开vim，输入执行`:GoInstallBinaries`，会自动安装go开发所需相关工具(会安装到GOPATH/bin，下面列出)
    + guru        godef     dlv       gotags     golangci-lint  golint
    + gopls       motion    gorename  impl       gomodifytags   asmfmt
    + gogetdoc    fillstruct  errcheck  iferr     goimports  keyify
  - vim-go安装完后，每次保存即会做语法检查和自动格式化
  - 设置 gocode的快捷键
    + `inoremap <c-e> <C-x><C-o>` go代码提示，ctrl+e(以前用习惯了source insight)就会提示补全，e.g. time.Sl，此时按下ctrl+e，会出现Sleep等选择项，非常方便
  - 可参考：[vim--golang开发配置](https://blog.csdn.net/linglongwunv/article/details/82531852)
* omni completion (不需要安装，原本的vim中就有，C的不用，C++的需要单独安装下)
  - 自动补全关键字
* `Bundle 'vim-scripts/a.vim'`  *.cpp 和 *.h 间切换
  - `nmap <Leader>ch :A<CR>` .vimrc中添加该快捷键配置，子窗口中显示 *.cpp 或 *.h
* `Bundle 'Mizuchi/STL-Syntax'` 增加对 STL\C++14等的C++语法高亮，e.g. `recursive_mutex`高亮
* `Bundle 'vim-scripts/OmniCppComplete'` 主要用于 C/C++ 代码补全，需要 ctag 支持
  - 可以设置自动生成ctag，否则需要手动执行ctags，`ctags -R --c++-kinds=+p --fields=+iaS --extra=+q`

*感谢作者，感谢开源世界*
