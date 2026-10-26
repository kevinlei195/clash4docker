# 手动构建镜像

> 面向使用者的构建指南 —— 在自己的机器上构建 glash 镜像,或推送到自己的 registry。
>
> 本仓库**不发布官方镜像产物**,也没有任何自动发布流水线。镜像必须自行构建。
>
> 开发者视角的 CI 对照见 [`./build.md`](./build.md);国内网络受限环境的方案见 [`./build-in-china.md`](./build-in-china.md)。

---

## 1. 前置条件

| 项 | 要求 |
| --- | --- |
| Docker Engine | **20.10+**(buildx 内置版本 ≥ v0.10) |
| buildx | 随 Docker 附带,`docker buildx version` 可用 |
| builder 实例 | 一个 `docker-container` driver 的 buildx 实例(用于缓存) |
| 磁盘 | 每个变体约 1.5 GB(含构建缓存) |
| 网络 | 能访问 `github.com` 与 `api.github.com` |

检查环境:

```bash
docker --version
docker buildx version
docker buildx ls
```

### 创建 builder 实例

`docker-container` driver 会启动一个常驻的 BuildKit 容器,跨命令复用构建缓存(避免每次冷启动重新拉取 `moby/buildkit`):

```bash
docker buildx create --name glash-builder --driver docker-container --use
```

已存在则直接复用:

```bash
docker buildx use glash-builder
```

> 用完可清理:`docker buildx rm glash-builder`(会一并删除 BuildKit 容器)。

---

## 2. 最快路径:一条命令

```bash
git clone https://github.com/gangz1o/clash4docker.git
cd clash4docker

docker buildx build \
  --builder glash-builder \
  --platform linux/amd64 \
  --load \
  -t glash:latest .
```

构建完成后镜像就在本地:

```bash
docker images glash:latest
docker run --rm --entrypoint /app/mihomo glash:latest -v
# Mihomo Meta alpha-smart-<SHA> linux amd64 with go1.x.x ...
```

> 如果你的机器是 arm64(NAS / 树莓派 / ARM 服务器),把 `--platform linux/amd64` 换成 `--platform linux/arm64`。

---

## 3. 构建变体

镜像只包含 **Smart 内核**(vernesong/mihomo fork)。构建期唯一的内容维度是 Dashboard:

| `UI` | Dashboard | 镜像体积(amd64) |
| --- | --- | --- |
| `metacubexd`(默认) | MetaCubeX/metacubexd | ~155 MB |
| `zashboard` | Zephyruso/zashboard | ~166 MB |

### metacubexd(默认)

```bash
docker buildx build --builder glash-builder \
  --platform linux/amd64 \
  --load \
  -t glash:metacubexd .
```

### zashboard

```bash
docker buildx build --builder glash-builder \
  --build-arg UI=zashboard \
  --platform linux/amd64 \
  --load \
  -t glash:zashboard .
```

两种 Dashboard 都通过 mihomo 的 `:9090/ui` 暴露,运行时接口完全一致 —— 换 Dashboard 不需要改任何 compose 配置。

详见 [`../configuration/build-flavors.md`](../configuration/build-flavors.md)。

---

## 4. 全部 build-arg

| build-arg | 默认值 | 说明 |
| --- | --- | --- |
| `UI` | `metacubexd` | Dashboard:`metacubexd` \| `zashboard` |
| `MIHOMO_SHORT_SHA_SMART` | 空 | Smart 内核的 7 位 SHA。**留空 = 自动解析上游最新资产** |
| `MIHOMO_TAG_SMART` | `Prerelease-Alpha` | 上游 release tag |
| `MIHOMO_REPO_SMART` | `vernesong/mihomo` | 上游仓库 |
| `METACUBEXD_VERSION` | `v1.273.1` | 仅 `UI=metacubexd` 时生效 |
| `ZASHBOARD_VERSION` | `v3.29.1` | 仅 `UI=zashboard` 时生效 |
| `HTTP_PROXY` / `HTTPS_PROXY` | 无 | BuildKit 预定义变量,注入到构建步骤环境;网络受限时使用 |

> `HTTP_PROXY` / `HTTPS_PROXY` 是 BuildKit 的预定义 build-arg,无需在 `Dockerfile` 里声明 `ARG` 即可生效。

### 内核版本:自动 vs 固定

上游 `Prerelease-Alpha` 是**滚动 tag** —— 每次上游提交都会覆盖同一 tag 下的资产文件名(资产名内嵌 SHA 会变)。因此:

**默认(推荐)** —— 留空 `MIHOMO_SHORT_SHA_SMART`,构建时调 GitHub API 列出实际资产名再下载:

```bash
docker buildx build --builder glash-builder \
  --platform linux/amd64 \
  --load \
  -t glash:latest .
```

日志中会看到解析过程:

```
[download-mihomo] 查询 vernesong/mihomo@Prerelease-Alpha 的最新资产...
[download-mihomo] 解析到资产: mihomo-linux-amd64-compatible-alpha-smart-4624551.gz
```

**固定版本** —— 显式指定 SHA,跳过 API 查询(适合离线构建或 GitHub API 限流):

```bash
docker buildx build --builder glash-builder \
  --build-arg MIHOMO_SHORT_SHA_SMART=4624551 \
  --platform linux/amd64 \
  --load \
  -t glash:pinned .
```

> 未认证的 GitHub API 限流是 60 req/h。频繁构建时建议用固定 SHA。
>
> 上游更新内核后,**已构建的镜像不会自动更新** —— 需要新内核时重新构建。

详见 [`../configuration/kernel-selection.md`](../configuration/kernel-selection.md)。

---

## 5. 交互式构建脚本

仓库提供 `scripts/build-interactive.sh`,问答式引导选择参数并执行构建。零依赖,纯 Bash。

```bash
./scripts/build-interactive.sh                      # 简单模式
./scripts/build-interactive.sh --advanced           # 高级模式(展开全部 build-arg)
./scripts/build-interactive.sh --ui zashboard       # 命令行覆盖
./scripts/build-interactive.sh --dry-run            # 只打印命令,不真构建
./scripts/build-interactive.sh --help               # 全部参数
```

常用参数:

| 参数 | 说明 |
| --- | --- |
| `--ui VAL` | `metacubexd` \| `zashboard` |
| `--mihomo-short-sha-smart V` | 7 位 hex SHA;留空 = 自动解析 |
| `--platform P` | 目标平台,逗号分隔(默认 `linux/amd64`) |
| `--tag T` | 输出 tag(默认 `glash-dev:<ui>`) |
| `--load` / `--push` | 加载到本地 / 推送到 registry |
| `--user NAME` | 推送时的仓库用户名前缀 |
| `--builder NAME` | buildx 实例名(默认 `glash-builder`) |

> `--dry-run` 会输出完整命令,便于复制到 CI 或排查问题。

---

## 6. 多架构构建

目标架构由 `TARGETARCH` 自动推导,对应上游资产:

| 架构 | 上游资产 |
| --- | --- |
| `linux/amd64` | `mihomo-linux-amd64-compatible-alpha-smart-<SHA>.gz` |
| `linux/arm64` | `mihomo-linux-arm64-alpha-smart-<SHA>.gz` |
| `linux/arm/v7` | `mihomo-linux-armv7-alpha-smart-<SHA>.gz` |

### 准备 QEMU(Linux 必需)

```bash
docker run --privileged --rm tonistiigi/binfmt --install all
```

macOS / Windows 的 buildx 已内置 QEMU,无需额外操作。

### 单架构:逐个 `--load`

`--load` **不支持多架构**。想在本地同时拿到多个平台的镜像,分别构建:

```bash
for arch in linux/amd64 linux/arm64; do
  docker buildx build --builder glash-builder \
    --platform "${arch}" \
    --load \
    -t "glash:latest-${arch//\//-}" .
done
```

### 多架构:推送 manifest list

真正得到多架构镜像需要 `--push` 到 registry:

```bash
docker login registry.example.com

docker buildx build --builder glash-builder \
  --platform linux/amd64,linux/arm64,linux/arm/v7 \
  --tag registry.example.com/myaccount/glash:latest \
  --push .
```

推送后 `docker pull registry.example.com/myaccount/glash:latest` 会自动选择宿主匹配的架构。

---

## 7. 推送到自己的 registry

本仓库不发布官方镜像,需要多台机器共用时自行分发:

```bash
docker login registry.example.com

# 单架构
docker buildx build --builder glash-builder \
  --platform linux/amd64 \
  --tag registry.example.com/myaccount/glash:latest \
  --push .

# 多架构
docker buildx build --builder glash-builder \
  --platform linux/amd64,linux/arm64,linux/arm/v7 \
  --tag registry.example.com/myaccount/glash:latest \
  --push .
```

推送后把 compose 模板里的 `image:` 改成你的地址,其余不动:

```yaml
services:
  glash:
    image: registry.example.com/myaccount/glash:latest
```

国内 registry 选择与镜像代理方案见 [`./build-in-china.md`](./build-in-china.md)。

---

## 8. 用 docker compose 构建

仓库的 compose 模板都已配好,直接:

```bash
docker compose build
```

build-arg 也能从 compose 传入:

```yaml
services:
  glash:
    build:
      context: .
      args:
        UI: zashboard
```

> 模板里的 `image:` 是给「拉取已发布镜像」场景用的。走 `docker compose build` 时会覆盖为本地构建产物。

---

## 9. 验证构建产物

### 快速检查

```bash
# 内核版本
docker run --rm --entrypoint /app/mihomo glash:latest -v
# 期望:Mihomo Meta alpha-smart-<SHA> linux amd64 ...

# Dashboard 资源已落地
docker run --rm --entrypoint sh glash:latest -c 'ls /app/ui | head'

# GeoData 已打包
docker run --rm --entrypoint sh glash:latest -c 'ls /app/geodata'
# 期望:country.mmdb  geoip.metadb  geosite.dat
```

### 仓库自带测试

```bash
# 容器级冒烟(健康检查、/version、/ui/、SAFE_PATHS)
bash tests/test_container.sh glash:latest

# 内核断言(实体文件、alpha-smart 标识、KERNEL 校验)
bash tests/test_kernel.sh glash:latest
```

### 手工验证 Smart 策略组

准备一份含 `type: smart` 的配置:

```yaml
# /tmp/glash-smart/config.yaml
port: 7790
socks-port: 7791
mixed-port: 7792
allow-lan: false
mode: rule
log-level: silent
ipv6: false
external-controller: 0.0.0.0:9080
secret: 'dev-smoke'
dns: { enable: false }
proxies:
  - { name: direct, type: direct, udp: true }
proxy-groups:
  - name: "🚀 Smart"
    type: smart
    proxies: [direct]
    url: "http://www.gstatic.com/generate_204"
    interval: 300
rules:
  - IP-CIDR,127.0.0.0/8,DIRECT,no-resolve
  - MATCH,🚀 Smart
```

启动并断言:

```bash
docker run -d --rm --name glash-smoke \
  -v /tmp/glash-smart/config.yaml:/root/.config/mihomo/config.yaml:ro \
  -e SECRET=dev-smoke \
  glash:latest

curl -sH "Authorization: Bearer dev-smoke" http://127.0.0.1:9080/version
# 期望:{"meta":true,"version":"alpha-smart-<SHA>"}

curl -sH "Authorization: Bearer dev-smoke" http://127.0.0.1:9080/group/weights
# 期望:{"errors":{},"weights":{"🚀 Smart":null}}
```

---

## 10. 常见问题

<details>
<summary><b>Q: 构建报 <code>404</code>,提示找不到 alpha-smart 内核</b></summary>

多半是显式指定的 SHA 不存在。检查上游实际资产:

```bash
curl -fsSL -H "Accept: application/vnd.github+json" \
  https://api.github.com/repos/vernesong/mihomo/releases/tags/Prerelease-Alpha \
  | grep -o '"name": *"mihomo-linux-[^"]*alpha-smart[^"]*"'
```

确认后用正确的 SHA 重建,或去掉 `MIHOMO_SHORT_SHA_SMART` 让构建自动解析。

</details>

<details>
<summary><b>Q: 构建报 "未能从 GitHub API 获取资产列表"</b></summary>

GitHub API 不可达或触发限流(未认证 60 req/h)。两种解法:

```bash
# 1. 显式指定 SHA,跳过 API
docker buildx build --build-arg MIHOMO_SHORT_SHA_SMART=<sha> ...

# 2. 给构建配代理(BuildKit 会把这两个变量注入到 RUN 步骤的环境)
docker buildx build \
  --build-arg HTTP_PROXY=http://192.168.1.1:7890 \
  --build-arg HTTPS_PROXY=http://192.168.1.1:7890 ...
```

helper 脚本用 `curl` 下载,会遵循 `HTTP_PROXY` / `HTTPS_PROXY` 环境变量。

</details>

<details>
<summary><b>Q: 构建很慢 / 每次都重新下载</b></summary>

BuildKit 缓存没命中。确认用的是 `docker-container` driver 的 builder:

```bash
docker buildx ls   # glash-builder 的 DRIVER 列应为 docker-container
```

用 `default` driver(`docker` driver)缓存能力有限。若仍是冷启动,检查网络到 GitHub 的连通性。

</details>

<details>
<summary><b>Q: <code>--load</code> 报 "docker exporter does not currently support exporting manifest lists"</b></summary>

`--load` 不支持多架构。一次只构建一个平台,或改用 `--push` 到 registry。

</details>

<details>
<summary><b>Q: 容器启动报 "KERNEL='standard' 不支持"</b></summary>

当前镜像只包含 Smart 内核。删除 compose 里的 `KERNEL` 环境变量(或改为 `KERNEL=smart`)后重启。

</details>

<details>
<summary><b>Q: 想减小镜像体积</b></summary>

镜像已经只含一个内核,没有可裁剪的内核层。可选方向:

- 用 `zashboard` 之外的默认 `metacubexd`(省约 11 MB)
- 构建后用 `docker image prune -f` 清理 dangling 层
- 用 `docker save` / `docker export` 后自行裁剪(会破坏健康检查与文件权限,不推荐)

</details>

---

## 11. 清理

```bash
# 停掉 BuildKit 实例(下次构建会冷启动稍慢)
docker stop buildx_buildkit_glash-builder0

# 或彻底删除 builder(下次用 docker buildx create 重建)
docker buildx rm glash-builder

# 删除本地构建产物
docker rmi glash:latest glash:metacubexd glash:zashboard

# 清理 dangling 层
docker image prune -f
```

---

## 相关文档

| 主题 | 文档 |
| --- | --- |
| 构建指南总览(CI + 手动) | [`./build.md`](./build.md) |
| 国内网络环境构建 | [`./build-in-china.md`](./build-in-china.md) |
| 内核说明与版本解析 | [`../configuration/kernel-selection.md`](../configuration/kernel-selection.md) |
| Dashboard 选择 | [`../configuration/build-flavors.md`](../configuration/build-flavors.md) |
| 部署方式与 compose 模板 | [`../install/compose-deployment.md`](../install/compose-deployment.md) |
| 故障排查 | [`../operations/troubleshooting.md`](../operations/troubleshooting.md) |
