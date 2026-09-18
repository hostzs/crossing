#!/bin/sh

set -eu

OUTPUT_DIR="output"

PROXY_SOURCE="sources/manual-proxy.list"
DIRECT_SOURCE="sources/manual-direct.list"

DIRECT_REMOTE_URL="https://raw.githubusercontent.com/Loyalsoldier/clash-rules/release/direct.txt"

echo "========================================"
echo "Crossing Rule Builder"
echo "========================================"
echo

mkdir -p "$OUTPUT_DIR"

# ============================================================
# 临时文件清理
# ============================================================

TMP_FILES=""

cleanup() {
    if [ -n "$TMP_FILES" ]; then
        rm -f $TMP_FILES
    fi
}

trap cleanup EXIT INT TERM

new_tmp() {
    TMP=$(mktemp)
    TMP_FILES="$TMP_FILES $TMP"
    echo "$TMP"
}

# ============================================================
# 构建规则
#
# 参数：
#
# $1 = NAME
# $2 = 本地 SOURCE
# $3 = OUTPUT 前缀
# $4 = 远程规则 URL，可为空
# ============================================================

build_rule() {

    NAME="$1"
    SOURCE="$2"
    OUTPUT="$3"
    REMOTE_URL="${4:-}"

    OUTPUT_YAML="$OUTPUT.yaml"
    OUTPUT_LIST="$OUTPUT.list"
    OUTPUT_MRS="$OUTPUT.mrs"

    echo "========================================"
    echo "开始构建：$NAME"
    echo "========================================"
    echo
    echo "原始数据：$SOURCE"
    echo "输出 YAML：$OUTPUT_YAML"
    echo "输出 TEXT：$OUTPUT_LIST"
    echo "输出 MRS：$OUTPUT_MRS"

    if [ -n "$REMOTE_URL" ]; then
        echo "远程规则：$REMOTE_URL"
    fi

    echo

    # ========================================================
    # 保存旧输出
    # ========================================================

    OLD_YAML=$(new_tmp)
    OLD_LIST=$(new_tmp)
    OLD_MRS=$(new_tmp)

    [ -f "$OUTPUT_YAML" ] && cp "$OUTPUT_YAML" "$OLD_YAML"
    [ -f "$OUTPUT_LIST" ] && cp "$OUTPUT_LIST" "$OLD_LIST"
    [ -f "$OUTPUT_MRS" ] && cp "$OUTPUT_MRS" "$OLD_MRS"

    # ========================================================
    # 临时文件
    # ========================================================

    TMP_RAW=$(new_tmp)
    TMP_IDN=$(new_tmp)
    TMP_SORTED=$(new_tmp)
    TMP_REMOTE=$(new_tmp)

    # ========================================================
    # 读取本地规则
    # ========================================================

    if [ ! -f "$SOURCE" ]; then
        echo "错误：找不到规则文件：$SOURCE"
        exit 1
    fi

    grep -v '^[[:space:]]*$' "$SOURCE" \
        | grep -v '^[[:space:]]*#' \
        | sed 's/[[:space:]]*#.*$//' \
        | sed 's/^[[:space:]]*//' \
        | sed 's/[[:space:]]*$//' \
        > "$TMP_RAW"

    # ========================================================
    # 兼容：
    #
    # DOMAIN-SUFFIX,example.com
    # DOMAIN,example.com
    #
    # 最终统一为：
    #
    # example.com
    # ========================================================

    sed -i \
        -e 's/^DOMAIN-SUFFIX,//' \
        -e 's/^DOMAIN,//' \
        "$TMP_RAW"

    LOCAL_COUNT=$(grep -c . "$TMP_RAW" || true)

    echo "本地规则：$LOCAL_COUNT"

    # ========================================================
    # 下载远程规则
    # ========================================================

    REMOTE_SHA256=""

    if [ -n "$REMOTE_URL" ]; then

        echo
        echo "下载远程规则..."

        curl -fsSL \
            --retry 3 \
            --connect-timeout 15 \
            --max-time 120 \
            "$REMOTE_URL" \
            -o "$TMP_REMOTE"

        REMOTE_SHA256=$(sha256sum "$TMP_REMOTE" | awk '{print $1}')

        echo "远程规则 SHA256：$REMOTE_SHA256"

        # ----------------------------------------------------
        # Loyalsoldier direct.txt
        #
        # 目前需要的是 domain 类型规则。
        #
        # 支持：
        #
        # DOMAIN-SUFFIX,example.com
        # DOMAIN,example.com
        #
        # DOMAIN-KEYWORD / IP-CIDR 等非 domain 规则不加入
        # ----------------------------------------------------

        grep -E '^(DOMAIN-SUFFIX|DOMAIN),' "$TMP_REMOTE" \
            | sed \
                -e 's/^DOMAIN-SUFFIX,//' \
                -e 's/^DOMAIN,//' \
            >> "$TMP_RAW" || true

        REMOTE_COUNT=$(grep -E '^(DOMAIN-SUFFIX|DOMAIN),' "$TMP_REMOTE" | wc -l | tr -d ' ' || true)

        echo "远程 domain 规则：$REMOTE_COUNT"
    fi

    # ========================================================
    # IDN 转 Punycode
    # ========================================================

    echo
    echo "开始 IDN 转 Punycode..."

    python3 - "$TMP_RAW" "$TMP_IDN" <<'PY'
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

        # 去掉可能存在的前导点
        domain = domain.lstrip(".")

        # IDN → Punycode
        try:
            domain = domain.encode("idna").decode("ascii")
        except Exception:
            pass

        # 去掉末尾 .
        domain = domain.rstrip(".")

        if domain:
            out.write(domain + "\n")
            count += 1

print(f"IDN 转换后：{count}")
PY

    # ========================================================
    # 去重 + 排序
    # ========================================================

    sort -u "$TMP_IDN" > "$TMP_SORTED"

    DOMAIN_COUNT=$(grep -c . "$TMP_SORTED" || true)

    echo "去重后：$DOMAIN_COUNT"
    echo

    # ========================================================
    # SOURCE SHA256
    #
    # Proxy：
    #   只计算 manual-proxy.list
    #
    # Direct：
    #   同时计算：
    #   manual-direct.list
    #   Loyalsoldier direct.txt
    #
    # 这样远程规则变化可以被检测到。
    # ========================================================

    LOCAL_SHA256=$(sha256sum "$SOURCE" | awk '{print $1}')

    if [ -n "$REMOTE_URL" ]; then

        SOURCE_SHA256=$(
            {
                printf '%s  %s\n' "$LOCAL_SHA256" "$SOURCE"
                printf '%s  %s\n' "$REMOTE_SHA256" "$REMOTE_URL"
            } | sha256sum | awk '{print $1}'
        )

    else

        SOURCE_SHA256="$LOCAL_SHA256"

    fi

    # ========================================================
    # 更新时间
    # ========================================================

    UPDATED=$(TZ="Asia/Shanghai" date +"%Y-%m-%d %H:%M:%S CST")

    # ========================================================
    # 生成 YAML
    # ========================================================

    {
        echo "# NAME: $NAME"
        echo "# AUTHOR: edward"
        echo "# REPO: https://github.com/hostzs/crossing"
        echo "# UPDATED: $UPDATED"
        echo "# SOURCE-SHA256: $SOURCE_SHA256"
        echo "# COUNT: $DOMAIN_COUNT"

        if [ -n "$REMOTE_URL" ]; then
            echo "# REMOTE-SOURCE: $REMOTE_URL"
            echo "# REMOTE-SHA256: $REMOTE_SHA256"
        fi

        echo "#"
        echo "# Generated by Crossing Rule Builder"
        echo

        while IFS= read -r domain
        do
            echo "  - $domain"
        done < "$TMP_SORTED"

    } > "$OUTPUT_YAML"

    # ========================================================
    # 生成 LIST
    # ========================================================

    {
        echo "# NAME: $NAME"
        echo "# AUTHOR: edward"
        echo "# REPO: https://github.com/hostzs/crossing"
        echo "# UPDATED: $UPDATED"
        echo "# SOURCE-SHA256: $SOURCE_SHA256"
        echo "# COUNT: $DOMAIN_COUNT"

        if [ -n "$REMOTE_URL" ]; then
            echo "# REMOTE-SOURCE: $REMOTE_URL"
            echo "# REMOTE-SHA256: $REMOTE_SHA256"
        fi

        echo "#"

        while IFS= read -r domain
        do
            echo "$domain"
        done < "$TMP_SORTED"

    } > "$OUTPUT_LIST"

    echo
    echo "YAML 和 TEXT 生成完成"

    # ========================================================
    # 生成 MRS
    # ========================================================

    echo
    echo "开始生成 MRS..."

    mihomo convert-ruleset domain text \
        "$OUTPUT_LIST" \
        "$OUTPUT_MRS"

    echo
    echo "MRS 生成完成"

    # ========================================================
    # 判断实际输出是否变化
    # ========================================================

    YAML_CHANGED=0
    LIST_CHANGED=0
    MRS_CHANGED=0

    if [ ! -s "$OLD_YAML" ] || ! cmp -s "$OUTPUT_YAML" "$OLD_YAML"; then
        YAML_CHANGED=1
    fi

    if [ ! -s "$OLD_LIST" ] || ! cmp -s "$OUTPUT_LIST" "$OLD_LIST"; then
        LIST_CHANGED=1
    fi

    if [ ! -s "$OLD_MRS" ] || ! cmp -s "$OUTPUT_MRS" "$OLD_MRS"; then
        MRS_CHANGED=1
    fi

    # ========================================================
    # 如果实际规则没有变化
    #
    # 恢复旧文件，避免 UPDATED 导致无意义修改
    # ========================================================

    if [ "$YAML_CHANGED" -eq 1 ] || \
       [ "$LIST_CHANGED" -eq 1 ] || \
       [ "$MRS_CHANGED" -eq 1 ]; then

        echo "检测到 $NAME 输出内容变化："

        if [ "$YAML_CHANGED" -eq 1 ]; then
            echo "  $OUTPUT_YAML：变化"
        else
            echo "  $OUTPUT_YAML：无变化"
        fi

        if [ "$LIST_CHANGED" -eq 1 ]; then
            echo "  $OUTPUT_LIST：变化"
        else
            echo "  $OUTPUT_LIST：无变化"
        fi

        if [ "$MRS_CHANGED" -eq 1 ]; then
            echo "  $OUTPUT_MRS：变化"
        else
            echo "  $OUTPUT_MRS：无变化"
        fi

    else

        echo "输出内容没有变化"
        echo "恢复旧文件，避免因为 UPDATED 时间产生无意义提交"

        if [ -s "$OLD_YAML" ]; then
            cp "$OLD_YAML" "$OUTPUT_YAML"
        else
            rm -f "$OUTPUT_YAML"
        fi

        if [ -s "$OLD_LIST" ]; then
            cp "$OLD_LIST" "$OUTPUT_LIST"
        else
            rm -f "$OUTPUT_LIST"
        fi

        if [ -s "$OLD_MRS" ]; then
            cp "$OLD_MRS" "$OUTPUT_MRS"
        else
            rm -f "$OUTPUT_MRS"
        fi

    fi

    echo
    echo "$NAME 构建完成"
    echo "  域名数量：$DOMAIN_COUNT"
    echo "  SOURCE SHA256：$SOURCE_SHA256"

    if [ -n "$REMOTE_URL" ]; then
        echo "  REMOTE SHA256：$REMOTE_SHA256"
    fi

    echo
}


# ============================================================
# 构建 Proxy
# ============================================================

build_rule \
    "proxy" \
    "$PROXY_SOURCE" \
    "$OUTPUT_DIR/proxy"


# ============================================================
# 构建 Direct
#
# 本地：
#   sources/manual-direct.list
#
# +
#
# 远程：
#   Loyalsoldier direct.txt
# ============================================================

build_rule \
    "direct" \
    "$DIRECT_SOURCE" \
    "$OUTPUT_DIR/direct" \
    "$DIRECT_REMOTE_URL"


echo "========================================"
echo "全部规则构建完成"
echo "========================================"
echo
