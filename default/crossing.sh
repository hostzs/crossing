#!/bin/bash

echo "开始执行"

cat > source.txt <<EOF
google.com
youtube.com
baidu.com
github.com
googleapis.com
EOF

echo "筛选 google 相关域名"

grep "google" source.txt > update.txt

echo "修改规则格式"

sed -i 's/google/google-test/g' update.txt

echo "处理完成"
