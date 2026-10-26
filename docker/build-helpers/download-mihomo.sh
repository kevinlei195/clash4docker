#!/bin/sh
# 下载 Smart 版 mihomo 内核二进制
# 用法: download-mihomo.sh <arch> <repo> <tag> <short_sha> <out_dir>
#
# 参数:
#   arch       : amd64 | arm64 | arm
#   repo       : vernesong/mihomo
#   tag        : Prerelease-Alpha
#   short_sha  : 可选,7 位 hex SHA。指定后直接拼接资产名,跳过 GitHub API 查询;
#                留空则自动从 release assets 中解析最新的 alpha-smart-<sha> 资产。
#   out_dir    : 输出目录(必须预先创建)
#
# 说明:
#   上游 vernesong/mihomo 的 Prerelease-Alpha 是滚动 tag,每次上游提交都会
#   覆盖同一 tag 下的资产文件名(内嵌的 SHA 会变)。因此默认不硬编码 SHA,
#   而是调用 GitHub API 列出该 release 的实际资产名再下载,避免资产改名后
#   构建静默 404。
set -eu

arch="$1"
repo="$2"
tag="$3"
short_sha="$4"
out_dir="$5"

case "${arch}" in
    amd64) a="amd64" ;;
    arm64) a="arm64" ;;
    arm)   a="armv7" ;;
    *) echo "[download-mihomo] unsupported arch: ${arch}" >&2; exit 1 ;;
esac

mkdir -p "${out_dir}"

api_url="https://api.github.com/repos/${repo}/releases/tags/${tag}"

# 列出 release 资产名(每行一个,只保留 .gz 内核包)
fetch_asset_names() {
    curl -fsSL \
        -H "Accept: application/vnd.github+json" \
        -H "User-Agent: glash-docker-build" \
        "${api_url}" \
        | tr ',' '\n' \
        | sed -n 's/.*"name"[[:space:]]*:[[:space:]]*"\(mihomo-linux-[^"]*\.gz\)".*/\1/p'
}

# 从资产列表中挑选目标文件。
#   - amd64 优先 compatible 变体(glibc 兼容,与上游标准内核选型一致)
#   - 其余架构取普通变体
#   - 允许存在 go1xx / v1 / v2 等变体后缀,统一归一化为基础变体
pick_asset() {
    # 精确候选优先级
    for candidate in \
        "mihomo-linux-${a}-compatible-alpha-smart-" \
        "mihomo-linux-${a}-alpha-smart-"
    do
        match=$(printf '%s\n' "${ASSET_NAMES}" \
            | grep "^${candidate}" \
            | grep -v -- '-go[0-9]' \
            | grep -v -- '-v[0-9]-' \
            | head -n 1 || true)
        if [ -n "${match}" ]; then
            printf '%s\n' "${match}"
            return 0
        fi
    done
    return 1
}

if [ -n "${short_sha}" ]; then
    # 显式指定 SHA:直接拼接资产名(离线/限流场景)
    if [ "${a}" = "amd64" ]; then
        file="mihomo-linux-${a}-compatible-alpha-smart-${short_sha}.gz"
    else
        file="mihomo-linux-${a}-alpha-smart-${short_sha}.gz"
    fi
    echo "[download-mihomo] 使用指定的 SHA: ${short_sha}"
else
    echo "[download-mihomo] 查询 ${repo}@${tag} 的最新资产..."
    ASSET_NAMES="$(fetch_asset_names)"
    if [ -z "${ASSET_NAMES}" ]; then
        echo "[download-mihomo] 未能从 GitHub API 获取资产列表。" >&2
        echo "[download-mihomo] 可通过 --build-arg MIHOMO_SHORT_SHA_SMART=<sha> 显式指定。" >&2
        exit 1
    fi
    file="$(pick_asset || true)"
    if [ -z "${file}" ]; then
        echo "[download-mihomo] 在 release 资产中找不到匹配 ${a} 的 alpha-smart 内核。" >&2
        echo "[download-mihomo] 可用资产:" >&2
        printf '%s\n' "${ASSET_NAMES}" | grep 'alpha-smart' | sed 's/^/  /' >&2 || true
        exit 1
    fi
    echo "[download-mihomo] 解析到资产: ${file}"
fi

url="https://github.com/${repo}/releases/download/${tag}/${file}"

echo "[download-mihomo] downloading smart kernel: ${url}"
if ! curl -fsSL "${url}" -o "${out_dir}/mihomo.gz"; then
    echo "[download-mihomo] 下载失败: ${url}" >&2
    if [ -n "${short_sha}" ]; then
        echo "[download-mihomo] 请确认 SHA ${short_sha} 在 release ${tag} 中存在。" >&2
    fi
    exit 1
fi
gunzip "${out_dir}/mihomo.gz"
chmod +x "${out_dir}/mihomo"
echo "[download-mihomo] OK: ${out_dir}/mihomo"
