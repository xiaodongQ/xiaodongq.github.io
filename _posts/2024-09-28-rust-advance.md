---
title: Rust学习实践（三） -- Rust特性：生命周期及函数式编程
categories: [编程语言, Rust]
tags: Rust
---

Rust学习实践，进一步学习梳理Rust特性。

## 1. 背景

上两篇过了一遍Rust基础语法并进行demo练习，本篇继续学习下Rust特性。

相关特性主要包含：生命周期、函数式编程（迭代器和闭包）、智能指针、循环引用、多线程并发编程；异步编程、Macro宏编程、Unsafe等。

限于篇幅，分多篇博客笔记梳理记录，本篇主要涉及：**生命周期** 及 **函数式编程（涉及闭包和迭代器）**。

*说明：本博客作为个人学习实践笔记，可供参考但非系统教程，可能存在错误或遗漏，欢迎指正。若需系统学习，建议参考原链接。*

## 2. 生命周期

[之前](https://xiaodongq.github.io/2024/09/17/rust-relearn-overview/)过基础语法时，简单提到过生命周期的基本使用，这次进一步学习下。

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

对借用(`&`)的再进行借用：`& (*借用变量)`

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

`&'static`针对的仅仅是引用指向的数据，而不是持有该引用的变量，对于变量来说，还是要遵循相应的作用域规则。

常见场景：字符串字面值 和 特征对象 的生命周期都是 `'static`

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

## 3. 函数式编程

函数式特性：闭包Closure、迭代器Iterator、模式匹配、枚举。这些函数式特性可以让代码的可读性和易写性大幅提升。

### 3.1. 闭包基本示例

[第一篇](https://xiaodongq.github.io/2024/09/17/rust-relearn-overview/) 简单介绍过闭包，下面用一个简单示例看闭包的好处（完整代码见 [github work_example](https://github.com/xiaodongQ/rust_learning/tree/master/test_functional/bin/work_example.rs)）。

1、基础代码：不同公司工作不同工作时长，工作内容是写代码

```rust
/* ================== 基本工作：要求写指定时长的代码 =================== */
fn program(duration: u32) {
    println!("program duration:{}", duration);
}

fn work(time_base: u32, company_type: &str) {
    if company_type == "955" {
        program(time_base * 1);
    } else if company_type == "996" {
        program(time_base * 2);
    } else {
        println!("other company");
    }
}
```

2、新需求1：工作内容需要转换，`program()`改成`write_ppt()`

* 存在的问题：需定义新的工作内容函数，并且要修改多处调用函数的位置。
* 解决方式：使用函数成员，调用处统一修改为函数成员即可。

```rust
/* ================== 新需求1：工作内容修改为写ppt =================== */
// 通过函数变量来修改工作内容
fn write_ppt(duration: u32) {
    println!("write_ppt duration:{}", duration);
}
fn work2(time_base: u32, company_type: &str) {
    // 函数作为参数传递，可以动态修改工作内容
    // let action = program;
    let action = write_ppt;
    if company_type == "955" {
        action(time_base * 1);
    } else if company_type == "996" {
        action(time_base * 2);
    } else {
        println!("other company");
    }
}
```

2、新需求2：工作内容需要转换，`program()`改成`write_ppt()`，`write_ppt()`改成`write_report()`

* 存在的问题：不仅入参需修改，工作内容函数也需要修改，并且要修改多处调用函数的位置。
* 解决方式：使用闭包，后续再修改工作内容，只需修改闭包即可，无需修改其它地方。

```rust
/* ================== 新需求2：工作内容修改为销售，由时长调整为质量等级 =================== */
// 使用闭包，并捕获外部变量
fn work3(level: &str, company_type: &str) {
    let action = || {
        println!("company_type:{}, sell product, achieve level:{}", company_type, level);
    };

    if company_type == "955" {
        action();
    } else if company_type == "996" {
        action();
    } else {
        println!("other company");
    }
}
```

```rust
fn main() {
    work(8, "955");
    work2(8, "996");
    work3("good", "955");
}
```

运行：

```sh
[MacOS-xd@qxd ➜ test_functional git:(master) ✗ ]$ cargo run --bin work_example 
   Compiling test_functional v0.1.0 (/Users/xd/Documents/workspace/src/rust_path/rust_learning/test_functional)
    Finished `dev` profile [unoptimized + debuginfo] target(s) in 0.52s
     Running `target/debug/work_example`
program duration:8
write_ppt duration:16
company_type:955, sell product, achieve level:good
```

通过上述示例，无论要修改什么，只要修改闭包 `action` 的实现即可，其它地方只负责调用。

### 3.2. 闭包相关特性

#### 3.2.1. 闭包的类型推导

编译器会对闭包的类型进行推导

* `let sum = |x, y| x + y`
    * 针对sum闭包，如果你只进行了声明，但是没有使用，编译器会报错提示你为x和y添加类型标注，因为它缺乏必要的上下文
    * 如果加上`println!("sum(1, 2) = {}", sum(1, 2));`，则编译器会自动推导出x和y的类型为i32，编译正常
* 也可以显式标注类型：`let sum = |x: i32, y: i32| -> i32 { x + y };`

虽然类型推导很好用，但是它不是泛型，当编译器推导出一种类型后，它就会一直使用该类型

#### 3.2.2. 闭包的3种`Fn`系列特征

当闭包从环境中捕获一个值时，会分配内存去存储这些值。与之相比，函数就不会去捕获这些环境值，因此定义和使用函数不会拥有这种内存负担。

闭包捕获变量有三种途径，对应三种`Fn`特征(`trait`)：

1、**`FnOnce` 特征**：该类型的闭包会拿走被捕获变量的所有权。**只能调用一次**，不能对已失去所有权的闭包变量进行二次调用。

```rust
fn fn_once<F>(func: F)
where
    F: FnOnce(usize) -> bool,
{
    println!("{}", func(3));
    
    // 下面会报错，因为 FnOnce 只能调用一次，上面调用后 func 的所有权已经转移
    println!("{}", func(4));
    // 上面where子句中，也在约束里添加Copy特征，即：`F: FnOnce(usize) -> bool + Copy,`，
    // 则调用时使用的将是它的拷贝，所以并没有发生所有权的转移。那么第二次调用 func(4) 就不会报错了
}

// 使用方式
fn test_fn_once() {
    println!("=========== test_fn_once ===========");
    let x = vec![1, 2, 3];

    fn_once(|z|{z == x.len()});

    // 如果要强制闭包转移所有权，可以使用在参数列表前加上 `move` 关键字
    // fn_once(move |z|{z == x.len()});
}
```

2、**`FnMut` 特征**：以**可变借用**的方式捕获环境中的值，可以修改该值

```rust
fn test_fn_mut() {
    println!("=========== test_fn_mut ===========");
    let mut s = String::new();

    // 若按此处定义，则update_string调用时编译器会报错，内部不支持变量的可变借用。需要将update_string定义为可变闭包
    // 添加mut关键字，可看到rust-analyzer推断其类型为 `impl FnMut(&str)`
    // let update_string = |str| s.push_str(str);

    let mut update_string = |str| s.push_str(str);

    update_string("hello");
    update_string(", world");

    println!("{:?}", s);
}
```

上面也可转换为下述形式，将闭包传给一个函数，并标记其类型为可变闭包，由编译器自动推导出其类型：

```rust
fn test_fn_mut_param() {
    println!("=========== test_fn_mut_param ===========");
    let mut s = String::new();
    let update_string =  |str| s.push_str(str);
    // 闭包作为参数传递给函数，此处会转移所有权
    exec_fn_mut(update_string);
    println!("{:?}", s);
}

// 泛型参数标注闭包为 FnMut 特征，并传递可变借用
fn exec_fn_mut<'a, F: FnMut(&'a str)>(mut f: F) {
    f("hello2");
    f(", world2");
}
```

上面`exec`处会转移闭包的所有权，可知此处闭包没有实现`Copy`特征。但并不是所有闭包都是没实现`Copy`特征的。

* 闭包自动实现`Copy`特征(trait)的规则是：只要闭包捕获的类型都实现了`Copy`特征的话，这个闭包就会默认实现`Copy`特征。

3、**`Fn` 特征**：以**不可变借用**的方式捕获环境中的值

```rust
fn test_fn_trait() {
    println!("=========== test_fn_trait ===========");
    let mut s = "hello".to_string();

    // 传给 exec_fn 会报错，该闭包中要修改变量，而 Fn 特征要求闭包为不可变借用
    // let update_string =  |str| s.push_str(str);

    let update_string = |str| println!("{}, {}", s, str);
    exec_fn(update_string);

    println!("s: {:?}", s);
}

// 泛型参数标注闭包为 Fn 特征，并传递不可变借用的闭包
fn exec_fn<'a, F: Fn(&'a str)>(f: F) {
    f("world")
}
```

上述完整代码([test_fn_trait](https://github.com/xiaodongQ/rust_learning/tree/master/test_functional/bin/test_fn_trait.rs))运行结果：

```sh
# cargo run --bin test_fn_trait
...
sum(1, 2) = 3
=========== test_fn_once ===========
fn_once: true
=========== test_fn_mut ===========
"hello, world"
=========== test_fn_mut_param ===========
"hello2, world2"
=========== test_fn_trait ===========
hello, world
s: "hello"
```

**三种 `Fn`特征 的关系：**

* 所有的闭包都自动实现了 `FnOnce` 特征，因此任何一个闭包都至少可以被调用一次
* 没有 移出所捕获变量所有权 的闭包自动实现了 `FnMut` 特征
* 不需要对捕获变量进行改变的闭包自动实现了 `Fn` 特征

#### 3.2.3. 闭包作为函数返回值

```rust
fn main() {
    let f = factory(2);
    println!("f(3) = {}", f(3));
}

fn factory(x:i32) -> impl Fn(i32) -> i32 {

    let num = 5;
    move |x| x + num

    // 注意：impl Trait 的返回方式有一个非常大的局限，就是只能返回同样的类型
    // 就算签名一样的闭包，类型也是不同的，因此在这种情况下，就无法再使用 impl Trait 的方式去返回闭包
    // if x > 1{
    //     move |x| x + num
    // } else {
    //     move |x| x - num
    // }
}
```

### 3.3. 迭代器

#### 3.3.1. 基本使用

下述是几个迭代器的使用示例，Rust把数组当成一个迭代器，直接去遍历其中的元素，从哪里开始，从哪里结束，都无需操心。

```rust
fn test_iter() {
    let arr = [1, 2, 3];
    // 严格来说，Rust中的for循环是编译器提供的语法糖，最终还是对迭代器中的元素进行遍历。
    // 数组实现了 IntoIterator 特征，编译器通过for语法糖，自动把实现了该特征的数组类型转换为迭代器
    for v in arr {
        println!("{}",v);
    }
    // 对数值序列进行迭代
    for i in 1..10 {
        println!("{}", i);
    }
    // 通过IntoIterator特征的 into_iter 方法，显式转换为迭代器
    for v in arr.into_iter() {
        println!("{}", v);
    }
    // 显式定义迭代器，并进行迭代
    let it = arr.iter();
    for v in it {
        println!("{}", v);
    }
}
```

在 Rust 中，迭代器是**惰性初始化**的，意味着如果你不使用它，那么它将不会发生任何事。这种惰性初始化的方式确保了创建迭代器不会有任何额外的性能损耗，其中的元素也不会被消耗，只有使用到该迭代器的时候，一切才开始。

3种转换为迭代器的方法：

* `into_iter`：会夺走所有权
* `iter`：借用
* `iter_mut`：可变借用

迭代器的`next`方法：用于显式迭代，返回`Option`类型，当迭代器中还有元素时，返回`Some`，否则返回`None`。

```rust
fn test_next() {
    let arr = [1, 2, 3];
    // next 会改变迭代器其中的状态数据，所以迭代器定义时需要使用 mut 关键字
    let mut arr_iter = arr.into_iter();
    // 若通过iter_mut定义迭代器，则迭代器中的数据会自动变为可变数据，下面断言比较需调整为 assert_eq!(arr_iter.next(), Some(&mut 1)); 形式
    // let mut arr_iter = arr.iter_mut();
    // 通过next方法，显式迭代
    assert_eq!(arr_iter.next(), Some(1));
    assert_eq!(arr_iter.next(), Some(2));
    assert_eq!(arr_iter.next(), Some(3));
    assert_eq!(arr_iter.next(), None);
}
```

#### 3.3.2. 适配器

只有实现了 `Iterator`特征 才叫迭代器。`Iterator`特征有很多不同功能的方法，标准库提供了默认实现。具体可参考：[Rust标准库 -- Iterator trait](https://ggdoc.rust-lang.org/std/iter/trait.Iterator.html#method.sum)

迭代器的方法，分2大类：

* **消费性适配器（`consuming adaptors`）**：只要迭代器上的某个方法(`A`)在其内部调用了`next`方法，那么该方法(`A`)就被称为消费性适配器。
    * 因为 `next` 方法会消耗掉迭代器上的元素，所以方法`A`的调用也会消耗掉迭代器上的元素
    * 比如 `Iterator`特征 中的 [sum方法](https://doc.rust-lang.org/std/iter/trait.Iterator.html#method.sum)，它会拿走迭代器的所有权，然后通过不断调用 `next` 方法对里面的元素进行求和
* **迭代器适配器**：顾名思义，会返回一个新的迭代器，这是实现链式方法调用的关键，比如：`v.iter().map().filter()...`
    * 与消费者适配器不同，迭代器适配器是惰性的，意味着你需要一个消费者适配器来收尾，最终将迭代器转换成一个具体的值
    * 比如：`v1.iter().map(|x| x + 1).collect();`，[collect方法](https://doc.rust-lang.org/std/iter/trait.Iterator.html#method.collect) 就是一个消费者适配器，它将迭代器转换为一个具体的值

## 4. 特征：Trait

前面学习Rust基本特性时，特征(`trait`)一带而过，本篇有好几处涉及到trait的一些特性，此处也补充学习下这块的模糊留白。

类似其他语言中的接口（`interface`）和抽象类（`abstract class`），定义了某个类型必须实现的一组方法，用于定义共享的行为。

### 4.1. 基本使用示例

```rust
// 定义一个特征
pub trait Summary {
    // 签名，不包含具体实现
    fn summarize_author(&self) -> String;

    // 也可以定义默认实现，为类型impl实现时可进行重载
    fn summarize(&self) -> String {
        format!("(Read more from {}...)", self.summarize_author())
    }
}

// 定义一个类型，并为其实现特征
pub struct Weibo {
    pub username: String,
    pub content: String
}
// 实现特征
impl Summary for Weibo {
    fn summarize_author(&self) -> String {
        format!("@{}", self.username)
    }
}

// 使用方式
fn main() {
    let weibo = Weibo{username: "sunface".to_string(),content: "好像微博没Tweet好用".to_string()};
    println!("{}",weibo.summarize());
}
```

### 4.2. 作为函数参数

```rust
pub fn notify(item: &impl Summary) {
    println!("Breaking news! {}", item.summarize());
}
```

意思是：实现了`Summary`特征 的 `item` 参数。可以使用任何实现了`Summary`特征的类型作为该函数的参数，同时在函数体内，还可以调用该特征的方法。

### 4.3. 特征约束

`impl Trait`语法实际是一个语法糖，形如 `T: Summary` 被称为**特征约束**。

下面是几种使用形式：

```rust
// 函数接受一个实现了 Summary特征 的 iterm
pub fn notify<T: Summary>(item: &T) {
    println!("Breaking news! {}", item.summarize());
}

// 两个参数是同一类型，且该类型实现了 Summary特征
pub fn notify<T: Summary>(item1: &T, item2: &T) {}

// 多重特征约束，实现了 Summary特征 和 Display特征
pub fn notify<T: Summary + Display>(item: &T) {}
// 不用特征约束的话，可以这么写
pub fn notify(item: &(impl Summary + Display)) {}

// 特征约束很复杂的时候，可以使用 where 简化
fn some_function<T: Display + Clone, U: Clone + Debug>(t: &T, u: &U) -> i32 {}
// 用 where约束 简化如下：
fn some_function<T, U>(t: &T, u: &U) -> i32
    where T: Display + Clone,
          U: Clone + Debug
{}
```

### 4.4. 作为返回值

这种返回值方式有一个很大的限制：只能有一个具体的类型。要实现返回不同类型，需要使用"**特征对象**"

```rust
// 对于 returns_summarizable 的调用者而言，只知道返回了一个实现了 Summary 特征的对象，但是并不知道返回了一个 Weibo 类型
fn returns_summarizable() -> impl Summary {
    Weibo {
        username: String::from("sunface"),
        content: String::from(
            "m1 max太厉害了，电脑再也不会卡",
        )
    }
}
```

### 4.5. 通过`derive`派生特征

`#[derive(Debug)]`形式，是一种`特征派生`语法，被 `derive` 标记的对象会自动实现对应的默认特征代码，继承相应的功能。（`derive /dɪ'raɪv/`，导出、源于、由来）

* 例如 `Debug` 特征，它有一套自动实现的默认代码，当你给一个结构体标记后，就可以使用 `println!("{:?}", s)` 的形式打印该结构体的对象。
* 再如 `Copy` 特征，它也有一套自动实现的默认代码，当标记到一个类型上时，可以让这个类型自动实现 `Copy` 特征，进而可以调用 `copy` 方法，进行自我复制。

> 总之，`derive` 派生出来的是 Rust 默认给我们提供的特征，在开发过程中极大的简化了自己手动实现相应特征的需求，当然，如果你有特殊的需求，还可以自己手动重载该实现。

### 4.6. 通过`std::prelude`引入特征

如果你要使用一个特征的方法，那么你需要将该特征引入当前的作用域中。

Rust 提供了一个非常便利的办法，即把**最常用的标准库中的特征**通过 `std::prelude` 模块提前引入到当前作用域中。（`prelude /'preljuːd/`，开端、序幕）

```rust
use std::prelude;
// xxx
```

### 4.7. 特征对象

要先学习理解下智能指针，此处先简单记录，后续再进一步学习：[特征对象](https://course.rs/basic/trait/trait-object.html)。

在 Rust 中，特征对象（trait object）是一种特殊的动态分发机制，它允许你在运行时处理不同类型的值。特征对象通常用于当你需要一个可以引用多种类型值的接口，而这些类型都实现了相同的 trait。

特征对象通过 `Box<dyn Trait>` 或者 `&dyn Trait` 的形式来表示，其中`Trait`代指具体特征，比如`Box<dyn Work>`。

类似于C++的抽象类指针，通过多态来实现不同类型的对象调用同一接口。

## 5. 小结

梳理学习了 生命周期、函数式编程（涉及闭包和迭代器）、特征（trait）等特性。其他特性在后续的篇幅继续学习。

## 6. 参考

1、[Rust语言圣经(Rust Course) -- 基础入门：认识生命周期](https://course.rs/basic/lifetime.html)

2、[Rust语言圣经(Rust Course) -- Rust 进阶学习](https://course.rs/advance/intro.html)

3、[The Rust Programming Language -- Validating References with Lifetimes](https://doc.rust-lang.org/book/ch10-03-lifetime-syntax.html)

4、[Rust语言圣经(Rust Course) -- 特征 Trait](https://course.rs/basic/trait/trait.html)

5、[Rust标准库 -- Iterator trait](https://ggdoc.rust-lang.org/std/iter/trait.Iterator.html#method.sum)
