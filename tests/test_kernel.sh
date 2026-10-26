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

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# 测试目录必须建在仓库内:CI runner 以嵌套容器(dind)方式运行,
# daemon 与 job 容器只共享仓库工作区,/tmp 并不共享 ——
# 用 /tmp 会导致 bind mount 到 daemon 侧的空目录,容器内看不到 config.yaml。
TEST_DIR="$(mktemp -d "${REPO_DIR}/.clash4docker-kernel-ci.XXXXXX")"
CONFIG_DIR="${TEST_DIR}/config"
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

SECRET_VALUE="ci-test"
cid=""

cleanup() {
    if [ -n "${cid}" ]; then
        docker rm -f "${cid}" >/dev/null 2>&1 || true
    fi
    rm -rf "${TEST_DIR}"
}
trap cleanup EXIT

# 启动容器并等待 controller 就绪。
#
# 注意:这里刻意不用 --rm —— 容器若启动失败,需要保留它才能读取日志定位问题。
# controller 需要 Authorization 头才能响应 /version,否则一律 401。
wait_for_controller() {
    local env_args=("$@")
    local i
    cid="$(docker run -d \
        -v "${CONFIG_DIR}:/root/.config/mihomo" \
        -e "SECRET=${SECRET_VALUE}" \
        "${env_args[@]}" \
        "${image}")"

    for i in $(seq 1 30); do
        # 容器已经退出 -> 立刻失败,不要继续空等
        if ! docker inspect --format '{{.State.Running}}' "${cid}" 2>/dev/null | grep -q true; then
            echo "FAIL: 容器启动后立即退出(exit=$(docker inspect --format '{{.State.ExitCode}}' "${cid}" 2>/dev/null || echo '?'))" >&2
            dump_container_logs
            return 1
        fi

        # controller 带 Authorization 头才返回 200
        if docker exec "${cid}" wget -q -O- \
            --header="Authorization: Bearer ${SECRET_VALUE}" \
            http://127.0.0.1:9080/version 2>/dev/null | grep -q '"version"'; then
            return 0
        fi
        sleep 1
    done

    echo "FAIL: controller 在 30 秒内未就绪" >&2
    dump_container_logs
    return 1
}

dump_container_logs() {
    echo "----- container logs -----" >&2
    docker logs "${cid}" 2>&1 | tail -40 >&2 || true
    echo "-------------------------" >&2
}

stop_container() {
    if [ -n "${cid}" ]; then
        docker rm -f "${cid}" >/dev/null 2>&1 || true
        cid=""
    fi
}

# 1. /app/mihomo 必须是可执行的实体文件(不是指向 /opt/mihomo/* 的软链)
target="$(docker run --rm --entrypoint sh "${image}" -c 'readlink -f /app/mihomo; ls -ld /app/mihomo' || true)"
resolved="$(printf '%s\n' "${target}" | head -n 1)"

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

# 3. 默认启动即使用 Smart 内核 —— 用 controller 回报的版本确认
wait_for_controller || exit 1
reported="$(docker exec "${cid}" wget -q -O- \
    --header="Authorization: Bearer ${SECRET_VALUE}" \
    http://127.0.0.1:9080/version 2>/dev/null || true)"
if ! printf '%s\n' "${reported}" | grep -qi 'alpha-smart'; then
    echo "FAIL: controller 回报的版本不是 Smart:${reported}" >&2
    dump_container_logs
    exit 1
fi
echo "OK 默认启动使用 Smart 内核(controller 回报 ${reported})"
stop_container

# 4. 显式 KERNEL=smart 仍然可用(向后兼容)
wait_for_controller -e KERNEL=smart || exit 1
echo "OK KERNEL=smart 正常启动"
stop_container

# 5. KERNEL=standard 必须被拒绝(镜像只包含 smart)
output="$(docker run --rm \
    -v "${CONFIG_DIR}:/root/.config/mihomo" \
    -e "SECRET=${SECRET_VALUE}" -e KERNEL=standard "${image}" 2>&1 || true)"
if printf '%s\n' "${output}" | grep -q "只包含 smart"; then
    echo "OK KERNEL=standard 被明确拒绝"
else
    echo "FAIL 未检测到预期错误信息。容器输出如下:" >&2
    printf '%s\n' "${output}" >&2
    exit 1
fi

echo "OK test_kernel.sh"
