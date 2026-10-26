# 构建指南

> 本项目不发布官方镜像产物。本仓库提供 CI 校验(只构建、不推送)与手动构建(本地或自有 registry)两条路径。本文是一站式对照,具体国内网络方案见 [`build-in-china.md`](./build-in-china.md),PR CI 门禁与文档-only 策略见 [`ci.md`](./ci.md)。

## 概览

| 维度 | CI 校验 | 手动构建 |
| --- | --- | --- |
| 触发方式 | GitHub Actions / Gitea Actions | `docker buildx build` |
| 默认产物 | 无(仅验证构建可成功,不产出可分发镜像) | 本地镜像,默认同样为 both |
| 主要受众 | 贡献者 — PR 合并门禁 | 所有人 — 自部署 / 自有 registry 分发 |
| 必备 secret | 无 | 无(推到私有 registry 时需自行配置登录) |
| 默认缓存 | GitHub Actions 用 GHA cache,Gitea 暂未启用 | 不使用(除非手动指定) |

两条路径共用同一个 `Dockerfile`。镜像只包含 Smart 内核(vernesong/mihomo Smart fork),构建期参数只有 `UI=metacubexd|zashboard` 与内核版本相关参数(`MIHOMO_SHORT_SHA_SMART` 等)。详见 [`../configuration/build-flavors.md`](../configuration/build-flavors.md) 与 [`../configuration/kernel-selection.md`](../configuration/kernel-selection.md)。

> **仓库不包含任何镜像发布路径**:没有 Release 触发的构建推送 workflow,也没有 registry 登录凭据。需要镜像产物时,用下面的手动构建流程自行构建并推送到你控制的 registry。

---

# Part 1 · CI 校验(只构建,不发布)

## GitHub Actions

仓库只有一个 workflow:

| 文件 | 触发 | 用途 |
| --- | --- | --- |
| `.github/workflows/ci.yml` | PR / `master` 推送 | PR 校验(changes/shell/smoke/build/ci-gate 五段) |

### PR CI

`.github/workflows/ci.yml` 在 PR 提交或 `master` 同步时会依次跑:

1. **changes** — 用 `dorny/paths-filter` 判定本次变更是否涉及运行时(非纯文档),非运行时变更可跳过后续耗时任务
2. **shell** — `bash -n` 语法检查 + `test_mode.sh` / `test_reload.sh` / `test_modules.sh` + Alpine BusyBox `awk` 环境回归
3. **smoke** — `docker buildx` 构建 `glash-ci:amd64`,驱动 `test_container.sh` 与 `test_kernel.sh`
4. **kernel-sha** — 调 GitHub API 校验上游 Smart 内核资产可解析且版本标识含 `alpha-smart`
5. **build** — 三平台(`linux/amd64`、`linux/arm64`、`linux/arm/v7`)的 `outputs: type=cacheonly` 矩阵,验证构建可成功
6. **ci-gate** — 汇总前五段结果,作为 PR 合并门禁

### 发布边界

该 workflow 使用只读仓库权限,不包含 `docker/login-action`、registry 凭据或 `push: true` 步骤。它只用于验证,不产出可分发镜像。

镜像分发由使用者自行完成,见 [Part 2 · 手动构建](#part-2--手动构建)。

## Gitea Actions

`.gitea/workflows/ci.yml` 是 GitHub 工作流的等价镜像,默认行为一致:

- 同样的 PR 矩阵、smoke 构建与内核资产校验
- 同样只构建、不推送

### 与 GitHub 的差异

| 维度 | GitHub Actions | Gitea Actions |
| --- | --- | --- |
| Action 来源 | `docker/build-push-action@v5` 等官方市场 | 同 —— 协议兼容,多数通用 action 可直接复用 |
| 缓存 | `cache-from: type=gha` + `cache-to: type=gha,mode=max` | 暂未启用。Gitea 实例若提供 registry,可在 `.gitea/workflows/ci.yml` 加 `cache-from: type=registry,ref=<your-registry>/cache` |
| 上下文变量 | `github.server_url`、`github.repository` | `gitea.server_url`、`gitea.repository` —— label 中已替换 |

## 升级清单(维护者)

下面变更会触发 CI,建议在合并前一并处理:

| 升级项 | 涉及的文件/参数 |
| --- | --- |
| Smart 内核版本 | 留空 `MIHOMO_SHORT_SHA_SMART` 即自动跟随上游最新;需要固定版本时改 `Dockerfile` 的 `ARG MIHOMO_SHORT_SHA_SMART=<sha>` |
| Smart 内核通道 | `Dockerfile` 改 `ARG MIHOMO_TAG_SMART=<tag>` 或 `ARG MIHOMO_REPO_SMART=<owner/repo>` |
| MetacubexD Dashboard | `Dockerfile` 改 `ARG METACUBEXD_VERSION=vX.Y.Z`(`UI=metacubexd` 时生效) |
| zashboard Dashboard | `Dockerfile` 改 `ARG ZASHBOARD_VERSION=vX.Y.Z`(`UI=zashboard` 时生效) |
| buildx action 版本 | `.github/workflows/*.yml`、`.gitea/workflows/*.yml` 中的 `actions/checkout` / `docker/build-push-action` 版本号 |
| alpine 基础镜像 | `Dockerfile` 两处 `FROM alpine:X.Y`(builder 与 runtime),保持一致 |

升级后建议跑一次本地 `docker buildx build --load .` 把 `tests/test_container.sh` 与 `tests/test_kernel.sh` 跑一遍再合并。

> 上游 `Prerelease-Alpha` 是滚动 tag,资产名内嵌的 SHA 会随上游提交变化。`kernel-sha` job 会在 PR 时校验资产可解析,避免静默失效。

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

### 1. 默认 —— Smart 内核 + metacubexd

```bash
cd /path/to/clash4docker
docker buildx build \
  --builder glash-builder \
  --platform linux/amd64 \
  --load \
  -t glash-dev:default .
```

构建产物:

- `/app/mihomo` 是 Smart 内核实体文件(vernesong/mihomo Smart fork)
- 启动即使用该内核,无需 `KERNEL` 配置
- 默认 7890/7891/7892 端口(可用 `HTTP_PORT` 等环境变量覆写)

### 2. 切换 Dashboard

```bash
docker buildx build --builder glash-builder \
  --build-arg UI=zashboard \
  --platform linux/amd64 \
  --load \
  -t glash-dev:zashboard .
```

### 3. 固定内核版本

默认留空 `MIHOMO_SHORT_SHA_SMART` 时,构建会调 GitHub API 解析上游最新资产。需要固定版本(离线构建或 API 限流场景):

```bash
docker buildx build --builder glash-builder \
  --build-arg MIHOMO_SHORT_SHA_SMART=4624551 \
  --platform linux/amd64 \
  --load \
  -t glash-dev:pinned .
```

### 4. 通过 docker compose build

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
        UI: zashboard
```

### 4.2 分发到你自己的 registry

本仓库不发布官方镜像。若需要多台机器共用同一份镜像,自行构建后推送到你控制的 registry:

```bash
# 登录(按你的 registry 替换)
docker login registry.example.com

# 单架构推送
docker buildx build --builder glash-builder \
  --platform linux/amd64 \
  --tag registry.example.com/myaccount/glash:latest \
  --push .

# 多架构推送(需要 QEMU)
docker buildx build --builder glash-builder \
  --platform linux/amd64,linux/arm64,linux/arm/v7 \
  --tag registry.example.com/myaccount/glash:latest \
  --push .
```

推送后把 compose 模板里的 `image:` 改成你的镜像地址即可,其余配置不动:

```yaml
services:
  glash:
    image: registry.example.com/myaccount/glash:latest
```

国内网络环境下的 registry 选择见 [`build-in-china.md`](./build-in-china.md) 的"镜像推送"段。

### 4.3 跨平台构建

```bash
# 需要 QEMU(在 Linux 上)
docker run --privileged --rm tonistiigi/binfmt --install all

# 多平台并导出到镜像(同号多 tag)
docker buildx build --builder glash-builder \
  --platform linux/amd64,linux/arm64 \
  --tag glash-dev:multi \
  --load .
# 注意:--load 不支持跨平台;要真正得到多平台镜像得用 --push 到 registry
# 或者一次性只 load 一个平台
```

如果想在本地同时得到 amd64 与 arm64 镜像,跑两遍分别 `--load` 即可。

### 4.4 升级 Smart 内核的本地步骤

```bash
# 上游 vernesong/mihomo release 拿到新 SHA(资产名内嵌)
NEW_SHA=abcdef0

# 改 Dockerfile
sed -i "s/MIHOMO_SHORT_SHA_SMART=.*/MIHOMO_SHORT_SHA_SMART=${NEW_SHA}/" Dockerfile

# 构建并冒烟
docker buildx build --builder glash-builder --load -t glash-dev:pinned .

# 验证 Smart 内核确已在镜像里
docker run --rm glash-dev:pinned /app/mihomo -v
# 期望输出包含 alpha-smart-<新 SHA>
```

> 不改 Dockerfile 也可以 —— 留空 `MIHOMO_SHORT_SHA_SMART` 时构建会自动解析上游最新资产。

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
bash tests/test_container.sh glash-dev:default

# 内核断言:实体文件 + alpha-smart 版本标识 + KERNEL 校验
bash tests/test_kernel.sh glash-dev:default
```

### 手工验证(smart 策略组配置)

1. 准备含 `type: smart` 的配置到 `/tmp/glash-smart/config.yaml`:

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

2. 启动:

   ```bash
   docker run -d --rm --name glash-smoke-smart \
     -v /tmp/glash-smart/config.yaml:/root/.config/mihomo/config.yaml:ro \
     -e SECRET=dev-smoke \
     glash-dev:default
   ```

3. 断言确为 Smart 内核:

   ```bash
   curl -sH "Authorization: Bearer dev-smoke" http://127.0.0.1:9080/version
   # 期望:{"meta":true,"version":"alpha-smart-<SHA>"}

   curl -sH "Authorization: Bearer dev-smoke" http://127.0.0.1:9080/group/weights
   # 期望:{"errors":{},"weights":{"🚀 Smart":null}}
   ```

## 清理

构建会创建 buildkit 容器与本地镜像:

```bash
# 停掉 BuildKit 实例(下次构建会冷启动稍慢)
docker stop buildx_buildkit_glash-builder0

# 或彻底删除 builder(下次用 `docker buildx create` 重建)
docker buildx rm glash-builder

# 删除本地构建产物
docker rmi glash-dev:default glash-dev:zashboard

# 可选:清理 dangling 层
docker image prune -f
```

---

# 故障排查(常见问题)

<details>
<summary><b>Q: 构建时报上游资产 404 / 找不到 alpha-smart 内核</b></summary>

上游 `vernesong/mihomo` 的 `Prerelease-Alpha` 是滚动 tag,资产名内嵌的 SHA 会随上游提交变化。构建时留空 `MIHOMO_SHORT_SHA_SMART` 会自动调 GitHub API 解析最新资产,通常不会出这个问题。

若仍失败:

1. 确认脚本能列出资产 —— 直接跑 `sh docker/build-helpers/download-mihomo.sh amd64 vernesong/mihomo Prerelease-Alpha "" /tmp/kc`,失败时会打印可用资产列表
2. GitHub API 未认证限流是 60 req/h,可能触发。可改用显式 SHA:`--build-arg MIHOMO_SHORT_SHA_SMART=<sha>`,跳过 API 查询
3. 确认 `MIHOMO_TAG_SMART` 指向的 release 仍包含 `alpha-smart` 资产

</details>

<details>
<summary><b>Q: 容器启动后 9090 端口无响应,但日志显示 mihomo 已启动</b></summary>

通常是另一个 `glash` 实例占用了 7890/9090。冒烟测试时换用 `HTTP_PORT=7790` `SOCKS_PORT=7791` `MIXED_PORT=7792` 或直接改示例配置到非冲突端口。`external-controller`(`9090`)需要改 `config.yaml`。

</details>

<details>
<summary><b>Q: 容器启动报 "proxy group[0]: unsupported type: smart"</b></summary>

当前镜像只包含 Smart 内核,正常情况下不应出现此错误。检查:

```bash
docker exec <容器> /app/mihomo -v
```

期望输出含 `alpha-smart`。若显示标准版本,说明用的是旧镜像 —— 重新构建即可。

</details>

<details>
<summary><b>Q: 启动报 "KERNEL='standard' 不支持(当前镜像只包含 smart 内核)"</b></summary>

当前镜像只包含 Smart 内核。删除 compose 里的 `KERNEL` 环境变量(或改为 `KERNEL=smart`)后重启容器。

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
./scripts/build-interactive.sh                       # 简单模式:问 UI / tag / platform / 加载方式
./scripts/build-interactive.sh --advanced            # 高级模式:展开全部 build-arg
./scripts/build-interactive.sh --dry-run             # 只打印命令,不真构建
./scripts/build-interactive.sh --ui zashboard --tag my:zas
./scripts/build-interactive.sh --push --user myaccount      # 推送到自己的 registry
./scripts/build-interactive.sh --platform linux/arm64,linux/amd64
./scripts/build-interactive.sh --help               # 全部参数说明
```

特性:

- 复用或自动创建 `glash-builder`(docker-container driver)以获得 BuildKit 缓存
- 命令行参数可与交互混用;非 TTY 场景下走默认或命令行覆盖
- `--dry-run` 输出完整 `docker buildx build` 命令,便于 CI / 调试
- 校验:UI 取值、平台、tag 字符、SemVer、SHA 格式

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
