---
title: GitHub Pages及jekyll搭建博客
categories: 工具
tags: jekyll
---

使用GitHub Pages和jekyll搭建个人博客。

### 1. 遇到的问题

博客最初clone自以下模板：

一个淡雅简明的博客风格: [Gaohaoyang](https://github.com/Gaohaoyang/gaohaoyang.github.io.git)

创建及使用过程中注意事项及遇到的问题：

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

4. gitalk配置repo时，提示"ERROR: NOT FOUND"，去掉`repo: 'xiaodongq.github.io/'`中的`/`后正常

---

### 2. jekyll安装 (*Windows环境*)

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

### 3. 自己搭建jekyll结构

这里有各个目录和文件的用途，还有些具体的操作，适合手动操作一遍

[搭建一个免费的，无限流量的Blog----github Pages和Jekyll入门](http://www.ruanyifeng.com/blog/2012/08/blogging_with_jekyll.html)

### 4. 2023更新博客框架

简化博客风格，借用[wenfh2020](https://wenfh2020.com/)的风格。
![示例](/images/2023-05-05-21-51-21.png)

参考：[github + jekyll 搭建博客](https://wenfh2020.com/2020/02/17/make-blog/)

### 5. 2025更新博客框架

原有框架的翻页和搜索不大好用，前端不大懂（后续考虑折腾一下），换一个现有的模板。

主题：[jekyll-theme-chirpy](https://github.com/cotes2020/jekyll-theme-chirpy)，里面有几篇示例文章介绍了效果和写博客的语法。

[博客主页](https://chirpy.cotes.page/)

效果很丰富，可以参考中文博客：[文本和排版](https://pansong291.github.io/chirpy-demo-zhCN/posts/text-and-typography/)，[对应仓库](https://github.com/pansong291/chirpy-demo-zhCN)

图标修改，生成网站: [icon-batch](https://lzltool.cn/icon-batch)、
[realfavicongenerator](https://realfavicongenerator.net/)

#### 5.1. 博客头部结构修改

1、博客头部结构

有差异，若有多个标签，需要修改为 `[tag1, tag2]` 方式；

分类最多 2 ~~个~~ **层**，如果分层则用`[]`

1）原来的

```
---
layout: _posts
title: CPU及内存调度（三） -- 内存问题定位工具和实验
categories: CPU及内存调度
tags: 内存
---

* content
{:toc}

介绍内存问题定位工具并进行相关实验：Valgrind Massif、AddressSanitizer、Memory Leak and Growth火焰图 和 bcc中内存相关的工具。



## 1. 背景
...
```

2）新结构，默认的layout就为`post`，不用显式指定layout。

* 可以指定`date`，显示博文的`创建日期`和`创建时间`，不指定则会取文件名的日期，时间则默认0点。
    * 会自动显示博文的`修改日期`
* categories和tag，可以用`[]`包裹，也可不用，不用时表示一个成员
    * categories里表示层级目录，最多2级。比如：`categories: [后端, 分布式]`，则会到`后端/分布式`分类里，可能有其他分类，如`后端/数据库`
    * 标签则可用`[]`指定多个，每个里面可以有空格。虽然建议小写但中文和部分术语还是无法统一小写，不全小写也不影响

```
---
title: TITLE
date: YYYY-MM-DD HH:MM:SS +/-TTTT
categories: [TOP_CATEGORIE, SUB_CATEGORIE]
tags: [TAG1, TAG2]     # TAG names should always be lowercase
---

简短描述xxx

## 章节1
...
```

示例：

```yml
---
title:      "xxxxxx"
date:       2024-06-05
# 归类在：xxx1/xxx2，不分层则可 categories: xxx1
categories: [xxx1,xxx2]
tag: [xxx1,xxx2,xxx3]
math: true
description: xxxxxxx
comments: true
---
```

#### 5.3. git 提交要求

github workflow里会检查提交log的规范性：

`- uses: wagoid/commitlint-github-action@v6`

`feat, fix, docs, style, refactor, test, chore`

```sh
feat: note
xxx
```

#### 5.4. 显示提示效果

引用后面加：`{: .prompt-tip }`、`{: .prompt-info }`、`{: .prompt-warning }`、`{: .prompt-danger }`

```md
> The posts' _layout_ has been set to `post` by default, so there is no need to add the variable _layout_ in the Front Matter block.
{: .prompt-tip }
```

```md
> An example showing the `tip` type prompt.
{: .prompt-tip }

> An example showing the `info` type prompt.
{: .prompt-info }

> An example showing the `warning` type prompt.
{: .prompt-warning }

> An example showing the `danger` type prompt.
{: .prompt-danger }
```

#### 5.5. 设置图片宽度和高度

`![Desktop View](/assets/img/favicons/sample/mockup.png){: width="700" height="400" }`，也可缩写`w=`、`h=`

#### 5.6. 图片位置

默认情况下，图片居中，可以使用 `normal`、`left` 和 `right` 类之中的一个指定位置

正常位置：`![Desktop View](/assets/img/favicons/sample/mockup.png){: .normal }`

向左对齐：`![Desktop View](/assets/img/favicons/sample/mockup.png){: .left }`

向左浮动：可以实现图在左侧，右侧是文字的效果：

`![Desktop View](/assets/img/favicons/sample/mockup.png){: width="972" height="589" .w-50 .left}`

向右浮动：可以实现图在右侧，左侧是文字的效果：

`![Desktop View](/assets/img/favicons/sample/mockup.png){: width="972" height="589" .w-50 .right}`

> 指定位置后，不应添加图片标题。

#### 5.7. 深色/浅色模式、阴影

`light`/`dark`指定深浅，在切换主题时，图片也会有不同效果

`![Light mode only](/path/to/light-mode.png){: .light }`

![Desktop View](/assets/img/favicons/sample/mockup.png){: .shadow }

#### 5.8. 置顶帖子

可以将一个或多个帖子置顶到首页，置顶的帖子会根据其发布日期以相反的顺序排序

```
---
pin: true
---
```

#### 5.9. 隐藏代码块行号

可以隐藏行号：`.nolineno`

```shell
echo 'No more line numbers!'
```
{: .nolineno }

#### 5.10. 脚注

`footnote[^footnote]`形式：

```
Click the hook will locate the footnote[^footnote], and here is another footnote[^fn-nth-2].
```

在文章最后：

```
[^footnote]: The footnote source
[^fn-nth-2]: The 2nd footnote source
```

#### 5.11. 链接

除了 `[]()` 形式，还可以：

`<http://127.0.0.1:4000>`


#### 5.12. 列表

主要是其中的`待办列表`，可以展示勾选框：

```
### Ordered list

1. Firstly
2. Secondly
3. Thirdly

### Unordered list

- Chapter
  - Section
    - Paragraph

### ToDo list

- [ ] Job
  - [x] Step 1
  - [x] Step 2
  - [ ] Step 3
```

#### 5.13. 描述列表

会避免展示成 `* xxx` 里面的缩进形式

```
Sun
: the star around which the earth orbits

Moon
: the natural satellite of the earth, visible by reflected light from the sun
```

#### 5.14. 安装Giscus 评论系统

参考：[Hugo 博客引入 Giscus 评论系统](https://www.lixueduan.com/posts/blog/02-add-giscus-comment/)

配置到 _config.yml 的 giscus

#### 5.15. cdn加速

jsDeliver

#### 5.16. 网站数据统计

page view和分析，使用：[goatcounter](https://www.goatcounter.com/)

统计见：[xd goatcounter](https://xiaodongq.goatcounter.com/)

#### 5.17. markdown解析器：kramdown

kramdown 是一个用 Ruby 实现的 Markdown 的解析器，Jekyll默认就是使用kramdown。

介绍：[kramdown Documentation](https://kramdown.gettalong.org/documentation.html)

支持的语法：[kramdown Syntax](https://kramdown.gettalong.org/syntax.html)，支持内容比较丰富，比如数学公式、脚注（`footnote[^footnote]`，`[^footnote]: xxx`）。

#### 5.2. 个性化修改：博客名称兼容

之前的博客里面，有的贴了历史文章的链接，新生成的博客链接通过`permalink`修改规则，保持兼容

```yml
defaults:
  - scope:
      path: "" # An empty string here means all files in the project
      type: posts
    values:
      layout: post
      comments: true # Enable comments in posts.
      toc: true # Display TOC column in posts.
      # DO NOT modify the following parameter unless you are confident enough
      # to update the code of all other post links in this project.
      # 博客链接格式：https://xiaodongq.github.io/posts/memory-management/
      # permalink: /posts/:title/
      # 修改类型为：https://xiaodongq.github.io/2025/03/20/memory-management/
      permalink: /:year/:month/:day/:title/
```
