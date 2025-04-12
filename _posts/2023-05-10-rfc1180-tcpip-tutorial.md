---
layout: _post
title: RFC1180学习笔记
categories: 网络
tags: 网络
---

* content
{:toc}

[[译] RFC 1180：朴素 TCP/IP 教程（1991）](http://arthurchiao.art/blog/rfc1180-a-tcp-ip-tutorial-zh/) 学习笔记



## 1. 前言

RFC1180一篇很简洁易懂的TCP/IP入门教程，这篇翻译也很好。对网络栈和IP路由规则解释得很清晰，配合抓包对照理解更佳。

## 2. ARP

ARP请求：收到192.168.1.100的广播包，谁是192.168.1.2（当IP不在ARP表时，广播ARP请求）
![2023-05-13-20230513083912](/images/2023-05-13-20230513083912.png)

arp应答：自己是192.168.1.2，应答mac给192.168.1.100
![2023-05-13-20230513084048](/images/2023-05-13-20230513084048.png)

## 3. IP层路由

IP模块路由规则：
![2023-05-13-ip-route](/images/2023-05-13-ip-route.jpg)

访问网站，2层目的mac为光猫mac，ip为网站ip：
![2023-05-13-20230513085740](/images/2023-05-13-20230513085740.png)

`iptables -I/-A`时，INPUT/OUTPUT/FORWARD三个规则链 分别对应IP层的 入向/出向/转发

## 4. 主机名和网络名

`/etc/hosts` 中保存**主机名**和**IP地址**的对应关系

`/etc/networks` 中保存**网络名**和**网络号**的对应关系

`route add/del`时，`-net`和`-host`分别指定网络和主机
