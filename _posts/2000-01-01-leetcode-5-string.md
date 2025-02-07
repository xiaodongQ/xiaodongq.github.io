---
layout: post
title: LeetCode刷题学习（五） -- 字符串
categories: LeetCode
tags: LeetCode 数据结构与算法
---

* content
{:toc}

LeetCode刷题学习记录，字符串篇。



## 1. 344.反转字符串

[344. Reverse String](https://leetcode.cn/problems/reverse-string/)

要求原地反转字符串，只借助`O(1)`的额外空间。

### 1.1. 思路和解法

双指针。

```cpp
class Solution {
public:
    void reverseString(vector<char>& s) {
        int left = 0;
        int right = s.size() - 1;
        // 保持区间的开闭一致
        char tmp;
        while (left <= right) {
            tmp = s[left];
            s[left] = s[right];
            s[right] = tmp;
            left++;
            right--;
        }
    }
};
```

参考链接中，还提供了通过`位运算`（异或）进行交换的实现方式。

```cpp
s[i] ^= s[j]; // 两数的异或结果
s[j] ^= s[i]; // 由于异或运算可逆，得到原来的s[i]
s[i] ^= s[j]; // 得到 s[j]
```

for循环更简洁一点：

```cpp
void reverseString(vector<char>& s) {
    // for循环更简洁
    char tmp;
    for (int left = 0, right = s.size() - 1; left < s.size()/2; left++, right--) {
        tmp = s[left];
        s[left] = s[right];
        s[right] = tmp;
    }
}
```

## 2. 541.反转字符串II

[541. Reverse String II](https://leetcode.cn/problems/reverse-string-ii/description/)

给定整数k，每2k个字符进行处理，只反转每2k中的前k个字符。

如果剩余字符少于 k 个，则将剩余字符全部反转，如：`abcdefgh`，给定3，则变为`cba def hg`

如果剩余字符小于 2k 但大于或等于 k 个，则反转前 k 个字符，其余字符保持原样，如：`abcde`，给定3，则变为`cba de`

### 2.1. 思路和解法

比 344.反转字符串 复杂一些。

思路：每次移动2k，再单独看2k内的区间怎么处理。

```cpp
class Solution {
public:
    string reverseStr(string s, int k) {
        // 每次移动2k
        for (int i = 0; i < s.size(); i += 2*k) {
            // 剩余字符少于 k 个，反转剩下所有字符
            if (s.size() - i < k) {
                // 这里用了STL的reverse算法（若不是直接的解题关键，也可以用库函数）
                reverse(s.begin() + i, s.end());
            } else {
                // 每k个进行反转
                reverse(s.begin() + i, s.begin() + i + k);
            }
        }

        return s;
    }
};
```

概率上还是>=k会概率高一些，可以放前面（不过if...else分支无所谓，如果还有其他情况则可将概率高的放前面以减少判断次数）

```cpp
if (s.size() - i >= k) {
    // 每k个进行反转
    reverse(s.begin() + i, s.begin() + i + k);
} else {
    // 反转剩余字符
    reverse(s.begin() + i, s.end());
}
```

`reverse`算法也可调整成自己实现，`void my_reverse(string &s, int start, int end)`，其中实现即"344.反转字符串"对应解法。

## 3. 替换数字

非原题：[替换数字](https://www.programmercarl.com/kamacoder/0054.%E6%9B%BF%E6%8D%A2%E6%95%B0%E5%AD%97.html)

给定一个字符串 s，它包含小写字母和数字字符，请编写一个函数，将字符串中的字母字符保持不变，而将每个数字字符替换为number。

示例："a1b2c3"，函数应该将其转换为 "anumberbnumbercnumber"

### 3.1. 思路和解法

先遍历数组获取 数字字符 的数量，然后扩容字符串大小，从后往前填充（原位置`idx1--`，新位置`idx2--`）

## 4. 151.翻转字符串里的单词

[151. Reverse Words in a String](https://leetcode.cn/problems/reverse-words-in-a-string/)

反转字符串句子中的所有单词，反转后的字符串中单词以一个空格分隔。

原字符串中，两个单词间可能有多余的空格、前面或者后面也可能包含多余的空格

### 4.1. 思路和解法

#### 4.1.1. 方式1：借助反转函数

先实现功能，借助语言内置的API，不限制辅助空间使用。

步骤：1）字符串拆分成单词数组 2）数组反转 3）数组拼接

```cpp
class Solution {
public:
    string reverseWords(string s) {
        // 方式1：先实现功能，借助语言内置的API，不限制辅助空间使用。
        // 1）字符串拆分成单词数组 2）数组反转 3）数组拼接
        std::istringstream iss(s);
        vector<string> words;
        string word;
        while (iss >> word) {
            words.push_back(word);
        }
        // 翻转，直接使用<algorithm>库中的std::reverse
        std::reverse(words.begin(), words.end());
        // 数组重新拼接
        std::ostringstream oss;
        for (auto i=0; i < words.size(); i++) {
            if (i > 0) {
                oss << " ";
            }
            oss << words[i];
        }
        return oss.str();
    }
};
```

* 时间复杂度：`O(n)`
    * `iss`构造时从`s`读取时需要完整遍历，时间复杂度`O(n)`
    * `reverse`反转一般基于双指针法实现，复杂度`O(m)`，`m`是单词个数
    * 重新拼接也是`O(n)`
    * 由于`m`一般小于等于`n`，总体时间复杂度`O(n)`
* 空间复杂度：`O(n)`
    * `words`存储单词需要`O(n)`，`oss`拼接也需要`O(n)`，整体空间复杂度`O(n)`

```sh
61/61 cases passed (3 ms)
Your runtime beats 39.11 % of cpp submissions
Your memory usage beats 10.67 % of cpp submissions (11.7 MB)
```

#### 4.1.2. 方式2：借助双端队列

借助双端队列实现反转，并使用额外辅助空间

```cpp
    // 方式2：借助双端队列实现反转
    string reverseWords(string s) {
        int left = 0;
        int right = s.size() - 1;
        // 去除前面空格，并记录有效起始位置left
        while (left <= right && s[left] == ' ') {
            left++;
        }
        // 去除后面空格，并记录有效终止位置right
        while (left <= right && s[right] == ' ') {
            right--;
        }
        // 中间处理，并检查空格
        deque<string> words;
        string word;
        while (left <= right) {
            char c = s[left];
            // 新单词
            if (!word.empty() && c == ' ') {
                words.push_front(word);
                word = "";
            } else if (c != ' ') { // 此处单独区分' '，而不是仅else
                word += c;
            }
            left++;
        }
        // 最后一个单词
        words.push_front(word);
        
        // 借助string，拼接新字符串
        string result;
        for (auto i = 0; i < words.size(); i++) {
            if (i > 0) {
                result += " ";
            }
            result += words[i];
        }
        return result;
    }
```

* 时间复杂度：`O(n)`
    * 前后空格处理，均为`O(n)`（实际两者加起来最大不会超过n）
    * 中间处理，要遍历，`O(n)`
    * 最后拼接 `O(m)`
* 空间复杂度：`O(n)`
    * `deque`和最后的`string`辅助，都需要`O(n)`

```sh
61/61 cases passed (3 ms)
Your runtime beats 39.11 % of cpp submissions
Your memory usage beats 14.82 % of cpp submissions (10.5 MB)
```

#### 4.1.3. 方式3：自行实现反转和去除空格

思路步骤：1）先去除多余空格 2）反转所有字符 3）反转单词

空间复杂度能做到`O(1)`

对于移除多余空格，使用快慢指针的思路处理。容易出错，如下就是第一次的错误实现：

```cpp
    // 错误：有3个及以上连续空格时，移动和覆盖就会有问题，有多余空格
    void removeExtraSpace(string &s) {
        int left = 0;
        int right = s.size() - 1;
        while (left <= right) {
            if (left > 0 && s[left] == ' ' && s[left] == s[left-1]) {
                s[left-1] = s[left];
                continue;
            }
            left++;
        }
        s.resize(left);
    }
```

参考链接思路，去除所有空格，并在单词间加空格（相对于单词间多个空格的处理，更简洁明了）

但是处理最后一个字符可能会多加空格，需要单独处理，这个细节也容易出错，下面的最后处理避免遗漏。

```cpp
void removeExtraSpace(string &s) {
        int slow = 0;
        int fast = 0;
        // 前一个字符是否为空格。此处要初始化为true，否则第一个字符为空格时会保留多余空格
        bool is_space = true;
        while (fast < s.size()) {
            // 非空格前移
            if (s[fast] != ' ') {
                s[slow++] = s[fast];
                is_space = false;
            } else if (!is_space){
                // 当前是空格，且则前一个字符是非空格，则说明一个单词结束，添加空格
                // 特别注意第一个空格不加 slow!=0
                s[slow++] = ' ';
                is_space = true;
            } // else即当前为空格，前一个也为空格，则slow不需要移动
            
            fast++;
        }
        // 重新调整字符串大小
        if (slow > 0 && s[slow - 1] == ' ') {
            slow--; // 如果最后字符是空格，去掉它
        }
        s.resize(slow);
    }
```

更为简洁的方式：每次处理直到碰到非空字符

```cpp
    void removeExtraSpace(string &s) {
        int slow = 0;
        int fast = 0;
        while (fast < s.size()) {
            // 非空格才处理
            if (s[fast] != ' ') {
                // 单词间空格
                if (slow != 0) {
                    s[slow++] = ' ';
                }
                // 每次处理直到空格为止
                while (fast < s.size() && s[fast] != ' ') {
                    s[slow++] = s[fast++];
                }
                continue;
            }
            fast++;
        }
        s.resize(slow);
    }
```

对应的反转和完整流程如下：

```cpp
    // 反转函数，反转单词时复用该函数，因此指定反转范围
    void reverse(string &s, int left, int right) {
        // 双指针法
        int tmp;
        for (int i = left, j = right; i < j; i++, j--) {
            tmp = s[i];
            s[i] = s[j];
            s[j] = tmp;
        }
    }

    // 自行实现反转逻辑，辅助空间O(1)
    string reverseWords(string s) {
        // 1）先去除多余空格
        removeExtraSpace(s);
        // 2）反转所有字符串
        reverse(s, 0, s.size() - 1);
        // 3）反转单词
        int start = 0;
        for (int i = 0; i <= s.size(); i++) {
            if (i == s.size() || s[i] == ' ') {
                reverse(s, start, i - 1);
                start = i + 1;
            }
        }
        return s;
    }
```

## 右旋字符串

非LeetCode原题：[右旋字符串](https://kamacoder.com/problempage.php?pid=1065)

将字符串中的后面 k 个字符移到字符串的前面，实现字符串的右旋转操作

例如：对于输入字符串 "abcdefg" 和整数 2，函数应该将其转换为 "fgabcde"

### 思路和解法


## 5. 参考

1、[代码随想录 -- 字符串](https://www.programmercarl.com/0344.%E5%8F%8D%E8%BD%AC%E5%AD%97%E7%AC%A6%E4%B8%B2.html)

2、[LeetCode中文站](https://leetcode.cn/)

3、GPT
