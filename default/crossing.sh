#!/bin/bash

echo "开始执行"

cat > source.txt <<EOF
google.com
youtube.com
baidu.com
github.com
google.com
baidu.com
googleapis.com
github.com
EOF

echo "开始排序和去重"

sort source.txt | uniq > update.txt

echo "处理完成"
