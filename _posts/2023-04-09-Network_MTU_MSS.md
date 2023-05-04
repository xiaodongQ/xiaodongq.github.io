---
layout: post
title: 网络实验-设置机器的MTU和MSS
categories: 案例实验
tags: 网络
---

* content
{:toc}

网络案例实践：设置机器的MTU和MSS。



## 概念

主要参考laixintao 老师的文章：[有关 MTU 和 MSS 的一切](https://www.kawabangga.com/posts/4983)

### MTU

* MTU(Maximum Transmission Unit，最大传输单元) 指的是二层协议（即数据链路层）里面的最大传输单元，一般MTU都是1500。
	- 1500是一个平衡折衷的结果，太大的MTU出错概率更大、重传代价更大、对设备性能要求更高（以太网是分组交换网络，路由设备或交换机转发下一跳前需要存储未发完的数据）
	- 而太小则传输效率更低

* MUT长度图示（未包含以太网头信息 14字节 和 尾部校验和FCS 4字节）：

![报文MTU长度](https://www.kawabangga.com/wp-content/uploads/2023/03/ethernet-mtu.jpeg)
[图片来源](https://www.kawabangga.com/posts/4983)

* 一个标准的以太网数据帧的长度为：**`1500 + 14 + 4 = 1518` 字节**
* 超过MTU的数据帧一般会被丢弃，出现该现象的典型场景是 **VPN** 和 **overlay** 网络

* 另外记录一下关于二层、三层交换机的特点(之前概念比较模糊)：  
	- 三层交换机：基于`网络层`的`IP地址`进行`路由选择和分组过滤`  
	- 二层交换机：基于`数据链路层`的`MAC地址`进行`数据帧`的传输  
	- 不同的VLAN间通信：二层交换机需要搭配路由器使用，而三层交换机自身带路由功能。  

### MSS

MSS(Maximum Segment Size，最大报文长度) 指的是 TCP 层的最大传输数据大小。

* 为了保证发送的数据不超过MTU，各层需要保证其最大的数据长度：
	 - IP层需要保证其`Packet`数据不超过 `1500 - 20 = 1480 字节`(减去20字节IP报文头)
	 - TCP层需要保证其`Segment`数据不超过 `1480 - 20 = 1460 字节`(IP Package内容长度减去TCP头)

> * TCP层如何知道二层(数据链路层)的MTU
	- 网卡驱动知道 2 层的 MTU 是多少；
	- 3 层协议栈 IP 会问网卡驱动 MTU 是多少；
	- 4 层协议 TCP 会问 IP Max Datagram Data Size (MDDS) 是多少；
> * TCP 层的最大传输数据大小，就叫做 MSS (Maximum segment size).

* TCP 在握手的时候，会把自己的 MSS 宣告给对方，进行MSS协商
	- SYN 包里面的 TCP option 字段中，会带有 `MSS`，如果不带的话，default 是 536. 对方也会把 MSS 发送过来，这时候两端会比较 MSS 值，都是**选择一个最小的值作为传输的 MSS**.

## 实验

### 1. 查看TCP握手协商过程 (正常网页访问抓包)

* 步骤：  
	- 1、 开启wireshark抓包  
	- 2、 浏览器进入网站 `www.baidu.com`，而后停止抓包  
	- 3、 过滤包 `tcp contains "baidu"`进行实验分析  

* 协商过程查看

抓包如下：<div align=center><img src="/_resources/MSS/MSS_pkg.png"/></div>

可看到三次握手时，src端(客户端)MSS=1460, dst端(网站服务端)MSS=1452，协商后数据传输时Len=1452，展开看TCP头时也可看到`[TCP Segment Len: 1452]`

### 2. 修改一端的MSS

* MSS设置的方法：
	- 1、iptables: 
		+ `iptables -I OUTPUT -p tcp -m tcp --tcp-flags SYN,RST SYN -j TCPMSS --set-mss 48`
	- 2、 ip route: 
		+ `ip route change 192.168.11.0/24 dev ens33 proto kernel scope link src 192.168.11.111 metric 100 advmss 48`
	- 3、 程序可以自己设置，本质上是自己往 TCP option 里写 MSS
		+ python：`tcp = TCP(dport=80, flags="S",options=[('MSS',48),('SAckOK', '')])`
	- 4、 也可以直接调整网卡上的 MTU：`ifconfig eth0 mtu 800 up`.
		+ 这样 Kernel 的 TCP 栈在建立连接的时候会自动计算 MSS。

#### ping 测试

* 步骤
	- 环境说明：主机1：mac笔记本(192.168.1.2) + 主机2：linux主机(192.168.1.150)
	- 1、到linux端通过iptables设置MSS
		- `iptables -I OUTPUT -p tcp -m tcp --tcp-flags SYN,RST SYN -j TCPMSS --set-mss 1000`
	- 2、mac端启动wireshark抓包
	- 3、linux端ping mac端：`ping 192.168.1.2 -s 2000`
* 抓包分析
	- 观察到IP分片

#### scp 测试

* 步骤
	- 1、到linux端通过iptables设置MSS
		- `iptables -I OUTPUT -p tcp -m tcp --tcp-flags SYN,RST SYN -j TCPMSS --set-mss 50`
	- 2、生成200字节测试文件用于scp测试 `dd if=/dev/zero of=/home/test.data bs=1 count=200`
	- 3、到linux端开启抓包 `tcpdump -i enp4s0 -s 0 -w set_mss50_scp.pcap -v`
	- 4、scp拷贝文件，结束后停止抓包。获取抓包文件后wireshark分析
	- 5、清理iptables规则，重新设置mss为1000，抓包为`set_mss1000_scp.pcap`


## 收获

很认可任总这句：  
> 这种一次性把问题、知识搞明白的能力很重要，如果你一直碰到一直不分析搞清楚，那么即使十年工作经验也是徒然

## 参考

1. [知识星球实验案例](https://t.zsxq.com/0cOVm843F)
2. [有关 MTU 和 MSS 的一切](https://www.kawabangga.com/posts/4983)
3. [什么是MTU？为什么MTU值普遍都是1500？](https://cloud.tencent.com/developer/article/1862409)