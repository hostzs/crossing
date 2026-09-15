#!/bin/bash

echo "开始下载真实数据"

curl -L -o source.txt https://raw.githubusercontent.com/iflyelf/gwf/main/direct.txt

echo "下载完成"

echo "文件大小："
wc -l source.txt
