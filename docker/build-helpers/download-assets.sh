#!/bin/sh
# 下载 MetacubexD Dashboard 与 GeoIP / GeoSite / Country 数据
# 用法: download-assets.sh <metacubexd_version>
set -eu

metacubexd_version="$1"

mkdir -p ui
echo "[download-assets] metacubexd ${metacubexd_version}"
curl -fsSL "https://github.com/MetaCubeX/metacubexd/releases/download/${metacubexd_version}/compressed-dist.tgz" \
    -o dashboard.tgz
tar -xzf dashboard.tgz -C ui
rm -f dashboard.tgz

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
