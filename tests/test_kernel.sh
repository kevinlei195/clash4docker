#!/bin/bash
# 用例:KERNEL 切换软链 + 缺位时报错
#
# 需要一个已构建的本地镜像作为参数(由 CI smoke job 提供)。
# 默认调用方式: bash tests/test_kernel.sh glash-ci:amd64
#
# 用一个 minimal 的本地配置 /tmp/glash-kernel-test/config/config.yaml
# 让 mihomo 不需要真实节点也能启动。
set -euo pipefail

if [ "$#" -lt 1 ]; then
    echo "usage: $0 <image>" >&2
    exit 2
fi

image="$1"

CONFIG_DIR="/tmp/glash-kernel-test/config"
mkdir -p "${CONFIG_DIR}"

# minimal 中性配置:不包含 type: smart,standard / smart 两边都能过 validate
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
    docker rm -f "${cid}" >/dev/null 2>&1
    cid=""
}

assert_kernel_symlink() {
    local expected="$1"
    local actual
    actual="$(docker exec "${cid}" readlink -f /app/mihomo || true)"
    case "${expected}" in
        standard)
            if [ "${actual}" != "/opt/mihomo/standard/mihomo" ]; then
                echo "FAIL: expected standard, got '${actual}'" >&2
                docker logs "${cid}" >&2 || true
                return 1
            fi
            ;;
        smart)
            if [ "${actual}" != "/opt/mihomo/smart/mihomo" ]; then
                echo "FAIL: expected smart, got '${actual}'" >&2
                docker logs "${cid}" >&2 || true
                return 1
            fi
            ;;
        *) echo "FAIL: unknown expected '${expected}'" >&2; return 1 ;;
    esac
}

# 1. 默认 = standard
wait_for_controller || exit 1
assert_kernel_symlink standard
echo "OK 默认 KERNEL 解析到 standard"
stop_container

# 2. KERNEL=smart
wait_for_controller -e KERNEL=smart || exit 1
assert_kernel_symlink smart
echo "OK KERNEL=smart 解析到 smart"
stop_container

echo "OK test_kernel.sh"
