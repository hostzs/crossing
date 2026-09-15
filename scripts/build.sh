#!/bin/bash

set -e

echo "========================================"
echo "Crossing Rule Builder"
echo "========================================"

SOURCE="sources/manual-proxy.list"
OUTPUT_YAML="output/proxy.yaml"
OUTPUT_LIST="output/proxy.list"
OUTPUT_MRS="output/proxy.mrs"

echo "原始数据：$SOURCE"
echo "输出 YAML：$OUTPUT_YAML"
echo "输出 TEXT：$OUTPUT_LIST"
echo "输出 MRS：$OUTPUT_MRS"
echo ""

python3 <<'PY'
from pathlib import Path
from datetime import datetime, timezone
import hashlib
import subprocess
import sys

SOURCE = Path("sources/manual-proxy.list")
OUTPUT_YAML = Path("output/proxy.yaml")
OUTPUT_LIST = Path("output/proxy.list")
OUTPUT_MRS = Path("output/proxy.mrs")

# ============================================================
# 读取原始文件
# ============================================================

raw = SOURCE.read_text(encoding="utf-8")

source_hash = hashlib.sha256(
    raw.encode("utf-8")
).hexdigest()

lines = raw.splitlines()

domains = []

for line in lines:
    line = line.strip()

    # 跳过空行
    if not line:
        continue

    # 跳过注释
    if line.startswith("#"):
        continue

    # 如果用户误写成 DOMAIN-SUFFIX,example.com
    # 自动提取域名
    if "," in line:
        parts = line.split(",", 1)

        if parts[0].strip().upper() == "DOMAIN-SUFFIX":
            line = parts[1].strip()

    if line:
        domains.append(line)

print(f"读取域名：{len(domains)}")

# ============================================================
# IDN → Punycode
# ============================================================

converted = []

for domain in domains:
    try:
        domain = domain.rstrip(".").encode("idna").decode("ascii")
    except Exception as e:
        print(f"警告：无法转换域名：{domain}")
        print(f"原因：{e}")
        continue

    converted.append(domain.lower())

print(f"IDN 转换后：{len(converted)}")

# ============================================================
# 去重 + 排序
# ============================================================

domains = sorted(set(converted))

print(f"去重后：{len(domains)}")
print("")

# ============================================================
# 时间
# ============================================================

updated = datetime.now(timezone.utc).strftime(
    "%Y-%m-%d %H:%M:%S UTC"
)

# ============================================================
# 生成 YAML
# ============================================================

yaml_lines = []

yaml_lines.append("# NAME: proxy")
yaml_lines.append("# AUTHOR: edward")
yaml_lines.append("# REPO: https://github.com/hostzs/crossing")
yaml_lines.append(f"# UPDATED: {updated}")
yaml_lines.append("# BEHAVIOR: domain")
yaml_lines.append("# FORMAT: yaml")
yaml_lines.append(f"# DOMAIN: {len(domains)}")
yaml_lines.append(f"# TOTAL: {len(domains)}")
yaml_lines.append(f"# SOURCE-SHA256: {source_hash}")
yaml_lines.append("")
yaml_lines.append("payload:")

for domain in domains:
    yaml_lines.append(f"  - {domain}")

yaml_content = "\n".join(yaml_lines) + "\n"

# ============================================================
# 生成纯文本 LIST
# ============================================================

list_lines = []

for domain in domains:
    list_lines.append(domain)

list_content = "\n".join(list_lines) + "\n"

# ============================================================
# 写入 YAML / LIST
# ============================================================

OUTPUT_YAML.parent.mkdir(parents=True, exist_ok=True)

OUTPUT_YAML.write_text(
    yaml_content,
    encoding="utf-8"
)

OUTPUT_LIST.write_text(
    list_content,
    encoding="utf-8"
)

print("YAML 和 TEXT 生成完成")

PY

# ============================================================
# 使用 Mihomo 生成 MRS
# ============================================================

echo ""
echo "开始生成 MRS..."

if ! command -v mihomo >/dev/null 2>&1; then
    echo "错误：找不到 mihomo"
    exit 1
fi

mihomo convert-ruleset domain text \
  "$OUTPUT_LIST" \
  "$OUTPUT_MRS"

# ============================================================
# 完成
# ============================================================

echo ""
echo "生成完成："
echo "  域名数量：$(grep -cve '^[[:space:]]*$' "$OUTPUT_LIST")"
echo "  SHA256：$(sha256sum "$SOURCE" | awk '{print $1}')"
echo "  YAML：$OUTPUT_YAML"
echo "  TEXT：$OUTPUT_LIST"
echo "  MRS：$OUTPUT_MRS"
