#!/bin/sh
# 下载 Dashboard 与 GeoIP / GeoSite / Country 数据
# 用法: download-assets.sh <ui> <metacubexd_version> <zashboard_version>
#
# 参数:
#   ui                   : metacubexd | zashboard
#   metacubexd_version   : 仅 metacubexd 模式使用,如 v1.273.1
#   zashboard_version    : 仅 zashboard 模式使用,如 v3.29.1
set -eu

ui="$1"
metacubexd_version="$2"
zashboard_version="$3"

mkdir -p ui

case "${ui}" in
    metacubexd)
        echo "[download-assets] metacubexd ${metacubexd_version}"
        curl -fsSL "https://github.com/MetaCubeX/metacubexd/releases/download/${metacubexd_version}/compressed-dist.tgz" \
            -o dashboard.tgz
        tar -xzf dashboard.tgz -C ui
        rm -f dashboard.tgz
        ;;
    zashboard)
        echo "[download-assets] zashboard ${zashboard_version}"
        curl -fsSL "https://github.com/Zephyruso/zashboard/releases/download/${zashboard_version}/dist.zip" \
            -o dashboard.zip
        # zashboard 的 dist.zip 解压后多一层 dist/ 目录;展平到 ui/,让 mihomo
        # 的 external-ui: /app/ui 直接指向 SPA 根。
        unzip -q dashboard.zip -d ui/_extract
        # 复制 dist/ 下的可见文件与隐藏文件(.well-known, .htaccess 等 SPA 可能用到)
        cp -r ui/_extract/dist/. ui/
        rm -rf ui/_extract dashboard.zip
        ;;
    *)
        echo "[download-assets] unknown UI='${ui}'" >&2
        exit 1
        ;;
esac

mkdir -p geodata
echo "[download-assets] geoip"
curl -fsSL "https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/geoip.metadb" \
    -o geodata/geoip.metadb
echo "[download-assets] geosite"
curl -fsSL "https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/geosite.dat" \
    -o geodata/geosite.dat
echo "[download-assets] country"
curl -fsSL "https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/country.mmdb" \
    -o geodata/country.mmdb

echo "[download-assets] OK"
