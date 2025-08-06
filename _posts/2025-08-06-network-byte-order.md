---
title: 网络实验 -- 搞懂大小端字节序
description: 实验验证小端字节序
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

## 3. 设计实验：case1

网络交互协议结构如下：
```sh
----------------------------------------------
| 协议头 (14字节)                             |
----------------------------------------------
| Magic(2 char) | Version(2)  |  Command(2) |
| BodyLen(4)    | Checksum(4)               |
----------------------------------------------
| 协议体 (变长)                               |
----------------------------------------------
| Field1(4) | Field2(4) | ... | FieldN(N)   |
----------------------------------------------
```

### 3.1. 客户端程序

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
    MAGIC    = "AB" // 2字节字符数组
    VERSION  = 0x0101
    CMD_TEST = 0x0001
)

type Header struct {
    Magic    [2]byte
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
        Magic:    [2]byte{MAGIC[0], MAGIC[1]},
        Version:  VERSION,
        Command:  CMD_TEST,
        BodyLen:  uint32(bodyBuf.Len()),
    }
    // 虽然此处header打印16字节（也有对齐补齐），但下面传输的二进制是手动指定了二进制流
    log.Printf("header len:%d, bodyBuf len:%d", unsafe.Sizeof(Header{}), bodyBuf.Len())

    // 计算校验和（基于大端序数据计算）
    checksum := calculateChecksum(bodyBuf.Bytes())
    header.Checksum = checksum

    // 序列化协议头
    headerBuf := new(bytes.Buffer)
    headerBuf.Write(header.Magic[:]) // 直接写入字节数组
    binary.Write(headerBuf, binary.BigEndian, header.Version)
    binary.Write(headerBuf, binary.BigEndian, header.Command)
    binary.Write(headerBuf, binary.BigEndian, header.BodyLen)
    binary.Write(headerBuf, binary.BigEndian, header.Checksum)
    log.Printf("req headerBuf len:%d, bodyBuf len:%d", headerBuf.Len(), bodyBuf.Len())

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
    fmt.Printf("  Magic:    %s (0x%X)\n", string(header.Magic[:]), header.Magic)
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

### 3.2. 服务端程序

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
    // 2字节字符数组
    char magic[2];
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
        std::cout << "len:" << len << ", rc:" << rc << std::endl;
        if (rc <= 0) {
            std::cerr << "接收失败: " << (rc == 0 ? "连接关闭" : strerror(errno)) << std::endl;
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
    std::cout << "Magic: ";
    for (int i = 0; i < 2; ++i) {
        printf("%c(0x%02X) ", header.magic[i], (uint8_t)header.magic[i]);
    }
    std::cout << std::endl;
    // 已经转换过本地字节序了，此处不用再转换
    std::cout << "  Version:  0x" << std::hex << header.version << "\n";
    std::cout << "  Command:  0x" << std::hex << header.command << "\n";
    std::cout << "  BodyLen:  " << std::dec << header.bodyLen << "\n";
    std::cout << "  Checksum: 0x" << std::hex << header.checksum << "\n";

    std::cout << "\nBody:\n";
    std::cout << "  SeqNum:   0x" << std::hex << body.seqNum << "\n";
    std::cout << "  Timestamp:0x" << std::hex << body.timestamp << "\n";
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
        if (header.magic[0] != 'A' || header.magic[1] != 'B') {
            std::cerr << "Invalid magic: " 
                      << header.magic[0] << header.magic[1] << std::endl;
            close(client_fd);
            continue;
        }

        // 转换成本地字节序
        header.version = ntohs(header.version);
        header.command = ntohs(header.command);
        header.bodyLen = ntohl(header.bodyLen);
        header.checksum = ntohl(header.checksum);

        // 接收协议体
        std::cout << "bodyLen:" << header.bodyLen << std::endl;
        char* bodyData = new char[header.bodyLen];
        if (!recvAll(client_fd, bodyData, header.bodyLen)) {
            std::cerr << "recv body failed" << std::endl;
            delete[] bodyData;
            close(client_fd);
            continue;
        }

        // 验证校验和（基于大端字节序数据计算，两端保持一致）
        uint32_t expectedChecksum = calculateChecksum(bodyData, header.bodyLen);
        if (header.checksum != expectedChecksum) {
            std::cerr << "checksum mismatch (expected: 0x" 
                      << std::hex << expectedChecksum 
                      << ", got: 0x" << header.checksum 
                      << ")" << std::endl;
            delete[] bodyData;
            close(client_fd);
            continue;
        }

        // 反序列化协议体
        Body body;
        if (header.bodyLen >= sizeof(body)) {
            memcpy(&body, bodyData, sizeof(body));
            // 转换成本地字节序
            body.seqNum = ntohl(body.seqNum);
            body.timestamp = be64toh(body.timestamp);
        } else {
            std::cerr << "Body too small: " << header.bodyLen 
                      << " < " << sizeof(body) << std::endl;
            close(client_fd);
            continue;
        }

        // 组合原始报文用于打印
        char* fullPacket = new char[sizeof(header) + header.bodyLen];
        memcpy(fullPacket, &header, sizeof(header));
        memcpy(fullPacket + sizeof(header), bodyData, header.bodyLen);

        printPacket(header, body, fullPacket, sizeof(header) + header.bodyLen);

        delete[] bodyData;
        delete[] fullPacket;
        close(client_fd);
    }

    close(server_fd);
    return 0;
}
```

### 3.3. 编译

```sh
[root@xdlinux ➜ byte_order git:(main) ✗ ]$ cat make.sh 
g++ -o server server.cpp
go build -o client client.go
```

### 3.4. 运行、抓包和结果分析

`./server`运行服务端，并开启抓包`tcpdump -i lo port 8080 -w 8080.cap -v`，而后`./client`触发请求。

详细结果如下，可看到客户端和服务端的header和body长度都是一致的：`14`和`16`字节。
* C++结构中设置了`#pragma pack(1)`，按1字节对齐补齐
* Go客户端传输时也通过`binary.Write`指定流式数据，也不涉及对齐

#### 3.4.1. 客户端结果

```sh
[root@xdlinux ➜ case1_pragma_pack git:(main) ✗ ]$ ./client
2025/08/07 06:46:49 header len:16, bodyBuf len:16
# 实际发送的头长度为14，上面unsafe.Sizeof(Header{})还是c方式打印的结构体长度
2025/08/07 06:46:49 req headerBuf len:14, bodyBuf len:16
发送成功:
Header:
  Magic:    AB (0x4142)
  Version:  0x0101
  Command:  0x0001
  BodyLen:  16
  Checksum: 0x0000066E

Body:
  SeqNum:   0x11223344
  Timestamp:0x5566778899AABBCC
  Data:     "TEST"

Raw Bytes (30 bytes):
  [0000] 41 42 01 01 00 01 00 00
  [0008] 00 10 00 00 06 6E 11 22
  [0010] 33 44 55 66 77 88 99 AA
  [0018] BB CC 54 45 53 54
```

#### 3.4.2. 服务端结果

```sh
[root@xdlinux ➜ case1_pragma_pack git:(main) ✗ ]$ ./server
Server listening on port 8080...
size Header:14
len:14, rc:14
bodyLen:16
len:16, rc:16

Received Packet:
Header:
Magic: A(0x41) B(0x42) 
  Version:  0x101
  Command:  0x1
  BodyLen:  16
  Checksum: 0x66e

Body:
  SeqNum:   0x11223344
  Timestamp:0x5566778899aabbcc
  Data:     'TEST'

Raw Bytes (1e bytes):
  [0000] 41 42 01 01 01 00 10 00 
  [0008] 00 00 6E 06 00 00 11 22 
  [0010] 33 44 55 66 77 88 99 AA 
  [0018] BB CC 54 45 53 54
```

#### 3.4.3. 抓包结果

`follow TCP Stream`查看16进制信息，可看到和上面客户端、服务端都是一致的（都转换为了大端序）

```sh
00000000  41 42 01 01 00 01 00 00  00 10 00 00 06 6e 11 22   AB...... .....n."
00000010  33 44 55 66 77 88 99 aa  bb cc 54 45 53 54         3DUfw... ..TEST
```

## 4. case2：不指定pragma pack

注释去掉C++服务端的`#pragma pack(1)`，再编译运行。
```cpp
// #pragma pack(push, 1)
struct Header {
    // 2字节字符数组
    char magic[2];
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
// #pragma pack(pop)
```

### 4.1. 客户端：和原来一样

```sh
[root@xdlinux ➜ case2_no_pragma_pack git:(main) ✗ ]$ ./client 
2025/08/07 06:56:56 header len:16, bodyBuf len:16
2025/08/07 06:56:56 req headerBuf len:14, bodyBuf len:16
发送成功:
Header:
  Magic:    AB (0x4142)
  Version:  0x0101
  Command:  0x0001
  BodyLen:  16
  Checksum: 0x0000066E

Body:
  SeqNum:   0x11223344
  Timestamp:0x5566778899AABBCC
  Data:     "TEST"

Raw Bytes (30 bytes):
  [0000] 41 42 01 01 00 01 00 00
  [0008] 00 10 00 00 06 6E 11 22
  [0010] 33 44 55 66 77 88 99 AA
  [0018] BB CC 54 45 53 54
```

### 4.2. 服务端：报错

由于结构体默认的对齐补齐规则，识别头长度变成了`16`字节，以该方式接收导致数据错位了：`bodyLen:1048576`

```sh
[root@xdlinux ➜ case2_no_pragma_pack git:(main) ✗ ]$ ./server 
Server listening on port 8080...
size Header:16
len:16, rc:16
bodyLen:1048576
len:1048576, rc:14
len:1048562, rc:0
接收失败: 连接关闭
recv body failed
```

## 5. case3：客户端调整

针对服务端无法变动的场景，比如只是写工具获取服务端信息，就只能调整客户端逻辑：**<mark>精确匹配服务端的结构体对齐方式</mark>**。

### 5.1. 服务端默认对齐布局

再看下服务端结构，默认对齐：
```cpp
// #pragma pack(push, 1)
struct Header {
    // 2字节字符数组
    char magic[2];     // 0-1
    uint16_t version;  // 2-3
    uint16_t command;  // 4-5
                       // 6-7 对齐，填充2字节
    uint32_t bodyLen;  // 8-11
    uint32_t checksum; // 12-15
}; // 总大小16字节

struct Body {
    uint32_t seqNum;    // 0-3
                        // 4-7 对齐，填充4字节
    uint64_t timestamp; // 8-15
    char data[4];       // 16-19
                        // 20-23 补齐，填充4字节
}; // 总大小24字节
// #pragma pack(pop)
```


并在服务端增加：
```cpp
std::cout << "Magic offset: " << offsetof(Header, magic) << std::endl;
std::cout << "Version offset: " << offsetof(Header, version) << std::endl;
std::cout << "Command offset: " << offsetof(Header, command) << std::endl;
std::cout << "BodyLen offset: " << offsetof(Header, bodyLen) << std::endl;
```

```sh
[root@xdlinux ➜ case3_client_padding git:(main) ✗ ]$ ./server
Server listening on port 8080...
size Header:16
len:16, rc:16
Magic offset: 0
Version offset: 2
Command offset: 4
BodyLen offset: 8
bodyLen:16
len:16, rc:16
Body too small: 16 < 24
```

### 5.2. 方法1：手动添加填充字段

```go
package main

import (
    "encoding/binary"
    "fmt"
    "log"
    "net"
    "strconv"
    "unsafe"
)

const (
    MAGIC    = "AB" // 2字节字符数组
    VERSION  = 0x0101
    CMD_TEST = 0x0001
)

type Header struct {
    Magic    [2]byte  // 0-1
    Version  uint16   // 2-3 (紧接Magic，不需要填充)
    Command  uint16   // 4-5
    _        [2]byte  // 6-7: 2字节填充，和C一致
    BodyLen  uint32   // 8-11
    Checksum uint32   // 12-15
} // 总大小16字节

// 而不是：
// type Header struct {
//     Magic    [2]byte  // 2字节
//     _        [2]byte  // 填充2字节：使Version从4字节开始（假设4字节对齐）
//     Version  uint16   // 2字节
//     Command  uint16   // 2字节
//     BodyLen  uint32   // 4字节
//     Checksum uint32   // 4字节
// }

type Body struct {
    SeqNum    uint32   // 0-3
    _         [4]byte  // 4-7: 填充（使Timestamp对齐到8字节）
    Timestamp uint64   // 8-15
    Data      [4]byte  // 16-19
    _         [4]byte  // 20-23: 填充（使总大小为24字节），和C++补齐对应
}

// 序列化时手动处理填充
func serializeHeader(h Header) []byte {
    buf := make([]byte, 16)
    // 按实际偏移量写入
    copy(buf[0:2], h.Magic[:])          // 0-1
    binary.BigEndian.PutUint16(buf[2:4], h.Version)  // 2-3
    binary.BigEndian.PutUint16(buf[4:6], h.Command)  // 4-5
    // 6-7 为填充区（保留为0）
    binary.BigEndian.PutUint32(buf[8:12], h.BodyLen) // 8-11
    binary.BigEndian.PutUint32(buf[12:16], h.Checksum) // 12-15
    return buf
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
    // bodyBuf := new(bytes.Buffer)
    // binary.Write(bodyBuf, binary.BigEndian, body.SeqNum)
    // binary.Write(bodyBuf, binary.BigEndian, body.Timestamp)
    // bodyBuf.Write(body.Data[:])
    // 也按对齐补齐填充后的偏移来设置数据，和服务端保持一致
    bodyBuf := make([]byte, 24)
    binary.BigEndian.PutUint32(bodyBuf[0:4], body.SeqNum)
    binary.BigEndian.PutUint64(bodyBuf[8:16], body.Timestamp)
    copy(bodyBuf[16:20], body.Data[:])

    // 准备协议头
    header := Header{
        Magic:    [2]byte{MAGIC[0], MAGIC[1]},
        Version:  VERSION,
        Command:  CMD_TEST,
        BodyLen:  uint32(len(bodyBuf)),
    }
    // 虽然此处header打印16字节（也有对齐补齐），但下面传输的二进制是手动指定了二进制流
    log.Printf("Header len:%d, Body len:%d", unsafe.Sizeof(Header{}), unsafe.Sizeof(Body{}))

    // 计算校验和（基于大端序数据计算）
    checksum := calculateChecksum(bodyBuf)
    header.Checksum = checksum

    // 序列化协议头
    headerBuf := serializeHeader(header)
    log.Printf("req headerBuf len:%d, bodyBuf len:%d", len(headerBuf), len(bodyBuf))

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
    fmt.Printf("  Magic:    %s (0x%X)\n", string(header.Magic[:]), header.Magic)
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

```sh
[root@xdlinux ➜ case3_client_padding git:(main) ✗ ]$ ./client
2025/08/07 07:56:59 Header len:16, Body len:24
2025/08/07 07:56:59 req headerBuf len:16, bodyBuf len:24
发送成功:
Header:
  Magic:    AB (0x4142)
  Version:  0x0101
  Command:  0x0001
  BodyLen:  24
  Checksum: 0x0000066E

Body:
  SeqNum:   0x11223344
  Timestamp:0x5566778899AABBCC
  Data:     "TEST"

Raw Bytes (40 bytes):
  [0000] 41 42 01 01 00 01 00 00
  [0008] 00 00 00 18 00 00 06 6E
  [0010] 11 22 33 44 00 00 00 00
  [0018] 55 66 77 88 99 AA BB CC
  [0020] 54 45 53 54 00 00 00 00
```

```sh
[root@xdlinux ➜ case3_client_padding git:(main) ✗ ]$ ./server
Server listening on port 8080...
size Header:16
len:16, rc:16
Magic offset: 0
Version offset: 2
Command offset: 4
BodyLen offset: 8
bodyLen:24
len:24, rc:24

Received Packet:
Header:
Magic: A(0x41) B(0x42) 
  Version:  0x101
  Command:  0x1
  BodyLen:  24
  Checksum: 0x66e

Body:
  SeqNum:   0x11223344
  Timestamp:0x5566778899aabbcc
  Data:     'TEST'

Raw Bytes (28 bytes):
  [0000] 41 42 01 01 01 00 00 00 
  [0008] 18 00 00 00 6E 06 00 00 
  [0010] 11 22 33 44 00 00 00 00 
  [0018] 55 66 77 88 99 AA BB CC 
  [0020] 54 45 53 54 00 00 00 00
```

## 6. 小结

大小端字节序、网络字节序实验。

## 7. 参考

* LLM