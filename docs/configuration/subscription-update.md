# 订阅更新机制

订阅下载后会先在候选文件中完成环境变量覆写、自定义 Hook 和 Mihomo 原生校验,全部成功才替换当前配置。定时更新使用 Controller 热加载,失败时保留或恢复旧配置,不会为了更新订阅主动重启容器。

## 启动时没有本地配置

1. 尝试直连 `SUB_URL`。
2. 直连失败且设置了 `DOWNLOAD_PROXY` 时,尝试外部代理。
3. 下载内容通过基础检查、环境覆写、Hook 和 Mihomo 原生校验后才会安装。
4. 所有候选配置都不可用时容器退出,不会留下无效配置。

## 启动时已有本地配置

1. 先尝试直连获取新订阅。
2. 如果直连不可用,使用现有配置启动 Mihomo。
3. 等待本地代理就绪,再通过当前 HTTP 或 Mixed 代理更新订阅。
4. 更新失败时继续运行现有配置。
5. 如果现有配置也无法启动,最后尝试 `DOWNLOAD_PROXY`。

## 定时更新

1. 检查 `http://127.0.0.1:9090/version` 和 `SECRET` 鉴权。
2. 使用当前配置中的 HTTP 或 Mixed 端口作为本地代理下载订阅。
3. 在候选文件中执行覆写、Hook、基础校验和 Mihomo 原生校验。
4. 安装候选配置并调用 Controller 热加载,不终止 Mihomo 进程。
5. 热加载失败时恢复旧配置并执行补偿加载。
6. 文件锁会阻止两个更新任务同时修改配置。

专项日志:

```bash
docker exec glash cat /var/log/subscription.log
```

## 手动更新

设置 `SUB_URL` 后,即使没有配置 `SUB_CRON`,容器也会生成手动更新命令:

```bash
docker exec glash /app/update_sub.sh
```

手动更新与定时更新使用相同的本地代理、校验、Hook、热加载和失败恢复流程。它要求 Mihomo 已经运行,并且 `SECRET` 与运行中的 Controller 配置一致。

## 相关文档

- 环境变量参考:[`./environment-variables.md`](./environment-variables.md)
- 自定义 Hook:[`./hooks.md`](./hooks.md)
- TUN 模式:[`./tun-mode.md`](./tun-mode.md)
- 故障排查:[`../operations/troubleshooting.md`](../operations/troubleshooting.md)