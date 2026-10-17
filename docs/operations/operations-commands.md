# 运维命令

常用运维命令的速查清单。

## 容器状态

```bash
# 容器状态与健康检查
docker ps --filter name=glash
docker inspect glash --format '{{.State.Status}} health={{if .State.Health}}{{.State.Health.Status}}{{end}} restart={{.RestartCount}} oom={{.State.OOMKilled}}'
```

## 日志查看

```bash
# 主日志
docker logs --tail=200 glash

# 订阅更新日志
docker exec glash tail -n 200 /var/log/subscription.log
```

## 当前生效配置

```bash
# 当前生效的关键配置
docker exec glash sh -c "grep -E '^(port|socks-port|mixed-port|allow-lan|mode|external-controller|secret|authentication|tun|dns):' /root/.config/mihomo/config.yaml"
```

## Controller 验证

```bash
# Controller 是否可访问;配置 SECRET 时添加 Authorization 请求头
curl http://127.0.0.1:9090/version
curl -H 'Authorization: Bearer your-secret' http://127.0.0.1:9090/version
```

## 配置校验

```bash
# Mihomo 原生配置校验
docker exec glash /app/mihomo -t -d /root/.config/mihomo -f /root/.config/mihomo/config.yaml
```

## 手动更新订阅

```bash
docker exec glash /app/update_sub.sh
```

## 相关文档

- 故障排查:[`./troubleshooting.md`](./troubleshooting.md)
- 升级与版本固定:[`./upgrade.md`](./upgrade.md)
- 订阅更新机制:[`../configuration/subscription-update.md`](../configuration/subscription-update.md)