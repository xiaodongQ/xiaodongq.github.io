---
layout: post
title: Mac搭建python开发环境遇到的问题
categories: Linux
tags: Linux Mac Python pip
---

* content
{:toc}

在慕课网上了解python的web框架django，搭建python环境时遇到些问题。

OS X系统自带了python运行环境，但作为开发不是很方便，tab键无补全提示；另外后续需要安装一些模块。所以安装一下ipython和pip。

使用`easy_install pip`安装pip，但由于网络原因一直下载安装不成功，于是又安装了一个python 2.7.11，
`brew install python`，安装python会自带pip。

由于gfw的因素安装软件很慢，还需要改一下pip获取资源的路径，即pypi源，新建 ~/.pipe/pip.conf配置，
使用阿里云，如下

>[global]
index-url = http://mirrors.aliyun.com/pypi/simple/
[install]
trusted-host=mirrors.aliyun.com

ipython就可以通过pip安装了 `pip install ipython`
