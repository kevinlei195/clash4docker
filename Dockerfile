# glash - Clash Docker 镜像
# 基于 Mihomo Smart 内核(vernesong/mihomo fork)+ 多种 Dashboard
# 作者: gangz1o
#
# 镜像只包含 Smart 内核,支持 type: smart 策略组、ASN 偏好等增强特性。
#
# 通过 UI build-arg 决定打包的 Dashboard:
#   metacubexd - MetaCubeX/metacubexd(默认)
#   zashboard  - Zephyruso/zashboard
#
# 内核版本通过 MIHOMO_SHORT_SHA_SMART 固定;留空则构建时自动从
# vernesong/mihomo 的 Prerelease-Alpha release 中解析最新资产。

ARG UI=metacubexd
ARG MIHOMO_REPO_SMART=vernesong/mihomo
ARG MIHOMO_TAG_SMART=Prerelease-Alpha
ARG MIHOMO_SHORT_SHA_SMART=""
ARG METACUBEXD_VERSION=v1.273.1
ARG ZASHBOARD_VERSION=v3.29.1

FROM --platform=$BUILDPLATFORM alpine:3.19 AS builder
ARG UI
ARG MIHOMO_REPO_SMART
ARG MIHOMO_TAG_SMART
ARG MIHOMO_SHORT_SHA_SMART
ARG METACUBEXD_VERSION
ARG ZASHBOARD_VERSION
ARG TARGETARCH

RUN apk add --no-cache curl unzip ca-certificates

WORKDIR /build
COPY docker/build-helpers/ /tmp/h/

# Smart 内核(仅此一种)
RUN /tmp/h/download-mihomo.sh \
    "${TARGETARCH}" "${MIHOMO_REPO_SMART}" "${MIHOMO_TAG_SMART}" \
    "${MIHOMO_SHORT_SHA_SMART}" /build/mihomo-out

# Dashboard + GeoIP / GeoSite / Country.mmdb
RUN /tmp/h/download-assets.sh "${UI}" "${METACUBEXD_VERSION}" "${ZASHBOARD_VERSION}"

# 最终镜像
FROM alpine:3.19
ARG UI

LABEL maintainer="gangz1o" \
      description="Clash Docker with Mihomo Smart Core and Dashboard - Subscription Support" \
      org.opencontainers.image.dashboard="${UI}"

# 安装运行时依赖
# curl: 用于下载订阅配置
# sed/grep: 用于处理配置文件
RUN apk add --no-cache ca-certificates tzdata bash tini curl sed grep flock && \
    mkdir -p /app /app/ui /app/geodata /root/.config/mihomo /var/log

# 从构建阶段复制文件
COPY --from=builder /build/mihomo-out/mihomo /app/mihomo
COPY --from=builder /build/ui /app/ui
# Geodata 放在 /app/geodata,启动时复制到配置目录
COPY --from=builder /build/geodata /app/geodata

# 复制启动脚本
COPY start.sh /app/start.sh
COPY lib /app/lib

# 设置执行权限
RUN set -eux; \
    chmod +x /app/mihomo; \
    chmod +x /app/start.sh /app/lib/glash/*.sh

# 设置环境变量
ENV TZ=Asia/Shanghai
ENV MIHOMO_CONFIG_DIR=/root/.config/mihomo

# 暴露端口
# 7890: HTTP 代理
# 7891: SOCKS5 代理
# 7892: 混合代理 (HTTP + SOCKS5)
# 9090: API 控制器
EXPOSE 7890 7891 7892 9090

# 挂载配置目录
VOLUME ["/root/.config/mihomo"]

# 健康检查
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD /bin/sh -c "if [ -n \"$SECRET\" ]; then wget -q --header=\"Authorization: Bearer $SECRET\" -O /dev/null http://127.0.0.1:9090/version; else wget -q -O /dev/null http://127.0.0.1:9090/version; fi || exit 1"

# 使用 tini 作为 init 进程
ENTRYPOINT ["/sbin/tini", "--"]
CMD ["/app/start.sh"]
