#!/bin/bash

set -e

SOURCE="sources/manual-proxy.list"
OUTPUT_YAML="output/proxy.yaml"
OUTPUT_LIST="output/proxy.list"

echo "========================================"
echo "Crossing Rule Builder"
echo "========================================"

echo "原始数据：$SOURCE"
echo "输出 YAML：$OUTPUT_YAML"
echo "输出 TEXT：$OUTPUT_LIST"
echo ""

python3 <<'PY'
from pathlib import Path
from datetime import datetime
import hashlib

SOURCE = Path("sources/manual-proxy.list")
OUTPUT_YAML = Path("output/proxy.yaml")
OUTPUT_LIST = Path("output/proxy.list")

domains = []

# ============================================================
# 1. 读取源文件
# ============================================================

with SOURCE.open("r", encoding="utf-8") as f:
    for line in f:

        # 去除首尾空白
        line = line.strip()

        # 空行
        if not line:
            continue

        # 整行注释
        if line.startswith("#"):
            continue

        # 去除行尾注释
        if "#" in line:
            line = line.split("#", 1)[0].strip()

        if not line:
            continue

        # ====================================================
        # 2. 清理 URL
        # ====================================================

        if "://" in line:
            line = line.split("://", 1)[1]

        # 去掉路径
        line = line.split("/", 1)[0]

        # 去掉端口
        if ":" in line and not line.startswith("["):
            line = line.split(":", 1)[0]

        # ====================================================
        # 3. 基础标准化
        # ====================================================

        line = line.strip().lower().rstrip(".")

        if not line:
            continue

        domains.append(line)

print(f"读取域名：{len(domains)}")


# ============================================================
# 4. IDN → Punycode
# ============================================================

normalized = []

for domain in domains:

    try:
        domain = domain.encode("idna").decode("ascii")
    except UnicodeError:
        print(f"警告：无法转换 IDN：{domain}")
        continue

    normalized.append(domain)

print(f"IDN 转换后：{len(normalized)}")


# ============================================================
# 5. 去重 + 排序
# ============================================================

domains = sorted(set(normalized))

print(f"去重后：{len(domains)}")


# ============================================================
# 6. 计算源文件 SHA256
# ============================================================

source_hash = hashlib.sha256(
    SOURCE.read_bytes()
).hexdigest()


# ============================================================
# 7. 生成时间
# ============================================================

updated = datetime.now().astimezone().strftime(
    "%Y-%m-%d %H:%M:%S"
)


# ============================================================
# 8. 生成 proxy.yaml
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

OUTPUT_YAML.parent.mkdir(parents=True, exist_ok=True)

OUTPUT_YAML.write_text(
    "\n".join(yaml_lines) + "\n",
    encoding="utf-8"
)


# ============================================================
# 9. 生成 proxy.list
# ============================================================

list_lines = []

for domain in domains:
    list_lines.append(domain)

OUTPUT_LIST.write_text(
    "\n".join(list_lines) + "\n",
    encoding="utf-8"
)


# ============================================================
# 10. 输出结果
# ============================================================

print("")
print("生成完成：")
print(f"  域名数量：{len(domains)}")
print(f"  SHA256：{source_hash}")
print(f"  YAML：{OUTPUT_YAML}")
print(f"  TEXT：{OUTPUT_LIST}")
