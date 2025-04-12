---
title: C++不可拷贝类和右值引用
categories: C/C++
tags: 右值引用
---

介绍右值引用和不可拷贝类在C++11之前和C++11中，以及boost中的用法。

并对C++11中新特性：delete弃置函数和default，以及constexpr进行说明。

## 不可拷贝类

参考：

[C++ 编写一个不可复制的类](https://blog.csdn.net/flyfish1986/article/details/43305363)

其中介绍C++11之前和C++11中，以及Boost中的实现使用

>Effective C++:条款06
若不想使用编译器自动生成的函数，就该明确拒绝 .
Explicitly disallow the use of complier-generated functions you do not want.

### C++11前的写法

定义如下基类再进行继承(noncopyable类名可自定义)

```cpp
class noncopyable
{
protected:
    noncopyable() {}
    ~noncopyable() {}
private:
    noncopyable(const noncopyable&);
    noncopyable& operator=(const noncopyable&);
};

class Example:private noncopyable{
    ...
};
```

### C++11的写法

定义类，并使用delete关键字限定 拷贝构造函数 和 拷贝赋值运算符(复制赋值运算符)

```cpp
class Example
{
protected:
    constexpr Example() = default;
    ~Example() = default;
    Example(const Example&) = delete;
    Example& operator=(const Example&) = delete;
};
```

C++11中的`delete`弃置函数 和 `default`函数，参考：

[C++11 标准新特性：Defaulted 和 Deleted 函数](https://www.ibm.com/developerworks/cn/aix/library/1212_lufang_c11new/)

* `= delete`
    - 在某些情况下，假设我们不允许发生类对象之间的拷贝和赋值，可是又无法阻止编译器隐式自动生成默认的拷贝构造函数以及拷贝赋值操作符，那这就成为一个问题了。
    - 为了能够让程序员显式的禁用某个函数，C++11 标准引入了一个新特性：deleted 函数。
    - Deleted 函数特性还可用于禁用类的某些转换构造函数，从而避免不期望的类型转换。`X(int) = delete; `
    - Deleted 函数特性还可以用来禁用某些用户自定义的类的 new 操作符，从而避免在自由存储区创建类的对象。`void *operator new(size_t) = delete;`
    - 非类的成员函数，即普通函数也可以被声明为 deleted 函数。
* `= default`
    - 用户自定义了**非默认构造函数**(即有参数的构造)，却没定义默认构造函数(无参构造)时，`C c`形式定义变量会编译错误; 而若类定义中`C() = default;`指定使用默认特殊成员函数则正常。
    - 只需在函数声明后加上“=default;”，就可将该函数声明为 defaulted 函数，编译器将为显式声明的 defaulted 函数自动生成函数体。
    - Defaulted 函数特性仅适用于类的特殊成员函数，且该特殊成员函数没有默认参数。
    - Defaulted 函数既可以在类体里（inline）定义，也可以在类体外（out-of-line）定义。

对于上面的`constexpr`关键字，参考：

[constexpr和常量表达式](https://blog.csdn.net/qq_37653144/article/details/78518071)

* `constexpr`
    - constexpr是C++11开始提出的关键字，其意义与14版本有一些区别。
    - 指定变量或函数的值可在常量表达式中出现，可以在编译时求得函数或变量的值。
    - constexpr变量、constexpr函数、constexpr构造函数，各有要求
    - C++11中的constexpr指定的函数返回值和参数必须要保证是字面值
    - constexpr构造函数体一般来说应该是空的，因此对函数成员的初始化必须放在初始化列表中。
    - constexpr构造函数的详细要求，以下列出部分，参考[constexpr 说明符(C++11 起)](https://zh.cppreference.com/w/cpp/language/constexpr)
        + 构造函数体必须被弃置或预置，或只含有下列内容：
            * 空语句
            * static_assert 声明
            * 不定义类或枚举的 typedef 声明及别名声明
            * using 声明
            * using 指令
        + 对于 class 或 struct 的构造函数，每个子对象和每个非变体非 static 数据成员必须被初始化。

* constexpr的好处：
    - 是一种很强的约束，更好地保证程序的正确语义不被破坏。
    - 编译器可以在编译期对constexpr的代码进行非常大的优化，比如将用到的constexpr表达式都直接替换成最终结果等。
    - 相比宏来说，没有额外的开销，但更安全可靠。

关于类定义时自动产生的几个默认成员函数(特殊成员函数)，以下小节进行说明：

#### 特殊成员函数

参考：

[特殊成员函数](https://www.cnblogs.com/xinxue/p/5503836.html)

* C++98 编译器会隐式的产生四个函数：缺省构造函数，析构函数，拷贝构造函数 和 拷贝赋值运算符，它们称为**特殊成员函数 (special member function)**
* 在 C++11 中，除了上面四个外，特殊成员函数还有两个：移动构造函数 和 移动赋值运算符
    - [复制赋值运算符](https://zh.cppreference.com/w/cpp/language/copy_assignment)
    - [移动赋值运算符](https://zh.cppreference.com/w/cpp/language/move_assignment) (C++11 起)

参考伪代码：

```cpp
class DataOnly {
public:
    DataOnly ()                  // default constructor 缺省构造函数
    ~DataOnly ()                 // destructor 析构函数

    DataOnly (const DataOnly & rhs)            // copy constructor 拷贝构造函数
    DataOnly & operator=(const DataOnly & rhs) // copy assignment operator 拷贝赋值算子/运算符

    DataOnly (const DataOnly && rhs)         // C++11, move constructor 移动构造函数
    DataOnly & operator=(DataOnly && rhs)    // C++11, move assignment operator 移动赋值算子/运算符
};
```

#### 右值引用和移动语义

对移动构造函数和移动赋值运算符的说明

参考 知乎专栏[Modern C++学习笔记]：

[C++右值引用](https://zhuanlan.zhihu.com/p/54050093)

几个概念：

* 移动语义
    - 将内存的所有权从一个对象转移到另外一个对象，高效的移动用来替换效率低下的复制。
    - 对象的移动语义需要实现移动构造函数（move constructor）和移动赋值运算符（move assignment operator）。

* 左值引用
    - 智能绑定在左值上 (const引用例外: `int const& i = 42;`)
    - 函数入参 `func(int &input)`

* 右值引用
    - C++11标准添加了右值引用(rvalue reference)
    - 这种引用只能绑定右值，不能绑定左值，它使用两个&&来声明

右值引用示例：

```cpp
int&& i=42;
int j=42;
int&& k=j;  // 编译失败，j不是右值 编译报错："无法将左值‘int’绑定到‘int&&’"
```

```cpp
int x = 20;   // 左值
int&& rx = x * 2;  // x*2的结果是一个右值，rx延长其生命周期
int y = rx + 2;   // 因此你可以重用它：42
rx = 100;         // 一旦你初始化一个右值引用变量，该变量就成为了一个左值，可以被赋值
```

这点很重要：**初始化之后的右值引用将变成一个左值，如果是non-const还可以被赋值！**

函数接收示例：

```cpp
// 接收左值
void fun(int& lref)
{
    cout << "l-value reference\n";
}
// 接收右值
void fun(int&& rref)
{
    cout << "r-value reference\n";
}

// 其实它不仅可以接收左值，而且可以接收右值（如果你没有提供接收右值引用的重载版本(注意该前提)）
// 如果注释void fun(int&& rref)，fun(10);运行时，也会调用该函数
void fun(const int& clref)
{
    cout << "l-value const reference\n";
}

int main()
{
    int x = 10;
    fun(x);  // output: l-value reference
    fun(10); // output: r-value reference，若注释void fun(int&& rref)，则l-value const reference
    const int y = 10;
    fun(10);  // output: l-value const reference
}
```

* 一旦你已经自己创建了复制构造函数与复制赋值运算符后，编译器不会创建默认的移动构造函数和移动赋值运算符，这点要注意。
* 最好的话，这个4个函数一旦自己实现一个，就应该养成实现另外3个的习惯。
* 这就是移动语义，用移动而不是复制来避免无必要的资源浪费，从而提升程序的运行效率。
* 其实在C++11中，STL的容器都实现了移动构造函数与移动赋值运算符，这将大大优化STL容器。

* 有时候你需要将一个左值也进行移动语义（因为你已经知道这个左值后面不再使用），那么就必须提供一个机制来将左值转化为右值。
    - std::move就是专为此而生。注意示例中，move之后v1变空了。

```cpp
vector<int> v1{1, 2, 3, 4};
vector<int> v2 = v1;             // 此时调用复制构造函数，v2是v1的副本
vector<int> v3 = std::move(v1);  // 此时调用移动构造函数，v3与v1交换：v1为空，v3为{1, 2, 3, 4}
```

移动构造函数示例(参考[拷贝构造函数和移动构造函数](https://www.jianshu.com/p/f5d48a7f5a52)：

* 示例中编译添加了编译选项`-fno-elide-constructors`来禁止初始化变量时临时变量优化，若不禁止，5和7被优化了，如下：

```sh
[➜ /home/xd/workspace/src ]$ g++ test_mv_constructor.cpp

[➜ /home/xd/workspace/src ]$ ./a.out
-------------------------5-------------------------
Constructor
-------------------------6-------------------------
Move Constructor
-------------------------7-------------------------
Constructor
```

* -fno-elide-constructors选项

>-fno-elide-constructors
The C++ standard allows an implementation to omit creating a temporary which is only used to initialize another object of the same type. Specifying this option disables that optimization, and forces G++ to call the copy constructor in all cases.
当被用来初始化另一个相同类型的另外对象时，省略产生临时变量。 可以禁止此项优化，来强制使g++在所有的cases中调用copy constructor。

### Boost的实现用法

- Boost不仅将两种方法结合，还防止无意识的参数相关查找(protection from unintended ADL)
- ADL(Argument Dependent Lookup) 参考：[ADL（编程用语）](https://baike.baidu.com/item/ADL/18763333)
    + 完全限定名：带完整命名空间的路径标识
    + 限定域 和 无限定域，限定的作用域包含：类域、名字空间域、全局域
    + 也称Koenig查找，当编译器对无限定域的函数调用进行名字查找时，查找函数时，除了当前名字空间域以外，也会把函数参数类型所处的名字空间加入查找的范围

```cpp
namespace boost {
    namespace noncopyable_
    {
        class noncopyable
        {
        };
    }
    typedef noncopyable_::noncopyable noncopyable;
}

// 在写一个 class 的时候，继承 boost::noncopyable
class Apple: boost::noncopyable{};
```
