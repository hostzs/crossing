#!/bin/bash

echo "开始下载"

curl -L -o source.txt https://raw.githubusercontent.com/iflyelf/gwf/main/direct.txt

echo "下载完成"

echo "总行数："
wc -l source.txt

echo "前 20 行："
head -20 source.txt
