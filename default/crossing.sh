#!/bin/bash

echo "开始下载"

curl -L -o source.txt https://raw.githubusercontent.com/iflyelf/gwf/main/direct.txt

echo "下载完成"

echo "生成 direct.txt"

grep "^google" source.txt > direct.txt

echo "生成 proxy.txt"

grep "\.com$" source.txt > proxy.txt

echo "处理完成"

echo "direct.txt："
wc -l direct.txt

echo "proxy.txt："
wc -l proxy.txt
