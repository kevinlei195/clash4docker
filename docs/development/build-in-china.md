# 国内构建指南

> 国内网络环境下构建 Clash for Docker(glash) 的镜像、推送镜像、以及推送到 Gitea 等场景的注意事项与解决方案。

## 概览

国内网络环境下面临三类连通性问题:

1. **GitHub 资源下载** — `Dockerfile` 在 builder 阶段通过 `docker/build-helpers/download-*.sh` 从 `github.com` 下载 Mihomo 内核、MetacubexD Dashboard 和 GeoData
2. **Docker 基础镜像拉取** — `alpine:3.19` 默认从 `docker.io` 拉取
3. **镜像推送与 Git 推送** — Docker Hub 推送、Gitea SSH 等连通性

本文提供多种方案,**不修改源码**,全部通过环境变量、配置或临时文件解决。建议先跳到下一节"快速选择",根据自身场景选择方案。

## 快速选择

| 场景 | 推荐方案 |
| --- | --- |
| 已部署本地 HTTP 代理(Clash/SS/Surge 等) | 方案 B:BuildKit 代理 |
| 无代理,网络能偶尔访问 GitHub 镜像站 | 方案 C:GitHub 镜像代理 |
| 完全离线/无法访问任何 GitHub 资源 | 方案 D:预下载 + 临时 Dockerfile |
| Docker pull 卡在 `alpine:3.19` | 方案 A:registry-mirrors |
| 推送到 Docker Hub 受限 | 推送到国内 registry(参见"镜像推送"段) |
| Git 推送到 Gitea 受限 | 方案 E:SSH over Cloudflare Tunnel |

---

## 方案 A:配置 registry-mirrors

解决 `docker pull alpine:3.19` 卡死或失败的问题。

### Linux(`/etc/docker/daemon.json`)

```json
{
  "registry-mirrors": [
    "https://docker.mirrors.ustc.edu.cn",
    "https://hub-mirror.c.163.com",
    "https://mirror.ccs.tencentyun.com",
    "https://docker.m.daocloud.io"
  ]
}
```

可选镜像源:

| 镜像源 | 地址 |
| --- | --- |
| 中科大 | `https://docker.mirrors.ustc.edu.cn` |
| 网易 | `https://hub-mirror.c.163.com` |
| 腾讯云 | `https://mirror.ccs.tencentyun.com` |
| DaoCloud | `https://docker.m.daocloud.io` |
| 阿里云(需账号) | `https://<your-id>.mirror.aliyuncs.com` |

重启生效:

```bash
sudo systemctl restart docker
```

### macOS / Windows(Docker Desktop)

Settings → Docker Engine,在 JSON 中加入 `registry-mirrors`,Apply & Restart。

### 验证

```bash
docker info 2>&1 | grep -A5 "Registry Mirrors"
docker pull alpine:3.19
```

## 方案 B:BuildKit 代理(推荐)

将本地 HTTP 代理注入到构建阶段,让 `apk add`、`curl`、`git` 等所有命令都通过代理访问外网。

### 准备工作

确认本地代理服务可用,记下监听地址,例如:

- `http://127.0.0.1:7890`(Clash 默认)
- `http://127.0.0.1:7891`(SOCKS5,需 HTTP 协议入口)
- 局域网代理:`http://192.168.1.10:7890`

代理必须支持 **HTTPS CONNECT 隧道**,否则 `https://github.com` 仍会失败。

### 构建命令

```bash
docker buildx build \
  --build-arg "HTTP_PROXY=http://192.168.1.10:7890" \
  --build-arg "HTTPS_PROXY=http://192.168.1.10:7890" \
  --build-arg "NO_PROXY=localhost,127.0.0.1" \
  --network=host \
  -t clash4docker-local \
  --load \
  .
```

> `--network=host` 让容器使用宿主机网络,部分环境需要管理员权限;不使用时,代理 IP 应从容器视角可达(如 `host.docker.internal`)。

### 同时加速 Docker Hub 拉取

BuildKit 会通过 Docker 守护进程拉取基础镜像,镜像加速仍需配置 `registry-mirrors`(方案 A)。两者搭配使用效果最佳。

### 注意事项

- 镜像构建完成后,**这些代理变量会写入镜像层历史**(可用 `docker history` 查看)。如不希望泄露代理地址,请在最终 `Dockerfile` 的运行时阶段显式 `ENV` 重置
- CI 环境(参见下面"CI 环境")无需此方案

## 方案 C:GitHub 镜像代理

针对 GitHub 资源(`Dockerfile` 中 5 个 `https://github.com/...` 下载点),通过 URL 替换走镜像代理。

### 主流镜像代理

| 镜像代理 | 域名 | 模板 |
| --- | --- | --- |
| gh-proxy.com | `https://gh-proxy.com` | `https://gh-proxy.com/<原 URL>` |
| ghfast.top | `https://ghfast.top` | `https://ghfast.top/<原 URL>` |
| mirror.ghproxy.com | `https://mirror.ghproxy.com` | `https://mirror.ghproxy.com/<原 URL>` |

> ⚠️ 第三方镜像代理不在项目控制下,稳定性与可信度请自行评估,生产构建建议自建代理或预下载。

### 临时方案:不修改 Dockerfile,通过 BuildKit 注入

```bash
docker buildx build \
  --build-arg "GH_PROXY=https://gh-proxy.com" \
  -t clash4docker-local \
  --load \
  .
```

但 `Dockerfile` 内 `curl -fsSL` 使用的是写死的 `https://github.com/...`,**直接传 `GH_PROXY` 无效**,需要配合下面的 sed 临时替换。

### 推荐做法:临时修改 Dockerfile 输出

```bash
# 生成临时 Dockerfile,用 sed 把 github.com URL 替换成镜像代理
sed 's|https://github.com|https://gh-proxy.com/https://github.com|g' Dockerfile > Dockerfile.cn

docker buildx build \
  -f Dockerfile.cn \
  -t clash4docker-local \
  --load \
  .

# 构建完成,清理
rm -f Dockerfile.cn
```

> 该方案只在本地复制文件修改,不动项目源码。

## 方案 D:预下载 + 临时 Dockerfile(完全离线)

适用于**完全无法访问 GitHub** 的环境(本次构建测试即采用此方案)。

### 步骤

```bash
# 1. 创建临时构建目录
mkdir -p /tmp/glash-build && cd /tmp/glash-build

# 2. 通过任意可用通道下载 5 个资源(此处使用镜像代理示例)
for url in \
  "https://gh-proxy.com/https://github.com/MetaCubeX/mihomo/releases/download/v1.19.31/mihomo-linux-amd64-compatible-v1.19.31.gz" \
  "https://gh-proxy.com/https://github.com/MetaCubeX/metacubexd/releases/download/v1.273.1/compressed-dist.tgz" \
  "https://gh-proxy.com/https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/geoip.metadb" \
  "https://gh-proxy.com/https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/geosite.dat" \
  "https://gh-proxy.com/https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/country.mmdb"; do
  curl --max-time 60 -fsSL "$url" -O
done

# 3. 解压 mihomo(供 COPY 直接使用二进制)
gunzip -k mihomo-linux-amd64-compatible-v1.19.31.gz
chmod +x mihomo-linux-amd64-compatible-v1.19.31

# 4. 复制项目源码
cp /path/to/clash4docker/start.sh .
cp -r /path/to/clash4docker/lib .

# 5. 创建临时 Dockerfile(把 curl 下载改为 COPY)
cat > Dockerfile.local <<'EOF'
FROM --platform=$BUILDPLATFORM alpine:3.19 AS builder
RUN apk add --no-cache curl unzip ca-certificates
WORKDIR /build

# 本地缓存替代下载
COPY mihomo-linux-amd64-compatible-v1.19.31 /build/mihomo
COPY compressed-dist.tgz /build/dashboard.tgz
COPY geoip.metadb /build/geodata-tmp-geoip.metadb
COPY geosite.dat /build/geodata-tmp-geosite.dat
COPY country.mmdb /build/geodata-tmp-country.mmdb

RUN mkdir -p /build/ui /build/geodata && \
    tar -xzf /build/dashboard.tgz -C /build/ui && \
    rm /build/dashboard.tgz && \
    mv /build/geodata-tmp-geoip.metadb /build/geodata/geoip.metadb && \
    mv /build/geodata-tmp-geosite.dat /build/geodata/geosite.dat && \
    mv /build/geodata-tmp-country.mmdb /build/geodata/country.mmdb

FROM alpine:3.19
RUN apk add --no-cache ca-certificates tzdata bash tini curl sed grep flock && \
    mkdir -p /root/.config/mihomo /app/ui /app/geodata /var/log
COPY --from=builder /build/mihomo /app/mihomo
COPY --from=builder /build/ui /app/ui
COPY --from=builder /build/geodata /app/geodata
COPY start.sh /app/start.sh
COPY lib /app/lib
RUN chmod +x /app/start.sh /app/lib/glash/*.sh
ENV TZ=Asia/Shanghai
ENV MIHOMO_CONFIG_DIR=/root/.config/mihomo
EXPOSE 7890 7891 7892 9090
VOLUME ["/root/.config/mihomo"]
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD /bin/sh -c "if [ -n \"$SECRET\" ]; then wget -q --header=\"Authorization: Bearer $SECRET\" -O /dev/null http://127.0.0.1:9090/version; else wget -q -O /dev/null http://127.0.0.1:9090/version; fi || exit 1"
ENTRYPOINT ["/sbin/tini", "--"]
CMD ["/app/start.sh"]
EOF

# 6. 构建
docker buildx build -f Dockerfile.local -t clash4docker-local --load .

# 7. 清理
rm -f Dockerfile.local
```

ARM64 / ARMv7 需调整 mihomo 文件名,具体见 [`Dockerfile`](../../Dockerfile) 第 19-28 行的 `case` 分支。

---

## CI 环境构建(GitHub Actions)

GitHub 托管的 runner **位于境外**,通常不需要任何代理,GitHub、Docker Hub 访问均正常。

`.github/workflows/ci.yml` 在 Pull Request 上自动运行:

- Shell 测试(`ubuntu-latest`)
- AMD64 容器烟雾测试
- 多架构构建验证(`linux/amd64`、`linux/arm64`、`linux/arm/v7`)

`.github/workflows/docker-build.yml` 仅在发布 Release 时构建并推送 Docker Hub,使用 `secrets.DOCKERHUB_USERNAME` / `secrets.DOCKERHUB_TOKEN`。

### Fork 仓库

Fork 提交的 CI workflow 按只读权限运行,无仓库 secrets。如需让 fork 仓库的 CI 正常运行,首次需要仓库维护者在 PR 上批准"Actions"运行权限。

### 自托管 Runner

若使用自托管 Runner 位于国内,需在 Runner 主机上:

1. 配置 `registry-mirrors`(方案 A)
2. 通过 `HTTP_PROXY` / `HTTPS_PROXY` 环境变量为 Runner 提供代理

## 镜像推送

### Docker Hub 推送(Dockerfile 发布路径)

`.github/workflows/docker-build.yml` 默认推送到 `docker.io/gangz1o/glash`。GitHub Actions runner 在境外,**CI 发布路径不受国内网络限制**。

本地手工 `docker push` 到 Docker Hub 受限场景:

```bash
# 登录到国内镜像 registry(替换为你账号的镜像源)
docker tag gangz1o/glash:latest docker.m.daocloud.io/<your-namespace>/glash:latest
docker push docker.m.daocloud.io/<your-namespace>/glash:latest
```

### 推送到国内 registry 后使用

```yaml
# docker-compose.yml
services:
  glash:
    image: docker.m.daocloud.io/<your-namespace>/glash:latest
    # 或阿里云: registry.cn-hangzhou.aliyuncs.com/<your-namespace>/glash:latest
```

## 方案 E:Git 推送到 Gitea(SSH over Cloudflare Tunnel)

向 Gitea(`git@gitssh.szkyinfo.com:container/clash4docker.git`)等国内托管平台推送受限时,常见做法是通过 Cloudflare Tunnel 让 SSH 流量走 443 端口,避免被运营商干扰。

### `~/.ssh/config`

```sshconfig
Host gitssh.szkyinfo.com
  User git
  ProxyCommand cloudflared access ssh --hostname %h
```

### 准备 cloudflared

```bash
# 安装(略)
cloudflared service install <token>
systemctl status cloudflared
```

### 添加第二个 remote

```bash
git remote add gitea git@gitssh.szkyinfo.com:container/clash4docker.git
git remote -v
```

### 推送

```bash
# 首次推送
git push -u gitea master

# 双推(配合 push-all 别名)
git push origin master
git push gitea master
```

### 一次性双推别名

```bash
git config --global alias.push-all '!git push origin && git push gitea'
git push-all master
```

### 常见问题

- **推送超时**:Cloudflare Tunnel 经 443 出口,首次推送大量 commit 可能 1-3 分钟,耐心等待或重试
- **`connection reset by peer`**:网络抖动,重新执行 `git fetch` / `git push`
- **cloudflared 未运行**:`systemctl status cloudflared`,启动后重试

---

## Smart 内核构建

Smart 内核已整合进主镜像,通过 `KERNEL=smart` 环境变量启用。详细用法见 [`../configuration/kernel-selection.md`](../configuration/kernel-selection.md)。

如果只需要 Smart 内核(缩减镜像体积),构建时指定 `--build-arg FLAVORS=smart` 或 `=standard`/`=both`。参数说明见 [`../configuration/build-flavors.md`](../configuration/build-flavors.md)。

Smart 内核资产命名 `mihomo-linux-${ARCH}-alpha-smart-${MIHOMO_SHORT_SHA_SMART}.gz`,Mihomo 上游为 `https://github.com/vernesong/mihomo/releases/download/${MIHOMO_TAG_SMART}/...`,构建时由 `docker/build-helpers/download-mihomo.sh` 拼装。所有方案 A-E 中的 GitHub 资源下载策略对 Smart 内核同样适用 — 镜像代理 URL 模板仍为 `https://gh-proxy.com/<原 URL>`。

---

## 常见问题排查

### `curl: (28) Failed to connect to github.com port 443`

`Dockerfile` 中下载 GitHub 资源失败。

**排查**:

1. 主机是否能直连 `https://github.com`: `curl -I https://github.com`
2. 是否配置了代理: `echo $HTTPS_PROXY`
3. 代理是否支持 HTTPS CONNECT

**解决**:应用方案 B 或方案 C。

### `docker pull` 卡死或 `connection refused`

Docker 守护进程无法访问 `registry-1.docker.io`。

**解决**:应用方案 A,配置 `registry-mirrors`。

### Docker Hub 登录 `docker login` 失败

```bash
# 错误信息:Error response from daemon: Get "https://registry-1.docker.io/v2/": dial tcp ...
```

**解决**:

- 应用方案 A
- 或改推至国内 registry(参见"镜像推送")

### 构建过程中 `apt`/`apk` 找不到包

```text
ERROR: unable to select packages: ca-certificates (no such package)
```

通常是 `Dockerfile` 中的 `apk add --no-cache ca-certificates tzdata bash tini curl sed grep flock` 因 Alpine 镜像源同步慢而失败。

**解决**:

- 应用方案 A(Alpine 镜像源通常也含在 `registry-mirrors` 内)
- 或在构建时注入 Alpine 国内源: `--build-arg ALPINE_REPO=https://mirrors.aliyun.com/alpine/v3.19/main`(需临时修改 Dockerfile 使用 `${ALPINE_REPO}`)

### GitHub Actions 上的 Pull Request 显示 "waiting for status checks"

Fork 仓库的 CI 不会自动运行,需要仓库维护者在 UI 上批准"Actions for first-time contributors"。

**解决**:

- 维护者在 PR 页面点击"Approve run workflows"
- 或将 fork 改为同一组织的仓库后再发 PR

### 构建上下文过大,推送 `docker build` 卡顿

`docker build` 默认会把整个上下文发送到 BuildKit daemon。

**解决**:

```bash
# 用 .dockerignore 排除不必要的文件
cat > .dockerignore <<EOF
.git/
docs/
tests/
*.md
EOF

# 或使用 buildx 的远程构建
docker buildx create --use --driver remote
```

---

## 相关文档

- 本地开发与验证:[`./local-development.md`](./local-development.md)
- CI 检查:[`./ci.md`](./ci.md)
- 运行时结构:[`./runtime-structure.md`](./runtime-structure.md)
- Dockerfile:[`../../Dockerfile`](../../Dockerfile)
- CI workflow:[`../../.github/workflows/ci.yml`](../../.github/workflows/ci.yml)
- 发布 workflow:[`../../.github/workflows/docker-build.yml`](../../.github/workflows/docker-build.yml)