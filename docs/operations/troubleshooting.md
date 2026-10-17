# 故障排查

按故障现象归类的常见问题与排查步骤。

## Dashboard 提示"无法连接后端"

按顺序检查:

1. 从其他电脑或手机访问时,后端地址不能填 `127.0.0.1`,应填 `http://NAS-IP:9090`。
2. 运行 `docker port glash`,确认 9090 已映射。
3. 运行 `curl http://NAS-IP:9090/version`;设置密钥时加 Bearer 请求头。
4. 确认配置包含 `external-controller: 0.0.0.0:9090`。
5. 确认 Dashboard 中填写的密钥与 `SECRET` 一致。
6. HTTPS 页面不能连接 HTTP 后端;统一使用 HTTP,或给 UI 和 API 配置同域 HTTPS 反向代理。

## 容器正常,但 7890/7891/7892 无法连接

1. 确认 `ALLOW_LAN=true`。
2. 查看有效配置中的 `port`、`socks-port`、`mixed-port`。
3. Docker 映射右侧端口必须等于 Mihomo 容器内端口。
4. 机场订阅会修改端口时,设置 `HTTP_PORT`、`SOCKS_PORT`、`MIXED_PORT` 固定端口。
5. 检查宿主机防火墙;不要把代理端口直接暴露到公网。

## Dashboard 修改 Mixed 端口后,重启又变成 0 或原值

Dashboard 的修改是运行态配置,订阅刷新和容器重启可能重新加载磁盘配置。使用环境变量持久设置:

```yaml
environment:
  MIXED_PORT: "7892"
```

HTTP 和 SOCKS5 端口分别使用 `HTTP_PORT`、`SOCKS_PORT`。

## 订阅下载失败、下载到 HTML 或一直使用旧配置

1. 在宿主机运行 `curl -v '订阅地址'` 检查地址和响应。
2. 某些订阅依赖特定 User-Agent,可设置 `SUB_USER_AGENT`。
3. 首次启动没有本地配置、且订阅必须走代理时,设置 `DOWNLOAD_PROXY`。
4. 已有配置时,确认当前 HTTP 或 Mixed 端口能够访问网络。
5. 查看 `/var/log/subscription.log` 中的基础校验、Mihomo 校验或 Hook 错误。
6. 新订阅失败不会替换当前可用配置,这是预期的容错行为。

## 手动或定时更新提示 Controller/SECRET 错误

更新前会访问 9090 Controller。确保:

- 有 `external-controller: 0.0.0.0:9090`
- `SECRET` 与运行中配置的 `secret` 完全相同
- 9090 没被其他进程占用
- 本地请求没有被 `HTTP_PROXY` 等宿主环境变量劫持;项目内部请求已主动绕过代理

## 定时更新时出现 `Mihomo shutting down` 或容器重启

旧版本通过终止并重启 Mihomo 应用订阅,可能让 PID 1 退出。该流程从 v2.2.3 起已改为 Controller 热加载。升级并强制重建:

```bash
docker compose pull
docker compose up -d --force-recreate
```

随后检查实际镜像和容器启动时间,避免仍在运行旧容器。

## TUN 开启失败或局域网设备仍无法访问代理

1. 确认存在 `/dev/net/tun`,并已添加 `NET_ADMIN` 和设备映射。
2. 出现 `auto redirect`、`netlink`、`numerical result out of range` 时设置 `TUN_AUTO_REDIRECT=false`。
3. bridge 模式中的 TUN 不会自动接管宿主机或局域网流量。
4. 将 NAS 设为局域网网关还需要系统级 IP 转发、路由、防火墙/NAT;请按 NAS 系统文档检查。
5. 不要以 `ping` 作为唯一验证,改用 HTTP/SOCKS5 `curl` 测试。

## qBittorrent、Transmission 或 PT 入站异常

1. 如果客户端显式设置了代理,确认是否需要为 BT 流量关闭代理。
2. TUN/透明代理场景可用 `SRC-PORT`、`DST-PORT` 规则直连;订阅模式通过 Hook 持久注入。
3. 独立容器或独立设备优先按源 IP 设置 `SRC-IP-CIDR,...,DIRECT`。
4. 入站端口还需要在路由器、宿主机防火墙和 Docker 中正确转发;Mihomo 分流规则不能代替端口映射。

## 内存持续增长或容器被系统杀掉

先区分"连接数增长""内核内存未释放"和"Docker OOM":

```bash
docker stats --no-stream glash
docker inspect glash --format 'oom={{.State.OOMKilled}} exit={{.State.ExitCode}} restart={{.State.RestartCount}}'
docker logs --tail=300 glash
```

同时在 Dashboard 查看活跃连接数。如果存在数万连接,先定位产生连接的客户端、BT/PT 程序或可能的 TUN 路由回环;连接数与内存一起增长并不等于已经证明内存泄漏。

若升级到最新镜像后仍可复现,请在 issue 中提供:镜像标签、Mihomo 版本、CPU 架构、NAS/系统、完整 compose(隐去订阅和密码)、是否开启 TUN、问题前后的连接数与内存、`OOMKilled`、订阅更新时间及相关日志。

## 配置文件修改或环境覆写不生效

1. 订阅模式必须挂载可写目录,不能只读挂载单个文件。
2. 检查实际挂载内容:`docker exec glash head -n 30 /root/.config/mihomo/config.yaml`。
3. 环境变量修改后需要重建容器:`docker compose up -d --force-recreate`。
4. Dashboard 修改可能在下一次订阅更新后被环境变量覆写,这是持久覆写的设计行为。
5. Hook 只在订阅流程执行,纯本地配置模式不会运行 Hook。

## 相关文档

- 运维命令:[`./operations-commands.md`](./operations-commands.md)
- 环境变量参考:[`../configuration/environment-variables.md`](../configuration/environment-variables.md)
- 订阅更新机制:[`../configuration/subscription-update.md`](../configuration/subscription-update.md)