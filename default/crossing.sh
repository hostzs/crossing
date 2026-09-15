#!/bin/bash

echo "开始下载"

curl -L -o source.txt https://raw.githubusercontent.com/iflyelf/gwf/main/direct.txt

echo "下载完成"

echo "总行数："
wc -l source.txt

echo "搜索 google 相关域名"

grep "google" source.txt > update.txt

echo "搜索完成"

cat update.txt
