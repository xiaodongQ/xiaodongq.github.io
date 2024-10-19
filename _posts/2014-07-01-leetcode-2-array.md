---
layout: post
title: LeetCode刷题学习（二） -- 数组篇
categories: LeetCode
tags: LeetCode 数据结构与算法
---

* content
{:toc}

LeetCode刷题学习记录，数组篇。



## 1. 704.二分查找

### 1.1. 题目

[LeetCode题目链接：704. 二分查找](https://leetcode.cn/problems/binary-search/)

```
给定一个 n 个元素有序的（升序）整型数组 nums 和一个目标值 target  ，写一个函数搜索 nums 中的 target，如果目标值存在返回下标，否则返回 -1。


示例 1:

输入: nums = [-1,0,3,5,9,12], target = 9
输出: 4
解释: 9 出现在 nums 中并且下标为 4
示例 2:

输入: nums = [-1,0,3,5,9,12], target = 2
输出: -1
解释: 2 不存在 nums 中因此返回 -1
 

提示：

你可以假设 nums 中的所有元素是不重复的。
n 将在 [1, 10000]之间。
nums 的每个元素都将在 [-9999, 9999]之间。
```

### 1.2. 思路和解法

二分查找有两种常见写法。循环条件和判断条件容易搞错，记住遵循 `循环不变量规则`（循环过程中每次处理边界时，坚持根据区间的定义来操作）。

* 左闭右闭区间 `[]`
    * 区间：`left=0; right=size()-1`
    * 循环条件：`while(left <= right);`，`left == right`是有意义的，所以用`<=`
    * 区间更新：
        * 中间值更大时查找左区间，`right=middle-1`，即`[left, middle-1]`
        * 中间值更小时查找右区间，`left=middle+1`，即`[middle+1, right]`
        * 因为当前`middle`值肯定不满足`arr[middle] == target`，所以闭区间时边界需要基于`middle`前后调整
* 左闭右开区间 `[)`
    * 区间：`left=0; right=size()`
    * 循环条件：`while(left < right)`，由于右开区间时`left == right`没有意义，所以用`<`
    * 区间更新：
        * 中间值更大时找左区间，`right=middle`，因为右开区间不会去比较`arr[middle]`，即`[left, middle)`
        * 中间值更小时找右区间，`left=middle+1`，即`[middle + 1, right)`

左闭右闭区间：

```cpp
// 左闭右闭区间，[]
int search(vector<int>& nums, int target) {
    int left = 0;
    int right = nums.size() - 1;
    // left == right是有意义的，所以使用 <=
    while (left <= right) {
        // 避免溢出
        int mid = left + (right-left)/2;
        if (target == nums[mid]) {
            return mid;
        }
        // [left, mid-1]
        if (nums[mid] > target) {
            right = mid - 1;
        }else{
            // [mid+1, right]
            left = mid + 1;
        }
    }
    return -1;
}
```

左闭右开区间：

```cpp
// 左闭右开区间，[)
int search(vector<int>& nums, int target) {
    int left = 0;
    int right = nums.size();
    while (left < right) {
        int mid = left + (right-left)/2;
        if (nums[mid] == target) {
            return mid;
        }
        // 左区间 [)
        if (nums[mid] > target) {
            right = mid;
        } else {
            // 右区间
            left = mid + 1;
        }
    }

    return -1;
}
```

### 1.3. glibc中的二分查找

一般情况下，默认使用`左闭右开`区间。查看glibc中的二分查找，使用的也是`左闭右开`区间。

```c
// VERSION "2.40.9000"
// glibc/bits/stdlib-bsearch.h
__extern_inline void *
bsearch (const void *__key, const void *__base, size_t __nmemb, size_t __size,
     __compar_fn_t __compar)
{
  size_t __l, __u, __idx;
  const void *__p;
  int __comparison;

  __l = 0;
  __u = __nmemb;
  // 左闭右开区间，__u取的是数组总长度
  while (__l < __u)
    {
      // 中间值
      __idx = (__l + __u) / 2;
      __p = (const void *) (((const char *) __base) + (__idx * __size));
      __comparison = (*__compar) (__key, __p);
      // 即key < base[mid]，继续查左区间，将 right=mid
      if (__comparison < 0)
    __u = __idx;
      else if (__comparison > 0)
      // 即key > base[mid]，继续查右区间，将 left=mid+1
    __l = __idx + 1;
      else
    {
      return (void *) __p;
    }
    }

  return NULL;
}
```

## 2. 3.移除元素

[LeetCode题目链接：27. 移除元素](https://leetcode.cn/problems/remove-element/description/)

```
给你一个数组 nums 和一个值 val，你需要 原地 移除所有数值等于 val 的元素。元素的顺序可能发生改变。然后返回 nums 中与 val 不同的元素的数量。

假设 nums 中不等于 val 的元素数量为 k，要通过此题，您需要执行以下操作：

更改 nums 数组，使 nums 的前 k 个元素包含不等于 val 的元素。nums 的其余元素和 nums 的大小并不重要。
返回 k。
用户评测：

评测机将使用以下代码测试您的解决方案：

int[] nums = [...]; // 输入数组
int val = ...; // 要移除的值
int[] expectedNums = [...]; // 长度正确的预期答案。
                            // 它以不等于 val 的值排序。

int k = removeElement(nums, val); // 调用你的实现

assert k == expectedNums.length;
sort(nums, 0, k); // 排序 nums 的前 k 个元素
for (int i = 0; i < actualLength; i++) {
    assert nums[i] == expectedNums[i];
}
如果所有的断言都通过，你的解决方案将会 通过。

 

示例 1：

输入：nums = [3,2,2,3], val = 3
输出：2, nums = [2,2,_,_]
解释：你的函数函数应该返回 k = 2, 并且 nums 中的前两个元素均为 2。
你在返回的 k 个元素之外留下了什么并不重要（因此它们并不计入评测）。
示例 2：

输入：nums = [0,1,2,2,3,0,4,2], val = 2
输出：5, nums = [0,1,4,0,3,_,_,_]
解释：你的函数应该返回 k = 5，并且 nums 中的前五个元素为 0,0,1,3,4。
注意这五个元素可以任意顺序返回。
你在返回的 k 个元素之外留下了什么并不重要（因此它们并不计入评测）。
 

提示：

0 <= nums.length <= 100
0 <= nums[i] <= 50
0 <= val <= 100
```



## 3. 参考

1、[代码随想录 -- 数组篇](https://www.programmercarl.com/0704.%E4%BA%8C%E5%88%86%E6%9F%A5%E6%89%BE.html)
