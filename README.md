# Clash for Docker(glash)

基于 [Mihomo](https://github.com/MetaCubeX/mihomo) 内核、内置 [MetacubexD](https://github.com/MetaCubeX/metacubexd) Dashboard 的多架构 Docker 镜像。

Dockerhub
https://hub.docker.com/r/gangz1o/glash

## 内核选择

单一镜像 `gangz1o/glash:latest` 默认包含两个内核二进制,运行时通过环境变量 `KERNEL` 选择(默认 `standard`):

| `KERNEL` | 内核来源 | 特性 |
| --- | --- | --- |
| `standard`(默认) | `MetaCubeX/mihomo` | Mihomo 标准版 |
| `smart` | `vernesong/mihomo`(Smart fork) | `type: smart` 策略组、ASN 偏好、可选 LightGBM |

切换时不会自动重启容器,请显式 `docker compose up -d` 重启。Smart 内核的差异与用法见 [`docs/configuration/kernel-selection.md`](./docs/configuration/kernel-selection.md)。

如需缩减镜像体积,可自建时传入 `--build-arg FLAVORS=standard` 或 `=smart`,只打包单内核。详见 [`docs/configuration/build-flavors.md`](./docs/configuration/build-flavors.md)。

项目同时支持远程订阅和本地配置。订阅下载后会先在候选文件中完成环境变量覆写、自定义 Hook 和 Mihomo 原生校验;全部成功才替换当前配置。定时更新使用 Controller 热加载,失败时保留或恢复旧配置,不会为了更新订阅主动重启容器。

完整文档见 [`docs/`](./docs/README.md)。

## 功能

- Mihomo 与 MetacubexD 已打包进镜像
- 支持 `linux/amd64`、`linux/arm64`、`linux/arm/v7`
- 支持订阅首次下载、定时更新和手动更新
- 订阅更新默认通过当前 Mihomo 本地代理完成
- 下载失败不覆盖当前配置,热加载失败自动恢复旧配置
- 支持固定代理模式、代理端口、Dashboard 密钥和代理认证
- 支持持久开启或关闭 TUN,并可关闭不兼容的 `auto-redirect`
- 支持 DNS 覆写和订阅后自定义 Hook
- 预置 GeoIP、GeoSite 和 Country.mmdb 数据
- 内置健康检查、日志轮转示例和 `tini` 进程管理

## 开始之前

先选择适合自己的模式:

| 使用场景 | 推荐模式 | 配置挂载 | 是否需要 TUN |
| --- | --- | --- | --- |
| 使用机场订阅,希望自动更新 | 订阅模式 | 可写配置目录 | 否 |
| 自己维护完整 `config.yaml` | 本地配置模式 | 单文件可只读挂载 | 否 |
| 应用主动连接 HTTP/SOCKS5 代理 | 以上任一模式 | 均可 | 否 |
| 希望透明接管容器网络命名空间内的流量 | TUN 模式 | 可写配置目录 | 是 |
| 希望将 NAS/服务器作为整个局域网网关 | 高级网络部署 | 取决于平台 | 是,并需额外配置宿主机路由、防火墙和转发 |

> TUN 在 Docker bridge 网络中只修改容器自己的网络命名空间,不会因为开启 `TUN_ENABLED=true` 就自动接管宿主机或整个局域网。大多数用户只需要映射 7890/7891/7892 代理端口,不需要开启 TUN。

详细对比见 [`docs/install/`](./docs/install/)。

## 30 秒上手(订阅模式)

```yaml
# docker-compose.yml
services:
  glash:
    image: gangz1o/glash:latest
    container_name: glash
    restart: unless-stopped
    ports:
      - "7890:7890"   # HTTP
      - "7891:7891"   # SOCKS5
      - "7892:7892"   # HTTP + SOCKS5
      - "9090:9090"   # Dashboard 与 API
    volumes:
      - ./config:/root/.config/mihomo
    environment:
      TZ: Asia/Shanghai
      SUB_URL: https://your-subscription-url
      SUB_CRON: "0 */6 * * *"
      SECRET: change-this-dashboard-secret
      ALLOW_LAN: "true"
```

```bash
docker compose up -d
docker logs -f glash
```

> 配置目录必须可写。订阅模式不要把 `config.yaml` 单文件挂载为 `:ro`,容器需要保存订阅并写入环境变量覆写项。

完整示例与本地配置模式见 [`docs/install/quickstart-subscription.md`](./docs/install/quickstart-subscription.md)。

## 环境变量速查

最常用变量(完整列表见 [`docs/configuration/environment-variables.md`](./docs/configuration/environment-variables.md)):

| 变量 | 默认值 | 说明 |
| --- | --- | --- |
| `SUB_URL` | 空 | 订阅地址(订阅模式必填) |
| `SUB_CRON` | 空 | 定时表达式,例如 `0 */6 * * *` |
| `SECRET` | 空 | Dashboard/API 密钥 |
| `ALLOW_LAN` | 空 | `true` 时允许局域网访问代理端口 |
| `TZ` | `Asia/Shanghai` | 容器时区,决定 cron 执行时间 |
| `MODE` | 空 | 固定 Mihomo 运行模式:`rule` / `global` / `direct` |
| `HTTP_PORT` / `SOCKS_PORT` / `MIXED_PORT` | 空 | 固定端口,避免订阅刷新覆盖 |
| `TUN_ENABLED` | 空 | `true` 时持久开启 TUN |
| `KERNEL` | `standard` | 选择 mihomo 内核 (`standard`/`smart`);切换后请 `docker compose up -d` 重启容器 |

未列出的可选覆写项会保留订阅或本地配置中的原值。

## 文档导航

| 主题 | 文档 |
| --- | --- |
| 安装与快速开始 | [`docs/install/`](./docs/install/) |
| Dashboard 与代理端口使用 | [`docs/usage/`](./docs/usage/) |
| 环境变量与配置参考 | [`docs/configuration/`](./docs/configuration/) |
| 运维命令与故障排查 | [`docs/operations/`](./docs/operations/) |
| 运行时结构与本地开发 | [`docs/development/`](./docs/development/) |
| 国内构建指南(国内网络) | [`docs/development/build-in-china.md`](./docs/development/build-in-china.md) |
| PR CI 门禁 | [`docs/development/ci.md`](./docs/development/ci.md) |
| 完整文档目录 | [`docs/README.md`](./docs/README.md) |

## 社区与贡献

有问题或建议可以提交 [Issue](https://github.com/gangz1o/clash4docker/issues)。提交前请先搜索本仓库文档和已有 issue,并附上"故障排查"中列出的环境与日志信息。

- 论坛:[linux.do](https://linux.do/)
- Mihomo 配置文档:[wiki.metacubex.one](https://wiki.metacubex.one/)

## 致谢

感谢以下开源项目:

- [Mihomo](https://github.com/MetaCubeX/mihomo)
- [MetacubexD](https://github.com/MetaCubeX/metacubexd)


## License

MIT