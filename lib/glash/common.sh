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
# 解析 KERNEL=standard|smart(默认 standard) 并重写 MIHOMO_BIN 指向的软链
# 当镜像同时打包两个内核时(/opt/mihomo/standard 与 /opt/mihomo/smart),通过软链切换;
# 当镜像只打包 standard 时,链接到 /app/mihomo 仍是普通文件,本函数退化为 no-op。
resolve_mihomo_binary() {
    local flavor="${KERNEL:-standard}"
    case "${flavor}" in
        standard|smart)
            if [ ! -x "/opt/mihomo/${flavor}/mihomo" ]; then
                # 内核缺位(例如只构建了 standard 的镜像),让 MIHOMO_BIN 仍指向 /app/mihomo,
                # 这样老的标准镜像构建方式依然能跑。KERNEL=smart 时返回错误。
                if [ "${flavor}" = "smart" ]; then
                    log_error "❌ 当前镜像未包含 Smart 内核。请重新构建镜像时加入 FLAVORS=smart 或 FLAVORS=both。"
                    return 1
                fi
                log_info "🔧 当前内核: standard (使用 /app/mihomo)"
                return 0
            fi
            ln -sfn "/opt/mihomo/${flavor}/mihomo" "${MIHOMO_BIN}"
            log_info "🔧 当前内核: ${flavor} (${MIHOMO_BIN} → /opt/mihomo/${flavor}/mihomo)"
            return 0
            ;;
        *)
            log_error "❌ KERNEL='${flavor}' 不支持(应为 standard|smart)"
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
