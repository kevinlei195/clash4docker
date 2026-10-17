#!/bin/sh
# 下载 mihomo 内核二进制
# 用法: download-mihomo.sh <flavor> <arch> <version> <repo> <tag> <short_sha> <out_dir>
#
# 参数:
#   flavor     : standard | smart
#   arch       : amd64 | arm64 | arm
#   version    : 仅 standard 使用,如 v1.19.31
#   repo       : 仅 smart 使用,如 vernesong/mihomo
#   tag        : 仅 smart 使用,如 Prerelease-Alpha
#   short_sha  : 仅 smart 使用,如 83e67d0
#   out_dir    : 输出目录(必须预先创建)
set -eu

flavor="$1"
arch="$2"
version="$3"
repo="$4"
tag="$5"
short_sha="$6"
out_dir="$7"

case "${arch}" in
    amd64) a="amd64-compatible" ;;
    arm64) a="arm64" ;;
    arm)   a="armv7" ;;
    *) echo "[download-mihomo] unsupported arch: ${arch}" >&2; exit 1 ;;
esac

mkdir -p "${out_dir}"

case "${flavor}" in
    standard)
        url="https://github.com/MetaCubeX/mihomo/releases/download/${version}/mihomo-linux-${a}-${version}.gz"
        ;;
    smart)
        url="https://github.com/${repo}/releases/download/${tag}/mihomo-linux-${a}-alpha-smart-${short_sha}.gz"
        ;;
    *) echo "[download-mihomo] unknown flavor: ${flavor}" >&2; exit 1 ;;
esac

echo "[download-mihomo] downloading ${flavor} kernel: ${url}"
curl -fsSL "${url}" -o "${out_dir}/mihomo.gz"
gunzip "${out_dir}/mihomo.gz"
chmod +x "${out_dir}/mihomo"
echo "[download-mihomo] OK: ${out_dir}/mihomo"
