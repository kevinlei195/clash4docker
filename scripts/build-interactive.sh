#!/usr/bin/env bash
# glash 交互式镜像构建脚本
#
# 通过问答引导用户选择 build-arg,最后生成并执行 docker buildx build。
# 零依赖,纯 Bash。
#
# 用法:
#   ./scripts/build-interactive.sh                    # 简单模式(默认)
#   ./scripts/build-interactive.sh --advanced         # 高级模式,展开全部 7 个 build-arg
#   ./scripts/build-interactive.sh --dry-run          # 干跑,只打命令不执行
#   ./scripts/build-interactive.sh --flavors smart    # 命令行覆盖(可与交互混用)
#   ./scripts/build-interactive.sh --ui zashboard --tag my:zas
#   ./scripts/build-interactive.sh --push --user gangz1o
#   ./scripts/build-interactive.sh --platform linux/arm64
#   ./scripts/build-interactive.sh --builder my-builder
#   ./scripts/build-interactive.sh --help

set -euo pipefail

# ───── 静态元数据(与 Dockerfile 中 ARG 默认值同步) ─────
readonly DEFAULT_FLAVORS="both"
readonly DEFAULT_UI="metacubexd"
readonly DEFAULT_MIHOMO_VERSION="v1.19.31"
readonly DEFAULT_MIHOMO_REPO_SMART="vernesong/mihomo"
readonly DEFAULT_MIHOMO_TAG_SMART="Prerelease-Alpha"
readonly DEFAULT_MIHOMO_SHORT_SHA_SMART="83e67d0"
readonly DEFAULT_METACUBEXD_VERSION="v1.273.1"
readonly DEFAULT_ZASHBOARD_VERSION="v3.29.1"
readonly DEFAULT_BUILDER="glash-builder"
readonly DEFAULT_PLATFORM="linux/amd64"
readonly DEFAULT_TAG_PREFIX="glash-dev"
readonly SCRIPT_NAME="build-interactive.sh"

# 允许的 FLAVORS / UI 取值
readonly VALID_FLAVORS=("both" "standard" "smart")
readonly VALID_UI=("metacubexd" "zashboard")

# ───── 颜色与日志 ─────
if [ -t 1 ]; then
    C_RED=$'\033[31m'
    C_GREEN=$'\033[32m'
    C_YELLOW=$'\033[33m'
    C_CYAN=$'\033[36m'
    C_BOLD=$'\033[1m'
    C_RESET=$'\033[0m'
else
    C_RED=""; C_GREEN=""; C_YELLOW=""; C_CYAN=""; C_BOLD=""; C_RESET=""
fi

log_info()  { printf '%b[INFO]%b  %s\n' "${C_GREEN}" "${C_RESET}" "$*"; }
log_warn()  { printf '%b[WARN]%b  %s\n' "${C_YELLOW}" "${C_RESET}" "$*" >&2; }
log_error() { printf '%b[ERROR]%b %s\n' "${C_RED}" "${C_RESET}" "$*" >&2; }
log_step()  { printf '%b[STEP]%b  %s\n' "${C_CYAN}" "${C_RESET}" "$*"; }
die()       { log_error "$*"; exit 1; }

# ───── 工具函数 ─────
have_tty() { [ -t 0 ] && [ -t 1 ]; }

# 在数组里查找值,返回 0 表示存在
in_array() {
    local needle="$1"; shift
    local item
    for item in "$@"; do
        [ "${item}" = "${needle}" ] && return 0
    done
    return 1
}

# 校验语义版本号 v1.2.3 / v1.2.3-rc1 等
is_semver() {
    [[ "$1" =~ ^v[0-9]+\.[0-9]+\.[0-9]+([-.][0-9A-Za-z.-]+)?$ ]]
}

# 校验 7 位 hex SHA
is_short_sha() {
    [[ "$1" =~ ^[0-9a-f]{7}$ ]]
}

# 校验平台字符串(单/多平台)
is_platform() {
    local p="$1"
    [[ "${p}" =~ ^linux/(amd64|arm64|arm/v7)(,linux/(amd64|arm64|arm/v7))*$ ]]
}

# 校验 tag 字符(允许 : / . _ -)
is_tag() {
    [[ "$1" =~ ^[A-Za-z0-9_.:/-]+$ ]]
}

# ───── 输入函数 ─────
# ask_text "prompt" "default" -> stdout
ask_text() {
    local prompt="$1" default="${2:-}"
    local ans
    if have_tty; then
        if [ -n "${default}" ]; then
            read -rp "${prompt} [${default}]: " ans
        else
            read -rp "${prompt}: " ans
        fi
    else
        # 非 TTY 模式必须给默认
        [ -n "${default}" ] || die "非交互模式下 ${prompt} 缺少默认值"
        printf '%s\n' "${default}"
        return
    fi
    ans="${ans:-${default}}"
    printf '%s\n' "${ans}"
}

# ask_choice "prompt" "default_index" "opt1" "opt2" ... -> stdout (选择值)
ask_choice() {
    local prompt="$1" default_idx="${2:-1}"; shift 2
    local options=("$@")
    local i=1
    printf '%s\n' "${prompt}" >&2
    for opt in "${options[@]}"; do
        printf '  %d) %s\n' "$i" "${opt}" >&2
        i=$((i+1))
    done
    local ans
    if have_tty; then
        while :; do
            read -rp "选择 [${default_idx}]: " ans
            ans="${ans:-${default_idx}}"
            if [[ "${ans}" =~ ^[0-9]+$ ]] && [ "${ans}" -ge 1 ] && [ "${ans}" -le "${#options[@]}" ]; then
                printf '%s\n' "${options[$((ans-1))]}"
                return
            fi
            log_warn "无效选择: ${ans} (请输入 1-${#options[@]})"
        done
    else
        printf '%s\n' "${options[$((default_idx-1))]}"
    fi
}

# ask_yes_no "prompt" "default(y/n)" -> 0=yes, 1=no
ask_yes_no() {
    local prompt="$1" default="${2:-y}"
    if ! have_tty; then
        case "${default}" in
            y|Y|yes|YES) return 0 ;;
            *) return 1 ;;
        esac
    fi
    local ans
    while :; do
        read -rp "${prompt} [${default}]: " ans
        ans="${ans:-${default}}"
        case "${ans}" in
            y|Y|yes|YES) return 0 ;;
            n|N|no|NO) return 1 ;;
        esac
        log_warn "请输入 y 或 n"
    done
}

# ───── 状态与命令行参数 ─────
FLAVORS=""
UI=""
MIHOMO_VERSION=""
MIHOMO_REPO_SMART=""
MIHOMO_TAG_SMART=""
MIHOMO_SHORT_SHA_SMART=""
METACUBEXD_VERSION=""
ZASHBOARD_VERSION=""
BUILDER=""
PLATFORM=""
TAG=""
OUTPUT_MODE=""        # load | push
PUSH_USER=""
ADVANCED=0
DRY_RUN=0

print_help() {
    cat <<EOF
${SCRIPT_NAME} — glash 交互式镜像构建脚本

用法:
  ${SCRIPT_NAME} [选项]

模式:
  (无)                简单模式,只问 FLAVORS / UI / tag / platform / 加载方式
  --advanced          高级模式,展开全部 7 个 build-arg

构建参数(可用作命令行覆盖,非交互场景):
  --flavors VAL       FLAVORS  (both|standard|smart,默认 both)
  --ui VAL            UI       (metacubexd|zashboard,默认 metacubexd)
  --mihomo-version V  MIHOMO_VERSION
  --metacubexd-version V
  --zashboard-version V
  --mihomo-repo-smart V
  --mihomo-tag-smart V
  --mihomo-short-sha-smart V

执行:
  --builder NAME      buildx 实例名(默认 ${DEFAULT_BUILDER})
  --platform P        目标平台,逗号分隔(默认 ${DEFAULT_PLATFORM})
  --tag T             输出 tag(默认根据 FLAVORS 与 UI 自动生成)
  --load              加载到本地 docker(--load)
  --push              推送到 registry(--push);可与 --user 配合设默认仓库
  --user NAME         推送时使用的默认仓库用户名前缀,如 --push --user foo
                      -> 镜像 tag 改为 foo/glash:...;不传则提示
  --dry-run           只打印将要执行的命令,不真正构建

其它:
  -h, --help          显示此帮助

示例:
  ${SCRIPT_NAME}                                       # 简单模式全交互
  ${SCRIPT_NAME} --flavors smart --ui zashboard        # 命令行覆盖关键参数
  ${SCRIPT_NAME} --advanced --dry-run                  # 高级模式只打命令
  ${SCRIPT_NAME} --platform linux/arm64,linux/amd64    # 跨平台(配合 --push)
  ${SCRIPT_NAME} --push --user gangz1o --tag my:glash  # 推送到 Docker Hub
EOF
}

# 解析命令行(只覆盖已显式提供的项,未提供则保持空,后面走交互或默认)
parse_args() {
    while [ $# -gt 0 ]; do
        case "$1" in
            -h|--help)              print_help; exit 0 ;;
            --advanced)             ADVANCED=1 ;;
            --dry-run)              DRY_RUN=1 ;;
            --flavors)              FLAVORS="$2"; shift ;;
            --ui)                   UI="$2"; shift ;;
            --mihomo-version)       MIHOMO_VERSION="$2"; shift ;;
            --metacubexd-version)   METACUBEXD_VERSION="$2"; shift ;;
            --zashboard-version)    ZASHBOARD_VERSION="$2"; shift ;;
            --mihomo-repo-smart)    MIHOMO_REPO_SMART="$2"; shift ;;
            --mihomo-tag-smart)     MIHOMO_TAG_SMART="$2"; shift ;;
            --mihomo-short-sha-smart) MIHOMO_SHORT_SHA_SMART="$2"; shift ;;
            --builder)              BUILDER="$2"; shift ;;
            --platform)             PLATFORM="$2"; shift ;;
            --tag)                  TAG="$2"; shift ;;
            --load)                 OUTPUT_MODE="load" ;;
            --push)                 OUTPUT_MODE="push" ;;
            --user)                 PUSH_USER="$2"; shift ;;
            -*)
                die "未知参数: $1 (用 --help 查看用法)" ;;
            *)
                die "多余的位置参数: $1" ;;
        esac
        shift
    done
}

# 校验已设定的值(set -e 下不能写 `! cmd && die` 模式,改用 if)
validate_provided() {
    if [ -n "${FLAVORS}" ] && ! in_array "${FLAVORS}" "${VALID_FLAVORS[@]}"; then
        die "--flavors 必须是 ${VALID_FLAVORS[*]}"
    fi
    if [ -n "${UI}" ] && ! in_array "${UI}" "${VALID_UI[@]}"; then
        die "--ui 必须是 ${VALID_UI[*]}"
    fi
    if [ -n "${MIHOMO_VERSION}" ] && ! is_semver "${MIHOMO_VERSION}"; then
        die "--mihomo-version 形如 v1.2.3"
    fi
    if [ -n "${METACUBEXD_VERSION}" ] && ! is_semver "${METACUBEXD_VERSION}"; then
        die "--metacubexd-version 形如 v1.2.3"
    fi
    if [ -n "${ZASHBOARD_VERSION}" ] && ! is_semver "${ZASHBOARD_VERSION}"; then
        die "--zashboard-version 形如 v1.2.3"
    fi
    if [ -n "${MIHOMO_SHORT_SHA_SMART}" ] && ! is_short_sha "${MIHOMO_SHORT_SHA_SMART}"; then
        die "--mihomo-short-sha-smart 必须是 7 位 hex"
    fi
    if [ -n "${PLATFORM}" ] && ! is_platform "${PLATFORM}"; then
        die "--platform 形如 linux/amd64 或 linux/amd64,linux/arm64"
    fi
    if [ -n "${TAG}" ] && ! is_tag "${TAG}"; then
        die "--tag 含非法字符"
    fi
}

# ───── 校验环境 ─────
require_docker() {
    command -v docker >/dev/null 2>&1 || die "未检测到 docker,请先安装 Docker 20.10+"
    docker info >/dev/null 2>&1 || die "docker daemon 不可访问"
}

# 检查 buildx,确保有一个 docker-container driver 的 builder 可用
ensure_builder() {
    if ! docker buildx version >/dev/null 2>&1; then
        die "未检测到 docker buildx,请升级到 Docker 20.10+"
    fi
    local name="${BUILDER:-${DEFAULT_BUILDER}}"
    # docker buildx inspect 不支持 --format;改用 ls + grep
    local line
    line=$(docker buildx ls 2>/dev/null | awk -v n="${name}" '$1 ~ "^"n"[* ]" {print; exit}')
    if [ -n "${line}" ]; then
        # 解析 Driver 字段(第二列)
        local driver
        driver=$(echo "${line}" | awk '{print $2}')
        if [ "${driver}" = "docker-container" ]; then
            log_info "复用 buildx 实例: ${name} (driver: ${driver})"
            docker buildx use "${name}" >/dev/null 2>&1 || true
            return
        fi
        log_warn "${name} 当前 driver=${driver},不是 docker-container;继续创建会失败"
    fi
    log_step "创建 buildx 实例: ${name} (driver: docker-container)"
    docker buildx create --name "${name}" --driver docker-container --use >/dev/null
    log_info "已创建并切换到 ${name}"
}

# ───── 交互收集 ─────
print_banner() {
    printf '\n%b%s%b\n' "${C_BOLD}" "glash 交互式镜像构建脚本" "${C_RESET}"
    printf '镜像源: Dockerfile (本仓库)\n'
    printf '官方发布: gangz1o/glash (CI 自动构建)\n'
    printf '本脚本用于本地自构建,适合自定义 FLAVORS / UI / 内核版本\n\n'
}

# 简单模式
collect_simple() {
    log_step "1) FLAVORS — 内核组合"
    FLAVORS=$(ask_choice "选择 FLAVORS:" 1 \
        "both      - 双内核(默认)" \
        "standard  - 仅标准内核" \
        "smart     - 仅 Smart 内核")

    log_step "2) UI — Dashboard"
    UI=$(ask_choice "选择 UI:" 1 \
        "metacubexd - MetaCubeX/metacubexd(默认)" \
        "zashboard  - Zephyruso/zashboard")

    log_step "3) TAG — 输出镜像 tag"
    local default_tag
    default_tag="${DEFAULT_TAG_PREFIX}:${FLAVORS}-${UI}"
    TAG=$(ask_text "输出 tag" "${default_tag}")

    log_step "4) PLATFORM — 目标平台"
    PLATFORM=$(ask_text "目标平台(逗号分隔)" "${DEFAULT_PLATFORM}")

    log_step "5) 加载方式"
    OUTPUT_MODE=$(ask_choice "如何处理构建产物?" 1 \
        "load  - 加载到本地 docker(默认)" \
        "push  - 推送到 registry")

    if [ "${OUTPUT_MODE}" = "push" ]; then
        PUSH_USER=$(ask_text "推送仓库用户名前缀(留空用你 docker login 的账户)" "")
    fi
}

# 高级模式
collect_advanced() {
    log_step "1) FLAVORS — 内核组合"
    FLAVORS=$(ask_choice "选择 FLAVORS:" 1 \
        "both" "standard" "smart")

    log_step "2) UI — Dashboard"
    UI=$(ask_choice "选择 UI:" 1 \
        "metacubexd" "zashboard")

    log_step "3) TAG — 输出镜像 tag"
    local default_tag="${DEFAULT_TAG_PREFIX}:${FLAVORS}-${UI}"
    TAG=$(ask_text "输出 tag" "${default_tag}")

    log_step "4) PLATFORM"
    PLATFORM=$(ask_text "目标平台" "${DEFAULT_PLATFORM}")

    log_step "5) 加载方式"
    OUTPUT_MODE=$(ask_choice "如何处理构建产物?" 1 "load" "push")
    if [ "${OUTPUT_MODE}" = "push" ]; then
        PUSH_USER=$(ask_text "推送仓库用户名前缀(留空用 docker login 账户)" "")
    fi

    log_step "6) 进阶 build-arg(回车使用默认值)"
    MIHOMO_VERSION=$(ask_text        "MIHOMO_VERSION"          "${DEFAULT_MIHOMO_VERSION}")
    if [ "${UI}" = "metacubexd" ]; then
        METACUBEXD_VERSION=$(ask_text "METACUBEXD_VERSION"     "${DEFAULT_METACUBEXD_VERSION}")
    else
        METACUBEXD_VERSION="${DEFAULT_METACUBEXD_VERSION}"
    fi
    if [ "${UI}" = "zashboard" ]; then
        ZASHBOARD_VERSION=$(ask_text  "ZASHBOARD_VERSION"      "${DEFAULT_ZASHBOARD_VERSION}")
    else
        ZASHBOARD_VERSION="${DEFAULT_ZASHBOARD_VERSION}"
    fi
    if [ "${FLAVORS}" = "smart" ] || [ "${FLAVORS}" = "both" ]; then
        MIHOMO_REPO_SMART=$(ask_text       "MIHOMO_REPO_SMART"        "${DEFAULT_MIHOMO_REPO_SMART}")
        MIHOMO_TAG_SMART=$(ask_text        "MIHOMO_TAG_SMART"         "${DEFAULT_MIHOMO_TAG_SMART}")
        MIHOMO_SHORT_SHA_SMART=$(ask_text  "MIHOMO_SHORT_SHA_SMART"   "${DEFAULT_MIHOMO_SHORT_SHA_SMART}")
    else
        MIHOMO_REPO_SMART="${DEFAULT_MIHOMO_REPO_SMART}"
        MIHOMO_TAG_SMART="${DEFAULT_MIHOMO_TAG_SMART}"
        MIHOMO_SHORT_SHA_SMART="${DEFAULT_MIHOMO_SHORT_SHA_SMART}"
    fi
}

# 应用默认值(空值填默认)
apply_defaults() {
    : "${FLAVORS:=${DEFAULT_FLAVORS}}"
    : "${UI:=${DEFAULT_UI}}"
    : "${BUILDER:=${DEFAULT_BUILDER}}"
    : "${PLATFORM:=${DEFAULT_PLATFORM}}"
    : "${MIHOMO_VERSION:=${DEFAULT_MIHOMO_VERSION}}"
    : "${METACUBEXD_VERSION:=${DEFAULT_METACUBEXD_VERSION}}"
    : "${ZASHBOARD_VERSION:=${DEFAULT_ZASHBOARD_VERSION}}"
    : "${MIHOMO_REPO_SMART:=${DEFAULT_MIHOMO_REPO_SMART}}"
    : "${MIHOMO_TAG_SMART:=${DEFAULT_MIHOMO_TAG_SMART}}"
    : "${MIHOMO_SHORT_SHA_SMART:=${DEFAULT_MIHOMO_SHORT_SHA_SMART}}"
    : "${OUTPUT_MODE:=load}"
    : "${TAG:=${DEFAULT_TAG_PREFIX}:${FLAVORS}-${UI}}"

    validate_provided
}

# 生成 docker buildx build 命令
build_command() {
    local cmd=()
    cmd+=(docker buildx build)
    cmd+=(--builder "${BUILDER}")
    cmd+=(--build-arg "FLAVORS=${FLAVORS}")
    cmd+=(--build-arg "UI=${UI}")
    cmd+=(--build-arg "MIHOMO_VERSION=${MIHOMO_VERSION}")
    cmd+=(--build-arg "MIHOMO_REPO_SMART=${MIHOMO_REPO_SMART}")
    cmd+=(--build-arg "MIHOMO_TAG_SMART=${MIHOMO_TAG_SMART}")
    cmd+=(--build-arg "MIHOMO_SHORT_SHA_SMART=${MIHOMO_SHORT_SHA_SMART}")
    cmd+=(--build-arg "METACUBEXD_VERSION=${METACUBEXD_VERSION}")
    cmd+=(--build-arg "ZASHBOARD_VERSION=${ZASHBOARD_VERSION}")
    # 拆分 platform
    IFS=',' read -ra _plats <<< "${PLATFORM}"
    cmd+=(--platform "${PLATFORM}")

    local final_tag="${TAG}"
    if [ "${OUTPUT_MODE}" = "push" ] && [ -n "${PUSH_USER}" ]; then
        # 形如 my:tag -> user/my:tag
        if [[ "${TAG}" == */* ]]; then
            log_warn "tag 已含仓库前缀,忽略 --user"
        else
            final_tag="${PUSH_USER}/${TAG}"
        fi
    fi
    cmd+=(--tag "${final_tag}")

    if [ "${OUTPUT_MODE}" = "push" ]; then
        cmd+=(--push)
    else
        cmd+=(--load)
    fi

    cmd+=(.)
    printf '%s' "${cmd[*]}"
}

# 打印执行计划(单行命令,易复制)
print_plan() {
    printf '\n%b── 计划 ──%b\n' "${C_BOLD}" "${C_RESET}"
    local cmd
    cmd=$(build_command)
    printf '  %s\n' "${cmd}"
    printf '\n'
}

# 执行构建
run_build() {
    local cmd
    cmd=$(build_command)
    log_step "开始构建: ${TAG}"
    # shellcheck disable=SC2086
    ${cmd}
    log_info "构建完成: ${TAG}"
}

main() {
    parse_args "$@"
    require_docker

    print_banner

    if have_tty || [ "${ADVANCED}" -eq 1 ] || [ -n "${FLAVORS}${UI}${MIHOMO_VERSION}${METACUBEXD_VERSION}${ZASHBOARD_VERSION}${MIHOMO_SHORT_SHA_SMART}${PLATFORM}${TAG}${OUTPUT_MODE}${PUSH_USER}" ]; then
        # 至少有一个覆盖 / 显式要求高级模式 / 有 TTY 才走交互
        if [ "${ADVANCED}" -eq 1 ]; then
            collect_advanced
        elif have_tty && [ -z "${FLAVORS}${UI}${TAG}${PLATFORM}${OUTPUT_MODE}${PUSH_USER}${BUILDER}" ]; then
            collect_simple
        fi
    fi

    # 把未提供的项填默认
    BUILDER="${BUILDER:-${DEFAULT_BUILDER}}"
    apply_defaults

    # 如果 push 但 PUSH_USER 与 tag 已含仓库前缀,确认是否要交互
    if [ "${OUTPUT_MODE}" = "push" ] && [ -z "${PUSH_USER}" ] && have_tty && ! [[ "${TAG}" == */* ]]; then
        PUSH_USER=$(ask_text "推送仓库用户名前缀(留空用 docker login 账户)" "")
    fi

    ensure_builder
    print_plan

    if [ "${DRY_RUN}" -eq 1 ]; then
        log_info "干跑模式,跳过实际构建"
        exit 0
    fi

    if have_tty; then
        if ! ask_yes_no "执行构建?" "y"; then
            log_warn "用户取消"
            exit 3
        fi
    fi

    run_build
}

main "$@"
