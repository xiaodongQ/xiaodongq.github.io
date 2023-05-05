---
layout: post
title: GitHub Pages及jekyll搭建博客
categories: 工具
tags: jekyll
---

* content
{:toc}

*本人博客clone自以下模板:*

一个淡雅简明的博客风格: [Gaohaoyang](https://github.com/Gaohaoyang/gaohaoyang.github.io.git)




**创建及使用过程中注意事项及遇到的问题**

1. 标签小于2时，构建失败Page build failed，本地jekyll错误信息：divided by 0 in index.html

    问题描述：[issues 26](https://github.com/Gaohaoyang/gaohaoyang.github.io/issues/26)

2. 博客配置中\n\n\n\n表示将上面的内容展示在Home文章简介中，回车符代表的符号可能导致展示失败。

    > 在atom中右下角可以查看回车符

    有必要弄清 LF 和 CRLF的区别: [CRLF和LF](http://blog.csdn.net/samdy1990/article/details/24314957)

    > CRLF->Windows style：
    CRLF表示句尾使用回车换行两个字符(即我们常在Windows编程时使用"\r\n"换行)

    > LF->Unix Style：
    LF表示表示句尾，只使用换行.

3. 添加第三方评论功能时，需先在相关网站注册站点才能使用(添加站点名)

    Disqus 或 多说 获取short_name，然后添加到_config.yml文件中

    访问 [Disqus](https://disqus.com/) 或 [多说](http://duoshuo.com/) 根据提示操作即可。

    disqus操作：选择"I want to install Disqus on my site" -> 设置Website Name为github博客的地址，设置shortname（该name用于博客模板中进行配置）

---

### jekyll安装 (*Windows环境*)

[jekyll初级入门-jekyll安装运行](http://www.thxopen.com/jekyll/2014/04/25/i-and-jekyll.html)

1. 下载自己对应系统的版本(ruby和devkit都装)
    Ruby 2.0.0-p451 (x64)
    DevKit-mingw64-64-4.7.2-20130224-1432-sfx.exe
2. 安装，目录中不要有空格！
3. 然后添加环境变量：
    RUBY_HOME   d:/tool/ruby
    ruby --version 查看是否安装好
4. 进入到devkit安装目录
    - 执行初始化命令 ruby dk.rb init, 执行完后可以看到有config.yml文件生成
    - 执行 ruby dk.rb install

> 到这里ruby的环境已经安装完毕，你可以查看相关信息，比如gem版本
    `gem --version`
> 本地安装了那些插件
    `gem list --local`

* 以上步骤安装完后，在命令行输入gem install jekyll，等待自动安装完成

    `成功之后，再输入jekyll --version查看版本`

 使用，建立第一个站点：

 > 在命令行下随便进入一个目录，这里假设是d:/,输入jekyll new myblog，这时会在该目录下生成一个myblog的文件夹，先不管，命令行进入该目录cd myblog，再输入jekyll serve ,这个时候打开浏览器访问http://localhost:4000

### 自己搭建jekyll结构

这里有各个目录和文件的用途，还有些具体的操作，适合手动操作一遍

[搭建一个免费的，无限流量的Blog----github Pages和Jekyll入门](http://www.ruanyifeng.com/blog/2012/08/blogging_with_jekyll.html)

### 更新博客框架

简化博客风格，借用[wenfh2020](https://wenfh2020.com/)的风格。

参考：[github + jekyll 搭建博客](https://wenfh2020.com/2020/02/17/make-blog/)