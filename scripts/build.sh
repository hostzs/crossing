#!/bin/sh
set -eu

OUTPUT_DIR="output"

PROXY_SOURCE="sources/manual-proxy.list"
DIRECT_LOCAL_SOURCE="sources/manual-direct.list"

DIRECT_REMOTE_URL="https://raw.githubusercontent.com/Loyalsoldier/clash-rules/release/direct.txt"

PROXY_YAML="$OUTPUT_DIR/proxy.yaml"
PROXY_LIST="$OUTPUT_DIR/proxy.list"
PROXY_MRS="$OUTPUT_DIR/proxy.mrs"

DIRECT_YAML="$OUTPUT_DIR/direct.yaml"
DIRECT_LIST="$OUTPUT_DIR/direct.list"
DIRECT_MRS="$OUTPUT_DIR/direct.mrs"

echo "========================================"
echo "Crossing Rule Builder"
echo "========================================"
echo
echo "Proxy source：$PROXY_SOURCE"
echo "Direct local：$DIRECT_LOCAL_SOURCE"
echo "Direct remote：$DIRECT_REMOTE_URL"
echo

mkdir -p "$OUTPUT_DIR"

TMP_FILES=""

cleanup() {
    if [ -n "$TMP_FILES" ]; then
        rm -f $TMP_FILES
    fi
}

trap cleanup EXIT INT TERM

TMP_PROXY_RAW=$(mktemp)
TMP_PROXY_IDN=$(mktemp)
TMP_PROXY_SORTED=$(mktemp)

TMP_DIRECT_LOCAL=$(mktemp)
TMP_DIRECT_REMOTE=$(mktemp)
TMP_DIRECT_ALL=$(mktemp)
TMP_DIRECT_IDN=$(mktemp)
TMP_DIRECT_SORTED=$(mktemp)

OLD_PROXY_YAML=$(mktemp)
OLD_PROXY_LIST=$(mktemp)
OLD_PROXY_MRS=$(mktemp)

OLD_DIRECT_YAML=$(mktemp)
OLD_DIRECT_LIST=$(mktemp)
OLD_DIRECT_MRS=$(mktemp)

TMP_FILES="$TMP_PROXY_RAW \
$TMP_PROXY_IDN \
$TMP_PROXY_SORTED \
$TMP_DIRECT_LOCAL \
$TMP_DIRECT_REMOTE \
$TMP_DIRECT_ALL \
$TMP_DIRECT_IDN \
$TMP_DIRECT_SORTED \
$OLD_PROXY_YAML \
$OLD_PROXY_LIST \
$OLD_PROXY_MRS \
$OLD_DIRECT_YAML \
$OLD_DIRECT_LIST \
$OLD_DIRECT_MRS"

if [ -f "$PROXY_YAML" ]; then
    cp "$PROXY_YAML" "$OLD_PROXY_YAML"
fi

if [ -f "$PROXY_LIST" ]; then
    cp "$PROXY_LIST" "$OLD_PROXY_LIST"
fi

if [ -f "$PROXY_MRS" ]; then
    cp "$PROXY_MRS" "$OLD_PROXY_MRS"
fi

if [ -f "$DIRECT_YAML" ]; then
    cp "$DIRECT_YAML" "$OLD_DIRECT_YAML"
fi

if [ -f "$DIRECT_LIST" ]; then
    cp "$DIRECT_LIST" "$OLD_DIRECT_LIST"
fi

if [ -f "$DIRECT_MRS" ]; then
    cp "$DIRECT_MRS" "$OLD_DIRECT_MRS"
fi


########################################
# Proxy
########################################

echo "========================================"
echo "处理 Proxy Rules"
echo "========================================"
echo

grep -v '^[[:space:]]*$' "$PROXY_SOURCE" \
    | grep -v '^[[:space:]]*#' \
    | sed 's/[[:space:]]*#.*$//' \
    | sed 's/^[[:space:]]*//' \
    | sed 's/[[:space:]]*$//' \
    > "$TMP_PROXY_RAW"

sed -i \
    -e 's/^DOMAIN-SUFFIX,//' \
    -e 's/^DOMAIN,//' \
    "$TMP_PROXY_RAW"

python3 - "$TMP_PROXY_RAW" "$TMP_PROXY_IDN" <<'PY'
import sys

src = sys.argv[1]
dst = sys.argv[2]

count = 0

with open(src, "r", encoding="utf-8") as f, \
     open(dst, "w", encoding="utf-8") as out:

    for line in f:
        domain = line.strip().lower()

        if not domain:
            continue

        try:
            domain = domain.encode("idna").decode("ascii")
        except Exception:
            pass

        domain = domain.rstrip(".")

        if domain:
            out.write(domain + "\n")
            count += 1

print(f"Proxy IDN 转换后：{count}")
PY

sort -u "$TMP_PROXY_IDN" > "$TMP_PROXY_SORTED"

PROXY_COUNT=$(grep -c . "$TMP_PROXY_SORTED" || true)

PROXY_SOURCE_SHA256=$(sha256sum "$PROXY_SOURCE" | awk '{print $1}')

echo "Proxy 去重后：$PROXY_COUNT"
echo "Proxy SHA256：$PROXY_SOURCE_SHA256"
echo


########################################
# Direct - local
########################################

echo "========================================"
echo "处理 Direct 本地规则"
echo "========================================"
echo

if [ -f "$DIRECT_LOCAL_SOURCE" ]; then

    grep -v '^[[:space:]]*$' "$DIRECT_LOCAL_SOURCE" \
        | grep -v '^[[:space:]]*#' \
        | sed 's/[[:space:]]*#.*$//' \
        | sed 's/^[[:space:]]*//' \
        | sed 's/[[:space:]]*$//' \
        > "$TMP_DIRECT_LOCAL"

else

    : > "$TMP_DIRECT_LOCAL"

fi

sed -i \
    -e 's/^DOMAIN-SUFFIX,//' \
    -e 's/^DOMAIN,//' \
    "$TMP_DIRECT_LOCAL"

LOCAL_DIRECT_COUNT=$(grep -c . "$TMP_DIRECT_LOCAL" || true)

echo "本地 Direct：$LOCAL_DIRECT_COUNT"
echo


########################################
# Direct - remote
########################################

echo "========================================"
echo "下载 Loyalsoldier Direct"
echo "========================================"
echo

curl -fsSL \
    "$DIRECT_REMOTE_URL" \
    -o "$TMP_DIRECT_REMOTE"

REMOTE_DIRECT_SHA256=$(sha256sum "$TMP_DIRECT_REMOTE" | awk '{print $1}')

echo "Remote SHA256：$REMOTE_DIRECT_SHA256"
echo


########################################
# Direct - parse remote YAML
########################################

echo "========================================"
echo "解析 Loyalsoldier Direct"
echo "========================================"
echo

python3 - "$TMP_DIRECT_REMOTE" "$TMP_DIRECT_ALL" "$TMP_DIRECT_LOCAL" <<'PY'
import sys
import re

remote = sys.argv[1]
output = sys.argv[2]
local = sys.argv[3]

count_remote = 0
count_local = 0

domain_re = re.compile(
    r"^[A-Za-z0-9*_-]+(?:\.[A-Za-z0-9*_-]+)+$"
)

def write_domain(out, value):
    global count_remote

    value = value.strip()

    if not value:
        return

    # 去掉 YAML 引号
    if (
        len(value) >= 2
        and value[0] in ("'", '"')
        and value[-1] == value[0]
    ):
        value = value[1:-1]

    value = value.strip().lower().rstrip(".")

    if not value:
        return

    # 当前 Loyalsoldier direct.txt 是：
    #
    # payload:
    #   - 'example.com'
    #
    # 这里只提取真正的域名。
    if domain_re.match(value):
        out.write(value + "\n")
        count_remote += 1


with open(output, "w", encoding="utf-8") as out:

    # 先写远程规则
    with open(remote, "r", encoding="utf-8") as f:

        for line in f:

            line = line.strip()

            if not line.startswith("-"):
                continue

            value = line[1:].strip()

            write_domain(out, value)

    # 再写本地规则
    with open(local, "r", encoding="utf-8") as f:

        for line in f:

            value = line.strip()

            if not value:
                continue

            value = value.strip()

            if value.startswith("DOMAIN-SUFFIX,"):
                value = value[len("DOMAIN-SUFFIX,"):]

            elif value.startswith("DOMAIN,"):
                value = value[len("DOMAIN,"):]

            value = value.strip().lower().rstrip(".")

            if value:
                out.write(value + "\n")
                count_local += 1

print(f"Remote Direct：{count_remote}")
print(f"Local Direct：{count_local}")
PY

python3 - "$TMP_DIRECT_ALL" "$TMP_DIRECT_IDN" <<'PY'
import sys

src = sys.argv[1]
dst = sys.argv[2]

count = 0

with open(src, "r", encoding="utf-8") as f, \
     open(dst, "w", encoding="utf-8") as out:

    for line in f:

        domain = line.strip().lower()

        if not domain:
            continue

        try:
            domain = domain.encode("idna").decode("ascii")
        except Exception:
            pass

        domain = domain.rstrip(".")

        if domain:
            out.write(domain + "\n")
            count += 1

print(f"Direct IDN 转换后：{count}")
PY

sort -u "$TMP_DIRECT_IDN" > "$TMP_DIRECT_SORTED"

DIRECT_COUNT=$(grep -c . "$TMP_DIRECT_SORTED" || true)

echo
echo "Direct 最终去重后：$DIRECT_COUNT"
echo


########################################
# Combined hashes
########################################

DIRECT_LOCAL_SHA256=$(sha256sum "$DIRECT_LOCAL_SOURCE" 2>/dev/null \
    | awk '{print $1}' || true)

if [ -z "$DIRECT_LOCAL_SHA256" ]; then
    DIRECT_LOCAL_SHA256="EMPTY"
fi

DIRECT_COMBINED_SHA256=$(
    printf '%s\n' \
        "$DIRECT_LOCAL_SHA256" \
        "$REMOTE_DIRECT_SHA256" \
        | sha256sum \
        | awk '{print $1}'
)

UPDATED=$(TZ="Asia/Shanghai" date +"%Y-%m-%d %H:%M:%S CST")


########################################
# Generate Proxy YAML
########################################

{
    echo "# NAME: proxy"
    echo "# AUTHOR: edward"
    echo "# REPO: https://github.com/hostzs/crossing"
    echo "# UPDATED: $UPDATED"
    echo "# SOURCE-SHA256: $PROXY_SOURCE_SHA256"
    echo "# COUNT: $PROXY_COUNT"
    echo "#"
    echo "# Generated by Crossing Rule Builder"
    echo

    while IFS= read -r domain
    do
        echo "  - $domain"
    done < "$TMP_PROXY_SORTED"

} > "$PROXY_YAML"


########################################
# Generate Proxy LIST
########################################

{
    echo "# NAME: proxy"
    echo "# AUTHOR: edward"
    echo "# REPO: https://github.com/hostzs/crossing"
    echo "# UPDATED: $UPDATED"
    echo "# SOURCE-SHA256: $PROXY_SOURCE_SHA256"
    echo "# COUNT: $PROXY_COUNT"
    echo "#"

    while IFS= read -r domain
    do
        echo "$domain"
    done < "$TMP_PROXY_SORTED"

} > "$PROXY_LIST"


########################################
# Generate Proxy MRS
########################################

echo "生成 Proxy MRS..."

mihomo convert-ruleset domain text \
    "$PROXY_LIST" \
    "$PROXY_MRS"


########################################
# Generate Direct YAML
########################################

{
    echo "# NAME: direct"
    echo "# AUTHOR: edward"
    echo "# REPO: https://github.com/hostzs/crossing"
    echo "# UPDATED: $UPDATED"
    echo "# SOURCE-SHA256: $DIRECT_COMBINED_SHA256"
    echo "# COUNT: $DIRECT_COUNT"
    echo "# REMOTE-SOURCE: $DIRECT_REMOTE_URL"
    echo "# REMOTE-SHA256: $REMOTE_DIRECT_SHA256"
    echo "#"
    echo "# Generated by Crossing Rule Builder"
    echo

    while IFS= read -r domain
    do
        echo "  - $domain"
    done < "$TMP_DIRECT_SORTED"

} > "$DIRECT_YAML"


########################################
# Generate Direct LIST
########################################

{
    echo "# NAME: direct"
    echo "# AUTHOR: edward"
    echo "# REPO: https://github.com/hostzs/crossing"
    echo "# UPDATED: $UPDATED"
    echo "# SOURCE-SHA256: $DIRECT_COMBINED_SHA256"
    echo "# COUNT: $DIRECT_COUNT"
    echo "# REMOTE-SOURCE: $DIRECT_REMOTE_URL"
    echo "# REMOTE-SHA256: $REMOTE_DIRECT_SHA256"
    echo "#"

    while IFS= read -r domain
    do
        echo "$domain"
    done < "$TMP_DIRECT_SORTED"

} > "$DIRECT_LIST"


########################################
# Generate Direct MRS
########################################

echo
echo "生成 Direct MRS..."

mihomo convert-ruleset domain text \
    "$DIRECT_LIST" \
    "$DIRECT_MRS"


########################################
# Compare generated files
########################################

PROXY_YAML_CHANGED=0
PROXY_LIST_CHANGED=0
PROXY_MRS_CHANGED=0

DIRECT_YAML_CHANGED=0
DIRECT_LIST_CHANGED=0
DIRECT_MRS_CHANGED=0


if [ ! -f "$OLD_PROXY_YAML" ] || \
   ! cmp -s "$PROXY_YAML" "$OLD_PROXY_YAML"; then
    PROXY_YAML_CHANGED=1
fi

if [ ! -f "$OLD_PROXY_LIST" ] || \
   ! cmp -s "$PROXY_LIST" "$OLD_PROXY_LIST"; then
    PROXY_LIST_CHANGED=1
fi

if [ ! -f "$OLD_PROXY_MRS" ] || \
   ! cmp -s "$PROXY_MRS" "$OLD_PROXY_MRS"; then
    PROXY_MRS_CHANGED=1
fi


if [ ! -f "$OLD_DIRECT_YAML" ] || \
   ! cmp -s "$DIRECT_YAML" "$OLD_DIRECT_YAML"; then
    DIRECT_YAML_CHANGED=1
fi

if [ ! -f "$OLD_DIRECT_LIST" ] || \
   ! cmp -s "$DIRECT_LIST" "$OLD_DIRECT_LIST"; then
    DIRECT_LIST_CHANGED=1
fi

if [ ! -f "$OLD_DIRECT_MRS" ] || \
   ! cmp -s "$DIRECT_MRS" "$OLD_DIRECT_MRS"; then
    DIRECT_MRS_CHANGED=1
fi


########################################
# Restore old files if nothing changed
########################################

if [ "$PROXY_YAML_CHANGED" -eq 0 ] && \
   [ "$PROXY_LIST_CHANGED" -eq 0 ] && \
   [ "$PROXY_MRS_CHANGED" -eq 0 ] && \
   [ "$DIRECT_YAML_CHANGED" -eq 0 ] && \
   [ "$DIRECT_LIST_CHANGED" -eq 0 ] && \
   [ "$DIRECT_MRS_CHANGED" -eq 0 ]; then

    echo
    echo "========================================"
    echo "输出内容没有变化"
    echo "========================================"
    echo
    echo "仅 UPDATED 时间发生变化"
    echo "恢复旧文件，避免无意义提交"
    echo

    if [ -f "$OLD_PROXY_YAML" ]; then
        cp "$OLD_PROXY_YAML" "$PROXY_YAML"
    fi

    if [ -f "$OLD_PROXY_LIST" ]; then
        cp "$OLD_PROXY_LIST" "$PROXY_LIST"
    fi

    if [ -f "$OLD_PROXY_MRS" ]; then
        cp "$OLD_PROXY_MRS" "$PROXY_MRS"
    fi

    if [ -f "$OLD_DIRECT_YAML" ]; then
        cp "$OLD_DIRECT_YAML" "$DIRECT_YAML"
    fi

    if [ -f "$OLD_DIRECT_LIST" ]; then
        cp "$OLD_DIRECT_LIST" "$DIRECT_LIST"
    fi

    if [ -f "$OLD_DIRECT_MRS" ]; then
        cp "$OLD_DIRECT_MRS" "$DIRECT_MRS"
    fi

fi


########################################
# Summary
########################################

echo
echo "========================================"
echo "生成完成"
echo "========================================"
echo
echo "Proxy："
echo "  域名数量：$PROXY_COUNT"
echo "  SHA256：$PROXY_SOURCE_SHA256"
echo
echo "Direct："
echo "  本地规则：$LOCAL_DIRECT_COUNT"
echo "  远程规则：见上方解析结果"
echo "  最终去重：$DIRECT_COUNT"
echo "  Combined SHA256：$DIRECT_COMBINED_SHA256"
echo "  Remote SHA256：$REMOTE_DIRECT_SHA256"
echo
echo "输出："
echo "  $PROXY_YAML"
echo "  $PROXY_LIST"
echo "  $PROXY_MRS"
echo "  $DIRECT_YAML"
echo "  $DIRECT_LIST"
echo "  $DIRECT_MRS"
echo
