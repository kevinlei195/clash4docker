#!/bin/bash
# 用例:KERNEL 切换软链 + 缺位时报错
#
# 需要一个已构建的本地镜像作为参数(由 CI smoke job 提供)。
# 默认调用方式: bash tests/test_kernel.sh glash-ci:amd64
#
# 该脚本不依赖 docker-compose,可与 test_container.sh 一起并行验证。
set -euo pipefail

if [ "$#" -lt 1 ]; then
    echo "usage: $0 <image>" >&2
    exit 2
fi

image="$1"

cleanup() {
    docker rm -f "${cid:-}" >/dev/null 2>&1 || true
}
trap cleanup EXIT

# 1. 默认 KERNEL 应该是 standard
cid="$(docker run -d --rm "${image}" sleep 30)" || {
    echo "FAIL: cannot start container from ${image}" >&2
    exit 1
}
sleep 2
target="$(docker exec "${cid}" readlink -f /app/mihomo || true)"
case "${target}" in
    */opt/mihomo/standard/mihomo)
        echo "OK default KERNEL resolves to standard"
        ;;
    *)
        echo "FAIL default target: '${target}'" >&2
        docker logs "${cid}" >&2 || true
        exit 1
        ;;
esac
docker rm -f "${cid}" >/dev/null 2>&1

# 2. KERNEL=smart 启动后软链应切换
cid="$(docker run -d --rm -e KERNEL=smart "${image}" sleep 30)"
sleep 2
target="$(docker exec "${cid}" readlink -f /app/mihomo || true)"
case "${target}" in
    */opt/mihomo/smart/mihomo)
        echo "OK KERNEL=smart resolves to smart"
        ;;
    *)
        echo "FAIL KERNEL=smart target: '${target}'" >&2
        docker logs "${cid}" >&2 || true
        exit 1
        ;;
esac
docker rm -f "${cid}" >/dev/null 2>&1

# 3. 同一容器中切 KERNEL=standard 必须重启容器才生效(因此本次启动期仍沿用镜像的 /opt/mihomo 布局)
# 这里只是确认两种 KERNEL 在不同容器中都生效,切换语义由文档说明,不在此脚本里验证运行时热切换

echo "OK test_kernel.sh"
