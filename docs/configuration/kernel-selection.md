# 内核(Smart)

镜像只包含 **Smart 内核** — [vernesong/mihomo](https://github.com/vernesong/mihomo) 的 Smart fork。相比上游 `MetaCubeX/mihomo`,它额外提供:

- `type: smart` 策略组(按历史表现自动择优)
- ASN 偏好(`prefer-asn`)
- 可选 LightGBM 模型预测权重(`uselightgbm`)

Smart fork 基于上游 Alpha 分支开发,标准内核的语法(含 `type: select` / `url-test` / `fallback`)向后兼容,普通订阅可直接运行。

## 内核来源

| 项 | 值 |
| --- | --- |
| 仓库 | `vernesong/mihomo` |
| Release tag | `Prerelease-Alpha` |
| 架构 | `linux/amd64`、`linux/arm64`、`linux/arm/v7` |

上游的 `Prerelease-Alpha` 是**滚动 tag** — 每次上游提交都会覆盖同一 tag 下的资产文件名(资产名内嵌的 SHA 会变)。因此:

> 上游更新内核后,**已构建的镜像不会自动更新**。需要新内核时重新构建镜像即可。

## 版本解析方式

构建时若不指定 `MIHOMO_SHORT_SHA_SMART`,`docker/build-helpers/download-mihomo.sh` 会调用 GitHub API 列出 `Prerelease-Alpha` 的实际资产名,按目标架构挑选 `alpha-smart` 内核并下载。这样上游改资产名时不会静默 404。

也可以显式固定版本:

```bash
docker build -t my/glash:latest --build-arg MIHOMO_SHORT_SHA_SMART=4624551 .
```

显式指定时跳过 API 查询,适合离线构建或 GitHub API 限流场景。

## 自检当前内核

容器启动后,可用下列命令确认内核版本:

```bash
docker exec glash /app/mihomo -v
# 期望: Mihomo Meta alpha-smart-<SHA> linux amd64 with go1.x.x ...
```

`/app/mihomo` 是实体可执行文件(不是软链),镜像中只有一个内核。

## KERNEL 环境变量

镜像只包含 Smart 内核,`KERNEL` 环境变量仅保留用于兼容旧配置:

| 取值 | 行为 |
| --- | --- |
| 未设置 / `smart` | 正常使用 Smart 内核 |
| 其它值(如 `standard`) | 启动即报错:`❌ KERNEL='standard' 不支持(当前镜像只包含 smart 内核)` |

## LightGBM 模型(可选)

Smart 内核支持用 LightGBM 模型预测权重,需要在配置目录放置 `Model.bin`:

```yaml
lgbm-auto-update: true
lgbm-update-interval: 72
lgbm-url: "https://github.com/vernesong/mihomo/releases/download/LightGBM-Model/Model.bin"

proxy-groups:
  - name: "🚀 Smart"
    type: smart
    uselightgbm: true
    prefer-asn: true
```

模型文件可从上游 release 获取(见 [LightGBM-Model](https://github.com/vernesong/mihomo/releases/tag/LightGBM-Model)),放到宿主机挂载的配置目录即可。

## 相关文档

- Dashboard 选择:[`build-flavors.md`](./build-flavors.md)
- 环境变量:[`environment-variables.md`](./environment-variables.md)
- 构建指南:[`../development/build.md`](../development/build.md)
