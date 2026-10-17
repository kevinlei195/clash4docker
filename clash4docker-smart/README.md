# Clash for Docker — Smart (clash4docker-smart)

[![GitHub Stars](https://img.shields.io/github/stars/gangz1o/clash4docker?style=for-the-badge)](https://github.com/gangz1o/clash4docker/stargazers)
[![Docker Pulls](https://img.shields.io/docker/pulls/gangz1o/glash-smart?style=for-the-badge)](https://hub.docker.com/r/gangz1o/glash-smart)

基于 [vernesong/mihomo](https://github.com/vernesong/mihomo)（上游 [MetaCubeX/mihomo](https://github.com/MetaCubeX/mihomo) 的 Smart Group fork）的 Smart 内核 + [MetacubexD](https://github.com/MetaCubeX/metacubexd) Dashboard 多架构 Docker 镜像。

`clash4docker-smart` 与同仓库的 `clash4docker` 共享所有运行时逻辑（订阅、热加载、TUN、Hook、定时任务），区别只在于打包的内核。

## 与 clash4docker（标准内核）的差异

| 项 | clash4docker | clash4docker-smart（本项目） |
| --- | --- | --- |
| 内核仓库 | `MetaCubeX/mihomo` | `vernesong/mihomo` |
| 内核版本 | 稳定版（如 `v1.19.31`） | `Prerelease-Alpha`（Pre-release） |
| Docker 镜像 | `gangz1o/glash` | `gangz1o/glash-smart` |
| Smart 策略组 (`type: smart`) | ❌ | ✅ |
| ASN 偏好 (`prefer-asn`) | ❌ | ✅ |
| LightGBM 权重预测 (`uselightgbm`) | ❌ | ✅（需自带 `Model.bin`） |
| CLI 命令、`/version` Controller API | — | 完全兼容 |
| 订阅 / Hook / 热加载 / TUN / DNS 覆写 | — | 行为完全一致 |

> Smart 内核新增的 API（`/group/{name}/weights`、`/cache/smart/flush`、`/upgrade/lgbm`、`/connections/smart/{id}`）需要时可直接用 `curl` 调用，本项目 M0 暂未在 `lib/glash` 暴露独立命令。

## 快速开始

```bash
git clone https://github.com/gangz1o/clash4docker.git
cd clash4docker/clash4docker-smart
cp ../clash4docker/config.example.yaml ./config.yaml  # 或自行编写
docker compose up -d
docker logs -f glash-smart
```

需要订阅 / TUN / 固定端口等环境变量，请直接编辑仓库内的 `docker-compose.yml`，与同仓库 `clash4docker/docker-compose.yml` 字段一致。

## Smart 策略组用法

核心收益：Smart 组根据延迟、丢包率与 ASN 信息自动选择最佳节点，无需手工维护 `url-test` 间隔与节点排序。

最小示例：

```yaml
proxy-groups:
  - name: 🚀 Smart
    type: smart
    tolerance: 50          # 延迟抖动容差（ms）
    prefer-asn: true       # 优先按 ASN 选择
    proxies:
      - DIRECT
      - 示例节点-1
      - 示例节点-2
```

可选字段：

| 字段 | 默认 | 说明 |
| --- | --- | --- |
| `tolerance` | 50 | 延迟差值在容差内视为相同，避免抖动切换 |
| `prefer-asn` | false | 强制按 ASN 选择节点 |
| `policy-priority` | "1" | 节点名 pattern → 权重，支持 regex，例如 `"Premium:0.9;SG:1.3"` |
| `uselightgbm` | false | 使用 LightGBM 模型预测权重（需 `Model.bin`） |
| `collectdata` | false | 采集数据用于自训练模型（写到 `smart_weight_data.csv`） |
| `sample-rate` | 1.0 | 数据采集速率 |

## LightGBM（可选）

Smart 内核支持使用 LightGBM 模型预测权重，但镜像默认 **不打包** `Model.bin`。如需启用：

1. 把 `Model.bin` 放到配置目录：`./config/Model.bin`（容器内即 `/root/.config/mihomo/Model.bin`）。
2. 在配置中开启：

   ```yaml
   lgbm-auto-update: true
   lgbm-update-interval: 72
   lgbm-url: "https://github.com/vernesong/mihomo/releases/download/LightGBM-Model/Model.bin"
   ```

3. 在 Smart 策略组中加 `uselightgbm: true`。

完整用法见 [vernesong/mihomo LightGBM-Model Release 说明](https://github.com/vernesong/mihomo/releases/tag/LightGBM-Model)。

## 已知限制

- **上游为 Pre-release**：`vernesong/mihomo` 的发布通道只有一个 `Prerelease-Alpha` tag，构建参数 `MIHOMO_SHORT_SHA` 会跟随上游更新而失效，需要维护者主动 bump。
- **不一定向后兼容**：上游偶尔会有破坏性变更；如果出现 CLI 行为差异，请打开 issue 反馈。
- **Smart 行为是白盒**：调度策略由 Smart 内核控制，本项目不参与其内部逻辑。
- 本项目 `lib/glash` 等脚本与上游 `clash4docker` 共用，没有针对 Smart 专属 API 的封装（如 `/cache/smart/flush`、`/upgrade/lgbm`）。

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

## 环境变量与运维

与同仓库 `clash4docker` 完全一致（共享 `lib/glash/*` 脚本）。常见变量：

| 变量 | 必填 | 说明 |
| --- | --- | --- |
| `SUB_URL` | 否 | 远程订阅地址 |
| `SUB_CRON` | 否 | 自动更新 cron，如 `0 */6 * * *` |
| `SECRET` | 否 | Dashboard / API 密钥 |
| `HTTP_PORT` / `SOCKS_PORT` / `MIXED_PORT` | 否 | 固定代理端口 |
| `ALLOW_LAN` | 否 | 允许局域网访问 |
| `TUN_ENABLED` | 否 | 启用 TUN（需配合 `cap_add` 与 `/dev/net/tun`） |
| `MODE` | 否 | `rule` / `global` / `direct` |
| `DNS_OVERRIDE` | 否 | 用项目预设 DNS 完整覆写 |

完整列表、`/app/update_sub.sh` 手动更新命令、TUN / Hook 用法、故障排查请参考 [`../README.md`](../README.md) 或 [`../docs/ci.md`](../docs/ci.md) — Smart 内核对它们没有额外要求。

## 本地构建与测试

```bash
# 在 clash4docker 仓库根下执行
for s in clash4docker-smart/start.sh clash4docker-smart/lib/glash/*.sh clash4docker-smart/tests/*.sh; do
  bash -n "$s"
done

cd clash4docker-smart
bash tests/test_mode.sh
bash tests/test_reload.sh
bash tests/test_modules.sh

# 构建镜像
docker buildx build --platform linux/amd64 --load -t glash-smart-local .

# 烟雾测试（需要 Docker）
cd .. && bash tests/test_container.sh glash-smart-local
```

## CI

CI 与发布流水线在仓库根的 `.github/workflows/`，通过 `matrix.project: [clash4docker, clash4docker-smart]` 在同一个工作流中编排两套构建。

## 致谢

- [vernesong/mihomo](https://github.com/vernesong/mihomo) — Smart 内核（**Smart 策略组相关问题与上游 MetaCubeX 无关**）
- [MetaCubeX/mihomo](https://github.com/MetaCubeX/mihomo) — 标准内核
- [MetaCubeX/MetacubexD](https://github.com/MetaCubeX/metacubexd) — Dashboard

## License

MIT
