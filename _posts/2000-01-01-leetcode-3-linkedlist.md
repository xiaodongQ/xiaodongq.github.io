---
layout: post
title: LeetCode刷题学习（三） -- 链表篇
categories: LeetCode
tags: LeetCode 数据结构与算法
---

* content
{:toc}

LeetCode刷题学习记录，链表篇。



## 1. 基础

链表定义：

```cpp
// 单链表
struct ListNode {
    int val;  // 节点上存储的元素
    ListNode *next;  // 指向下一个节点的指针
    ListNode(int x) : val(x), next(NULL) {}  // 节点的构造函数
};

// 示例，初始化一个链表，构造函数便于初始化时对节点赋值
ListNode* head = new ListNode(5);
```

## 2. 203.移除链表元素

[203. Remove Linked List Elements](https://leetcode.com/problems/remove-linked-list-elements/)

### 2.1. 思路和解法

技巧：定义虚拟头节点，避免头节点单独处理。

另外有几个注意点：

* 虚拟头节点记得释放空间，不要直接`return dummyHead->next`
* C++里要删除的节点，一般也释放其空间
* 注意循环中判断`currNode->next`，而不是用 `currNode != nullptr`，并对`currNode`迭代

```cpp
/**
 * Definition for singly-linked list.
 * struct ListNode {
 *     int val;
 *     ListNode *next;
 *     ListNode() : val(0), next(nullptr) {}
 *     ListNode(int x) : val(x), next(nullptr) {}
 *     ListNode(int x, ListNode *next) : val(x), next(next) {}
 * };
 */
class Solution {
public:
    ListNode* removeElements(ListNode* head, int val) {
        // 定义一个虚拟节点，指向链表头
        ListNode *dummyHead = new ListNode();
        dummyHead->next = head;
        ListNode *currNode = dummyHead;
        // 注意循环中判断next，而不是用 currNode != nullptr，并对currNode迭代
        while (currNode->next != nullptr) {
            if (currNode->next->val == val) {
                // 下一个节点和val相等，则移除下个节点
                ListNode *tmp_node = currNode->next;
                currNode->next = currNode->next->next;
                delete tmp_node;
            } else {
                // 没有匹配到相等节点时迭代下一个，上面匹配到时next已经指向下一个了
                currNode = currNode->next;
            }
        }

        // dummyHead 是临时申请的空间，需要释放掉
        ListNode *node = dummyHead->next;
        delete dummyHead;

        // 返回的节点指针，是原来链表中已有的节点
        return node;
    }
};
```

### 2.2. Rust解法

Rust中如果要实现链表的话比较复杂，可作了解：[手把手带你实现链表](https://course.rs/too-many-lists/intro.html)

上面的题目链接（[203. Remove Linked List Elements](https://leetcode.com/problems/remove-linked-list-elements/)）中，已经给出了Rust中的链表定义。

```rust
#[derive(PartialEq, Eq, Clone, Debug)]
pub struct ListNode {
  pub val: i32,
  // Option枚举类型，Some(T)和None；返回Some(T)时，是堆上分配的Box智能指针
  pub next: Option<Box<ListNode>>
}

impl ListNode {
  // 内联属性
  #[inline]
  // 这里的new只是创建了一个新的ListNode实例，不是指分配在堆内存上
  fn new(val: i32) -> Self {
    ListNode {
      next: None,
      val
    }
  }
}
```

学习参考链接中的题解：

```rust
impl Solution {
    pub fn remove_elements(head: Option<Box<ListNode>>, val: i32) -> Option<Box<ListNode>> {
        // 使用智能指针
        let mut dummyHead = Box::new(ListNode::new(0));
        dummyHead.next = head;
        let mut cur = dummyHead.as_mut();
        // 使用take()替换std::mem::replace(&mut node.next, None)达到相同的效果，并且更普遍易读
        while let Some(nxt) = cur.next.take() {
            if nxt.val == val {
                cur.next = nxt.next;
            } else {
                cur.next = Some(nxt);
                cur = cur.next.as_mut().unwrap();
            }
        }
        dummyHead.next
    }
}
```

## 3. 参考

1、[代码随想录 -- 链表篇](https://www.programmercarl.com/%E9%93%BE%E8%A1%A8%E7%90%86%E8%AE%BA%E5%9F%BA%E7%A1%80.html)

2、[LeetCode中文站](https://leetcode.cn/)

3、[LeetCode英文站](https://leetcode.com/)
