---
layout: post
title: 网络实验-设置机器的MTU和MSS
categories: 案例实验
tags: 网络
---

* content
{:toc}

网络案例实践：设置机器的MTU和MSS。通过案例理解MTU和TCP MSS协商。



## 1. 概念

主要参考laixintao 老师的文章：[有关 MTU 和 MSS 的一切](https://www.kawabangga.com/posts/4983)

### 1.1. MTU

MTU(Maximum Transmission Unit，最大传输单元) 指的是二层协议（也有说三层协议的，不同的厂商，甚至同一厂商的不同产品型号对MTU的定义也不尽相同）里面的最大传输单元，以太网缺省MTU是1500。

1500是一个平衡折衷的结果。

* 太大的MTU出错概率更大、重传代价更大、对设备性能要求更高（以太网是分组交换网络，路由设备或交换机转发下一跳前需要存储未发完的数据）
* 而太小则传输效率更低

MTU长度图示（传输层以TCP为例，未包含以太网头信息 14字节 和 尾部校验和FCS 4字节）：

![以太帧MTU长度示意](/images/2023-05-06-17-00-50.png)  
[原图片来源](https://www.kawabangga.com/posts/4983)

一个标准的以太网数据帧的长度为：**`1500 + 14 + 4 = 1518` 字节**

超过MTU的数据帧一般会造成IP报文分片或者被丢弃，出现该现象的典型场景是 **VPN** 和 **overlay** 网络，这种网络会在之前的二层包基础上再包一层，如再添加一个header。

### 1.2. 如何保证发送的数据不超过MTU

若要保证以太帧不超过MTU，就需要各上层协议保证其最大的数据长度。比如对于MTU 1500来说：

1. IP层需要保证其`Packet`数据不超过 `1500 - 20 = 1480 字节`(减去20字节IP报文头)
2. TCP层需要保证其`Segment`数据(即下述的MSS)不超过 `1480 - 20 = 1460 字节`(IP Package内容长度减去TCP头)

示例：传输2000byte的数据，MTU为1500，就需要进行分片传输。若为tcp协议，1500中包含20byte的IP头+20byte的TCP头，每个分片最大payload数据长度为1460，需要分两个分片：1460、540；若为icmp，则分片1480+520

* 上层协议（如TCP层）如何知道二层(数据链路层)的MTU？

    - 网卡驱动知道 2 层的 MTU 是多少；
    - 3 层协议栈 IP 会问网卡驱动 MTU 是多少；
    - 4 层协议 TCP 会问 IP Max Datagram Data Size (MDDS) 是多少；

### 1.3. MSS

MSS(Maximum Segment Size，最大报文段长度) 指的是 TCP 层的最大传输数据大小。

* TCP 在握手的时候，会把自己的 MSS 宣告给对方，进行MSS协商
    - SYN 包里面的 TCP option 字段中，会带有 `MSS`，如果不带的话，default 是 536. 对方也会把 MSS 发送过来，这时候两端会比较 MSS 值，都是**选择一个最小的值作为传输的 MSS**。

### 1.4. 发送的数据超过MTU时各层的处理

每层协议向下一层协议传输数据时，会确保在其最大长度限制内，但也有各种各样的原因，导致下层收到的数据超出限制，此时各层协议有不同的处理机制。

* 数据链路层

超出MTU一般丢弃，依赖上层保证发送的数据不超过MTU。（也有协议支持拆分，如MLPPP）

* 网络层

若package超出MTU，IP层将其进行IP分片（IP Fragmentation），只有该package的所有fragment都收到后才能进行处理。IP分片会降低传输层传送数据的效率，且会增加数据传送失败率，需要避免IP分片。

IP协议头中的 DF(`Don't fragment`)标志位若设置为1，则表示路由设备收到package大小超过MTU时不进行分片，而是丢弃该包。

IP分片示意图：
![ip-fragmentation](https://www.kawabangga.com/wp-content/uploads/2023/04/ip-fragmentation.png)  
[图片来源](https://www.plixer.com/blog/netflow-security-detecting-ip-fragmentation-exploits-scrutinizer/)

* 传输层

kernel的协议栈会将数据(TCP/UDP)拆分为IP层正好能处理的长度发出去，注意此处的拆分是TCP拆成多个segment，在IP层并没有拆分，每个IP package里都包含TCP header。

## 2. 实验

### 2.1. 简单网页访问查看MSS协商

开启wireshark抓包，浏览器进入网站 `www.baidu.com`，而后停止抓包，过滤包`tcp contains "baidu"`

* 协商过程查看

抓包如图：![MSS_pkg](/images/2023-04-09-mss-pkg.png)

可看到三次握手时，src端(客户端)MSS=1460, dst端(网站服务端)MSS=1452，协商后数据传输时Len=1452，展开看TCP头时也可看到`[TCP Segment Len: 1452]`

### 2.2. MSS设置的方法说明

* 1、iptables:
    - `iptables -I OUTPUT -p tcp -m tcp --tcp-flags SYN,RST SYN -j TCPMSS --set-mss 100`
* 2、 ip route:
    - `ip route change 192.168.1.0/24 dev enp4s0 proto kernel scope link src 192.168.1.2 metric 100 advmss 100`
* 3、 程序可以自己设置，本质上是自己往 TCP option 里写 MSS
    - 如python：`tcp = TCP(dport=80, flags="S",options=[('MSS',48),('SAckOK', '')])`
* 4、 也可以直接调整网卡上的 MTU：`ifconfig eth0 mtu 800 up`.
    - 这样 Kernel 的 TCP 栈在建立连接的时候会自动计算 MSS。

### 2.3. ping 测试

环境说明：主机1：mac笔记本(192.168.1.2) + 主机2：linux pc主机(192.168.1.150)

1. 测试1：两端MTU均1500，ping packagesize 2000

    主机1启动wireshark，ping主机2，`ping 192.168.1.2 -s 2000`(指定要发送的数据长度，默认56，不包含8字节ICMP头)，保存抓包文件：[ping-s2000.pcapng](/images/srcfiles/ping-s2000.pcapng)

    抓包如图：![2023-05-07-ping_s2000_mtu1500](/images/2023-05-07-ping_s2000_mtu1500.png)  
    1）可看到请求和响应的ip报文都有两个分片(fragment)，第1个分片的ip报文1500，第2个548。  
    2）请求报文：其中第1个分片中20byte是IP头，1480是ICMP数据，IP头Flags中的`More fragments`为1，表示本package还有更多分片，`Fragment Offset`是0；第2个分片，548-20=528，其中包含了ICMP头(8字节)，ICMP数据为520。所以发送的数据长度为`1480+520+8=2008`(说明-s数据长度不包含ip头)

2. 测试2：对端MTU 500，本端1500，ping packagesize 2000

    到主机2设置MSS `ifconfig enp4s0 mtu 500 up`，而后ping主机2

    抓包如图：![2023-05-07-ping-s2000-smtu1500-d500](images/2023-05-07-ping-s2000-smtu1500-d500.png)  
    1）请求2个分片，依旧是1500+548  
    2）应答5个分片，4个500byte和1个108byte的ip分片，数据长度：`480*4+88=2008`（不包含每个分片中的ip头，包含完整package的icmp头）

3. 测试3：对端MTU 1500，本端500，ping packagesize 2000

    到主机1设置MSS `sudo ifconfig en0 mtu 500 up`，而后ping主机2

    抓包如图：![2023-05-07-ping-s2000-smtu500-d1500](/images/2023-05-07-ping-s2000-smtu500-d1500.png)  
    和上一个场景相反，请求报文拆成5个ip分片。

### 2.3.1. scp 测试

环境说明：主机1：mac笔记本(192.168.1.2) + 主机2：linux pc主机(192.168.1.150)

1. 测试1：到主机2设置MSS，主机1上开启抓包，并进行文件下载

```sh
    # 1、主机2上生成测试2000字节大小文件，用于scp测试
    dd if=/dev/zero of=/home/xd/workspace/experiment/temp.dat bs=1 count=2000
    
    # 2、主机2设置MSS，主机1默认1500-20-20=1460
    # TCPMSS模块、--set-mss设置特定MSS，--tcp-flags {标志位集合} {要判断哪个标志位等于1}此处SYN表示匹配第一次握手的报文
    iptables -I OUTPUT -p tcp -m tcp --tcp-flags SYN,RST SYN -j TCPMSS --set-mss 100
    iptables -I FORWARD -p tcp -m tcp --tcp-flags SYN,RST SYN -j TCPMSS --set-mss 100

    # 3、主机1上抓包，scp下载
    scp root@192.168.1.150:/home/xd/workspace/experiment/temp.dat .
```

抓包文件：[scp-overmss-smss1460-dmss100.pcapng](images/srcfiles/scp-overmss-smss1460-dmss100.pcapng)  
抓包截图：![2023-05-07-over-mss](/images/2023-05-07-over-mss.png)

* **疑问(TODO)**

使用该方式看报文交互没限制成功？三次握手时两端MSS是100和1460，传输时有132、256、1048等大小的tcp segment。以下尝试后仍有该问题
    1）尝试OUTPUT、FORWARD都添加规则
    2）尝试参考文章中关闭TSO(TCP Segment Offload)结果也一样(offload相关的选项都关闭了)，还是有超出100byte的包  
    offload：![2023-05-07-offload](/master/images/2023-05-07-offload.png)

```sh
    # 查看网卡offload
    ethtool -k enp4s0 |grep offload
    # 关闭offload相关配置
    ethtool -K enp4s0 tx off
    ethtool -K enp4s0 generic-receive-offload off
    ethtool -K enp4s0 rx-vlan-offload off
    ethtool -K enp4s0 tx-vlan-offload off
```

* 两端均限制MSS大小后是正常的，但是实际场景中一般是只有某一端才有问题。上述问题还待明确原因。
* 星球里面提问，答主给的一个思路是iptables trace跟踪下iptables的规则是否生效。上述抓包中其实能看到握手时主机2通告的MSS是100，规则是生效的。此处了解下iptables trace使用。

## 4. 参考

1. [知识星球实验案例](https://t.zsxq.com/0cOVm843F)
2. [有关 MTU 和 MSS 的一切](https://www.kawabangga.com/posts/4983)
3. [什么是MTU（Maximum Transmission Unit）？](https://info.support.huawei.com/info-finder/encyclopedia/zh/MTU.html)