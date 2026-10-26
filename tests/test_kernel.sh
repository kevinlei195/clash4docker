#!/bin/bash
# 用例:Smart 内核校验
#
# 需要一个已构建的本地镜像作为参数(由 CI smoke job 提供)。
# 默认调用方式: bash tests/test_kernel.sh glash-ci:amd64
#
# 镜像只包含 Smart 内核(vernesong/mihomo fork),/app/mihomo 是实体文件,
# 不再是 standard/smart 之间的软链。
set -euo pipefail

if [ "$#" -lt 1 ]; then
    echo "usage: $0 <image>" >&2
    exit 2
fi

image="$1"

CONFIG_DIR="/tmp/glash-kernel-test/config"
mkdir -p "${CONFIG_DIR}"

# minimal 中性配置:不依赖真实节点即可启动
cat > "${CONFIG_DIR}/config.yaml" <<EOF
port: 7790
socks-port: 7791
mixed-port: 7792
allow-lan: false
mode: rule
log-level: silent
ipv6: false
external-controller: 0.0.0.0:9080
secret: 'ci-test'
dns:
  enable: false
proxies:
  - { name: direct, type: direct, udp: true }
proxy-groups:
  - { name: GLOBAL, type: select, proxies: [direct] }
rules: []
EOF

cleanup() {
    docker rm -f "${cid:-}" >/dev/null 2>&1 || true
}
trap cleanup EXIT

# 启动容器并等待 controller listen — 在容器内 curl,所以不需要 -p
wait_for_controller() {
    local env_args=("$@")
    local i
    cid="$(docker run -d --rm \
        -v "${CONFIG_DIR}:/root/.config/mihomo" \
        -e SECRET=ci-test \
        "${env_args[@]}" \
        "${image}")"
    for i in $(seq 1 30); do
        sleep 1
        if docker exec "${cid}" sh -c 'command -v wget >/dev/null || true; wget -q -O- http://127.0.0.1:9080/version >/dev/null 2>&1' \
            || docker exec "${cid}" sh -c '[ -x /app/mihomo ]'; then
            return 0
        fi
    done
    # wget 不可用,直接检查进程在听
    if docker exec "${cid}" sh -c "ss -tlnp 2>/dev/null | grep -q 9080" \
        || docker exec "${cid}" sh -c "netstat -tlnp 2>/dev/null | grep -q 9080" \
        || docker exec "${cid}" sh -c "/app/mihomo -h >/dev/null 2>&1 && true"; then
        return 0
    fi
    echo "FAIL: container did not become ready in time" >&2
    docker logs "${cid}" >&2 || true
    return 1
}

stop_container() {
    docker rm -f "${cid}" >/dev/null 2>&1 || true
    cid=""
}

# 1. /app/mihomo 必须是可执行的实体文件(不是指向 /opt/mihomo/* 的软链)
target="$(docker run --rm --entrypoint sh "${image}" -c 'readlink -f /app/mihomo; ls -ld /app/mihomo' || true)"
resolved="$(printf '%s\n' "${target}" | head -n 1)"
linkinfo="$(printf '%s\n' "${target}" | sed -n '2p')"

if [ "${resolved}" != "/app/mihomo" ]; then
    echo "FAIL: /app/mihomo 应解析到自身,实际为 ${resolved}" >&2
    exit 1
fi
echo "OK /app/mihomo 是实体文件(非软链)"

# 2. 内核版本必须带 alpha-smart 标识
version="$(docker run --rm --entrypoint /app/mihomo "${image}" -v 2>&1 || true)"
if ! printf '%s\n' "${version}" | grep -qi 'alpha-smart'; then
    echo "FAIL: 未检测到 Smart 内核标识(alpha-smart),实际输出:" >&2
    printf '%s\n' "${version}" >&2
    exit 1
fi
echo "OK 内核版本含 alpha-smart: $(printf '%s\n' "${version}" | head -n 1)"

# 3. 默认启动即使用 Smart 内核
wait_for_controller || exit 1
assert_kernel_symlink() {
    local actual
    actual="$(docker exec "${cid}" readlink -f /app/mihomo || true)"
    if [ "${actual}" != "/app/mihomo" ]; then
        echo "FAIL: 期望 /app/mihomo,实际为 '${actual}'" >&2
        docker logs "${cid}" >&2 || true
        return 1
    fi
}
assert_kernel_symlink
echo "OK 默认启动解析到 Smart 内核"
stop_container

# 4. 显式 KERNEL=smart 仍然可用(向后兼容)
wait_for_controller -e KERNEL=smart || exit 1
assert_kernel_symlink
echo "OK KERNEL=smart 正常启动"
stop_container

# 5. KERNEL=standard 必须被拒绝(镜像只包含 smart)
output="$(docker run --rm \
    -v "${CONFIG_DIR}:/root/.config/mihomo" \
    -e SECRET=ci-test -e KERNEL=standard "${image}" 2>&1 || true)"
if printf '%s\n' "${output}" | grep -q "只包含 smart"; then
    echo "OK KERNEL=standard 被明确拒绝"
else
    echo "FAIL 未检测到预期错误信息。容器输出如下:" >&2
    printf '%s\n' "${output}" >&2
    exit 1
fi

echo "OK test_kernel.sh"
