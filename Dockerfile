# glash - Clash Docker 镜像
# 基于 Mihomo 内核 + MetacubexD Dashboard
# 作者: gangz1o
#
# 通过 FLAVORS build-arg 决定镜像包含的内核,可选项:
#   standard  - 仅标准内核(MetaCubeX/mihomo)
#   smart     - 仅 Smart 内核(vernesong/mihomo)
#   both      - 同时打包两种(默认)
#
# 运行时通过 KERNEL 环境变量在 standard 与 smart 之间切换
# (默认 standard)。切换 KERNEL 不会重启容器,需要用户显式重启。

ARG FLAVORS=both
ARG MIHOMO_VERSION=v1.19.31
ARG MIHOMO_REPO_SMART=vernesong/mihomo
ARG MIHOMO_TAG_SMART=Prerelease-Alpha
ARG MIHOMO_SHORT_SHA_SMART=83e67d0
ARG METACUBEXD_VERSION=v1.273.1

FROM --platform=$BUILDPLATFORM alpine:3.19 AS builder
ARG FLAVORS
ARG MIHOMO_VERSION
ARG MIHOMO_REPO_SMART
ARG MIHOMO_TAG_SMART
ARG MIHOMO_SHORT_SHA_SMART
ARG METACUBEXD_VERSION
ARG TARGETARCH

RUN apk add --no-cache curl unzip ca-certificates

WORKDIR /build
COPY docker/build-helpers/ /tmp/h/

# 标准内核
RUN case "${FLAVORS}" in \
        standard|both) \
            /tmp/h/download-mihomo.sh standard \
                "${TARGETARCH}" "${MIHOMO_VERSION}" "" "" "" /build/mihomo-standard ;; \
    esac

# Smart 内核
RUN case "${FLAVORS}" in \
        smart|both) \
            /tmp/h/download-mihomo.sh smart \
                "${TARGETARCH}" "" "${MIHOMO_REPO_SMART}" "${MIHOMO_TAG_SMART}" "${MIHOMO_SHORT_SHA_SMART}" /build/mihomo-smart ;; \
    esac

# Dashboard + GeoIP / GeoSite / Country.mmdb
RUN /tmp/h/download-assets.sh "${METACUBEXD_VERSION}"

# 最终镜像
FROM alpine:3.19
ARG FLAVORS

LABEL maintainer="gangz1o" \
      description="Clash Docker with Mihomo Core and MetacubexD Dashboard - Subscription Support" \
      org.opencontainers.image.flavors="${FLAVORS}"

# 安装运行时依赖
# curl: 用于下载订阅配置
# sed/grep: 用于处理配置文件
RUN apk add --no-cache ca-certificates tzdata bash tini curl sed grep flock && \
    mkdir -p /opt/mihomo/standard /opt/mihomo/smart /app /app/ui /app/geodata /root/.config/mihomo /var/log

# 从构建阶段复制文件(条件化,FLAVORS 不包含的内核层缺位时为空目录)
COPY --from=builder /build/mihomo-standard /opt/mihomo/standard/
COPY --from=builder /build/mihomo-smart /opt/mihomo/smart/
COPY --from=builder /build/ui /app/ui
# Geodata 放在 /app/geodata,启动时复制到配置目录
COPY --from=builder /build/geodata /app/geodata

# 复制启动脚本
COPY start.sh /app/start.sh
COPY lib /app/lib

# 设置执行权限与默认软链:仅在 standard 存在时设置,smart 不在镜像中时 KERNEL=smart 会启动报错
RUN set -eux; \
    if [ -f /opt/mihomo/standard/mihomo ]; then \
        chmod +x /opt/mihomo/standard/mihomo; \
        ln -sf /opt/mihomo/standard/mihomo /app/mihomo; \
    fi; \
    if [ -f /opt/mihomo/smart/mihomo ]; then \
        chmod +x /opt/mihomo/smart/mihomo; \
    fi; \
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
