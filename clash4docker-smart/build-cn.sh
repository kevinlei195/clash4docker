#!/bin/bash
# 国内/受限制网络环境下一键构建脚本
#   - 走方案 C: GitHub 镜像代理 (gh-proxy.com)
#   - 走方案 A: Alpine 国内 apk 镜像 (mirrors.aliyun.com)
# 输出: clash4docker-smart-local:latest (Docker 镜像)
# 用法:
#   ./build-cn.sh                      # 默认 amd64,代理=gh-proxy.com
#   ./build-cn.sh --platform arm64     # 指定架构
#   ./build-cn.sh --proxy https://xxx  # 指定其它代理
#   ./build-cn.sh --dry-run            # 只重新生成 Dockerfile.cn,不构建
#   ./build-cn.sh --smoke              # 构建后跑一次冒烟测试

set -euo pipefail

PROXY="https://gh-proxy.com"
PLATFORM="linux/amd64"
IMAGE_TAG="clash4docker-smart-local"
BUILD_CONTEXT="."
DRY_RUN=0
SMOKE=0

GLASH_APP_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
DOCKERFILE="$GLASH_APP_DIR/Dockerfile"
DOCKERFILE_CN="$GLASH_APP_DIR/Dockerfile.cn"

log_info() { printf '\033[32m[INFO]\033[0m %s\n' "$*"; }
log_warn() { printf '\033[33m[WARN]\033[0m %s\n' "$*" >&2; }
log_error() { printf '\033[31m[ERROR]\033[0m %s\n' "$*" >&2; }

usage() {
    sed -n '2,12p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
    exit "${1:-0}"
}

# 解析参数
while [ $# -gt 0 ]; do
    case "$1" in
        -h|--help) usage 0 ;;
        --platform)
            [ $# -ge 2 ] || { log_error "--platform 需要参数"; exit 1; }
            PLATFORM="linux/$2"
            shift 2
            ;;
        --proxy)
            [ $# -ge 2 ] || { log_error "--proxy 需要参数"; exit 1; }
            PROXY="$2"
            shift 2
            ;;
        --tag)
            [ $# -ge 2 ] || { log_error "--tag 需要参数"; exit 1; }
            IMAGE_TAG="$2"
            shift 2
            ;;
        --dry-run) DRY_RUN=1; shift ;;
        --smoke)   SMOKE=1;   shift ;;
        *) log_error "未知参数: $1"; usage 1 ;;
    esac
done

log_info "PROXY   = $PROXY"
log_info "PLATFORM= $PLATFORM"
log_info "IMAGE   = $IMAGE_TAG"
log_info "DRY_RUN = $DRY_RUN"
log_info "SMOKE   = $SMOKE"

# -----------------------------------------------------------------------------
# 1) 探活代理
# -----------------------------------------------------------------------------
log_info "探活代理 $PROXY ..."
PROXY_TEST_URL="${PROXY}/https://github.com/vernesong/mihomo/releases"
PROXY_HTTP=$(curl --max-time 12 -sI -o /dev/null -w "%{http_code}" "$PROXY_TEST_URL" || echo "000")
if [ "$PROXY_HTTP" != "200" ]; then
    log_error "代理 $PROXY 不可达 (HTTP $PROXY_HTTP)。请换其它代理或运行 ./build-cn.sh --proxy <URL>"
    exit 1
fi
log_info "代理可达 (HTTP 200)"

# -----------------------------------------------------------------------------
# 2) 重新生成 Dockerfile.cn
# -----------------------------------------------------------------------------
generate_dockerfile_cn() {
    log_info "正在生成 Dockerfile.cn ..."

    if [ ! -f "$DOCKERFILE" ]; then
        log_error "源 Dockerfile 找不到: $DOCKERFILE"
        exit 1
    fi

    # 2.1 sed 替换所有 https://github.com -> ${PROXY}/https://github.com
    sed -e "s|https://github.com|${PROXY}/https://github.com|g" \
        "$DOCKERFILE" > "$DOCKERFILE_CN"

    # 2.2 还原 LABEL 中被误改的 image.source(不是 URL 下载点,避免混淆)
    sed -i "s|${PROXY}/https://github.com/gangz1o/clash4docker|https://github.com/gangz1o/clash4docker|" "$DOCKERFILE_CN"

    # 2.3 注入 Alpine 国内源 (替换两处 apk add)
    python3 - "$DOCKERFILE_CN" <<'PY'
import sys
path = sys.argv[1]
src = open(path).read()

old1 = "RUN apk add --no-cache curl unzip ca-certificates"
new1 = ("RUN sed -i 's|dl-cdn.alpinelinux.org|mirrors.aliyun.com|g' /etc/apk/repositories "
        "&& apk update >/dev/null "
        "&& apk add --no-cache curl unzip ca-certificates")
src = src.replace(old1, new1, 1)

old2 = "RUN apk add --no-cache ca-certificates tzdata bash tini curl sed grep flock"
new2 = ("RUN sed -i 's|dl-cdn.alpinelinux.org|mirrors.aliyun.com|g' /etc/apk/repositories "
        "&& apk update >/dev/null "
        "&& apk add --no-cache ca-certificates tzdata bash tini curl sed grep flock")
src = src.replace(old2, new2, 1)

# 在文件头加一行注释提醒
header = (
    "# ！！！这是一个**镜像版** Dockerfile,仅供国内/受限制网络环境构建测试使用。\n"
    "# ！！！常规构建请用 ./Dockerfile;本文件由 build-cn.sh 重新生成。\n"
    "# ！！！维护约定:手工编辑后请跑 ./build-cn.sh 校验 URL 与 apk 源改写是否仍然完整。\n"
    "#\n"
    "# 与主 Dockerfile 的差异:\n"
    "#   1. 所有 https://github.com URL 通过 https://gh-proxy.com 镜像代理\n"
    "#   2. Alpine apk 源切到 https://mirrors.aliyun.com\n"
    "# 两者由 build-cn.sh 完成改写。任何对比上游 rebuild 的请求都应当使用 ./build-cn.sh。\n"
    "\n"
)

# 先剥离原文件最初的非 FROM 注释,只保留从 FROM 开始的内容
lines = src.splitlines()
keep_idx = 0
for i, ln in enumerate(lines):
    s = ln.strip()
    if s.startswith("FROM "):
        keep_idx = i
        break

new_src = header + "\n".join(lines[keep_idx:])
open(path, 'w').write(new_src)
PY

    log_info "Dockerfile.cn 已生成 ($(wc -l < "$DOCKERFILE_CN" | tr -d ' ') 行)"

    # 2.4 校验: 行数不为 0,包含 5 个改写后的 URL,包含 2 处阿里源注入
    URL_COUNT=$(grep -c "${PROXY}/https://github.com" "$DOCKERFILE_CN" || true)
    APK_COUNT=$(grep -c "mirrors.aliyun.com" "$DOCKERFILE_CN" || true)
    log_info "  github URL 改写命中: $URL_COUNT (期望 5)"
    log_info "  apk 源改写命中:   $APK_COUNT (期望 >=2)"
    if [ "$URL_COUNT" -ne 5 ] || [ "$APK_COUNT" -lt 2 ]; then
        log_error "Dockerfile.cn 改写校验失败,中止"
        exit 1
    fi
}

generate_dockerfile_cn

if [ "$DRY_RUN" = "1" ]; then
    log_info "--dry-run 已设置, 不构建镜像"
    exit 0
fi

# -----------------------------------------------------------------------------
# 3) 构建 (使用 git repo root 作为构建上下文, 这样可以拉 start.sh 与 lib/)
# -----------------------------------------------------------------------------
log_info "构建镜像 $IMAGE_TAG ($PLATFORM) ..."

# 选择构建上下文: 用仓库根目录 (因为 Dockerfile.cn 在子项目下, 它 COPY start.sh / lib 等)
REPO_ROOT=$(cd "$GLASH_APP_DIR/.." && pwd)
log_info "构建上下文: $REPO_ROOT/clash4docker-smart"

docker buildx build \
    --platform "$PLATFORM" \
    --load \
    -t "$IMAGE_TAG" \
    -f "$DOCKERFILE_CN" \
    "$GLASH_APP_DIR"

log_info "✅ 构建完成: $IMAGE_TAG"

# -----------------------------------------------------------------------------
# 4) 校验内核确实是 Smart
# -----------------------------------------------------------------------------
M_VERSION=$(docker run --rm "$IMAGE_TAG:latest" /app/mihomo -v 2>&1 | head -1 || true)
log_info "mihomo 版本: $M_VERSION"
if echo "$M_VERSION" | grep -q "alpha-smart"; then
    log_info "✅ 内核确认为 Smart 内核"
else
    log_warn "⚠️ 内核版本未匹配 alpha-smart,请检查是否下载到了错误的资源"
fi

# -----------------------------------------------------------------------------
# 5) 可选: 冒烟测试
# -----------------------------------------------------------------------------
if [ "$SMOKE" = "1" ]; then
    log_info "运行冒烟测试 ..."

    SMOKE_DIR=$(mktemp -d /tmp/glash-smart-smoke.XXXXXX)
    mkdir -p "$SMOKE_DIR/config"

    # 复用 example 配置;为避开主 cl ash-glash 已占用 7890/7891/9090,把端口改成非冲突
    cp "$GLASH_APP_DIR/config.example.yaml" "$SMOKE_DIR/config/config.yaml"
    sed -i -e 's|^port: 7890|port: 7895|' \
           -e 's|^socks-port: 7891|socks-port: 7896|' \
           -e 's|^mixed-port: 7892|mixed-port: 7897|' \
           -e 's|0.0.0.0:9090|0.0.0.0:9095|' \
           "$SMOKE_DIR/config/config.yaml"

    docker run -d --rm --name glash-smart-smoke \
        --network=host \
        -v "$SMOKE_DIR/config:/root/.config/mihomo" \
        -e TZ=Asia/Shanghai -e SECRET=smart-smoke \
        "$IMAGE_TAG:latest"

    sleep 7

    log_info "--- /version ---"
    curl -fsS -H "Authorization: Bearer smart-smoke" http://127.0.0.1:9095/version || true
    echo
    log_info "--- /group (Smart 类型) ---"
    curl -fsS -H "Authorization: Bearer smart-smoke" http://127.0.0.1:9095/group \
        | python3 -c "import json,sys; d=json.load(sys.stdin); \
                      print('\n'.join(f\"{g['type']:>10}  {g['name']}\" for g in d.get('proxies',[]) if g.get('type')=='Smart') or '(no Smart group)')"

    log_info "--- 容器日志片段 ---"
    docker logs glash-smart-smoke 2>&1 | grep -E "Smart|🚀|alpha-smart" | head -20

    docker stop glash-smart-smoke 2>/dev/null || true
    rm -rf "$SMOKE_DIR"
    log_info "✅ 冒烟完成,临时目录已清理"
fi
