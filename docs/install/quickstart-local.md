# 本地配置模式

> 适用场景:自己维护完整的 `config.yaml`,不需要订阅下载。

本地模式不会下载订阅,适合已经拥有完整 Mihomo 配置的用户。配置文件可以以只读方式单文件挂载,无需可写目录。

## docker-compose

```yaml
services:
  glash:
    image: gangz1o/glash:latest
    container_name: glash
    restart: unless-stopped
    ports:
      - "7890:7890"
      - "7891:7891"
      - "7892:7892"
      - "9090:9090"
    volumes:
      - ./config.yaml:/root/.config/mihomo/config.yaml:ro
    environment:
      TZ: Asia/Shanghai
```

## 最小配置示例

最小配置至少需要一个代理端口、`proxies` 或 `proxy-providers`,以及 Dashboard 所需的 Controller:

```yaml
mixed-port: 7892
allow-lan: true
mode: rule
external-controller: 0.0.0.0:9090
secret: "change-this-dashboard-secret"

proxies:
  # 你的节点

proxy-groups:
  # 你的代理组

rules:
  - MATCH,DIRECT
```

完整结构可参考 [`config.example.yaml`](../../config.example.yaml)。

## 注意事项

本地单文件使用 `:ro` 时**不要**设置会修改配置的环境变量,例如 `SECRET`、`MODE`、端口覆写、`TUN_ENABLED` 或 `DNS_OVERRIDE`。需要这些能力时请改为挂载可写目录。

## 下一步

- Dashboard 使用:[`../usage/dashboard.md`](../usage/dashboard.md)
- 代理端口使用:[`../usage/proxy-usage.md`](../usage/proxy-usage.md)
- 环境变量参考:[`../configuration/environment-variables.md`](../configuration/environment-variables.md)