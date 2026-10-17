# 自建镜像构建变体(`FLAVORS`)

`FLAVORS` 构建参数决定镜像包含的内核集合,只影响构建产物,不改变运行时接口。

## 取值

| 取值 | 包含的内核 | 默认 | 体积影响 |
| --- | --- | --- | --- |
| `both` | `standard` + `smart` | ✅ | 基准(+约 17 MB) |
| `standard` | 仅 `standard` | | ~15 MB |
| `smart` | 仅 `smart` | | ~17 MB |

## 用法

```bash
# 官方默认(both)
docker build -t my/glash:both --build-arg FLAVORS=both .

# 仅 standard(适合只用标准内核的部署)
docker build -t my/glash:standard --build-arg FLAVORS=standard .

# 仅 smart(供电信/网通出口差异敏感场景)
docker build -t my/glash:smart --build-arg FLAVORS=smart .
```

也可在 `docker compose build` 阶段声明:

```yaml
services:
  glash:
    build:
      context: .
      args:
        FLAVORS: standard
```

## 各 build-arg 取值范围

- `FLAVORS`: `standard` | `smart` | `both`(默认 `both`)
- `MIHOMO_VERSION`: 标准内核版本 tag,如 `v1.19.31`,默认 `v1.19.31`
- `MIHOMO_REPO_SMART`: Smart 内核所在仓库,默认 `vernesong/mihomo`
- `MIHOMO_TAG_SMART`: Smart 内核 release tag,默认 `Prerelease-Alpha`
- `MIHOMO_SHORT_SHA_SMART`: 7 位 git short SHA,嵌入产物名,默认 `83e67d0`
- `METACUBEXD_VERSION`: Dashboard 版本,默认 `v1.273.1`

如果维护者要升级 Smart 内核,只需把 `MIHOMO_SHORT_SHA_SMART` 替换成上游新 SHA,构建会自动取对应产物。

## 缺位行为

构建参数只决定镜像里有什么二进制,不影响入口语义。运行时由 `KERNEL` 选择哪一个 — 详见 [`kernel-selection.md`](./kernel-selection.md)。若镜像中不含所选内核,容器启动会立即报错并退出。
