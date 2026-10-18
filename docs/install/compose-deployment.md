# 部署方式索引

> glash 提供 6 种 compose 模板,分别覆盖最常见的部署场景。文件命名直接对应模式;按需 `docker compose -f docker-compose.<mode>.yml up -d` 即可。
>
> 本文档与 [`quickstart-subscription.md`](./quickstart-subscription.md) / [`quickstart-local.md`](./quickstart-local.md) 是互补关系:quickstart 用于"30 秒验证",本文给出"按场景选模板 + 组合 + 验证"。

## 1. 选择合适的模式

按以下决策树确定起点(任一节点不确定就回到更上面的"通用默认"):

```
Q1. 使用机场订阅 URL?
  ├─ 是 → 订阅模式 (docker-compose.subscription.yml)
  └─ 否 → 本地配置模式(默认 docker-compose.yml)
            │
            Q2. 订阅/配置里出现 type: smart 策略组?
            ├─ 是 → Smart 模式 (docker-compose.smart.yml)
            └─ 否 → 标准内核
                  │
                  Q3. 想要容器内透明接管流量(TUN)?
                  ├─ 是 → TUN 模式 (docker-compose.tun.yml)
                  └─ 否 → 默认即可
                        │
                        Q4. 整台 NAS / 服务器作为网络出口?
                        ├─ 是 → NAS / 网关模式 (docker-compose.nas-bridge.yml)
                        └─ 否 → 改用 host 模式 (docker-compose.host.yml) 即可
```

> 不确定走哪一条?直接用 `docker-compose.yml`(默认本地模式)验证 mihomo 与镜像本身,再按需切换。

## 2. 模式对照

| 模式 | 文件 | KERNEL | 网络 | TUN | 订阅 | 挂载 | 适用场景 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 默认 / 本地 | `docker-compose.yml` | `standard` | bridge + 端口映射 | 否 | 可选 | `./config` 可写 | 通用默认;自维护 config.yaml |
| 订阅 | `docker-compose.subscription.yml` | `standard` | bridge + 端口映射 | 否 | **必填** | `./config` 可写 | 机场订阅 + 定时更新 |
| Smart | `docker-compose.smart.yml` | `smart` | bridge + 端口映射 | 否 | 可选 | `./config` 可写 | 订阅/配置含 `type: smart` 策略组 |
| TUN | `docker-compose.tun.yml` | `standard` | bridge + 端口映射 | **是** | 可选 | `./config` 可写 | 容器内透明代理 |
| Host | `docker-compose.host.yml` | `standard` | host | 否 | 可选 | `./config` 可写 | 性能敏感 / 直接监听宿主端口 |
| NAS / 网关 | `docker-compose.nas-bridge.yml` | `smart` | host | **是** | 推荐 | `./config` 可写 | NAS 整网出口 / 家庭网关 |

> 默认情况下任何模板都可与"标准/智能内核"、"订阅/本地配置"自由组合。模板只是预设了最常见组合。

## 3. 模板详解

### 3.1 默认 / 本地模式(`docker-compose.yml`)

通用起点。最简用法:把 `config.example.yaml` 复制为 `./config.yaml`,挂为只读文件,所有环境变量保持注释状态。

```bash
cp config.example.yaml config.yaml
docker compose up -d
docker compose logs -f glash
```

订阅 / TUN / Smart 等高级功能全部以注释形式列出,按需取消注释即可。

### 3.2 订阅模式(`docker-compose.subscription.yml`)

为机场订阅用户准备。容器启动与 `SUB_CRON` 周期都会拉取最新配置,失败保留旧配置。

```bash
# 1. 编辑文件,把 SUB_URL 与 SECRET 改为自己的
vi docker-compose.subscription.yml

# 2. 启动
docker compose -f docker-compose.subscription.yml up -d
docker compose -f docker-compose.subscription.yml logs -f glash
```

**关键点**:
- `./config` 目录必须可写(订阅下载、env 覆写、Hook 都会写入此目录)
- `HTTP_PORT` / `SOCKS_PORT` / `MIXED_PORT` 推荐设置,固定端口避免订阅更新后端口跳变
- 切换 `KERNEL=smart` 时需重启容器

### 3.3 Smart 模式(`docker-compose.smart.yml`)

启用 Smart 内核,适合订阅/配置中包含 `type: smart` 策略组、ASN 偏好或希望使用 LightGBM 自动选优的场景。

```bash
docker compose -f docker-compose.smart.yml up -d
# 验证
docker exec glash /app/mihomo -v
# 期望:alpha-smart-<SHA>

curl -sH "Authorization: Bearer $SECRET" http://127.0.0.1:9090/group/weights
# 期望:{"errors":{},"weights":{"🚀 Smart":null}}
```

**关键点**:
- 官方 `gangz1o/glash:latest` 镜像同时打包 standard 与 smart,`KERNEL=smart` 决定用哪个
- 纯标准订阅也能用 Smart 内核跑(它向后兼容 `type: select` / `url-test` / `fallback`)
- 反之 Smart-only 配置在 standard 内核下会启动失败 — 见 [FAQ](#71-smart-策略组启动失败)

### 3.4 TUN 模式(`docker-compose.tun.yml`)

容器内 mihomo 创建虚拟网卡,接管容器内所有出网流量。适合"应用在容器里、想让它走代理但不想逐个配代理"。

```bash
docker compose -f docker-compose.tun.yml up -d
# 容器内验证(另一个 shell 进容器测外网)
docker exec glash wget -qO- http://www.gstatic.com/generate_204
```

**关键点**:
- 必须 `cap_add: NET_ADMIN` + `devices: /dev/net/tun`
- TUN **只影响容器自己的网络命名空间** — 宿主机与同宿主其它容器不会被自动接管
- NAS 自定义内核(群晖 DSM 等)可能不兼容 `auto-redirect`,改 `TUN_AUTO_REDIRECT=false`

### 3.5 Host 网络模式(`docker-compose.host.yml`)

容器共享宿主网络栈,7890/9090 等端口直接监听在宿主网卡上,绕过 docker NAT。

```bash
docker compose -f docker-compose.host.yml up -d
# 验证
curl -sH "Authorization: Bearer $SECRET" http://127.0.0.1:9090/version
```

**关键点**:
- 不再声明 `ports`(`host` 模式下端口映射会冲突报错)
- `SECRET` 必须够强:9090 直接暴露在宿主网卡
- macOS / Windows 上 `network_mode: host` 实际是 docker-desktop 的虚拟网桥 — 仍可继续用 `ports`
- 如需 TUN + host,优先看 `nas-bridge` 模板

### 3.6 NAS / 网关模式(`docker-compose.nas-bridge.yml`)

把 NAS(群晖 / 威联通 / 软路由 / 树莓派)整体变成家庭/办公室网络出口:Smart 内核 + TUN + host + 订阅 + DNS 接管。

```bash
docker compose -f docker-compose.nas-bridge.yml up -d
```

**关键点**(请通读)：
- 此模式只是"把容器运行起来";**真正的整网接管需要宿主侧配置**,模板末尾有 iptables / sysctl 最小示例
- 强烈建议先在旁路模式(端口映射 + 不开 TUN)验证镜像与订阅正常,再切到本模板
- DNS 接管时,容器内 53 端口被 mihomo 占用;若宿主有 systemd-resolved / dnsmasq 会冲突,需先停用

## 4. 组合使用

模板的"模式"是预设,你可以叠加或裁剪。

### 4.1 Smart + 订阅

最常见组合 — 直接用 `docker-compose.smart.yml`,打开 `SUB_URL` 注释(或复制 `docker-compose.subscription.yml` 模板并把 `KERNEL=standard` 改成 `KERNEL=smart`)。

### 4.2 Smart + TUN

把 `docker-compose.tun.yml` 中的 `# - KERNEL=smart` 取消注释;或者以 `docker-compose.tun.yml` 为基线,启用 `KERNEL=smart`。

### 4.3 Smart + TUN + Host

直接 `docker-compose.nas-bridge.yml` 即可。

### 4.4 模板叠加(docker compose 多文件)

docker compose 支持 `-f` 叠加,后写的覆盖前写的。常见用法:把自家环境变量(真实 `SECRET`、订阅 URL)放在私有 `docker-compose.local.yml`,与公开模板叠加:

```yaml
# docker-compose.local.yml
services:
  glash:
    environment:
      - SUB_URL=https://my-real-sub
      - SECRET=real-secret-123
```

```bash
# 本地测试,优先用私有文件覆盖
docker compose -f docker-compose.subscription.yml -f docker-compose.local.yml up -d
```

> 这种叠加姿势不修改仓库内模板,便于 `git pull` 升级。

### 4.5 多实例共存

`container_name: glash` 唯一,多实例时改容器名与端口:

```yaml
# docker-compose.second.yml
services:
  glash:
    container_name: glash-2
    ports:
      - '7890:7890'   # 第一实例
    # ...
```

```bash
docker compose -f docker-compose.yml up -d              # 第一实例
docker compose -f docker-compose.second.yml up -d       # 第二实例(KERNEL=smart 等差异化)
```

## 5. 迁移指南

### 5.1 从旧 `docker-compose.yml`(注释式)迁移

旧顶层 `docker-compose.yml` 末尾的"订阅模式示例"块已删除(与 `docker-compose.subscription.yml` 内容重复)。迁移:

| 旧用法 | 新用法 |
| --- | --- |
| 取消注释启用订阅 | `cp docker-compose.subscription.yml docker-compose.yml && 编辑` 或 `docker compose -f docker-compose.subscription.yml up -d` |
| 添加 `KERNEL=smart` | 在任一模板加 `- KERNEL=smart`,重启 |
| 启用 TUN | 改用 `docker-compose.tun.yml`,按需加 `KERNEL=smart` |

### 5.2 从 `gangz1o/glash-smart` 迁移

`glash-smart` 镜像已停止更新。对应迁移:

| 旧 | 新 |
| --- | --- |
| `image: gangz1o/glash-smart:latest` | `image: gangz1o/glash:latest` |
| 自带 Smart 内核 | 官方镜像已双打包,运行时由 `KERNEL=smart` 选择 |
| (无) | `docker-compose.smart.yml` 模板可直接用 |

## 6. 验证清单

任何模式启动后,建议依次做这些断言:

```bash
# 1. 容器健康
docker compose -f <your-file> ps
# STATUS 应为 Up (healthy),不是 Up(health: starting) 也不是 unhealthy

# 2. 内核版本
docker exec glash /app/mihomo -v
# standard:v1.19.x ; smart:alpha-smart-<SHA>

# 3. 软链指向当前 KERNEL
docker exec glash readlink -f /app/mihomo
# /opt/mihomo/standard/mihomo 或 /opt/mihomo/smart/mihomo

# 4. Controller 正常
curl -sH "Authorization: Bearer $SECRET" http://127.0.0.1:9090/version
# 期望:{"meta":true,"version":"..."}

# 5. 代理端口监听
docker exec glash sh -c 'wget -qO- http://127.0.0.1:9090/proxies | head -c 200; echo'
# 期望:看到 proxies 列表(订阅模式)或本地 config.yaml 内的节点

# 6. 出网代理能跑
curl -x http://127.0.0.1:7890 https://www.gstatic.com/generate_204 -o /dev/null -w "%{http_code}\n"
# 期望:204
```

## 7. 常见问题

### 7.1 启动报 "address already in use"

7890/7891/9090 已被占用。解决:
- 默认模式下:把所有 `'7890:7890'` 改成 `'7895:7890'` 等(宿主机端口 → 容器端口;容器内端口保留 7890)
- host 模式下:改 `HTTP_PORT=7895` 等环境变量,确保 7895 空闲
- 或停掉冲突进程

### 7.2 Smart 策略组启动失败

`docker logs glash` 报 `proxy group[0]: unsupported type: smart`:

- 镜像是否包含 Smart 内核?`docker exec glash ls /opt/mihomo/smart/` 应有 `mihomo` 文件
- 软链是否指对?`docker exec glash readlink -f /app/mihomo` 应是 `/opt/mihomo/smart/mihomo`
- 若是自建镜像(只 `FLAVORS=standard`)要切到 Smart,需重新构建并加 `--build-arg FLAVORS=both` 或 `=smart`

### 7.3 TUN 不工作

- `docker logs glash` 看是否报 "permission denied" / "operation not permitted" → cap_add 未生效
- 容器内 `cat /dev/net/tun` 应返回 `File descriptor in bad state`(说明 tun 设备可访问);返回 `No such file or directory` → devices 缺
- TUN 配置存在但容器内应用未走代理 → TUN 仅接管**容器内**流量,需用 `docker exec` 进去测;宿主机仍走原网卡

### 7.4 host 模式下 Dashboard 不可访问

- 是不是 `container_name: glash` 跟宿主已有容器重名 → 改名
- `SECRET` 是否设置?host 模式下没设 secret 也能用,只是没人防
- 防火墙:`sudo iptables -L -n | grep 9090` 应有 ACCEPT;`ufw` / `firewalld` 需放行

### 7.5 NAS / 桥接下整网设备无法上网

- 宿主机 `sysctl net.ipv4.ip_forward` 应为 1
- 路由器 / 客户端的默认网关是否指向 NAS IP
- DNS 服务器是否指向 NAS IP
- `iptables -t nat -L -n` 中 POSTROUTING MASQUERADE 与 PREROUTING REDIRECT 规则是否正确
- 容器内 `wget -qO- http://www.gstatic.com/generate_204` 应返回 204

更多排查见 [`../operations/troubleshooting.md`](../operations/troubleshooting.md)。

## 8. 相关文档

| 主题 | 文档 |
| --- | --- |
| 30 秒验证(订阅) | [`./quickstart-subscription.md`](./quickstart-subscription.md) |
| 30 秒验证(本地) | [`./quickstart-local.md`](./quickstart-local.md) |
| 内核选择(KERNEL) | [`../configuration/kernel-selection.md`](../configuration/kernel-selection.md) |
| 构建参数(FLAVORS) | [`../configuration/build-flavors.md`](../configuration/build-flavors.md) |
| 环境变量完整参考 | [`../configuration/environment-variables.md`](../configuration/environment-variables.md) |
| TUN 模式详解 | [`../configuration/tun-mode.md`](../configuration/tun-mode.md) |
| 故障排查 | [`../operations/troubleshooting.md`](../operations/troubleshooting.md) |
| 升级与版本 | [`../operations/upgrade.md`](../operations/upgrade.md) |
