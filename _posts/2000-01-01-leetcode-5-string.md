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

## 541. 反转字符串II

[541. Reverse String II](https://leetcode.cn/problems/reverse-string-ii/description/)

给定整数k，每2k个字符进行处理，只反转每2k中的前k个字符。

如果剩余字符少于 k 个，则将剩余字符全部反转，如：`abcdefgh`，给定3，则变为`cba def hg`

如果剩余字符小于 2k 但大于或等于 k 个，则反转前 k 个字符，其余字符保持原样，如：`abcde`，给定3，则变为`cba de`

### 思路和解法

比 344.反转字符串 复杂一些。


## 2. 参考

1、[代码随想录 -- 字符串](https://www.programmercarl.com/0344.%E5%8F%8D%E8%BD%AC%E5%AD%97%E7%AC%A6%E4%B8%B2.html)

2、[LeetCode中文站](https://leetcode.cn/)
