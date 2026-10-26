# Dashboard 选择(`UI`)

`UI` 构建参数决定镜像打包的 Dashboard 静态资源。**运行时接口零变化** — 始终通过 mihomo 的 `external-ui: /app/ui` 暴露在 `:9090/ui`,容器内启动逻辑不需要任何改动。

镜像只包含 Smart 内核(vernesong/mihomo fork),因此构建变体只剩 Dashboard 这一个维度。

## 取值

| 取值 | 包含 | 体积影响 | 备注 |
| --- | --- | --- | --- |
| `metacubexd` | `MetaCubeX/metacubexd`(`compressed-dist.tgz`) | 默认 | 默认 Dashboard |
| `zashboard` | `Zephyruso/zashboard`(`dist.zip`,含字体) | +5-7 MB | 自动检测后端;支持 PWA |

## 用法

```bash
# 默认(metacubexd)
docker build -t my/glash:metacubexd .

# zashboard 版
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

交互式构建脚本:

```bash
./scripts/build-interactive.sh --ui zashboard
```

## zashboard 特性提示

- **自动后端检测**:访问 `http://<host>:9090/ui/` 时,会自动尝试连接同源 `http://<host>:9090`,无需手动配 backend
- **PWA**:移动端"添加到主屏幕"可获得类原生 app 体验
- **升级按钮**:zashboard 自带的"升级 core" 按钮需要 mihomo 的 `external-ui-url` 配合。glash 镜像把 UI 资源预打包到 `/app/ui`,**升级按钮不会从远端拉取新版本**;如需更新,自建时改 `ZASHBOARD_VERSION` 重新 build 即可
- **PWA 入口**:与 metacubexd 一样通过 `:9090/ui` 访问

## 内核版本(build-arg)

内核版本相关的 build-arg 见 [`kernel-selection.md`](./kernel-selection.md)。核心是 `MIHOMO_SHORT_SHA_SMART` — 留空时构建会自动解析上游最新资产。

## 相关文档

- 内核来源与版本:[`kernel-selection.md`](./kernel-selection.md)
- 构建指南:[`../development/build.md`](../development/build.md)
