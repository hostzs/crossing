#!/bin/bash

echo "开始下载"

curl -L -o /tmp/source.txt https://raw.githubusercontent.com/iflyelf/gwf/main/direct.txt

echo "下载完成"

echo "原始数据行数："
wc -l /tmp/source.txt

echo ".com 数量："
grep -c "\.com$" /tmp/source.txt

echo ".cn 数量："
grep -c "\.cn$" /tmp/source.txt

echo "生成 direct.txt"

grep "^google" /tmp/source.txt > direct.txt

echo "生成 proxy.txt"

grep "\.com$" /tmp/source.txt > proxy.txt

echo "处理完成"

echo "direct.txt："
wc -l direct.txt

echo "proxy.txt："
wc -l proxy.txt
