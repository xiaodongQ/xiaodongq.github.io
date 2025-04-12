---
title: Vim编码识别及转换
categories: Linux
tags: Vim
---

## Vim编码

具体参考： [Vim文件编码识别与乱码处理](http://edyfox.codecarver.org/html/vim_fileencodings_detection.html)

在 Vim 中，有四个与编码有关的选项，它们是：fileencodings、fileencoding、encoding 和 termencoding。

1. encoding 是 Vim 内部使用的字符编码方式。
2. termencoding 是 Vim 用于屏幕显示的编码，在显示的时候，Vim 会把内部编码转换为屏幕编码，再用于输出。
3. fileencoding

    当 Vim 从磁盘上读取文件的时候，会对文件的编码进行探测，如果文件的编码方式和 Vim 的内部编码方式不同，Vim 就会对编码进行转换。转换完毕后，Vim 会将 fileencoding 选项设置为文件的编码。

4. 编码的自动识别是通过设置 fileencodings 实现的

**设置 fileencodings 的时候，一定要把要求严格的、当文件不是这个编码的时候更容易出现解码失败的编码方式放在前面，把宽松的编码方式放在后面。**

  `set fileencodings=ucs-bom,utf-8,cp936,gb18030,big5,euc-jp,euc-kr,latin1`

## Linux编码转换iconv

对比 fileencoding 和 encoding 的值，若不同则调用 iconv 将文件内容转换为encoding 所描述的字符编码方式，并且把转换后的内容放到为此文件开辟的 buffer 里。

e.g. 当前文件编码为gb2312(from)，转换为utf-8(to)，重定向到outputfilename

  `iconv -f gb2312 -t utf-8 inputfilename > outputfilename`

Windows中的文件编码转换直接转换可能出错中断，可先在 Atom中选择相关编码，文本内容都显示正常后保存，在进行iconv转换。
