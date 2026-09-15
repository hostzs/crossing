#!/bin/bash

set -e

SOURCE="sources/manual-proxy.list"
OUTPUT="output/proxy.yaml"

echo "========================================"
echo "Crossing Rule Builder"
echo "========================================"

echo "原始数据：$SOURCE"
echo "输出文件：$OUTPUT"
echo ""

python3 <<'PY'
from pathlib import Path
from datetime import datetime
import hashlib

SOURCE = Path("sources/manual-proxy.list")
OUTPUT = Path("output/proxy.yaml")

# --------------------------------------------------
# 读取原始数据
# --------------------------------------------------

domains = []

with SOURCE.open("r", encoding="utf-8") as f:
    for line in f:
        line = line.strip()

        # 忽略空行
        if not line:
            continue

        # 忽略注释
        if line.startswith("#"):
            continue

        # 去掉行内注释
        if "#" in line:
            line = line.split("#", 1)[0].strip()

        if not line:
            continue

        # 去掉可能出现的协议
        if "://" in line:
            line = line.split("://", 1)[1]

        # 去掉 URL 路径
        line = line.split("/", 1)[0]

        # 去掉端口
        if ":" in line and not line.startswith("["):
            line = line.split(":", 1)[0]

        line = line.strip().lower().rstrip(".")

        if not line:
            continue

        domains.append(line)


print(f"读取域名：{len(domains)}")


# --------------------------------------------------
# IDN → Punycode
# --------------------------------------------------

normalized = []

for domain in domains:
    try:
        # Python 内置 IDNA 编码
        domain = domain.encode("idna").decode("ascii")
    except UnicodeError:
        print(f"警告：无法转换 IDN：{domain}")
        continue

    normalized.append(domain)


print(f"IDN 转换后：{len(normalized)}")


# --------------------------------------------------
# 去重
# --------------------------------------------------

domains = sorted(set(normalized))

print(f"去重后：{len(domains)}")


# --------------------------------------------------
# 计算源文件 SHA256
#
# 用于 GitHub Actions 判断
# manual-proxy.list 是否发生变化
# --------------------------------------------------

source_hash = hashlib.sha256(
    SOURCE.read_bytes()
).hexdigest()


# --------------------------------------------------
# 生成时间
#
# 使用北京时间
# --------------------------------------------------

updated = datetime.now().astimezone().strftime(
    "%Y-%m-%d %H:%M:%S"
)


# --------------------------------------------------
# 生成 YAML
# --------------------------------------------------

lines = []

lines.append("# NAME: proxy")
lines.append("# AUTHOR: edward")
lines.append("# REPO: https://github.com/hostzs/crossing")
lines.append(f"# UPDATED: {updated}")
lines.append("# DOMAIN-KEYWORD: 0")
lines.append(f"# DOMAIN-SUFFIX: {len(domains)}")
lines.append("# IP-CIDR: 0")
lines.append("# PROCESS-NAME: 0")
lines.append(f"# TOTAL: {len(domains)}")
lines.append(f"# SOURCE-SHA256: {source_hash}")
lines.append("")
lines.append("payload:")

for domain in domains:
    lines.append(f"  - DOMAIN-SUFFIX,{domain}")


# --------------------------------------------------
# 写入文件
# --------------------------------------------------

OUTPUT.parent.mkdir(parents=True, exist_ok=True)

OUTPUT.write_text(
    "\n".join(lines) + "\n",
    encoding="utf-8"
)


print("")
print("生成完成：")
print(f"  域名数量：{len(domains)}")
print(f"  SHA256：{source_hash}")
print(f"  输出：{OUTPUT}")
PY

echo ""
echo "========================================"
echo "处理完成"
echo "========================================"
