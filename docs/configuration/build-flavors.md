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
# 默认(both)
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
- `UI`: `metacubexd` | `zashboard`(默认 `metacubexd`)— 选择 Dashboard,详见下节
- `MIHOMO_VERSION`: 标准内核版本 tag,如 `v1.19.31`,默认 `v1.19.31`
- `MIHOMO_REPO_SMART`: Smart 内核所在仓库,默认 `vernesong/mihomo`
- `MIHOMO_TAG_SMART`: Smart 内核 release tag,默认 `Prerelease-Alpha`
- `MIHOMO_SHORT_SHA_SMART`: 7 位 git short SHA,嵌入产物名,默认 `83e67d0`
- `METACUBEXD_VERSION`: metacubexd 版本,默认 `v1.273.1`,仅在 `UI=metacubexd` 时生效
- `ZASHBOARD_VERSION`: zashboard 版本,默认 `v3.29.1`,仅在 `UI=zashboard` 时生效

如果维护者要升级 Smart 内核,只需把 `MIHOMO_SHORT_SHA_SMART` 替换成上游新 SHA,构建会自动取对应产物。

## Dashboard 选择(`UI`)

`UI` 决定镜像打包的 Dashboard 静态资源。**运行时接口零变化** — 始终通过 mihomo 的 `external-ui: /app/ui` 暴露在 `:9090/ui`,容器内启动逻辑不需要任何改动。

| 取值 | 包含 | 体积影响 | 备注 |
| --- | --- | --- | --- |
| `metacubexd` | `MetaCubeX/metacubexd`(`compressed-dist.tgz`) | 默认 | 默认 Dashboard |
| `zashboard` | `Zephyruso/zashboard`(`dist.zip`,含字体) | +5-7 MB | 自动检测后端;支持 PWA |

### 用法

```bash
# 默认(metacubexd)
docker build -t my/glash:metacubexd .

# 自建 zashboard 版
docker build -t my/glash:zashboard --build-arg UI=zashboard .
```

compose 写法:

```yaml
services:
  glash:
    build:
      context: .
      args:
        UI: zashboard
```

### zashboard 特性提示

- **自动后端检测**:访问 `http://<host>:9090/ui/` 时,会自动尝试连接同源 `http://<host>:9090`,无需手动配 backend
- **PWA**:移动端"添加到主屏幕"可获得类原生 app 体验
- **升级按钮**:zashboard 自带的"升级 core" 按钮需要 mihomo 的 `external-ui-url` 配合。glash 镜像把 UI 资源预打包到 `/app/ui`,**升级按钮不会从远端拉取新版本**;如需更新,自建时改 `ZASHBOARD_VERSION` 重新 build 即可
- **PWA 入口**:与 metacubexd 一样通过 `:9090/ui` 访问

### 缺位行为

构建参数只决定镜像里有什么二进制,不影响入口语义。运行时由 `KERNEL` 选择哪一个 — 详见 [`kernel-selection.md`](./kernel-selection.md)。若镜像中不含所选内核,容器启动会立即报错并退出。
