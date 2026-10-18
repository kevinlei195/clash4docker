# 构建指南

> 本项目有两种构建姿势:CI 构建(把镜像推到 Docker Hub)与手动构建(本地构建用于验证或自部署)。本文是一站式对照,具体国内网络方案见 [`build-in-china.md`](./build-in-china.md),PR CI 门禁与文档-only 策略见 [`ci.md`](./ci.md)。

## 概览

| 维度 | CI 构建 | 手动构建 |
| --- | --- | --- |
| 触发方式 | GitHub Actions / Gitea Actions | `docker buildx build` |
| 默认产物 | 推到 `docker.io/gangz1o/glash`,含两个内核(`FLAVORS=both`) | 本地镜像,默认同样为 both |
| 主要受众 | 维护者 — release 发版 | 贡献者 — 本地验证 / 自部署 |
| 必备 secret | `DOCKERHUB_USERNAME` / `DOCKERHUB_TOKEN` | 无 |
| 默认缓存 | GitHub Actions 用 GHA cache,Gitea 暂未启用 | 不使用(除非手动指定) |

两个姿势共用同一个 `Dockerfile`,运行时内核选择通过环境变量 `KERNEL=standard|smart`,构建期参数通过 `FLAVORS=standard|smart|both` 与 `UI=metacubexd|zashboard`。详见 [`../configuration/build-flavors.md`](../configuration/build-flavors.md) 与 [`../configuration/kernel-selection.md`](../configuration/kernel-selection.md)。

---

# Part 1 · CI 构建

## GitHub Actions

工作流分两类文件:

| 文件 | 触发 | 用途 |
| --- | --- | --- |
| `.github/workflows/ci.yml` | PR / `master` 推送 | PR 校验(changes/shell/smoke/build/ci-gate 五段) |
| `.github/workflows/docker-build.yml` | Release `published` | 构建并推送 `gangz1o/glash:latest` 与版本 tag |

### PR CI

`.github/workflows/ci.yml` 在 PR 提交或 `master` 同步时会依次跑:

1. **changes** — 用 `dorny/paths-filter` 判定本次变更是否涉及运行时(非纯文档),非运行时变更可跳过后续耗时任务
2. **shell** — `bash -n` 语法检查 + `test_mode.sh` / `test_reload.sh` / `test_modules.sh` + Alpine BusyBox `awk` 环境回归
3. **smoke** — `docker buildx` 构建 `glash-ci:amd64`(`FLAVORS=both`)与 `glash-ci-standard:amd64`(`FLAVORS=standard`),分别驱动 `test_container.sh` 与 `test_kernel_absence.sh`
4. **build** — 三平台(`linux/amd64`、`linux/arm64`、`linux/arm/v7`) × 两种 `FLAVORS`(`both`、`standard`)的 `outputs: type=cacheonly` 矩阵,验证构建可成功而不发布
5. **ci-gate** — 汇总前四段结果,作为 PR 合并门禁

矩阵维度变化:本次集成后从原本的 `project: [clash4docker, clash4docker-smart]` 改为 `flavors: [both, standard]`。

### Release 构建

发版流程:

```bash
# 1. 打 tag 推送
git tag v1.3.0
git push origin v1.3.0

# 2. 在 GitHub 上 Release 该 tag (类型选择 "Published" 才会触发)
```

`.github/workflows/docker-build.yml` 行为:

- `ref: ${{ github.event.release.tag_name }}` 检出该 tag 对应的代码
- `FLAVORS=both` 构建三个架构
- 推送两个 tag:`docker.io/gangz1o/glash:latest` + `docker.io/gangz1o/glash:<release-tag>`
- 打上 `org.opencontainers.image.version` / `source` / `flavors` 等 OCI 标签
- 启用 `cache-from: type=gha` + `cache-to: type=gha,mode=max` 跨 run 复用

### 配置 secrets

在 GitHub 仓库 **Settings → Secrets and variables → Actions** 配置:

| Secret | 说明 |
| --- | --- |
| `DOCKERHUB_USERNAME` | Docker Hub 用户名 |
| `DOCKERHUB_TOKEN` | Docker Hub 访问令牌(不是密码) |

secrets 缺失会导致 release 推送失败,但 PR CI 不会受影响。

## Gitea Actions

`.gitea/workflows/{ci,docker-build}.yml` 是 GitHub 工作流的等价镜像,默认行为一致:

- 同样的 PR 矩阵、smoke 构建、release push
- 默认 `FLAVORS=both`
- 同样推到 `docker.io/gangz1o/glash`

### 与 GitHub 的差异

| 维度 | GitHub Actions | Gitea Actions |
| --- | --- | --- |
| Action 来源 | `docker/build-push-action@v5` 等官方市场 | 同 —— 协议兼容,多数通用 action 可直接复用 |
| 缓存 | `cache-from: type=gha` + `cache-to: type=gha,mode=max` | 暂未启用。Gitea 实例若提供 registry,可在 `.gitea/workflows/docker-build.yml` 加 `cache-from: type=registry,ref=<your-registry>/cache` |
| 上下文变量 | `github.server_url`、`github.repository` | `gitea.server_url`、`gitea.repository` —— label 中已替换 |
| Secrets 命名 | `DOCKERHUB_USERNAME`、`DOCKERHUB_TOKEN`(一致) | 同名,需在 Gitea 仓库的 secrets 里配置 |

### 配置 secrets

Gitea 仓库 **Settings → Secrets** 添加 `DOCKERHUB_USERNAME` 与 `DOCKERHUB_TOKEN`,命名与取值与 GitHub 一致。

## 升级清单(维护者)

下面变更会触发 CI,但建议在 release 流程里一并处理:

| 升级项 | 涉及的文件/参数 |
| --- | --- |
| 标准内核版本(MetaCubeX/mihomo) | `Dockerfile` 改 `ARG MIHOMO_VERSION=vX.Y.Z` |
| Smart 内核 SHA(vernesong/mihomo) | `Dockerfile` 改 `ARG MIHOMO_SHORT_SHA_SMART=<sha>`;若 release 通道变了再调 `MIHOMO_TAG_SMART` |
| MetacubexD Dashboard | `Dockerfile` 改 `ARG METACUBEXD_VERSION=vX.Y.Z`(`UI=metacubexd` 时生效) |
| zashboard Dashboard | `Dockerfile` 改 `ARG ZASHBOARD_VERSION=vX.Y.Z`(`UI=zashboard` 时生效) |
| buildx action 版本 | `.github/workflows/*.yml`、`.gitea/workflows/*.yml` 中的 `actions/checkout` / `docker/build-push-action` 版本号 |
| alpine 基础镜像 | `Dockerfile` 两处 `FROM alpine:X.Y`(builder 与 runtime),保持一致 |

升级后建议跑一次本地 `docker buildx build --build-arg FLAVORS=both --load .` 把 `tests/test_container.sh` 与 `tests/test_kernel*.sh` 跑一遍再合并。

---

# Part 2 · 手动构建

## 前置条件

- Docker Engine **20.10+**(buildx 内置版本不低于 v0.10)
- 自愿:在 Linux 上安装 `qemu-user-static` 以支持跨平台构建(在 macOS/Windows 上 buildx 已包含)
- 确认 buildx 列表里有一个 `docker-container` driver 的实例供缓存使用

```bash
docker --version
docker buildx version

# 不存在则创建一个(共用本地 docker daemon)
docker buildx create --name glash-builder --driver docker-container --use
```

`glash-builder` 名字为自定义;通过 `--driver docker-container`,后续的 `docker buildx build` 会自动启动一个 BuildKit 容器 `buildx_buildkit_glash-builder0` 并常驻,跨命令复用构建缓存。

> 想清理时:`docker buildx rm glash-builder` 会一并删除该容器。

## 标准构建(本地)

### 1. 默认 —— 双内核 both

```bash
cd /path/to/clash4docker
docker buildx build \
  --builder glash-builder \
  --build-arg FLAVORS=both \
  --platform linux/amd64 \
  --load \
  -t glash-dev:both .
```

构建产物:

- `:both` tag 镜像含 `/opt/mihomo/standard/mihomo` 与 `/opt/mihomo/smart/mihomo`
- 启动时由 `KERNEL` 环境变量决定使用哪一个
- 默认 7790/7791/7792 端口(可用 `HTTP_PORT` 等环境变量覆写)

### 2. 单内核 —— 缩减体积

```bash
# 仅 standard
docker buildx build --builder glash-builder \
  --build-arg FLAVORS=standard \
  --platform linux/amd64 \
  --load \
  -t glash-dev:standard .

# 仅 smart
docker buildx build --builder glash-builder \
  --build-arg FLAVORS=smart \
  --platform linux/amd64 \
  --load \
  -t glash-dev:smart .
```

这些镜像里 `/opt/mihomo/{standard,smart}/` 中不存在的那个目录为空。如果尝试设了不存在的 `KERNEL`,容器启动时会立即报错:

```
[ERROR] 当前镜像未包含 Smart 内核。请重新构建镜像时加入 FLAVORS=smart 或 FLAVORS=both。
```

### 3. 通过 docker compose build

`docker-compose.yml` 已配好,直接:

```bash
docker compose build
```

等价的 build-arg 也能从 compose 传入:

```yaml
services:
  glash:
    build:
      context: .
      args:
        FLAVORS: standard
```

### 3.5 zashboard 镜像(自建,官方不发布)

官方 `gangz1o/glash:latest` 只打包 metacubexd。需要 zashboard 走自建:

```bash
docker buildx build --builder glash-builder \
  --build-arg FLAVORS=both \
  --build-arg UI=zashboard \
  --platform linux/amd64 \
  --load \
  -t my/glash:zashboard .
```

镜像内 zashboard 自动展平到 `/app/ui/`,mihomo 通过 `:9090/ui` 暴露。运行时不需要任何额外配置,默认行为与 metacubexd 镜像完全一致。

### 4. 跨平台构建

```bash
# 需要 QEMU(在 Linux 上)
docker run --privileged --rm tonistiigi/binfmt --install all

# 多平台并导出到镜像(同号多 tag)
docker buildx build --builder glash-builder \
  --build-arg FLAVORS=both \
  --platform linux/amd64,linux/arm64 \
  --tag glash-dev:both-multi \
  --load .
# 注意:--load 不支持跨平台;要真正得到多平台镜像得用 --push 到 registry
# 或者一次性只 load 一个平台
```

如果想在本地同时得到 amd64 与 arm64 镜像,跑两遍分别 `--load` 即可。

### 5. 升级 Smart 内核 SHA 的本地步骤

```bash
# 上游 vernesong/mihomo release 拿到新 SHA
NEW_SHA=abcdef0

# 改 Dockerfile
sed -i "s/MIHOMO_SHORT_SHA_SMART=.*/MIHOMO_SHORT_SHA_SMART=${NEW_SHA}/" Dockerfile

# 构建并冒烟
docker buildx build --builder glash-builder \
  --build-arg FLAVORS=smart --load -t glash-dev:smart .

# 验证 Smart 内核确已在镜像里
docker run --rm glash-dev:smart /opt/mihomo/smart/mihomo -v
# 期望输出包含 alpha-smart-<新 SHA>

# 用 smart-only 配置做一次端到端(见下文"端到端验证")
```

## 受限网络下构建

国内网络环境的方案 A-E(registry-mirrors / BuildKit 代理 / 镜像代理 / 预下载 / SSH over Cloudflare)在 [`build-in-china.md`](./build-in-china.md) 详述。其中与本项目相关的几点:

- 方案 C 中 `sed 's|https://github.com|https://gh-proxy.com/https://github.com|g'` 的写法在集成后**仍然适用**,因为所有 GitHub URL 都来源于 helper 脚本中的 `https://github.com/...`。
- 方案 D 离线构建需要先用 `docker save` 或手动 curl 把 `mihomo` / `compressed-dist.tgz` / `geoip.metadb` / `geosite.dat` / `country.mmdb` 准备到镜像可达的位置。helper 脚本是为可联网环境设计的,完全离线时建议自行解包或挂载 bind。
- 方案 A 中 `alpine:3.19` 的镜像源覆盖同样有效。

## 端到端验证(已构建镜像怎么测)

构建完镜像后,推荐依次跑下面的测试。无需订阅、无需真实节点。

### 单元级 shell 测试(不需要 docker)

```bash
bash tests/test_mode.sh
bash tests/test_reload.sh
bash tests/test_modules.sh
```

### 容器级冒烟(需要 docker)

```bash
# 单次冒烟:需要 buildx 已构建的镜像
bash tests/test_container.sh glash-dev:both

# KERNEL 切换用例:default = standard;KERNEL=smart 后软链应切到 smart
bash tests/test_kernel.sh glash-dev:both

# 缺位报错用例:仅 standard 单内核镜像应拒绝 KERNEL=smart
bash tests/test_kernel_absence.sh glash-dev:standard-only
```

### 手工验证(KERNEL + smart-only 配置)

1. 准备 smart-only 配置到 `/tmp/glash-smart/config.yaml`:

   ```yaml
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

2. 用 `:both` 镜像 + `KERNEL=smart` 启动:

   ```bash
   docker run -d --rm --name glash-smoke-smart \
     -v /tmp/glash-smart/config.yaml:/root/.config/mihomo/config.yaml:ro \
     -e KERNEL=smart -e SECRET=dev-smoke \
     glash-dev:both
   ```

3. 断言确为 Smart 内核:

   ```bash
   curl -sH "Authorization: Bearer dev-smoke" http://127.0.0.1:9080/version
   # 期望:{"meta":true,"version":"alpha-smart-<SHA>"}

   curl -sH "Authorization: Bearer dev-smoke" http://127.0.0.1:9080/group/weights
   # 期望:{"errors":{},"weights":{"🚀 Smart":null}}

   # 反向:同样的 smart-only 配置,但 KERNEL=standard,容器应退出并打 "proxy group[0]: unsupported type: smart"
   ```

## 清理

构建会创建 buildkit 容器与本地镜像:

```bash
# 停掉 BuildKit 实例(下次构建会冷启动稍慢)
docker stop buildx_buildkit_glash-builder0

# 或彻底删除 builder(下次用 `docker buildx create` 重建)
docker buildx rm glash-builder

# 删除本地构建产物
docker rmi glash-dev:both glash-dev:standard glash-dev:smart

# 可选:清理 dangling 层
docker image prune -f
```

---

# 故障排查(常见问题)

<details>
<summary><b>Q: 构建时报 <code>"/build/mihomo-smart": not found</code></b></summary>

`FLAVORS=standard` 或 `=smart` 时触发了 `COPY --from=builder /build/mihomo-<flavor>` 源路径缺失。本次集成已在 `Dockerfile` builder 阶段预创建两个空目录 (`/build/mihomo-standard` 和 `/build/mihomo-smart`),使单 Flavor 构建合法。确认本地 `Dockerfile` 第 33-34 行有:

```dockerfile
RUN mkdir -p /build/mihomo-standard /build/mihomo-smart
```

</details>

<details>
<summary><b>Q: 容器启动后 9090 端口无响应,但日志显示 mihomo 已启动</b></summary>

通常是另一个 `clash-glash` 实例占用了 7890/9090。冒烟测试时换用 `HTTP_PORT=7790` `SOCKS_PORT=7791` `MIXED_PORT=7792` 或直接改示例配置到非冲突端口。`external-controller`(`9090`)需要改 `config.yaml`。

</details>

<details>
<summary><b>Q: KERNEL=smart 时容器立即退出并打印 "proxy group[0]: unsupported type: smart"</b></summary>

这是 standard 内核拒绝 `type: smart` 策略组,意味着软链尚未切到 Smart 内核(或者镜像只打了 standard)。检查:

```bash
docker exec <容器> readlink -f /app/mihomo
```

期望 `/opt/mihomo/smart/mihomo`。否则确认镜像确实是 `FLAVORS=smart` 或 `=both` 构建的。本项目所有 build-arg 默认 `FLAVORS=both`,CI 产物也使用 both。

</details>

<details>
<summary><b>Q: cross-build 时 cache 命中率低,build 慢</b></summary>

`docker-container` driver 默认每次新建独立 BuildKit 容器会重新拉取 `moby/buildkit:buildx-stable-1`。建议显式命名(`--name glash-builder`)并在 CI 中复用同一 builder 名。对于 GitHub Actions,`cache-from: type=gha` + `cache-to: type=gha,mode=max` 已经把镜像层 cache 推到 GH,跨 run 复用。

</details>

<details>
<summary><b>Q: <code>test_container.sh</code> 跑得很慢</b></summary>

默认健康检查超时 90 秒。Smart 内核带 `type: smart` 策略组时,首次初始化可能需要 5-10 秒(group 权重的样本测速)。把 `HEALTH_TIMEOUT_SECONDS=180` 传过去即可。

</details>

## 交互式构建脚本

仓库提供 `scripts/build-interactive.sh` 通过问答引导选择 build-arg,最后生成并执行 `docker buildx build`。零依赖,纯 Bash,在终端里直接跑即可。

```bash
./scripts/build-interactive.sh                       # 简单模式:问 FLAVORS / UI / tag / platform / 加载方式
./scripts/build-interactive.sh --advanced            # 高级模式:展开全部 7 个 build-arg
./scripts/build-interactive.sh --dry-run             # 只打印命令,不真构建
./scripts/build-interactive.sh --flavors smart --ui zashboard --tag my:zas
./scripts/build-interactive.sh --push --user gangz1o  # 推送到 Docker Hub
./scripts/build-interactive.sh --platform linux/arm64,linux/amd64
./scripts/build-interactive.sh --help               # 全部参数说明
```

特性:

- 复用或自动创建 `glash-builder`(docker-container driver)以获得 BuildKit 缓存
- 命令行参数可与交互混用;非 TTY 场景下走默认或命令行覆盖
- `--dry-run` 输出完整 `docker buildx build` 命令,便于 CI / 调试
- 校验:FLAVORS 取值、UI 取值、平台、tag 字符、SemVer、SHA 格式

`tests/test_build_interactive.sh` 覆盖 14 条断言(帮助文本、覆盖语义、错误校验、tag 拼接、多平台等),CI shell job 会自动跑。

## 相关文档

| 主题 | 文档 |
| --- | --- |
| 构建参数详情 | [`../configuration/build-flavors.md`](../configuration/build-flavors.md) |
| 运行时内核选择 | [`../configuration/kernel-selection.md`](../configuration/kernel-selection.md) |
| 环境变量完整参考 | [`../configuration/environment-variables.md`](../configuration/environment-variables.md) |
| 国内网络方案 | [`./build-in-china.md`](./build-in-china.md) |
| PR CI 门禁 | [`./ci.md`](./ci.md) |
| 本地开发步骤 | [`./local-development.md`](./local-development.md) |
| 运行时结构 | [`./runtime-structure.md`](./runtime-structure.md) |
