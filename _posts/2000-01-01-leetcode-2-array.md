---
title: LeetCode刷题学习（二） -- 数组篇
categories: [数据结构与算法, LeetCode]
tags: [LeetCode, 数据结构与算法]
---

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

## 2. 27.移除元素

VS Code 切换为英文站。

[LeetCode题目链接：27. Remove Element](https://leetcode.com/problems/remove-element/)

### 2.1. 思路和解法

双指针法（快慢指针）：慢指针指向有效成员下标，快指针按顺序迭代；若有元素要删除，则慢指针不步进

```cpp
class Solution {
public:
    int removeElement(vector<int>& nums, int val) {
        // 双指针法（快慢指针）
        // 慢指针指向有效成员下标，快指针按顺序迭代；若有元素要删除，则慢指针不步进
        int left = 0;
        int right = 0;
        while (right < nums.size()) {
            if (nums[right] != val) {
                nums[left++] = nums[right];
            }
            right++;
        }

        return left;
    }
};
```

### 2.2. Rust解法

```rust
impl Solution {
    pub fn remove_element(nums: &mut Vec<i32>, val: i32) -> i32 {
        // 变量命名风格按照 snake_case
        let mut left_idx = 0;
        for right in 0..nums.len() {
            if nums[right] != val {
                nums[left_idx] = nums[right];
                // Rust中没有 ++自增 和 --自减
                left_idx += 1;
            }
        }
        // 上述默认类型推导为usize，此处需转换
        return left_idx as i32;
    }
}
```

## 3. 977.有序数组的平方

[977. Squares of a Sorted Array](https://leetcode.com/problems/squares-of-a-sorted-array/description/)

### 3.1. 思路和解法

双指针法，原数组为非递减序，即递增序或者相等，首尾比较依次可得到每轮最大值。

时间复杂度为`O(n)`。

```cpp
class Solution {
public:
    vector<int> sortedSquares(vector<int>& nums) {
        // 双指针法，原数组为非递减序，即递增序或者相等，首尾比较依次可得到每轮最大值
        int left = 0;
        int right = nums.size() - 1;
        
        // 用于返回结果，nums作为引用传入只是减少数据拷贝，不要直接修改nums来返回结果
        // 构造时指定容量（初始值均为0），优化性能
        vector<int> result(nums.size(), 0);
        // 用于记录最大值存储位置，从数组最后开始
        int k = nums.size() - 1;

        // 循环不变量原则，[]时两侧索引值都是有意义的
        while (left <= right) {
            // 右边大或等于，都取右侧，并收缩右边界
            if (nums[right]*nums[right] >= nums[left]*nums[left]) {
                result[k--] = nums[right]*nums[right];
                right--;
            } else {
                // 取左侧值，并收缩左边界
                result[k--] = nums[left]*nums[left];
                left++;
            }
        }
        return result;
    }
};
```

### 3.2. Rust解法

**特别注意**：`right -= 1;`对应分支中，若取 `>=` ，则`nums`仅有一个成员时，无法通过用例，`right-1`会溢出（默认`usize`）。

（出于Rust实现中碰到的溢出风险，若边界涉及`unsigned`类型`-1`的，尽量放另外的分支）

```rust
impl Solution {
    pub fn sorted_squares(nums: Vec<i32>) -> Vec<i32> {
        let (mut left, mut right) = (0, nums.len()-1);
        // 用法：vec![1; 3]; 前者为元素值后者为长度
        let mut result: Vec<i32> = vec![0; nums.len()];
        let mut k = nums.len() - 1;
        while left <= right {
            // 特别注意，若取 >= ，则nums仅有一个成员时，无法通过用例，right-1会溢出（默认usize）
            // if nums[right]*nums[right] >= nums[left]*nums[left] {
            if nums[right]*nums[right] > nums[left]*nums[left] {
                result[k] = nums[right]*nums[right];
                right -= 1;
            } else {
                result[k] = nums[left]*nums[left];
                left += 1;
            }
            k -= 1;
        }
        result
    }
}
```

## 4. 209.长度最小的子数组

[209. Minimum Size Subarray Sum](https://leetcode.com/problems/minimum-size-subarray-sum/description/)

### 4.1. 思路和解法

滑动窗口（也可理解为双指针）。

* 题目中数组成员是正整数，求和是递增的，扩大`右边界`直到滑动窗口内总和`>=`目标值；
* 而后依次缩小`左边界`，当窗口内总和不满足`>=`则移动右边界；
    * 这里的思路是核心。若用左右边界作为循环条件 `while(left<=right)`，并判断求和条件退出循环，不简洁
* 每轮窗口变动，判断满足`>=`目标条件的窗口长度是否比最小值小

```cpp
class Solution {
public:
    int minSubArrayLen(int target, vector<int>& nums) {
        int result = INT32_MAX;
        // 滑动窗口起止
        int left = 0;
        int right = 0;
        // 滑动窗口长度
        int sub_len = 0;
        // 窗口内求和，题目中数组成员是正整数
        int sum = 0;
        for (int right = 0; right < nums.size(); right++) {
            sum += nums[right];
            // 基于窗口求和循环判断来调整左侧（避免下标作为循环，判断多次边界容易出错）
            while (sum >= target) {
                // 窗口长度
                sub_len = right - left + 1;
                if (sub_len < result) {
                    result = sub_len;
                }
                // 尝试收缩左侧
                sum -= nums[left];
                left++;
            }
        }
        if (result == INT32_MAX) {
            result = 0;
        }
        return result;
    }
};
```

时间复杂度：`O(n)`。

* 内存循环只是少量移动（实际只多移动一次），总体操作中，每个元素都是两次操作：进入滑动窗口、移出滑动窗口，即`O(2n)`。
* 求和都是在右边界延伸、以及左边界收缩时，基于原有的`sum`基础上增量修改的。

作为对比，收缩边界的循环条件，上面用的是总和判断，下面用左右边界判断，该方式可以通过提交，但是没有上面简洁。

```cpp
int minSubArrayLen(int target, vector<int>& nums) {
    int result = INT32_MAX;
    // 滑动窗口起止
    int left = 0;
    int right = 0;
    // 滑动窗口长度
    int sub_len = 0;
    // 窗口内求和，题目中数组成员是正整数
    int sum = 0;
    for (int right = 0; right < nums.size(); right++) {
        sum += nums[right];
        // 总和超过目标则开始收缩左边界，直到窗口内总和 < 目标值
        if (sum >= target) {
            while (left <= right) {
                // 窗口长度
                sub_len = right - left + 1;
                if ( sub_len < result ) {
                    result = sub_len;
                }
                sum -= nums[left++];
                // 退出条件
                if (sum < target) {
                    break;
                }
            }
        }
    }
    if (result == INT32_MAX) {
        result = 0;
    }
    return result;
}
```

### 4.2. Rust解法

```rust
impl Solution {
    pub fn min_sub_array_len(target: i32, nums: Vec<i32>) -> i32 {
        // 推导为 usize
        let (mut left, mut right) = (0, 0);
        // 下面有as i32，此处推导为i32，否则默认usize
        let mut sub_len = 0;
        // i32
        let mut result = i32::MAX;
        let mut sum = 0;
        while right < nums.len() {
            sum += nums[right];
            while sum >= target {
                // 注意这里的类型转换
                sub_len = (right - left + 1) as i32;
                // i32 做比较
                if sub_len < result {
                    result = sub_len;
                }
                sum -= nums[left];
                left += 1;
            }
            right += 1;
        }
        if result == i32::MAX {
            result = 0;
        }
        result as i32
    }
}
```

## 5. 59.螺旋矩阵II

[59. Spiral Matrix II](https://leetcode.com/problems/spiral-matrix-ii/description/)

### 5.1. 思路和解法

核心是保持循环不变量。左闭右开区间，每圈依次按 上->右->下->左 的顺序遍历。

理解点：记住每轮开始的起点，`(top, left)` 或 `(startx, starty)`，感觉前者更易理解。可以查看提交代码的对比：[59.spiral-matrix-ii_test](https://github.com/xiaodongQ/LeetCode/blob/master/cpp_exercise/59.spiral-matrix-ii_test.cpp)

```cpp
class Solution {
public:
    // 上述的每轮起始坐标(startx, starty) 换成 (top, left) 更易理解
    vector<vector<int>> generateMatrix(int n) {
        // 核心是保持循环不变量。左闭右开区间，每圈依次按 上->右->下->左 的顺序遍历
        // 每轮开始的行
        int top = 0;
        // 每轮开始的列
        int left = 0;
        // 各位置取值，从1开始
        int num = 1;
        // 轮次
        int round = n/2;
        // 每轮到达的右边界偏移（最右n-offset）
        // 由于是开区间，右边界到倒数第2列（ 即`[0, n-1)` ）
        int offset = 1;
        int i=0, j=0;
        // 结果，初始化时就申请好空间，避免push_back
        vector< vector<int> > result(n, vector<int>(n, 0));
        while (round-- > 0) {
            // 每轮的起点，行、列
            i = top;
            j = left;

            // 上边，此处依次获取一行记录 result[0][j]
            for (; j < n-offset; j++) {
                result[i][j] = num++;
            }
            // 右边，result[i][上轮的j列]
            for (; i < n-offset; i++) {
                result[i][j] = num++;
            }
            // 下边，注意是从右到左，result[上轮的i行][j]
            for (; j > left; j--) {
                result[i][j] = num++;
            }
            // 左边，注意是从下到上，result[i][上轮的j列]
            for (; i > top; i--) {
                result[i][j] = num++;
            }

            // 表示从顶往下一行 
            top++;
            // 表示从左往右一列
            left++;
            // n-offset 宽度变小
            offset++;
        }
        if (n % 2 == 1) {
            result[n/2][n/2] = num;
        }
        return result;
    }
};
```

### 5.2. Rust解法

```rust
impl Solution {
    pub fn generate_matrix(n: i32) -> Vec<Vec<i32>> {
        let mut input_n = n as usize;
        let mut round = n/2;
        // 每轮起点
        let (mut top, mut left): (usize, usize) = (0, 0);
        // 初始化时就申请空间，vec!的长度需要usize
        let mut result = vec![ vec![0; input_n]; input_n];
        let (mut i, mut j) = (0, 0);
        // 每轮的长度边界
        let mut offset = 1;
        let mut count = 1;
        while round > 0 {
            i = top;
            j = left;
            // 依次画 上->右->下->左，并保持左闭右开的循环不变量
            while j < input_n - offset {
                result[i][j] = count;
                count += 1;
                j += 1;
            }
            while i < input_n - offset {
                result[i][j] = count;
                count += 1;
                i += 1;
            }
            while j > left {
                result[i][j] = count;
                count += 1;
                j -= 1;
            }
            while i > top {
                result[i][j] = count;
                count += 1;
                i -= 1;
            }
            // 下一轮的起始位置移动坐标
            top += 1;
            left += 1;
            offset += 1;
            // 轮次减1
            round -= 1;
        }
        if n % 2 == 1 {
            result[input_n/2][input_n/2] = count;
        }
        
        result
    }
}
```

## 6. 区间和

非LeetCode上的原题，题目链接：[区间和](https://kamacoder.com/problempage.php?pid=1070)

题目：

* 给定一个整数数组 Array，请计算该数组在每个指定区间内元素的总和。
* 输入描述：第一行输入为整数数组 Array 的长度 `n`，接下来 n 行，每行一个整数，表示数组的元素。随后的输入为需要计算总和的区间下标：`a`，`b` （`b > = a`），直至文件结束。
* 输出描述：输出每个指定区间内元素的总和。
* 示例：输入3，而后3行输入3个数字；再指定下标区间 0,1，则表示求`arr[0]+arr[1]`

### 6.1. 思路和解法

1、暴力解法（朴素解法）

* 输入时用`vector`保存各成员，指定求和范围时通过`for`循环遍历求和。
* 假设数组长度为`n`，要查询`m`次，每次都是`0`到`n-1`的和，总的查询时间复杂度：`O(n) * m`，当查询次数较多时，该方法较慢
    * 时间复杂度：每个查询 `O(n)`（最坏情况都是遍历整个数组），没有预处理步骤（即预处理`O(1)`）
    * 空间复杂度：`O(1)`

2、**前缀和** 解法

数组输入时进行预处理，借助额外空间计算保存`前缀和`，空间复杂度：`O(n)`，而后计算区间和时每次只要`O(1)`

区间和为：`sums[right]-sums[left-1]`，`left=0`时，直接取`sums[right]`。

优化：区间和比数组长度多一位，`sums[0]`表示没有元素，则区间和为：`sums[right+1] - sums[left]`，边界处理更为简洁。

```cpp
#include <iostream>
#include <vector>
using namespace std;

int main() {
    int num = 0;
    printf("input array size...\n");
    scanf("%d", &num);

    vector<int> arr(num);
    // 前缀和数组长度+1，可以简化边界处理，sums[0]表示没有值
    vector<int> sums(num + 1, 0);
    for (int i = 0; i < num; i++) {
        printf("input array member[%d]:", i);
        scanf("%d", &arr[i]);

        sums[i + 1] = sums[i] + arr[i];
    }

    int left, right;
    printf("input range left,right...\n");
    scanf("%d,%d", &left, &right);
    if (left < 0 || left > num-1 || right < 0 || right > num - 1 || left > right) {
        printf("left:%d or right:%d invalid!\n", left, right);
        return -1;
    }
    printf("sum:%d\n", sums[right + 1] - sums[left]);

    return 0;
}
```

### 6.2. 单元测试

上述代码简单放到了一个`main`函数里，基于 [GTest](https://github.com/google/googletest) 拆分成可单元测试的代码块。

可参考：[GoogleTest Quickstart: Building with CMake](https://google.github.io/googletest/quickstart-cmake.html)

下面的完整代码，见：[range_sum/unit_test](https://github.com/xiaodongQ/LeetCode/tree/master/cpp_exercise/range_sum/unit_test)

#### 6.2.1. 实现

```cpp
// prefix_sum.cpp
// 计算前缀和
std::vector<int> computePrefixSum(const std::vector<int>& arr) {
    std::vector<int> sums(arr.size() + 1, 0); // 初始化前缀和数组
    for (size_t i = 0; i < arr.size(); ++i) {
        sums[i + 1] = sums[i] + arr[i];
    }
    return sums;
}

// 根据前缀和计算区间和
int rangeSum(const std::vector<int>& sums, int left, int right) {
    return sums[right + 1] - sums[left];
}
```

#### 6.2.2. 单元测试代码

prefix_sum_test.cpp：

```cpp
#include <gtest/gtest.h>
#include "prefix_sum.h"

TEST(PrefixSumTest, ComputePrefixSum) {
    std::vector<int> arr = {1, 2, 3, 4, 5};
    std::vector<int> expected_sums = {0, 1, 3, 6, 10, 15};
    std::vector<int> sums = computePrefixSum(arr);
    ASSERT_EQ(sums, expected_sums);
}

TEST(PrefixSumTest, RangeSum) {
    std::vector<int> arr = {1, 2, 3, 4, 5};
    std::vector<int> sums = computePrefixSum(arr);
    EXPECT_EQ(rangeSum(sums, 0, 1), 3); // 从0到1
    EXPECT_EQ(rangeSum(sums, 1, 3), 9); // 从1到3
    EXPECT_EQ(rangeSum(sums, 2, 4), 12); // 从2到4
}

int main(int argc, char **argv) {
    ::testing::InitGoogleTest(&argc, argv);
    return RUN_ALL_TESTS();
}
```

#### 6.2.3. CMakeLists.txt

CMake 3.11版本引入了`FetchContent`模块，提供了一种在配置阶段直接从外部项目下载源代码的能力，而不需要事先将代码下载到本地或作为项目的一部分提交到版本控制系统。

直接在里面引入GTest依赖：

```sh
cmake_minimum_required(VERSION 3.14)
project(prefix_sum_test)

# 设置编译器标志
# GoogleTest requires at least C++14
set(CMAKE_CXX_STANDARD 14)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# 通过cmake的模块，设置 Google Test
include(FetchContent)
FetchContent_Declare(
  googletest
  URL https://github.com/google/googletest/archive/refs/tags/v1.15.2.zip
)
FetchContent_MakeAvailable(googletest)

# 添加子目录，包含 Google Test
enable_testing()

# 添加单元测试
add_executable(
	prefix_sum_test
	prefix_sum_test.cpp
	prefix_sum.cpp
)
# 添加依赖关系
target_link_libraries(prefix_sum_test gtest gtest_main)

include(GoogleTest)
gtest_discover_tests(prefix_sum_test)
```

#### 6.2.4. 编译运行

`mkdir build; cd build; cmake ..; make`

CMake是跨平台的，MacOS上编译并运行：

```sh
[MacOS-xd@qxd ➜ build git:(master) ✗ ]$ ctest
Test project /Users/xd/Documents/workspace/src/cpp_path/LeetCode/cpp_exercise/range_sum/unit_test/build
    Start 1: PrefixSumTest.ComputePrefixSum
1/2 Test #1: PrefixSumTest.ComputePrefixSum ...   Passed    0.01 sec
    Start 2: PrefixSumTest.RangeSum
2/2 Test #2: PrefixSumTest.RangeSum ...........   Passed    0.01 sec

100% tests passed, 0 tests failed out of 2

Total Test time (real) =   0.02 sec

[MacOS-xd@qxd ➜ build git:(master) ✗ ]$ ./prefix_sum_test 
[==========] Running 2 tests from 1 test suite.
[----------] Global test environment set-up.
[----------] 2 tests from PrefixSumTest
[ RUN      ] PrefixSumTest.ComputePrefixSum
[       OK ] PrefixSumTest.ComputePrefixSum (0 ms)
[ RUN      ] PrefixSumTest.RangeSum
[       OK ] PrefixSumTest.RangeSum (0 ms)
[----------] 2 tests from PrefixSumTest (0 ms total)

[----------] Global test environment tear-down
[==========] 2 tests from 1 test suite ran. (0 ms total)
[  PASSED  ] 2 tests.
```

CentOS上编译后运行：

```sh
[CentOS-root@xdlinux ➜ build git:(master) ✗ ]$ ./prefix_sum_test 
[==========] Running 2 tests from 1 test suite.
[----------] Global test environment set-up.
[----------] 2 tests from PrefixSumTest
[ RUN      ] PrefixSumTest.ComputePrefixSum
[       OK ] PrefixSumTest.ComputePrefixSum (0 ms)
[ RUN      ] PrefixSumTest.RangeSum
[       OK ] PrefixSumTest.RangeSum (0 ms)
[----------] 2 tests from PrefixSumTest (0 ms total)

[----------] Global test environment tear-down
[==========] 2 tests from 1 test suite ran. (0 ms total)
[  PASSED  ] 2 tests.
```

## 7. 开发商购买土地

非LeetCode上的原题，题目链接：[开发商购买土地](https://kamacoder.com/problempage.php?pid=1044)

简化：

* `n * m` 的矩阵，按横向或纵向划分成两个子区域，每个区域包含一个或多个值，返回两个子区域总和差异最小值

### 7.1. 思路和解法

由于要算两部分差值，先遍历获取总和`sum`，则划分时另一半的就是`sum - 当前和sum1`，求两部分差值最小。

两种方式（前面遍历求`sum`都需要）：

* 1、分别从行和列方向遍历二维数组，计算差值（`abs( sum1, sum-sum1 )`）并同差值最小值`result`对比
* 2、可参考`前缀和`的思路，分别先算每行和每列的和放在不同数组；再从行和列方向遍历，前缀和即数组项累加，计算比较最小值

复杂度都是`O(n^2)`，此处前缀和只是一个思路，效率并不如第一种。

## 8. 参考

1、[代码随想录 -- 数组篇](https://www.programmercarl.com/0704.%E4%BA%8C%E5%88%86%E6%9F%A5%E6%89%BE.html)

2、[LeetCode中文站](https://leetcode.cn/)

3、[LeetCode英文站](https://leetcode.com/)

4、[Rust标准库 -- std::vec::Vec](https://doc.rust-lang.org/std/vec/struct.Vec.html)

5、[GoogleTest Quickstart: Building with CMake](https://google.github.io/googletest/quickstart-cmake.html)
