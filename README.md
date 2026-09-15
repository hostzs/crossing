# Crossing

一个用于 **Mihomo / Clash Meta** 的自定义代理域名规则集。

本项目维护一份个人代理域名列表，并通过 GitHub Actions 自动生成多种 Mihomo Rule Provider 格式：

* `proxy.yaml`
* `proxy.list`
* `proxy.mrs`

同时自动检测规则变化和 Mihomo 最新稳定版本，在需要时重新生成规则。

---

## 项目结构

```text
crossing/
├── .github/
│   └── workflows/
│       └── update.yml
│
├── sources/
│   └── manual-proxy.list
│
├── scripts/
│   └── build.sh
│
└── output/
    ├── proxy.yaml
    ├── proxy.list
    ├── proxy.mrs
    └── .mihomo-version
```

### 文件说明

| 文件                             | 说明                      |
| ------------------------------ | ----------------------- |
| `sources/manual-proxy.list`    | 手动维护的原始域名列表             |
| `scripts/build.sh`             | 规则生成脚本                  |
| `output/proxy.yaml`            | YAML 格式规则集              |
| `output/proxy.list`            | Text 格式规则集              |
| `output/proxy.mrs`             | Mihomo MRS 二进制规则集       |
| `output/.mihomo-version`       | 记录生成 MRS 时使用的 Mihomo 版本 |
| `.github/workflows/update.yml` | GitHub Actions 自动更新流程   |

---

# 添加域名

只需要修改：

```text
sources/manual-proxy.list
```

每行填写一个域名。

例如：

```text
# airport
赔钱机场.com
良心云.com
瑶瑶领先.com
fcvipaff.pro
getbn.net
ssrdog.com
idsduf.com
owdzmwy.com
mao2-gw.top
dg4.org
eixeix.com
```

支持：

* 普通域名
* 中文域名（IDN）
* `#` 注释
* 空行
* 重复域名

例如：

```text
# Google
google.com

# 中文域名
赔钱机场.com

# 重复项目
google.com
```

构建时会自动：

1. 删除空行
2. 删除注释
3. 转换 IDN 为 Punycode
4. 转换为小写
5. 去除域名末尾的 `.`
6. 自动去重
7. 自动排序

因此不需要手动写：

```text
DOMAIN-SUFFIX,google.com
```

只需要写：

```text
google.com
```

---

# DOMAIN-SUFFIX 与本项目规则

本项目的源文件使用**纯域名**，而不是：

```text
DOMAIN-SUFFIX,example.com
```

这是因为生成的 `proxy.list` / `proxy.mrs` 使用的是 Mihomo Rule Provider 的 `domain` 类型。

Mihomo 的 Rule Provider 支持 `domain`、`ipcidr` 和 `classical` 等 behavior；MRS 当前支持 `domain` 和 `ipcidr`。

在传统路由规则中：

```text
DOMAIN-SUFFIX,google.com,PROXY
```

可以匹配：

```text
google.com
www.google.com
mail.google.com
```

但不会匹配：

```text
content-google.com
```

Mihomo 官方文档也明确说明了这一行为。

---

# 输出文件

## proxy.yaml

适合查看和调试的 YAML 格式。

文件中包含：

```text
# NAME: proxy
# AUTHOR: edward
# REPO: https://github.com/hostzs/crossing
# UPDATED: ...
# SOURCE-SHA256: ...
# COUNT: ...
```

其中 `SOURCE-SHA256` 用于 GitHub Actions 判断源规则是否发生变化。

---

## proxy.list

纯文本域名规则。

例如：

```text
google.com
example.com
github.com
```

适合 Mihomo `rule-providers` 使用：

```yaml
rule-providers:
  proxy:
    type: http
    behavior: domain
    format: text
    url: "https://raw.githubusercontent.com/hostzs/crossing/main/output/proxy.list"
    interval: 86400
```

Mihomo 官方 Rule Provider 支持 `format: text`，并要求 `behavior` 与实际规则格式对应。

---

## proxy.mrs

Mihomo MRS 格式。

推荐在 Mihomo 中使用这个版本。

示例：

```yaml
rule-providers:
  proxy:
    type: http
    behavior: domain
    format: mrs
    url: "https://raw.githubusercontent.com/hostzs/crossing/main/output/proxy.mrs"
    interval: 86400
```

然后在 `rules` 中：

```yaml
rules:
  - RULE-SET,proxy,PROXY
```

Mihomo 官方配置示例同样使用 `behavior: domain` + `format: mrs`，并通过 `RULE-SET` 引用 Rule Provider。

---

# 推荐配置

如果使用 Mihomo，推荐直接使用 MRS：

```yaml
rule-providers:

  proxy:
    type: http
    behavior: domain
    format: mrs
    url: "https://raw.githubusercontent.com/hostzs/crossing/main/output/proxy.mrs"
    interval: 86400

rules:

  - RULE-SET,proxy,PROXY

  # 其他规则
  - MATCH,PROXY
```

其中：

```text
proxy
```

是 Rule Provider 的名称。

```text
PROXY
```

是你的代理策略组名称，需要根据自己的配置修改。

Mihomo 的 `RULE-SET` 用于引用 Rule Provider，因此需要先定义对应的 `rule-providers`。

---

# OpenClash

如果 OpenClash 使用 Mihomo 内核，同样可以通过 Rule Provider 使用本项目生成的规则。

推荐：

```text
output/proxy.mrs
```

对应：

```yaml
rule-providers:
  proxy:
    type: http
    behavior: domain
    format: mrs
    url: "https://raw.githubusercontent.com/hostzs/crossing/main/output/proxy.mrs"
    interval: 86400
```

然后：

```yaml
rules:
  - RULE-SET,proxy,PROXY
```

具体配置方式取决于 OpenClash 当前使用的配置文件和覆写方式。

---

# GitHub Actions 自动更新

本项目使用 GitHub Actions 自动维护规则。

工作流：

```text
每天检查
   │
   ├── manual-proxy.list 是否变化？
   │
   └── Mihomo 是否发布新稳定版本？
           │
           ↓
        需要更新？
        /       \
      否         是
      │          │
      ↓          ↓
   跳过构建    安装 Mihomo
                 │
                 ↓
              build.sh
                 │
        ┌────────┼────────┐
        ↓        ↓        ↓
      YAML      LIST      MRS
                 │
                 ↓
              Git Commit
```

当前定时任务：

```yaml
schedule:
  - cron: "0 0 * * *"
```

GitHub Actions 使用 UTC 时间，因此相当于：

```text
UTC 00:00
北京时间 08:00
```

---

# 更新判断

项目使用两个条件判断是否需要重新生成：

### 1. 源规则 SHA256

GitHub Actions 会计算：

```text
sources/manual-proxy.list
```

的 SHA256。

如果发生变化：

```text
SHA256 改变
    ↓
重新生成
```

### 2. Mihomo 版本

工作流会检查 Mihomo 最新稳定版本。

如果：

```text
旧版本 ≠ 最新版本
```

则重新生成 MRS。

这样即使源规则没有变化，Mihomo 更新后也可以重新生成 MRS。

---

# 手动更新

可以在 GitHub：

```text
Actions
→ Update Proxy Rules
→ Run workflow
```

手动执行。

手动运行会强制执行构建流程。

但是，如果：

```text
规则没有变化
+
Mihomo 没有变化
```

即使 `UPDATED` 时间发生变化，也不会产生无意义的 Git 提交。

---

# Mihomo MRS

MRS 是 Mihomo 支持的规则集格式。

本项目使用：

```bash
mihomo convert-ruleset domain text \
  output/proxy.list \
  output/proxy.mrs
```

生成：

```text
output/proxy.mrs
```

Mihomo 官方文档提供了 `convert-ruleset` 用于将规则集转换为 MRS，并说明 MRS 当前支持 `domain` / `ipcidr` behavior。

---

# 数据处理流程

原始数据：

```text
sources/manual-proxy.list
```

经过：

```text
读取
 ↓
过滤注释
 ↓
过滤空行
 ↓
IDN → Punycode
 ↓
小写化
 ↓
去除末尾 .
 ↓
去重
 ↓
排序
 ↓
生成 YAML
 ↓
生成 Text
 ↓
Mihomo 转换为 MRS
```

最终得到：

```text
output/proxy.yaml
output/proxy.list
output/proxy.mrs
```

---

# 当前规则数量

规则数量会根据：

```text
sources/manual-proxy.list
```

自动统计。

可以在 `proxy.yaml` 的头部看到：

```text
# COUNT: ...
```

---

# 项目地址

GitHub：

https://github.com/hostzs/crossing

---

# License

本项目主要用于个人规则整理与 Mihomo / Clash Meta 配置使用。

规则内容的版权及使用权归其原始来源或相应权利人所有。
