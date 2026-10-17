# 快速开始:订阅模式

> 适用场景:使用机场订阅 URL,希望容器自动下载并定期更新配置。

订阅下载后会先在候选文件中完成环境变量覆写、自定义 Hook 和 Mihomo 原生校验,全部成功才替换当前配置。定时更新使用 Controller 热加载,失败时保留或恢复旧配置,不会为了更新订阅主动重启容器。

## docker-compose

创建 `docker-compose.yml`:

```yaml
services:
  glash:
    image: gangz1o/glash:latest
    container_name: glash
    restart: unless-stopped
    ports:
      - "7890:7890" # HTTP
      - "7891:7891" # SOCKS5
      - "7892:7892" # HTTP + SOCKS5
      - "9090:9090" # Dashboard 与 API
    volumes:
      - ./config:/root/.config/mihomo
    environment:
      TZ: Asia/Shanghai
      SUB_URL: https://your-subscription-url
      SUB_CRON: "0 */6 * * *"
      SECRET: change-this-dashboard-secret
      ALLOW_LAN: "true"
      HTTP_PORT: "7890"
      SOCKS_PORT: "7891"
      MIXED_PORT: "7892"
```

启动并查看日志:

```bash
docker compose up -d
docker logs -f glash
```

配置目录必须可写。订阅模式不要把 `config.yaml` 单文件挂载为 `:ro`,因为容器需要保存订阅并写入环境变量覆写项。

## Docker Run

```bash
docker run -d \
  --name glash \
  --restart unless-stopped \
  -p 7890:7890 \
  -p 7891:7891 \
  -p 7892:7892 \
  -p 9090:9090 \
  -v /path/to/config:/root/.config/mihomo \
  -e SUB_URL=https://your-subscription-url \
  -e 'SUB_CRON=0 */6 * * *' \
  -e SECRET=change-this-dashboard-secret \
  -e ALLOW_LAN=true \
  -e HTTP_PORT=7890 \
  -e SOCKS_PORT=7891 \
  -e MIXED_PORT=7892 \
  gangz1o/glash:latest
```

## 下一步

- 环境变量参考:[`../configuration/environment-variables.md`](../configuration/environment-variables.md)
- Dashboard 使用:[`../usage/dashboard.md`](../usage/dashboard.md)
- 代理端口使用:[`../usage/proxy-usage.md`](../usage/proxy-usage.md)
- 订阅更新机制:[`../configuration/subscription-update.md`](../configuration/subscription-update.md)