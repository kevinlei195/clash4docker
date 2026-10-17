#!/bin/bash
# 用例:在不含 Smart 内核的镜像上运行 KERNEL=smart,启动应失败并给出清晰提示。
#
# 这是反向验证 —— 标准镜像(FLAVORS=standard)被尝试切到 Smart 内核时,
# resolve_mihomo_binary 必须报错,容器不会后台长跑。
#
# 用法: bash tests/test_kernel_absence.sh <standard-only-image>
set -euo pipefail

if [ "$#" -lt 1 ]; then
    echo "usage: $0 <standard-only-image>" >&2
    exit 2
fi

image="$1"

CONFIG_DIR="/tmp/glash-kernel-test/config"  # 复用 test_kernel.sh 准备的 minimal 目录
[ -d "${CONFIG_DIR}" ] || {
    echo "FAIL: 缺少 ${CONFIG_DIR};请先跑 test_kernel.sh" >&2
    exit 2
}

# start.sh 在 resolve 失败时 exit 1;容器立即退出
output="$(docker run --rm \
    -v "${CONFIG_DIR}:/root/.config/mihomo" \
    -e SECRET=ci-test -e KERNEL=smart "${image}" 2>&1 || true)"

if echo "${output}" | grep -q "Smart 内核"; then
    echo "OK 标准镜像在 KERNEL=smart 下报错清晰"
    exit 0
fi

echo "FAIL 未检测到预期错误信息。容器输出如下:" >&2
echo "${output}" >&2
exit 1
