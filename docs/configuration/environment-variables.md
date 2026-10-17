# 环境变量参考

未设置的可选覆写项会保留订阅或本地配置中的原值。

## 运行环境

| 变量 | 默认值 | 说明 |
| --- | --- | --- |
| `TZ` | `Asia/Shanghai` | 容器时区,也决定 cron 的执行时间 |
| `SAFE_PATHS` | 空 | 追加传给 Mihomo 的安全路径,多个容器内路径用冒号分隔;仅在配置引用挂载目录时需要 |
| `KERNEL` | `standard` | 选择 mihomo 内核:`standard`(MetaCubeX/Mihomo) / `smart`(vernesong/mihomo Smart fork)。切换后不会自动重启容器,需要 `docker compose up -d` 显式重启。详见 [`kernel-selection.md`](./kernel-selection.md) |

## 订阅与更新

| 变量 | 默认值 | 说明 |
| --- | --- | --- |
| `SUB_URL` | 空 | 返回 Mihomo/Clash YAML 配置的 HTTP(S) 订阅地址 |
| `SUB_CRON` | 空 | 5 段 cron 表达式;为空时不自动更新 |
| `DOWNLOAD_PROXY` | 空 | 首次下载无法直连、且没有可用本地配置时使用的外部代理 |
| `SUB_USER_AGENT` | `clash.meta` | 下载订阅使用的 User-Agent |

### 常用定时表达式

| 表达式 | 含义 |
| --- | --- |
| `0 */6 * * *` | 每 6 小时 |
| `0 0 * * *` | 每天 00:00 |
| `0 */12 * * *` | 每 12 小时 |
| `*/30 * * * *` | 每 30 分钟 |
| `0 8 * * *` | 每天 08:00 |

## 持久覆写

这些值会在启动和每次订阅更新时重新写入,避免 Dashboard 临时修改或机场订阅内容在重启后覆盖用户选择。

| 变量 | 可选值 | 说明 |
| --- | --- | --- |
| `SECRET` | 任意单行字符串 | Dashboard/API 密钥;使用定时更新时应与运行中配置一致 |
| `ALLOW_LAN` | `true` / `false` | 是否允许局域网访问代理端口 |
| `IPV6_ENABLED` | `true` / `false` | 同时覆写顶层 `ipv6` 和 `dns.ipv6`;未设置或为空时保留原值,在 `DNS_OVERRIDE` 之后生效 |
| `MODE` | `rule` / `global` / `direct` | 固定 Mihomo 运行模式 |
| `HTTP_PORT` | `1`–`65535` | 覆写顶层 `port` |
| `SOCKS_PORT` | `1`–`65535` | 覆写顶层 `socks-port` |
| `MIXED_PORT` | `1`–`65535` | 覆写顶层 `mixed-port` |
| `AUTHENTICATION` | `user:pass[,user:pass]` | HTTP、SOCKS5、Mixed 代理认证 |
| `DNS_OVERRIDE` | `true` / `false` | 为 `true` 时用项目预设完整覆写顶层 `dns` 配置 |
| `TUN_ENABLED` | `true` / `false` | 持久开启或关闭顶层 `tun` 配置 |
| `TUN_AUTO_REDIRECT` | `true` / `false` | `TUN_ENABLED=true` 时控制 `auto-redirect`;未设置时为 `true` |
| `FORCE_UNIFIED_DELAY_AND_TCP_CONCURRENT` | `true` / `false` | 订阅缺少 `unified-delay`、`tcp-concurrent` 时会补为 `true`;设为 `true` 时也覆写已有值 |

## 端口映射规则

Docker 端口格式是 `宿主机端口:容器端口`,右侧必须与 Mihomo 最终配置一致。例如希望外部继续使用 7890,但容器内 HTTP 端口固定为 17890:

```yaml
ports:
  - "7890:17890"
environment:
  HTTP_PORT: "17890"
```

推荐直接把容器内端口固定为项目默认值,这样订阅即使携带其他端口也不会破坏映射:

```yaml
ports:
  - "7890:7890"
  - "7891:7891"
  - "7892:7892"
environment:
  HTTP_PORT: "7890"
  SOCKS_PORT: "7891"
  MIXED_PORT: "7892"
```

## 相关文档

- 订阅模式快速开始:[`../install/quickstart-subscription.md`](../install/quickstart-subscription.md)
- 本地配置模式:[`../install/quickstart-local.md`](../install/quickstart-local.md)
- 代理端口使用:[`../usage/proxy-usage.md`](../usage/proxy-usage.md)