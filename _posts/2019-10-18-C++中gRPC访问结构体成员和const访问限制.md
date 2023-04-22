---
layout: post
title: C++中gRPC访问结构体成员和const访问限制
categories: C/C++
tags: const gRPC
---

* content
{:toc}

介绍C++中gRPC访问结构体成员的方式和const成员函数访问时的限制。



当gRPC proto协议中定义的message消息不仅仅包含基本的int、string等类型，还包含结构体类型时，访问结构体类型成员不适用`.变量名()/.set_变量名()`形式。

传入参数被const修饰时，访问内部非const函数，编译会遇到的问题和正常使用方式。

## gRPC C++访问结构体成员

参考：

[对set_allocated_和mutable_的使用](https://blog.csdn.net/wujunokay/article/details/51287312)

[gRPC Basics - C++](https://grpc.io/docs/tutorials/basic/cpp/)

对于grpc中的结构体成员，通过：
`request->mutable_B类型成员名b()` 的方式访问，

查看分析grpc生成的.cpp和.h文件代码，生成的成员函数为`mutable_`、`set_allocated_`，通过这种方式访问和设置成员。

### 代码演示

另外分析函数入参被限定为const时的访问情况：

#### 程序伪代码：

```cpp

// 假设 B b; 是A的成员变量
void func(const &B)
{
}
...(const A *request) 
{
    // A类中的成员b作为入参，调用func函数，表面上需要解引用作为入参，但直接解引用会报错
    func(*request->mutable_b());
}

// grpc访问结构体成员
// 若request为const修饰的变量，要调用如下func函数的话，需要解引用，会出现const的this调用非const函数，编译报类似下面错误。
```

#### 编译报错：

```sh
# const访问问题
错误：将‘const A’作为‘B* A::mutable_Bstructfield()’的‘this’实参时丢弃了类型限定 [-fpermissive]
```

#### 正确使用方式：

可通过新增变量方式解引用：

```cpp
    auto a = new A;  //注意资源的释放，可以改成智能指针防止忘记
    a->CopyFrom(*request)
    func(*a->mutable_b)
```

## const成员函数功能及使用

参考

zh.cppreference.com：
[const、volatile 及引用限定的成员函数](https://zh.cppreference.com/w/cpp/language/member_functions#const.E3.80.81volatile_.E5.8F.8A.E5.BC.95.E7.94.A8.E9.99.90.E5.AE.9A.E7.9A.84.E6.88.90.E5.91.98.E5.87.BD.E6.95.B0)

对const修饰成员函数的功能作用，做一个说明和实例演示。

const、volatile 及引用限定的成员函数

* 非静态成员函数可声明为带有 const、volatile 或 const volatile 限定符（这些限定符出现在函数声明中的形参列表之后）。
* cv 限定性不同的函数具有不同类型，从而可以相互重载。
* 在 cv 限定的函数体内，this 指针被 cv 限定，**const 成员函数中，只能正常地调用其他 const 成员函数。**

### 参考中的示例：

```cpp
#include <vector>
struct Array {
    std::vector<int> data;
    Array(int sz) : data(sz) {}
    // const 成员函数
    int operator[](int idx) const {
                          // this 具有类型 const Array*
        return data[idx]; // 变换为 (*this).data[idx];
    }
    // non-const member function
    int& operator[](int idx) {
                          // this 具有类型 Array*
        return data[idx]; // 变换为 (*this).data[idx]
    }
};
int main()
{
    Array a(10);
    a[1] = 1; // OK：a[1] 的类型是 int&
    const Array ca(10);
    ca[1] = 2; // 错误：ca[1] 的类型是 int
}
```

### 自定义类编译演示

单独定义简单类进行编译演示const变量及const成员函数

#### 印证：

1. const 成员函数中，只能正常地调用其他 const 成员函数
2. 定义的const 变量，只能访问非const成员函数

#### 自定义一个类演示

成员函数以const在形参列表后修饰：

```cpp
#include <iostream>
using namespace std;

class Apple
{
public:
    void print() const;
    void func2();
    void func3() const;
    Apple():color(1){}
private:
    int color;
};

void Apple::print() const
{
    cout << __FUNCTION__ << endl;
    // func2(); //编译报错：丢弃了类型限定 [-fpermissive]
    func3();
    cout << this->color << endl;
}

void Apple::func2()
{
    cout << __FUNCTION__ << endl;
}

void Apple::func3() const
{
    cout << __FUNCTION__ << endl;
}

int main(int argc, const char *argv[])
{
    Apple apple;
    apple.print(); // 以下调用都正常
    apple.func2();
    apple.func3();

    const Apple apple2;
    // apple2.func2();   //编译报错：将‘const Apple’作为‘void Apple::func2()’的‘this’实参时丢弃了类型限定 [-fpermissive]

    return 0;
}
```

#### 编译情况

```
[➜ /home/xd/workspace/src ]$ ./a.out
print
func3
1
```

放开print()函数中的 `func2()` 注释，编译报错：

```sh
[➜ /home/xd/workspace/src ]$ g++ test_const_func.cpp
test_const_func.cpp: 在成员函数‘void Apple::print() const’中:
test_const_func.cpp:19:8: 错误：将‘const Apple’作为‘void Apple::func2()’的‘this’实参时丢弃了类型限定 [-fpermissive]
```
