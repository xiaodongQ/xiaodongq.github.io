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

[LeetCode题目链接：704. 二分查找](https://leetcode.cn/problems/binary-search/)

### 1.1. 思路和解法

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

### 1.2. glibc中的二分查找

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

### 1.3. Rust解法

数组`Vec`相关接口，参考 [std::vec::Vec](https://doc.rust-lang.org/std/vec/struct.Vec.html)

* 数组长度`len()`，返回`usize`：`pub fn len(&self) -> usize`
* 需要注意`i32`和`usize`的转换，两者不会自动转换，不匹配则编译器会报错

```rust
impl Solution {
    pub fn search(nums: Vec<i32>, target: i32) -> i32 {
        let (mut left, mut right) = (0_i32, nums.len() as i32);
        let mut mid;
        while left < right {
            mid = (left+right)/2;
            if nums[mid as usize] > target {
                right = mid;
            } else if nums[mid as usize] < target {
                left = mid + 1;
            } else {
                return mid;
            }
        }

        -1
    }
}
```

## 2. 3.移除元素

VS Code 切换为英文站。

[LeetCode题目链接：27. Remove Element](https://leetcode.com/problems/remove-element/)

### 2.1. 思路和解法



## 3. 参考

1、[代码随想录 -- 数组篇](https://www.programmercarl.com/0704.%E4%BA%8C%E5%88%86%E6%9F%A5%E6%89%BE.html)
