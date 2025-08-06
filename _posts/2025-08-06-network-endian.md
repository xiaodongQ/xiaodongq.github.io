---
title: 网络实验 -- 搞懂大小端字节序
description: 实验对比大小端字节序
categories: [网络, 网络编程]
tags: [网络, 网络编程]
---


## 1. 引言

最近写小工具的过程中碰到客户端连接服务端时，传输的网络报文和预期不符，定位期间针对网络字节序又有些模糊了。

业务模型：
* Go开发小工具作为客户端，服务端是C++程序。
* 服务端基于私有的RPC协议进行通信，所以Go需要进行对应数据结构的序列化和反序列化适配，并进行网络通信。

大端、小端字节序和网络传输时的字节序经常容易混淆，常常是这次查了一下，下次碰到时又得去检索一遍进行确认，本篇进行实验增强印象和理解，尽量以后碰到时就不再模棱两可。

## 2. 字节序说明

### 2.1. 大小端和网络字节序

**字节序（`Byte Order`）**：是数据在内存中存储的顺序，尤其是 **<mark>多字节</mark>** 的数据
* 单字节数据其实不涉及混淆，比如单字节`0x01`；而多字节`0x0102`，就涉及`01`和`02`的存储和传输顺序了。

1、**大端序（`Big-Endian`）**：高位字节存储在低地址
* 示例：`0x12345678` 存储为 `12 34 56 78`，比如数组`int n[4]`，那`n[0]=12`、`n[3]=78`

2、**小端序（Little-Endian）**：低位字节存储在低地址
* 示例：`0x12345678` 存储为 `78 56 34 12`，比如数组`int n[4]`，那`n[0]=78`、`n[3]=12`

3、**网络字节序**
* TCP/IP协议强制使用 **<mark>大端序</mark>** 作为标准网络字节序（因为更符合人类阅读习惯），所有**网络传输的多字节数据必须使用大端序**

### 2.2. 查看字节序

`lscpu`可查看系统的字节序，可看到我当前系统（`Rocky Linux release 9.5 (Blue Onyx)`）为小端序

```sh
[root@xdlinux ➜ ~ ]$ lscpu | grep -i byte
Byte Order:                           Little Endian
```

## 3. 设计实验

网络交互协议结构如下：
```sh
----------------------------------------------
| 协议头 (14字节)                             |
----------------------------------------------
| Magic(2)   | Version(2)  | Command(2) |   |
| BodyLen(4) | Checksum(4) |                |
----------------------------------------------
| 协议体 (变长)                               |
----------------------------------------------
| Field1(4) | Field2(4) | ... | FieldN(N)   |
----------------------------------------------
```

### 3.1. 服务端程序

```cpp
#include <iostream>
#include <cstdint>
#include <arpa/inet.h>
#include <netinet/in.h>
#include <sys/socket.h>
#include <unistd.h>
#include <cstring>
#include <ctime>

// 此处设置pack后，会按1字节对齐，忽略结构体的对齐补齐
#pragma pack(push, 1)
struct Header {
    uint16_t magic;
    uint16_t version;
    uint16_t command;
    uint32_t bodyLen;
    uint32_t checksum;
};

struct Body {
    uint32_t seqNum;
    uint64_t timestamp;
    char data[4];
};
#pragma pack(pop)

bool recvAll(int sock, void* buf, size_t len) {
    char* ptr = (char*)buf;
    while (len > 0) {
        ssize_t rc = recv(sock, ptr, len, 0);
        if (rc <= 0) {
            std::cout << "len:" << len << ", rc:" << rc << std::endl;
            return false;
        }
        ptr += rc;
        len -= rc;
    }
    return true;
}

uint32_t calculateChecksum(const char* data, uint32_t len) {
    uint32_t sum = 0;
    for (uint32_t i = 0; i < len; ++i) {
        sum += (uint8_t)data[i];
    }
    return sum;
}

void printPacket(const Header& header, const Body& body, const char* raw, size_t totalLen) {
    std::cout << "\nReceived Packet:\n";
    std::cout << "Header:\n";
    std::cout << "  Magic:    0x" << std::hex << ntohs(header.magic) << "\n";
    std::cout << "  Version:  0x" << std::hex << ntohs(header.version) << "\n";
    std::cout << "  Command:  0x" << std::hex << ntohs(header.command) << "\n";
    std::cout << "  BodyLen:  " << std::dec << ntohl(header.bodyLen) << "\n";
    std::cout << "  Checksum: 0x" << std::hex << ntohl(header.checksum) << "\n";

    std::cout << "\nBody:\n";
    std::cout << "  SeqNum:   0x" << std::hex << ntohl(body.seqNum) << "\n";
    std::cout << "  Timestamp:0x" << std::hex << be64toh(body.timestamp) << "\n";
    std::cout << "  Data:     '";
    for (int i = 0; i < 4; ++i) {
        if (isprint(body.data[i])) std::cout << body.data[i];
        else std::cout << "\\x" << std::hex << (int)(uint8_t)body.data[i];
    }
    std::cout << "'\n";

    std::cout << "\nRaw Bytes (" << totalLen << " bytes):\n";
    for (size_t i = 0; i < totalLen; i += 8) {
        size_t end = std::min(i + 8, totalLen);
        printf("  [%04zX] ", i);
        for (size_t j = i; j < end; ++j) {
            printf("%02X ", (uint8_t)raw[j]);
        }
        std::cout << "\n";
    }
}

int main() {
    int server_fd = socket(AF_INET, SOCK_STREAM, 0);
    if (server_fd < 0) {
        std::cerr << "socket() failed: " << strerror(errno) << std::endl;
        return 1;
    }

    sockaddr_in addr{};
    addr.sin_family = AF_INET;
    addr.sin_addr.s_addr = INADDR_ANY;
    addr.sin_port = htons(8080);

    if (bind(server_fd, (sockaddr*)&addr, sizeof(addr)) < 0) {
        std::cerr << "bind() failed: " << strerror(errno) << std::endl;
        close(server_fd);
        return 1;
    }

    if (listen(server_fd, 5) < 0) {
        std::cerr << "listen() failed: " << strerror(errno) << std::endl;
        close(server_fd);
        return 1;
    }

    std::cout << "Server listening on port 8080..." << std::endl;

    while (true) {
        sockaddr_in client_addr{};
        socklen_t client_len = sizeof(client_addr);
        int client_fd = accept(server_fd, (sockaddr*)&client_addr, &client_len);
        if (client_fd < 0) {
            std::cerr << "accept() failed: " << strerror(errno) << std::endl;
            continue;
        }

        // 接收协议头
        Header header;
        std::cout << "size Header:" << sizeof(header) << std::endl;
        if (!recvAll(client_fd, &header, sizeof(header))) {
            std::cerr << "recv header failed" << std::endl;
            close(client_fd);
            continue;
        }

        // 验证Magic
        if (ntohs(header.magic) != 0xAABB) {
            std::cerr << "invalid magic number" << std::endl;
            close(client_fd);
            continue;
        }

        // 接收协议体
        uint32_t bodyLen = ntohl(header.bodyLen);
        std::cout << "bodyLen:" << bodyLen << std::endl;
        char* bodyData = new char[bodyLen];
        if (!recvAll(client_fd, bodyData, bodyLen)) {
            std::cerr << "recv body failed" << std::endl;
            delete[] bodyData;
            close(client_fd);
            continue;
        }

        // 验证校验和
        uint32_t expectedChecksum = calculateChecksum(bodyData, bodyLen);
        if (ntohl(header.checksum) != expectedChecksum) {
            std::cerr << "checksum mismatch (expected: 0x" 
                      << std::hex << expectedChecksum 
                      << ", got: 0x" << ntohl(header.checksum) 
                      << ")" << std::endl;
            delete[] bodyData;
            close(client_fd);
            continue;
        }

        // 反序列化协议体
        Body body;
        if (bodyLen >= sizeof(body)) {
            memcpy(&body, bodyData, sizeof(body));
            body.seqNum = ntohl(body.seqNum);
            body.timestamp = be64toh(body.timestamp);
        }

        // 组合原始报文用于打印
        char* fullPacket = new char[sizeof(header) + bodyLen];
        memcpy(fullPacket, &header, sizeof(header));
        memcpy(fullPacket + sizeof(header), bodyData, bodyLen);

        printPacket(header, body, fullPacket, sizeof(header) + bodyLen);

        delete[] bodyData;
        delete[] fullPacket;
        close(client_fd);
    }

    close(server_fd);
    return 0;
}
```

### 3.2. 客户端程序

```go
package main

import (
    "bytes"
    "encoding/binary"
    "fmt"
    "log"
    "net"
    "strconv"
    "unsafe"
)

const (
    MAGIC    = 0xAABB
    VERSION  = 0x0101
    CMD_TEST = 0x0001
)

type Header struct {
    Magic    uint16
    Version  uint16
    Command  uint16
    BodyLen  uint32
    Checksum uint32
}

type Body struct {
    SeqNum    uint32
    Timestamp uint64
    Data      [4]byte
}

func main() {
    conn, err := net.Dial("tcp", "localhost:8080")
    if err != nil {
        log.Fatal("连接失败:", err)
    }
    defer conn.Close()

    // 准备协议体
    body := Body{
        SeqNum:    0x11223344,
        Timestamp: 0x5566778899AABBCC,
        Data:      [4]byte{'T', 'E', 'S', 'T'},
    }

    // 序列化协议体
    bodyBuf := new(bytes.Buffer)
    binary.Write(bodyBuf, binary.BigEndian, body.SeqNum)
    binary.Write(bodyBuf, binary.BigEndian, body.Timestamp)
    bodyBuf.Write(body.Data[:])

    // 准备协议头
    header := Header{
        Magic:    MAGIC,
        Version:  VERSION,
        Command:  CMD_TEST,
        BodyLen:  uint32(bodyBuf.Len()),
    }
    log.Printf("header len:%d, bodyBuf len:%d", unsafe.Sizeof(Header{}), bodyBuf.Len())

    // 计算校验和
    checksum := calculateChecksum(bodyBuf.Bytes())
    header.Checksum = checksum

    // 序列化协议头
    headerBuf := new(bytes.Buffer)
    binary.Write(headerBuf, binary.BigEndian, header.Magic)
    binary.Write(headerBuf, binary.BigEndian, header.Version)
    binary.Write(headerBuf, binary.BigEndian, header.Command)
    binary.Write(headerBuf, binary.BigEndian, header.BodyLen)
    binary.Write(headerBuf, binary.BigEndian, header.Checksum)

    // 组合完整报文
    fullPacket := append(headerBuf.Bytes(), bodyBuf.Bytes()...)

    // 发送数据
    if _, err := conn.Write(fullPacket); err != nil {
        log.Fatal("发送失败:", err)
    }

    fmt.Println("发送成功:")
    printPacket(header, body, fullPacket)
}

func calculateChecksum(data []byte) uint32 {
    var sum uint32
    for _, b := range data {
        sum += uint32(b)
    }
    return sum
}

func printPacket(header Header, body Body, raw []byte) {
    fmt.Printf("Header:\n")
    fmt.Printf("  Magic:    0x%04X\n", header.Magic)
    fmt.Printf("  Version:  0x%04X\n", header.Version)
    fmt.Printf("  Command:  0x%04X\n", header.Command)
    fmt.Printf("  BodyLen:  %d\n", header.BodyLen)
    fmt.Printf("  Checksum: 0x%08X\n", header.Checksum)

    fmt.Printf("\nBody:\n")
    fmt.Printf("  SeqNum:   0x%08X\n", body.SeqNum)
    fmt.Printf("  Timestamp:0x%016X\n", body.Timestamp)
    fmt.Printf("  Data:     %s\n", strconv.Quote(string(body.Data[:])))

    fmt.Printf("\nRaw Bytes (%d bytes):\n", len(raw))
    for i := 0; i < len(raw); i += 8 {
        end := i + 8
        if end > len(raw) {
            end = len(raw)
        }
        fmt.Printf("  [%04X] % X\n", i, raw[i:end])
    }
}
```

### 3.3. 编译

```sh
[root@xdlinux ➜ byte_order git:(main) ✗ ]$ cat make.sh 
g++ -o server server.cpp
go build -o client client.go
```

## 4. 运行、抓包和结果分析

`./server`运行服务端，并开启抓包`tcpdump -i any port 8080 -w 8080.cap -v`，而后`./client`触发请求。

详细结果如下，可看到客户端和服务端的body长度都是一致的：`16`字节

```cpp
// c++结构，不考虑对齐补齐，因为设置了：#pragma pack(1)
struct Body {
    uint32_t seqNum;
    uint64_t timestamp;
    char data[4];
};
```

```go
type Body struct {
    SeqNum    uint32
    Timestamp uint64
    Data      [4]byte
}
```

### 4.1. 客户端结果

```sh
[root@xdlinux ➜ byte_order git:(main) ✗ ]$ ./client
2025/08/07 00:06:09 header len:16, bodyBuf len:16
发送成功:
Header:
  Magic:    0xAABB
  Version:  0x0101
  Command:  0x0001
  BodyLen:  16
  Checksum: 0x0000066E

Body:
  SeqNum:   0x11223344
  Timestamp:0x5566778899AABBCC
  Data:     "TEST"

Raw Bytes (30 bytes):
  [0000] AA BB 01 01 00 01 00 00
  [0008] 00 10 00 00 06 6E 11 22
  [0010] 33 44 55 66 77 88 99 AA
  [0018] BB CC 54 45 53 54
```

### 4.2. 服务端结果

```sh
[root@xdlinux ➜ byte_order git:(main) ✗ ]$ ./server     
Server listening on port 8080...
size Header:14
bodyLen:16

Received Packet:
Header:
  Magic:    0xaabb
  Version:  0x101
  Command:  0x1
  BodyLen:  16
  Checksum: 0x66e

Body:
  SeqNum:   0x44332211
  Timestamp:0xccbbaa9988776655
  Data:     'TEST'

Raw Bytes (1e bytes):
  [0000] AA BB 01 01 00 01 00 00 
  [0008] 00 10 00 00 06 6E 11 22 
  [0010] 33 44 55 66 77 88 99 AA 
  [0018] BB CC 54 45 53 54 
```

### 4.3. 抓包结果

`follow TCP Stream`查看16进制信息：

```sh
00000000  aa bb 01 01 00 01 00 00  00 10 00 00 06 6e 11 22   ........ .....n."
00000010  33 44 55 66 77 88 99 aa  bb cc 54 45 53 54         3DUfw... ..TEST
```

## case2：不指定pragma pack

注释去掉C++服务端的`#pragma pack(1)`，再编译运行，**服务端就报错了，接收到的长度字段不对**。

客户端：
```sh
[root@xdlinux ➜ case2 git:(main) ✗ ]$ ./client 
2025/08/07 00:09:39 header len:16, bodyBuf len:16
发送成功:
Header:
  Magic:    0xAABB
  Version:  0x0101
  Command:  0x0001
  BodyLen:  16
  Checksum: 0x0000066E

Body:
  SeqNum:   0x11223344
  Timestamp:0x5566778899AABBCC
  Data:     "TEST"

Raw Bytes (30 bytes):
  [0000] AA BB 01 01 00 01 00 00
  [0008] 00 10 00 00 06 6E 11 22
  [0010] 33 44 55 66 77 88 99 AA
  [0018] BB CC 54 45 53 54
```

服务端：
```sh
[root@xdlinux ➜ case2 git:(main) ✗ ]$ ./server 
Server listening on port 8080...
size Header:16
bodyLen:1048576
len:1048562, rc:0
recv body failed
```

## case3

```go
package main

import (
    "encoding/binary"
    "fmt"
    "log"
    "net"
    "strconv"
)

const (
    MAGIC    = 0xAABB
    VERSION  = 0x0101
    CMD_TEST = 0x0001
)

// 假设服务端默认8字节对齐
type Header struct {
    Magic    uint16
    _        [2]byte // 填充到4字节
    Version  uint16
    Command  uint16
    _        [2]byte // 填充到8字节
    BodyLen  uint32
    _        [4]byte // 填充到8字节
    Checksum uint32
    _        [4]byte // 填充到8字节
}

type Body struct {
    SeqNum    uint32
    Timestamp uint64
    Data      [4]byte
}

func main() {
    conn, err := net.Dial("tcp", "localhost:8080")
    if err != nil {
        log.Fatal("连接失败:", err)
    }
    defer conn.Close()

    // 准备协议体
    body := Body{
        SeqNum:    0x11223344,
        Timestamp: 0x5566778899AABBCC,
        Data:      [4]byte{'T', 'E', 'S', 'T'},
    }

    // 序列化协议体
    bodyBuf := make([]byte, 16)
    binary.BigEndian.PutUint32(bodyBuf[0:4], body.SeqNum)
    binary.BigEndian.PutUint64(bodyBuf[4:12], body.Timestamp)
    copy(bodyBuf[12:16], body.Data[:])

    // 准备协议头
    header := Header{
        Magic:    MAGIC,
        Version:  VERSION,
        Command:  CMD_TEST,
        BodyLen:  uint32(len(bodyBuf)),
    }

    // 计算校验和
    checksum := calculateChecksum(bodyBuf)
    header.Checksum = checksum

    // 序列化协议头（手动处理填充）
    headerBuf := make([]byte, 24)
    binary.BigEndian.PutUint16(headerBuf[0:2], header.Magic)
    binary.BigEndian.PutUint16(headerBuf[4:6], header.Version)
    binary.BigEndian.PutUint16(headerBuf[8:10], header.Command)
    binary.BigEndian.PutUint32(headerBuf[12:16], header.BodyLen)
    binary.BigEndian.PutUint32(headerBuf[20:24], header.Checksum)

    // 组合完整报文
    fullPacket := append(headerBuf, bodyBuf...)

    // 发送数据
    if _, err := conn.Write(fullPacket); err != nil {
        log.Fatal("发送失败:", err)
    }

    fmt.Println("发送成功:")
    printPacket(header, body, fullPacket)
}

func calculateChecksum(data []byte) uint32 {
    var sum uint32
    for _, b := range data {
        sum += uint32(b)
    }
    return sum
}

func printPacket(header Header, body Body, raw []byte) {
    fmt.Printf("Header:\n")
    fmt.Printf("  Magic:    0x%04X\n", header.Magic)
    fmt.Printf("  Version:  0x%04X\n", header.Version)
    fmt.Printf("  Command:  0x%04X\n", header.Command)
    fmt.Printf("  BodyLen:  %d\n", header.BodyLen)
    fmt.Printf("  Checksum: 0x%08X\n", header.Checksum)

    fmt.Printf("\nBody:\n")
    fmt.Printf("  SeqNum:   0x%08X\n", body.SeqNum)
    fmt.Printf("  Timestamp:0x%016X\n", body.Timestamp)
    fmt.Printf("  Data:     %s\n", strconv.Quote(string(body.Data[:])))

    fmt.Printf("\nRaw Bytes (%d bytes):\n", len(raw))
    for i := 0; i < len(raw); i += 8 {
        end := i + 8
        if end > len(raw) {
            end = len(raw)
        }
        fmt.Printf("  [%04X] % X\n", i, raw[i:end])
    }
}
```

## 5. 小结

大小端字节序、网络字节序实验。

## 6. 参考

* LLM