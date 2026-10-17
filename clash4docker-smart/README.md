# Clash for Docker — Smart (clash4docker-smart)

[![GitHub Stars](https://img.shields.io/github/stars/gangz1o/clash4docker?style=for-the-badge)](https://github.com/gangz1o/clash4docker/stargazers)
[![Docker Pulls](https://img.shields.io/docker/pulls/gangz1o/glash-smart?style=for-the-badge)](https://hub.docker.com/r/gangz1o/glash-smart)

基于 [vernesong/mihomo](https://github.com/vernesong/mihomo)（上游 [MetaCubeX/mihomo](https://github.com/MetaCubeX/mihomo) 的 Smart Group fork）的 Smart 内核 + [MetacubexD](https://github.com/MetaCubeX/metacubexd) Dashboard 多架构 Docker 镜像。

`clash4docker-smart` 与同仓库的 `clash4docker` 共享所有运行时逻辑（订阅、热加载、TUN、Hook、定时任务），区别只在于打包的内核二进制。

---

## 目录

1. [与 clash4docker（标准内核）的差异](#与-clash4docker标准内核的差异)
2. [Smart vs Meta 全局差异](#smart-vs-meta-全局差异)
3. [Smart 独有字段详解](#smart-独有字段详解)
4. [Smart 策略组完整指南](#smart-策略组完整指南)
5. [策略模式对比](#策略模式对比)
6. [权重计算逻辑](#权重计算逻辑)
7. [LightGBM 指南](#lightgbm-指南)
8. [数据收集（自训练）](#数据收集自训练)
9. [Smart TUN 配置](#smart-tun-配置)
10. [UI 推荐与选型](#ui-推荐与选型)
11. [实战配置模板](#实战配置模板)
12. [Smart API 端点](#smart-api-端点)
13. [快速开始](#快速开始)
14. [升级 Smart 内核](#升级-smart-内核)
15. [已知限制](#已知限制)
16. [环境变量与运维](#环境变量与运维)
17. [本地构建与测试](#本地构建与测试)
18. [CI / 致谢 / License](#ci--致谢--license)

---

## 与 clash4docker（标准内核）的差异

| 项 | clash4docker | clash4docker-smart（本项目） |
| --- | --- | --- |
| 内核仓库 | `MetaCubeX/mihomo` | `vernesong/mihomo` |
| 内核版本 | 稳定版（如 `v1.19.31`） | `Prerelease-Alpha`（Pre-release） |
| Docker 镜像 | `gangz1o/glash` | `gangz1o/glash-smart` |
| Smart 策略组 (`type: smart`) | ❌ | ✅ |
| ASN 偏好 (`prefer-asn`) | ❌ | ✅ |
| LightGBM 权重预测 (`uselightgbm`) | ❌ | ✅（需自带 `Model.bin`） |
| `geosite-mode` / `geoip-mode` / `geodat-format` | ❌ | ✅ |
| TUN `strict-route` | ❌ | ✅ |
| 数据收集 (`smart-collector-size`) | ❌ | ✅ |
| CLI 命令、`/version` Controller API | 完全一致 | 完全一致 |
| 订阅 / Hook / 热加载 / DNS 覆写 | 完全一致 | 完全一致 |

> Smart 内核新增的 API（`/group/{name}/weights`、`/cache/smart/flush`、`/upgrade/lgbm`、`/connections/smart/{id}`）需要时可直接用 `curl` 调用，本项目 M0 暂未在 `lib/glash` 暴露独立命令。

---

## Smart vs Meta 全局差异

| 字段 | Meta | Smart | 说明 |
| --- | :---: | :---: | --- |
| `geosite-mode` | ❌ | ✅ | geosite 匹配引擎模式 |
| `geoip-mode` | ❌ | ✅ | geoip 匹配模式 |
| `geodat-format` | ❌ | ✅ | geoip/geosite 数据文件格式 |
| `tun.strict-route` | ❌ | ✅ | TUN 严格路由防泄漏 |
| `lgbm-auto-update` | ❌ | ✅ | LightGBM 模型自动更新 |
| `lgbm-update-interval` | ❌ | ✅ | 模型更新间隔（小时） |
| `lgbm-url` | ❌ | ✅ | 模型下载 URL |
| `smart-collector-size` | ❌ | ✅ | 数据收集文件上限（MB） |
| `experimental.fgr` | ✅ | ✅ | Fine-Grade Routing |
| `find-process-mode` | ✅ | ✅ | 进程选路 |
| `tcp-concurrent` | ✅ | ✅ | TCP 并发 |

策略组层面：

| 字段 | Meta | Smart | 说明 |
| --- | :---: | :---: | --- |
| `type: smart` | ❌ | ✅ | 智能策略组 |
| `policy-priority` | ❌ | ✅ | 节点优先级（pattern:weight） |
| `uselightgbm` | ❌ | ✅ | 使用 LightGBM 预测 |
| `collectdata` | ❌ | ✅ | 收集训练数据 |
| `strategy` | ❌ | ✅ | sticky-sessions / round-robin |

---

## Smart 独有字段详解

### `geosite-mode`

控制 `geosite:` 规则匹配引擎：

```yaml
geosite-mode: fast       # 默认,快速匹配,使用预编译索引
# legacy                 # 兼容旧版,逐条遍历
# mapped                 # 映射模式,支持别名展开
```

### `geoip-mode`

控制 `geoip:` 规则匹配：

```yaml
geoip-mode: fast         # 默认,使用 mmdb 优化查询
# performance           # 性能优先,更激进缓存
```

### `geodat-format`

GeoIP / GeoSite 数据文件格式：

```yaml
geodat-format: auto      # 默认,自动检测
# mmdb                  # MaxMind GeoLite2 格式(推荐)
# dat                   # Clash 传统 .dat 格式
```

### `tun.strict-route`

Smart 特有，配合 `stack: system` 一起使用，避免流量泄漏到直连网卡：

```yaml
tun:
  enable: true
  stack: system
  auto-route: true
  auto-redirect: true
  auto-detect-interface: true
  strict-route: true
```

### LightGBM & 数据收集字段

```yaml
# LightGBM 全局
lgbm-auto-update: false            # 默认 false
lgbm-update-interval: 72           # 默认 72 小时
lgbm-url: "https://github.com/vernesong/mihomo/releases/download/LightGBM-Model/Model.bin"

# 数据收集(为自训练采集训练集)
smart-collector-size: 100          # 默认 100 MB,达上限后停止采集
```

---

## Smart 策略组完整指南

### 基本结构

```yaml
proxy-groups:
  - name: 🚀 Smart
    type: smart                     # 策略组类型为智能
    include-all: true                # 包含所有代理节点
    policy-priority: "Premium:1.5;HK:1.2;SG:1.1;JP:1.0;US:0.9"
    strategy: sticky-sessions        # sticky-sessions / round-robin
    uselightgbm: false              # 使用 LightGBM 预测权重(默认 false)
    collectdata: false              # 收集训练数据(默认 false)
    health-check:
      enable: true
      url: https://www.gstatic.com/generate_204
      interval: 60
      timeout: 5
      lazy: true
```

### `policy-priority`

格式：`<节点名 pattern:权重>`，分号分隔，支持 regex 与子串：

| 值 | 含义 |
| --- | --- |
| `<1` | 低优先级 |
| `1` | 默认优先级 |
| `>1` | 高优先级 |

示例：新加坡权重最高，香港次之，美国最低，其余默认：

```yaml
policy-priority: "Premium:0.9;SG:1.3;HK:1.1"
# Premium 权重 0.9(低);SG 权重 1.3(高);HK 权重 1.1(较高);其余默认 1.0
```

### `strategy`

| 模式 | 说明 | 适用 |
| --- | --- | --- |
| `sticky-sessions` | 同一目标锁定同一节点 | 日常推荐（网银、支付、登录会话） |
| `round-robin` | 多节点轮询分配流量 | 性能测试、最大化节点利用率 |

> ⚠️ Smart 组的 `tolerance` 与外层 `interval` 参数**不生效**，统一改用 `health-check` 块。

### 过滤与筛选

Smart 组同样支持 `include-all` + `filter` 完成区域筛选：

```yaml
- name: 🛠️ 智能-美国
  type: smart
  include-all: true
  filter: "(?i)美|us|usa|america"
  policy-priority: "HK:1.2;SG:1.1"
  strategy: sticky-sessions
  health-check:
    enable: true
    url: https://www.gstatic.com/generate_204
    interval: 60
```

### 完整示例（含 LightGBM）

```yaml
- name: 🌟 Premium 智能
  type: smart
  include-all: true
  policy-priority: "Premium:1.5;HK:1.2;SG:1.1;JP:1.0;US:0.9"
  strategy: sticky-sessions
  uselightgbm: true                # 启用 LightGBM
  collectdata: true                # 采集训练数据
  health-check:
    enable: true
    url: https://www.gstatic.com/generate_204
    interval: 60
    timeout: 5
    lazy: true
```

---

## 策略模式对比

| 模式 | 行为 | 优点 | 缺点 | 典型场景 |
| --- | --- | --- | --- | --- |
| `sticky-sessions` | 同一目标锁定同一节点 | 减少 TCP 握手，登录态稳定 | 单一节点故障恢复慢 | 日常使用、网银、API |
| `round-robin` | 多节点轮询 | 充分利用节点，避开热点 | 会话状态易断 | 压测、大流量下载 |

---

## 权重计算逻辑

### 核心因素

Smart 内核根据以下因素**自动**计算节点权重，无需手工维护 `url-test` 间隔与排序：

| 因素 | 来源 |
| --- | --- |
| 节点延迟 | `health-check` 响应时间 |
| 连接成功率 | 请求成功/失败比例 |
| 用户使用习惯 | 历史流量模式 |
| 网络质量评估 | 实时网络状况 |

### 降级节点恢复

对被判"降级"的节点，Smart 采用**渐进式恢复**策略，避免临时抖动造成永久权重惩罚：

| 时间间隔 | 恢复动作 |
| --- | --- |
| 5 分钟 | 第 1 次尝试恢复部分权重 |
| 10 分钟 | 第 2 次尝试 |
| 15 分钟 | 第 3 次尝试 |
| 30 分钟 | 完全恢复权重 |

---

## LightGBM 指南

### 三步启用

1. 把 `Model.bin` 放到配置目录（容器内即 `~/Model.bin`，对应 `Model.bin`）：
   ```bash
   # CLI / 本地
   mkdir -p ~/.config/mihomo
   curl -L https://github.com/vernesong/mihomo/releases/download/LightGBM-Model/Model.bin \
     -o ~/.config/mihomo/Model.bin

   # Docker (clash4docker-smart)
   curl -L https://github.com/vernesong/mihomo/releases/download/LightGBM-Model/Model.bin \
     -o ./config/Model.bin
   ```
2. 在配置中开启全局：
   ```yaml
   lgbm-auto-update: true
   lgbm-update-interval: 72
   lgbm-url: "https://github.com/vernesong/mihomo/releases/download/LightGBM-Model/Model.bin"
   ```
3. 在 Smart 策略组内开启 `uselightgbm: true`。

### 模型路径速查

| 环境 | 路径 |
| --- | --- |
| OpenClash | `/etc/openclash/Model.bin` |
| CLI 本地 | `~/.config/mihomo/Model.bin` |
| clash4docker-smart | `./config/Model.bin`（即容器内 `~/.config/mihomo/Model.bin`） |

> 本项目 M0 阶段**不会自动打包 `Model.bin`**，请按需在启动容器后自行下载。

### 注意事项

- 预训练模型**未必适合**你的网络环境。
- 想要更准：先用 `collectdata: true` 跑一段时间，再自己训练模型替换。
- `uselightgbm: true` 是真正使用模型预测的开关；全局字段仅控制自动下载。

---

## 数据收集（自训练）

### 启用

```yaml
smart-collector-size: 100   # 默认 100 MB;达到后停止采集
```

输出文件 `smart_weight_data.csv` 中的列即 LightGBM 模型训练所需的 30 维特征。

### 输出路径

| 环境 | 路径 |
| --- | --- |
| OpenClash | `/etc/openclash/smart_weight_data.csv` |
| CLI 本地 | `~/.config/mihomo/smart_weight_data.csv` |
| clash4docker-smart | `./config/smart_weight_data.csv` |

### 训练思路

数据足够后，可使用 vernesong 提供的 feature transforms（`component/smart/lightgbm/transform.go`）按列特征工程后训练 LightGBM v4.x 模型：

```python
import lightgbm as lgb
import pandas as pd

data = pd.read_csv("smart_weight_data.csv")
# ... 与上游 transforms.go 对齐的特征工程
model = lgb.train(...)
model.save_model("CustomModel.bin")
```

替换为自定义模型后，将文件命名 `Model.bin` 覆盖配置目录即可（需要关 `lgbm-auto-update` 防止被覆写）。

---

## Smart TUN 配置

推荐配置（容器接管自身网络命名空间）：

```yaml
tun:
  enable: true
  stack: system              # Smart 推荐,比 mixed 更高效
  auto-route: true
  auto-redirect: true
  auto-detect-interface: true
  strict-route: true         # Smart 特有,严格路由避免流量泄漏
```

Docker compose 同步取消注释：

```yaml
services:
  glash-smart:
    cap_add:
      - NET_ADMIN
    devices:
      - /dev/net/tun:/dev/net/tun
```

NAS 报 `auto redirect ... netlink receive` 时设置环境变量 `TUN_AUTO_REDIRECT=false`。

### Docker 网络边界提醒

- bridge 模式 TUN 仅影响容器自身命名空间，不会自动接管宿主机或局域网。
- 想让 NAS 作为局域网网关需要本机侧 IP forward / 路由 / 防火墙 / NAT，单纯 TUN 不够。

---

## UI 推荐与选型

| UI | Smart 兼容性 | 风格 | 说明 |
| --- | :---: | --- | --- |
| **metacubexd** | ✅ **推荐** | 现代风格 | 与 vernesong/mihomo 配套开发，对 Smart 策略组展示最完整 |
| zashboard | ✅ | 终端风格 | 通用、活跃维护 |
| yacd | ✅ | 经典 | 轻量 |
| dashboard | ✅ | 极简 | Meta 官方 |

本项目已把 **metacubexd** 默认打包进 `Dockerfile`，无需额外配置即可访问 `http://host:9090/ui/`。

要启用 zashboard，可在配置中加：

```yaml
external-ui-url: "https://github.com/Zephyruso/zashboard/archive/refs/heads/gh-pages.zip"
```

---

## 实战配置模板

本目录提供了一份白名单 + Smart 主出口的端到端示例 [`config.example.yaml`](./config.example.yaml)，可直接复制为 `config.yaml` 后填入订阅地址。结构总览：

| 段 | 作用 |
| --- | --- |
| Smart 全局 | geosite-mode/geoip-mode/geodat-format + LightGBM/数据收集字段 |
| DNS | 国内走国内、其余走 DoH 的双栈解析 |
| `proxy-providers.all` | 订阅入口（与 `proxies` 内联二选一） |
| `proxies` | 演示用 VMess / SS / Trojan |
| `proxy-groups` | 🇭🇰/🇹🇼/🇸🇬/🇯🇵/🇰🇷/🇺🇸 分组 + 🚀 Smart 主出口 + 🎯 国内 + 🛑 广告拦截 + 🐟 兜底 |
| `rule-providers` | Loyalsoldier/clash-rules 全套 |
| `tun` | 推荐片段（注释形式，按需启用） |

如果你更习惯**黑名单**模式（默认直连、按需代理），把文件末尾的 `MATCH,🚀 Smart` 改为 `MATCH,DIRECT` 即可。

---

## Smart API 端点

| 端点 | 方法 | 说明 |
| --- | --- | --- |
| `/group/{name}/weights` | GET | 查看某个 Smart 组的节点权重 |
| `/group/weights` | GET | 查看全部 Smart 组的节点权重 |
| `/cache/smart/flush` | POST | 刷新 Smart 调度缓存 |
| `/cache/smart/flush/{configname}` | POST | 刷新指定配置名下的调度缓存 |
| `/connections/smart/{id}` | DELETE | 降级某条连接，让 Smart 重新选择节点 |
| `/upgrade/lgbm` | POST | 触发 LightGBM 模型重新下载 |

调用示例（容器内）：

```bash
curl -H "Authorization: Bearer ${SECRET:-your-secret}" \
     http://127.0.0.1:9090/group/weights | jq

curl -X POST -H "Authorization: Bearer ${SECRET:-your-secret}" \
     http://127.0.0.1:9090/cache/smart/flush
```

---

## 快速开始

```bash
git clone https://github.com/gangz1o/clash4docker.git
cd clash4docker/clash4docker-smart
cp config.example.yaml config.yaml
# 编辑 config.yaml：填入 secret / 订阅 URL（订阅模式）或修改 proxies（内联模式）
docker compose up -d
docker logs -f glash-smart
```

需要订阅 / TUN / 固定端口等环境变量，请直接编辑仓库内的 `docker-compose.yml`，与同仓库 `clash4docker/docker-compose.yml` 字段一致。

---

## 升级 Smart 内核

修改 `clash4docker-smart/Dockerfile`：

```dockerfile
ARG MIHOMO_TAG=Prerelease-Alpha
ARG MIHOMO_SHORT_SHA=<新的 7 位 SHA>
```

查看最新 SHA 的方式：

```bash
curl -fsSL https://api.github.com/repos/vernesong/mihomo/releases | \
  python3 -c "import sys,json; r=json.load(sys.stdin)[0]; \
    print([a['name'] for a in r['assets'] if a['name'].startswith('mihomo-linux-amd64-compatible-alpha-smart-')][0])"
```

---

## 已知限制

- **上游为 Pre-release**：`vernesong/mihomo` 唯一的发布通道是 `Prerelease-Alpha`，构建参数 `MIHOMO_SHORT_SHA` 会跟随上游更新失效，需要维护者主动 bump。
- **不保证向后兼容**：上游偶尔引入破坏性变更；CLI 行为若出现差异，请开 issue 反馈。
- **Smart 行为是白盒**：调度策略由 Smart 内核控制，本项目不参与其内部逻辑。
- 本项目 `lib/glash` 等脚本与上游 `clash4docker` 共用，没有针对 Smart 专属 API 的封装（flush / lgbm-upgrade / smart 权重查询），需要时直接 curl。
- 本项目 M0 不打包 `Model.bin`，启用 LightGBM 前请自行下载。

---

## 环境变量与运维

与同仓库 `clash4docker` 完全一致（共享 `lib/glash/*` 脚本）：

| 变量 | 必填 | 说明 |
| --- | --- | --- |
| `SUB_URL` | 否 | 远程订阅地址；配合 `config.example.yaml` 中的 proxy-providers 即可全自动 |
| `SUB_CRON` | 否 | 自动更新 cron，如 `0 */6 * * *` |
| `SECRET` | 否 | Dashboard / Controller 密钥 |
| `HTTP_PORT` / `SOCKS_PORT` / `MIXED_PORT` | 否 | 固定代理端口 |
| `ALLOW_LAN` | 否 | 允许局域网访问 |
| `TUN_ENABLED` | 否 | 启用 TUN（需配合 `cap_add` 与 `/dev/net/tun`） |
| `TUN_AUTO_REDIRECT` | 否 | NAS 报 netlink 时设为 `false` |
| `MODE` | 否 | `rule` / `global` / `direct` |
| `DNS_OVERRIDE` | 否 | 用项目预设 DNS 完整覆写 |

完整列表、`/app/update_sub.sh` 手动更新、TUN / Hook 用法、故障排查请参考 [`../README.md`](../README.md) — Smart 内核对它们没有额外要求。

---

## 本地构建与测试

```bash
# 仓库根下执行
for s in clash4docker-smart/start.sh clash4docker-smart/lib/glash/*.sh clash4docker-smart/tests/*.sh; do
  bash -n "$s"
done

cd clash4docker-smart
bash tests/test_mode.sh
bash tests/test_reload.sh
bash tests/test_modules.sh

# 校验示例配置能否被 Smart 内核接受
mihomo -t -d /tmp -f clash4docker-smart/config.example.yaml   # 需要 mihomo 二进制在 PATH
```

容器构建与烟雾测试在 Docker daemon 可用时：

```bash
cd /workspace/userspace/clash4docker
docker buildx build --platform linux/amd64 --load \
  -t clash4docker-smart-local clash4docker-smart/

# 注意：实际 smoke 测试直接复用 tests/test_container.sh 会按 7890/7891/7892 启动，
# 新镜像容器名是 glash-smart，请手工指定容器名执行命令，或参考 ../tests/test_container.sh 改造。
```

---

## CI / 致谢 / License

CI 与发布流水线在仓库根的 `.github/workflows/`，通过 `matrix.project: [clash4docker, clash4docker-smart]` 在同一个工作流中编排两套构建。

- [vernesong/mihomo](https://github.com/vernesong/mihomo) — Smart 内核（**Smart 策略组相关问题与上游 MetaCubeX 无关**）
- [MetaCubeX/mihomo](https://github.com/MetaCubeX/mihomo) — 标准内核
- [MetaCubeX/MetacubexD](https://github.com/MetaCubeX/metacubexd) — 配套 Dashboard
- [Loyalsoldier/clash-rules](https://github.com/Loyalsoldier/clash-rules) — 规则集
- 模板参考：[ClashMihomo](https://github.com/...) 配置实例

License：MIT
