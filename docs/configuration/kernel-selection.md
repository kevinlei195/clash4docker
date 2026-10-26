# 内核选择(KERNEL)

默认构建(`FLAVORS=both`)的镜像同时打包两个 mihomo 内核二进制,运行时通过 `KERNEL` 环境变量选择其中一个:

| 取值 | 内核 | 适用场景 |
| --- | --- | --- |
| `standard` | `MetaCubeX/mihomo`(默认) | 大多数用户;社区原版 |
| `smart` | `vernesong/mihomo` Smart fork | 订阅包含 `type: smart` 策略组,或希望使用 ASN 偏好等 Smart 增强 |

## 启用 Smart 内核

订阅 `KERNEL=smart` 与原有配置一致,其余变量与文档同:

```yaml
services:
  glash:
    image: my/glash:latest   # 替换为你自己构建/推送的镜像
    container_name: glash
    restart: unless-stopped
    environment:
      KERNEL: smart
      TZ: Asia/Shanghai
      SUB_URL: https://your-subscription-url
      SUB_CRON: "0 */6 * * *"
      SECRET: change-this-dashboard-secret
      ALLOW_LAN: "true"
    ports:
      - "7890:7890"
      - "7891:7891"
      - "7892:7892"
      - "9090:9090"
    volumes:
      - ./config:/root/.config/mihomo
```

切换 `KERNEL` 不会自动重启容器,请显式重启:

```bash
docker compose up -d
```

## 切换需重启的原因

Smart 内核的 `type: smart` 策略组、ASN 偏好等特性是**内核层**实现的,而热加载只重读配置文件,不会重新初始化内核功能模块。在订阅更新过程里自动重启容器会让"永不因订阅变更重启" 这条现有契约失效,所以本项目**不在运行时自动重启**。

如果只是想启用 Smart 内核而暂时不想重启:

1. 先确认订阅内容包含 `type: smart`
2. 备份当前订阅配置
3. 把 `KERNEL` 改成 `smart`,然后 `docker compose up -d`
4. 第一次启动会因为旧策略组配置无法通过 Smart 内核校验而失败 → 这是预期的,订阅会自动重试,获取到含 `type: smart` 的新配置后即可启动

## 自检当前内核

容器启动后,可用下列命令确认使用的是哪一个二进制:

```bash
docker exec glash readlink -f /app/mihomo
# 期望: /opt/mihomo/standard/mihomo
#       /opt/mihomo/smart/mihomo

docker exec glash /app/mihomo -v
# 期望: Mihomo Meta v1.19.x    (standard)
#       Mihomo Meta Smart ...  (smart)
```

## 缺位时报错

如果自建镜像时只打包 `FLAVORS=standard`,但又设了 `KERNEL=smart`,容器启动会立即失败并给出明确错误:

```
[ERROR] 当前镜像未包含 Smart 内核。请重新构建镜像时加入 FLAVORS=smart 或 FLAVORS=both。
```

说明无需猜测,可直接对照 [`docs/configuration/build-flavors.md`](./build-flavors.md) 调整构建参数。
