# TUN 模式

TUN 模式让 Mihomo 在容器内透明接管 TCP/UDP 流量,而无需在客户端单独配置代理。本文档介绍如何在 Docker 中启用 TUN 及其网络边界。

> ⚠️ TUN 在 Docker bridge 网络中只修改容器自己的网络命名空间,不会因为开启 `TUN_ENABLED=true` 就自动接管宿主机或整个局域网。大多数用户只需要映射 7890/7891/7892 代理端口,不需要开启 TUN。

## 启用 TUN

TUN 需要 Linux TUN 设备和 `NET_ADMIN` 能力:

```yaml
services:
  glash:
    image: gangz1o/glash:latest
    container_name: glash
    restart: unless-stopped
    cap_add:
      - NET_ADMIN
    devices:
      - /dev/net/tun:/dev/net/tun
    ports:
      - "7890:7890"
      - "7891:7891"
      - "7892:7892"
      - "9090:9090"
    volumes:
      - ./config:/root/.config/mihomo
    environment:
      SUB_URL: https://your-subscription-url
      TUN_ENABLED: "true"
```

## 默认 TUN 配置

项目注入的默认 TUN 配置为:

```yaml
tun:
  enable: true
  stack: mixed
  auto-route: true
  auto-redirect: true
  auto-detect-interface: true
```

## 关闭 auto-redirect 解决兼容问题

如果日志出现以下错误,通常是 NAS 内核、netlink、iptables/nftables 与 `auto-redirect` 不兼容:

```text
Start TUN listening error: auto redirect ... netlink receive ...
```

可关闭自动重定向后重建容器:

```yaml
environment:
  TUN_ENABLED: "true"
  TUN_AUTO_REDIRECT: "false"
```

```bash
docker compose up -d --force-recreate
```

## Docker 网络边界

- **bridge 模式**:TUN 路由位于 glash 容器自己的网络命名空间,只影响该命名空间。
- **其他容器**:通常应显式配置 `HTTP_PROXY`、`HTTPS_PROXY` 或 `ALL_PROXY`,而不是期待 glash 的 TUN 自动接管它们。
- **宿主机和局域网网关**:需要宿主机网络命名空间、IP forwarding、防火墙/NAT 和正确的默认网关设置;不同 NAS 系统限制不同,本项目的一个环境变量无法代替这些系统配置。
- **`network_mode: host`** 会直接影响宿主网络,应了解路由和防火墙后再使用;host 模式下不要再配置 `ports`。

## 验证 TUN 是否生效

不要只用 `ping` 判断代理是否正常。普通 HTTP/SOCKS5 代理不代理 ICMP,部分远端也会丢弃 ICMP;优先使用前文的 `curl` 命令验证。

## 相关文档

- 环境变量参考:[`./environment-variables.md`](./environment-variables.md)
- 故障排查:[`../operations/troubleshooting.md`](../operations/troubleshooting.md)