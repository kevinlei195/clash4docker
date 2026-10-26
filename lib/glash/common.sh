#!/bin/bash

CONFIG_DIR="${CONFIG_DIR:-${MIHOMO_CONFIG_DIR:-/root/.config/mihomo}}"
CONFIG_FILE="${CONFIG_FILE:-${CONFIG_DIR}/config.yaml}"
HOOK_DIR="${HOOK_DIR:-/app/hooks.d}"
UI_DIR="${UI_DIR:-/app/ui}"
GEODATA_DIR="${GEODATA_DIR:-/app/geodata}"
CRON_FILE="${CRON_FILE:-/etc/crontabs/root}"
UPDATE_SCRIPT='/app/update_sub.sh'
PID_FILE="${PID_FILE:-/var/run/mihomo.pid}"
UPDATE_LOCK_FILE="${UPDATE_LOCK_FILE:-/var/run/glash-subscription-update.lock}"
MIHOMO_BIN="${MIHOMO_BIN:-/app/mihomo}"
# 镜像只包含 Smart 内核(vernesong/mihomo fork)。
# 历史上镜像同时打包 standard 与 smart,靠 KERNEL 环境变量切换软链;
# 现在内核唯一,本函数只做 KERNEL 取值校验,不再切换任何链接。
resolve_mihomo_binary() {
    local flavor="${KERNEL:-smart}"
    case "${flavor}" in
        smart)
            log_info "🔧 当前内核: smart (${MIHOMO_BIN})"
            return 0
            ;;
        *)
            log_error "❌ KERNEL='${flavor}' 不支持(当前镜像只包含 smart 内核)"
            return 1
            ;;
    esac
}

# 校验最终 MIHOMO_BIN 可执行
verify_mihomo_binary() {
    local target
    target="$(readlink -f "${MIHOMO_BIN}" 2>/dev/null || true)"
    if [ -z "${target}" ] || [ ! -x "${target}" ]; then
        log_error "❌ Mihomo 二进制不可执行: ${MIHOMO_BIN}"
        return 1
    fi
}

RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
CYAN="\033[36m"
RESET="\033[0m"

log_info() {
    printf '%b[INFO]%b %b%s%b %s\n' "${GREEN}" "${RESET}" "${CYAN}" "$(date '+%Y-%m-%d %H:%M:%S')" "${RESET}" "$*"
}

log_warn() {
    printf '%b[WARN]%b %b%s%b %s\n' "${YELLOW}" "${RESET}" "${CYAN}" "$(date '+%Y-%m-%d %H:%M:%S')" "${RESET}" "$*" >&2
}

log_error() {
    printf '%b[ERROR]%b %b%s%b %s\n' "${RED}" "${RESET}" "${CYAN}" "$(date '+%Y-%m-%d %H:%M:%S')" "${RESET}" "$*" >&2
}

make_sibling_temp() {
    local target="$1"
    local label="${2:-tmp}"
    mktemp "${target}.${label}.XXXXXX"
}

replace_file() {
    local source_file="$1"
    local target_file="$2"

    if ! cp -f "${source_file}" "${target_file}"; then
        log_error "❌ 文件写入失败: ${target_file}"
        return 1
    fi
}

yaml_quote() {
    local value="$1"
    if [[ "${value}" == *$'\n'* || "${value}" == *$'\r'* ]]; then
        return 1
    fi
    value=${value//\'/\'\'}
    printf "'%s'" "${value}"
}
