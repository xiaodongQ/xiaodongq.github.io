---
layout: post
title: Rust学习实践（三） -- Rust特性进阶学习（上）
categories: Rust
tags: Rust
---

* content
{:toc}

Rust学习实践，进一步学习梳理Rust特性。



## 1. 背景

上两篇过了一遍Rust基础语法并进行demo练习，本篇继续进一步学习下Rust特性。

相关特性主要包含：生命周期、函数式编程（迭代器和闭包）、智能指针、循环引用、多线程并发编程；异步编程、Macro宏编程、Unsafe等，分两篇博客笔记梳理记录。

*说明：本博客作为个人学习实践笔记，可供参考但非系统教程，可能存在错误或遗漏，欢迎指正。若需系统学习，建议参考原链接。*

## 2. 生命周期

[之前](https://xiaodongq.github.io/2024/09/17/rust-relearn-overview/)过基础语法时，简单提到过生命周期的基本使用，这次进一步理解下。

基于下述链接梳理学习：

* [Rust语言圣经(Rust Course) -- 基础入门：认识生命周期](https://course.rs/basic/lifetime.html)
* [Rust语言圣经(Rust Course) -- 进阶学习：生命周期](https://course.rs/advance/lifetime/intro.html)
* [The Rust Programming Language -- Validating References with Lifetimes](https://doc.rust-lang.org/book/ch10-03-lifetime-syntax.html)

对应代码练习，在 [test_lifetime](https://github.com/xiaodongQ/rust_learning/tree/master/test_lifetime)。

> 在大多数时候，我们无需手动的声明生命周期，因为编译器可以自动进行推导。但是当多个生命周期存在，且编译器无法推导出某个引用的生命周期时，就需要我们手动标明生命周期。

**生命周期标注并不会改变任何引用的实际作用域**，标记生命周期只是告诉Rust编译器，多个引用之间的生命周期关系。


### 2.1. 函数中的生命周期示例

**函数的返回值如果是一个引用类型，那么它的生命周期只会来源于：**

* 从参数获取 （称为`输入生命周期`，返回值的生命周期则称为`输出生命周期`）
* 从函数体内部新创建的变量获取（典型的悬垂引用，编译器会报错拦截）

再贴一个上述基础入门中的例子：下面 `longest` 函数中的参数和返回值标注，表示返回值的生命周期取作用域最小的那个。

```rust
// 此处生命周期标注仅仅说明，这两个参数 x、y 和返回值至少活得和 'a 一样久(因为返回值要么是 x，要么是 y)
// 实际上，这意味着返回值的生命周期与参数生命周期中的较小值一致
// 由于返回值的生命周期也被标记为 'a，因此返回值的生命周期也是 x 和 y 中作用域较小的那个
fn longest<'a>(x: &'a str, y: &'a str) -> &'a str {
    if x.len() > y.len() {
        x
    } else {
        y
    }
}

// 编译会出错，因为result的访问超出了string2的作用域（最小的那个生命周期）
fn return_lifetime() {
    let string1 = String::from("long string is long");
    let result;
    {
        let string2 = String::from("xyz");
        // 此处会编译报错（括号外使用了result），
        // 因为 longest 返回的生命周期是 string1和string2中较小的那个生命周期，离开括号后string2的生命周期已经结束
        result = longest(string1.as_str(), string2.as_str());
    }
    // 注释下面这条访问result的语句，则不会报错，只是警告上面的result没使用
    println!("The longest string is {}", result);
}
```

另外举例说明下面几种函数生命周期相关的场景，可在IDE中修改验证：

* `longest`中写死返回第一个参数`x`的引用：该情况则`y`不需要标注生命周期，此时可编译通过
    * `fn longest2<'a>(x: &'a str, y: & str) -> &'a str { x }` （编译成功，注意此处y并没有生命周期标注）
* `悬垂引用（dangling reference）`示例，返回内部新建字符串的引用，编译会报错
    * `fn longest3<'a>(x: & str, y: &str) -> &'a str { String::from("hello") }` （编译失败）
* 针对上述悬垂引用的问题，一个解决方式是：返回所有权，并把内部新建字符串的所有权转移给调用者
    * `fn longest4<'a>(x: &'a str, y: &str) -> String { String::from("hello") }` （编译成功）

### 2.2. 结构体中的生命周期

调整cargo项目中的目录结构，不同文件验证不同场景。比如在 `main_struct.rs` 中验证struct结构体的生命周期。

通过 `cargo build --bin test_lifetime` 或 `cargo run --bin main_function` 指定`--bin`方式进行独自的编译和运行验证。

```sh
[MacOS-xd@qxd ➜ test_lifetime git:(master) ✗ ]$ tree -L 3
.
├── Cargo.lock
├── Cargo.toml
├── src
│   ├── bin
│   │   ├── main_function.rs
│   │   └── main_struct.rs
│   └── main.rs
```

结构体中生命周期定义示例：

```rust
// 先声明生命周期，再使用生命周期标注
struct ImportantExcerpt<'a> {
    part: &'a str,
}
```

* 其中有一个引用成员字段，因此必须标注生命周期
* 该生命周期标注说明，结构体`ImportantExcerpt`所 引用的字符串str 必须比 该结构体 活得更久

下述两个case进行说明：第2个case中结构体中引用字段 比 结构体 本身的生命周期短，编译会报错。

```rust
// 需要保证结构体中引用字段的生命周期 比 结构体本身的生命周期 **更长**
fn test_success() {
    let novel = String::from("Call me Ishmael. Some years ago...");
    let first_sentence = novel.split('.').next().expect("Could not find a '.'");
    let text = ImportantExcerpt {
        part: first_sentence,
    };
    println!("info: {:?}", text);
}

// 编译失败
fn test_failed() {
    // 结构体定义
    let text;

    {
        let novel = String::from("Call me Ishmael. Some years ago...");
        // next() 返回一个 Option<&'a str>，成功时，返回一个切片引用
        let first_sentence = novel.split('.').next().expect("Could not find a '.'");
        // 引用字段的生命周期 比 结构体本身的生命周期 短，而大括号外又访问了，所以会编译失败（注释外面访问则可正常编译运行）
        text = ImportantExcerpt {
            part: first_sentence,
        };
        // 正常打印
        println!("info1: {:?}", text);
    }
    
    // 大括号外访问，结构体和其中字段引用的生命周期不满足生命周期条件，所以会编译失败
    println!("info2: {:?}", text);
}
```

### 2.3. 生命周期消除规则

生命周期消除的三条规则（编译器如何让输入和输出生命周期保持对应）：

* 1、每一个引用参数都会获得独自的生命周期
    * `fn foo<'a, 'b>(x: &'a i32, y: &'b i32)`
* 2、若只有一个`输入生命周期`(函数参数中只有一个引用类型)，那么该生命周期会被赋给所有的`输出生命周期`
    * 也就是所有返回值的生命周期都等于该输入生命周期
    * `fn foo(x: &i32) -> &i32` 等同于 `fn foo<'a>(x: &'a i32) -> &'a i32`
* 3、若存在多个输入生命周期，且其中一个是 `&self` 或 `&mut self`，则 `&self` 的生命周期被赋给所有的输出生命周期
    * 拥有 `&self` 形式的参数，说明该函数是一个**方法**，该规则让方法的使用便利度大幅提升
    * 上面是未显式标记时的默认表现，也可手动标注生命周期进行指定。比如将部分输出生命周期指定得更短

示例：`fn first_word(s: &str) -> &str { xxx }`，编译器应用上述规则的简化过程如下

* 首先，应用第1条规则，为每个参数标注一个生命周期
    * `fn first_word<'a>(s: &'a str) -> &str { xxx }`
* 然后，应用第2条规则，因为只有一个`输入生命周期`，所以返回值生命周期（`输出生命周期`）也是 `'a`
    * `fn first_word<'a>(s: &'a str) -> &'a str { xxx }`
* 此时，编译器为函数签名中的所有引用都自动添加了具体的生命周期，因此编译通过，且用户无需手动去标注生命周期

### 2.4. 方法中的生命周期

为具有生命周期的结构体实现方法时，使用的语法和 泛型参数语法 类似：

* `impl`中必须使用结构体的完整名称，包括 `<'a>`，因为生命周期标注也是结构体类型的一部分（比如上面的`ImportantExcerpt<'a>`）
* 方法签名中，往往不需要标注生命周期，得益于生命周期消除的第一和第三规则

```rust
struct ImportantExcerpt<'a> {
    part: &'a str,
}

impl<'a> ImportantExcerpt<'a> {
    fn announce_and_return_part(&self, announcement: &str) -> &str {
        println!("Attention please: {}", announcement);
        self.part
    }
}
```

编译器应用消除规则的简化过程如下：

* 首先，编译器应用第1条规则，为每个输入参数标注一个生命周期
    * `fn announce_and_return_part<'b>(&'a self, announcement: &b' str) -> &str { xxx }`
    * 注意：编译器不知道`announcement`参数的生命周期到底多长，因此它无法简单的给予它生命周期`'a`，而是重新声明了一个全新的生命周期`'b`
* 然后，应用第3条规则，将`&self`的生命周期赋给返回值`&str`
    * `fn announce_and_return_part<'b>(&'a self, announcement: &'b str) -> &'a str { xxx }`

若手动标注返回值的生命周期为`'b`，则需要说明`'a`和`'b`的关系，即`'a`的生命周期必须大于等于`'b`的生命周期，否则编译失败。有两种方式：

1. 在函数定义后面添加生命周期约束，即`where 'a: 'b`，表示`'a`的生命周期必须大于等于`'b`的生命周期
    * 下面`where`语句的代码规范要求是：换行，并且where 子句和 where 关键字不在同一行
2. 把 `'a` 和 `'b` 都在同一个地方声明，比如：`impl<'a: 'b, 'b>`

```rust
// 方式1，通过where添加生命周期约束
impl<'a> ImportantExcerpt <'a> {
    fn print_and_return_part2<'b>(&'a self, info: &'b str) -> &'b str 
    where
        'a : 'b,
    {
        println!("info: {}", info);
        self.part
    }
}

// 方式2: 在函数签名中显式地标注生命周期
impl<'a: 'b, 'b> ImportantExcerpt <'a> {
    // 上面声明了'b，这里就不需要再声明了
    fn print_and_return_part3(&'a self, info: &'b str) -> &'b str {
        println!("info: {}", info);
        self.part
    }
}
```

### 2.5. 无届生命周期

不安全代码(`unsafe`)经常会凭空产生引用或生命周期，这些生命周期被称为是 **无界(unbound)** 的。

无界生命周期往往是在解引用一个裸指针(裸指针 raw pointer)时产生的，换句话说，它是凭空产生的，因为输入参数根本就没有这个生命周期：

```rust
// 参数 x 是一个裸指针，它并没有任何生命周期，
// 然后通过 unsafe 操作后，它被进行了解引用，变成了一个 Rust 的标准引用类型，该类型必须要有生命周期，也就是 'a
fn f<'a, T>(x: *const T) -> &'a T {
    unsafe {
        &*x
    }
}
```

在实际应用中，要尽量避免这种无界生命周期。

最简单的避免无界生命周期的方式就是在函数声明中运用生命周期消除规则。**若一个输出生命周期被消除了，那么必定因为有一个输入生命周期与之对应。**

### 2.6. 生命周期约束：HRTB

在Rust中，`Higher-Ranked Trait Bounds (HRTB)`（高阶trait约束）是一种用来表达更复杂的生命周期和泛型约束的语法。

#### 2.6.1. `'a: 'b`语法

`'a: 'b`：说明两个生命周期的长短关系

* 若两个引用的生命周期 `'a >= 'b`，则可以定义 `'a: 'b`，表示 `'a` 至少要活得跟 `'b` 一样久

示例及说明：

* 结构体`DoubleRef`拥有两个引用字段，类型都是泛型`T`，每个引用都拥有自己的生命周期
* 生命周期约束`'b: 'a`，表示 `'b` 必须活得比 `'a` 久，也就是结构体中的 `s` 字段引用的值必须要比 `r` 字段引用的值活得要久

```rust
struct DoubleRef<'a, 'b:'a, T> {
    r: &'a T,
    s: &'b T
}
```

#### 2.6.2. `T: 'a`语法

`T: 'a`：表示类型 `T` 必须比 `'a` 活得要久

示例及说明：

```rust
// 结构体字段 r 引用了 T，因此 r 的生命周期 'a 必须要比 T 的生命周期更短(被引用者的生命周期必须要比引用长)。
// 泛型T生命周期更长
struct Ref<'a, T: 'a> {
    r: &'a T
}

// 从 1.31 版本开始，编译器可以自动推导 T: 'a 类型的约束，只需写成如下形式即可
struct Ref<'a, T> {
    r: &'a T
}
```

### 2.7. 其他

#### 2.7.1. 闭包函数的消除规则

下面两个一模一样功能的函数，一个正常编译，一个却报错，错误原因是编译器无法推测返回的引用和传入的引用谁活得更久：

```rust
// 对于函数的生命周期而言，它的消除规则之所以能生效是因为它的生命周期完全体现在签名的引用类型上，在函数体中无需任何体现
fn fn_elision(x: &i32) -> &i32 { x }

// 会报错
// 闭包并没有函数那么简单，它的生命周期分散在参数和闭包函数体中(主要是它没有确切的返回值签名)
// Rust 语言开发者目前其实是有意针对函数和闭包实现了两种不同的生命周期消除规则
let closure_slision = |x: &i32| -> &i32 { x };
```

> 上述类似的问题，可能很难被解决，建议大家遇到后，还是老老实实用正常的函数，不要秀闭包了。

#### 2.7.2. NLL: Non-Lexical Lifetimes

`NLL: Non-Lexical Lifetimes`，**非词法生命周期**：

`NLL` 是 Rust 1.31 版本引入的一个新特性，它允许编译器在编译时自动推导出生命周期，无需手动标注。

在 `NLL` 出现之前，Rust 使用一种相对简单的“**词法**”生命周期规则，这意味着一个引用的有效范围通常由包含它的最内层大括号 `{}` 来界定。`NLL`引入了一种更加智能的方式来确定变量的生命周期。

规则变化：由 "引用的生命周期正常来说应该从借用开始一直持续到作用域结束" 变为 "**引用的生命周期从借用处开始，一直持续到最后一次使用的地方**"

```rust
fn test_nll() {
   let mut s = String::from("hello");

    let r1 = &s;
    let r2 = &s;
    println!("{} and {}", r1, r2);
    // 新编译器中(1.31开始)，r1,r2作用域在这里结束

    let r3 = &mut s;
    println!("{}", r3);

    // 若此处还访问r1,r2，则可变引用r3存在，r1,r2被借用，无法访问。编译器会报错
    // println!("{}", r2);
}
```

#### 2.7.3. reborrow: 再借用

```rust
fn test_reborrow() {
    let mut p = Point { x: 0, y: 0 };
    let r = &mut p;
    // 对于再借用而言，rr 再借用时不会破坏借用规则，但是不能在它的生命周期内再使用原来的借用 r
    let rr: &Point = &*r;
    // rr最后一次使用，基于NLL规则，rr作用域在这里结束

    println!("{:?}", rr);
    // 在 rr 的生命周期外，r 依然可以使用
    r.move_to(10, 10);
    println!("{:?}", r);
}

// 上面需要的结构体和方法定义
#[derive(Debug)]
struct Point {
    x: i32,
    y: i32,
}
impl Point {
    fn move_to(&mut self, x: i32, y: i32) {
        self.x = x;
        self.y = y;
    }
}
```

#### 2.7.4. `&'static`生命周期

`&'static` 生命周期表示一个引用存活得跟剩下的程序一样久。

* `&'static`针对的仅仅是引用指向的数据，而不是持有该引用的变量，对于变量来说，还是要遵循相应的作用域规则。
* 常见场景：字符串字面值 和 特征对象 的生命周期都是 `'static`
    * `&'static` 是一种具体的引用类型，指代那些引用了程序全程有效数据的引用。意味着该引用指向的数据在程序的整个运行期间都是有效的。
    * `T: 'static` 是一个泛型约束，其中`T`是某个类型参数。这里的 `'static` 表示类型 T 中包含的所有引用（如果有的话）都需要至少有 `'static` 生命周期

```rust
fn main() {
    let mark_twain: &str = "Samuel Clemens";
    print_author(mark_twain);
    print(mark_twain);
    get_memory_location();
}

// 'static 生命周期
fn print_author(author: &'static str) {
    println!("{}", author);
}

// 特征对象的生命周期也是 'static
// T: 'static
fn print<T: Display + 'static>(message: &T) {
    println!("{}", message);
}

// &'static 生命周期针对的仅仅是引用，而不是持有该引用的变量，对于变量来说，还是要遵循相应的作用域规则
fn get_memory_location() -> (usize, usize) {
    // “Hello World” 是字符串字面量，因此它的生命周期是 `'static`.
    // 但持有它的变量 `string` 的生命周期就不一样了，它完全取决于变量作用域，对于该例子来说，也就是当前的函数范围
    let string = "Hello World!";
    let pointer = string.as_ptr() as usize;
    let length = string.len();
    (pointer, length)
    // `string` 在这里被 drop 释放
    // 虽然变量被释放，无法再被访问，但是"Hello World!"数据依然还会继续存活
}
```

## 3. 小结


## 4. 参考

1、[Rust语言圣经(Rust Course) -- 基础入门：认识生命周期](https://course.rs/basic/lifetime.html)

2、[Rust语言圣经(Rust Course) -- Rust 进阶学习](https://course.rs/advance/intro.html)

3、[The Rust Programming Language -- Validating References with Lifetimes](https://doc.rust-lang.org/book/ch10-03-lifetime-syntax.html)
