---
title: 行为型设计模式-命令模式
categories: 设计模式
tags: 设计模式
---

行为型设计模式-命令模式模式示例记录

## 1. 背景

通过示例(C++)加强对设计模式的体感。

## 2. 23种设计模式简要说明

![23种设计模式](/images/2024-05-12-20240512100608.png)

这里说明命令模式

## 3. 命令模式(Command Pattern)

命令模式（Command Pattern）是设计模式中的一种行为型模式，它将一个请求封装为一个对象，从而使你可用不同的请求对客户进行参数化；对请求排队或记录请求日志，以及支持可撤销的操作。命令模式允许系统在不了解具体请求的情况下，对请求进行排队、记录、操作、撤销等处理。

### 3.1. 主要角色

1. **命令（Command）**：声明了一个执行操作的接口。
2. **具体命令（ConcreteCommand）**：实现命令接口，具体执行一个操作。
3. **调用者（Invoker）**：负责调用命令对象执行请求，相关命令的对象保持在一个集合中。
4. **接收者（Receiver）**：执行命令的具体对象，真正执行命令的地方。

### 3.2. 工作原理

1. 客户端创建具体的命令对象，并设置它的接收者。
2. 调用者将命令对象保存在一个集合中。
3. 调用者调用命令对象上的执行方法，命令对象会调用接收者的相应方法来完成请求。

### 3.3. 优点

1. **解耦**：命令模式将请求者与执行者解耦，降低了系统的耦合度。
2. **扩展性**：增加新的命令很容易，只需要实现新的具体命令类即可。
3. **可记录与撤销**：可以将命令对象存储起来，以便在需要时撤销命令或重新执行命令。
4. **队列请求**：可以将命令对象放入队列中，按照队列的顺序执行命令。

### 3.4. 示例场景

假设你正在开发一个文本编辑器，用户可以对文档进行多种操作，如撤销、重做、复制、粘贴等。使用命令模式，你可以将这些操作封装为命令对象，并允许用户按照任何顺序执行这些命令。同时，你还可以轻松实现撤销和重做功能，因为你可以将命令对象存储起来，并在需要时重新执行或撤销它们。

### 3.5. 代码示例

```cpp
#include <iostream>  
#include <vector>  
#include <memory>  
  
// Command基类  
class Command {  
public:  
    virtual ~Command() {}  
    virtual void execute() = 0;  
    virtual void undo() = 0;  
};  
  
// Receiver类  
class Receiver {  
public:  
    void actionPerformed() {  
        std::cout << "Action performed!" << std::endl;  
    }  
    void undoAction() {  
        std::cout << "Action undone!" << std::endl;  
    }  
};  
  
// ConcreteCommand类  
class ConcreteCommand : public Command {  
private:  
    Receiver* receiver;  
public:  
    ConcreteCommand(Receiver* receiver) : receiver(receiver) {}  
    void execute() override {  
        receiver->actionPerformed();  
    }  
    void undo() override {  
        receiver->undoAction();  
    }  
};

// Invoker类，它持有一个或多个Command对象的std::shared_ptr
class Invoker {  
private:  
    std::vector<std::shared_ptr<Command>> commands;  
public:  
    void storeCommand(std::shared_ptr<Command> command) {  
        commands.push_back(command);  
    }  
    void executeCommand(int index) {  
        if (index >= 0 && index < commands.size()) {  
            commands[index]->execute();  
        }  
    }  
    void undoCommand(int index) {  
        if (index >= 0 && index < commands.size()) {  
            commands[index]->undo();  
        }  
    }  
};

int main() {  
    Receiver receiver;  
    std::shared_ptr<Command> command(new ConcreteCommand(&receiver));  
  
    Invoker invoker;  
    invoker.storeCommand(command);  
  
    // 执行命令  
    invoker.executeCommand(0);  
  
    // 撤销命令（这里只是假设，因为实际上我们只有一个命令）  
    invoker.undoCommand(0);  
  
    return 0;  
}
```

g++ command.cpp -std=c++11 -o command

## 4. 小结

1、通过示例介绍了命令模式

## 5. 参考

1、GPT
