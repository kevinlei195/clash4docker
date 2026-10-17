# Dashboard 使用

容器内置 [MetacubexD](https://github.com/MetaCubeX/metacubexd) Dashboard,提供图形化的代理管理与流量查看界面。

## 访问地址

浏览器访问:

```text
http://<Docker 宿主机 IP>:9090/ui/
```

首次进入时填写:

| 项目 | 填写内容 |
| --- | --- |
| 后端地址 | `http://<Docker 宿主机 IP>:9090` |
| 密钥 | 与 `SECRET` 或配置文件中的 `secret` 一致 |

> 只有浏览器本身运行在 Docker 宿主机上时,才能使用 `http://127.0.0.1:9090`。从另一台电脑或手机访问 NAS 时,`127.0.0.1` 指向的是电脑或手机自己,必须填写 NAS 的实际 IP。

## HTTPS 注意事项

如果使用 HTTPS 域名访问 Dashboard,后端也必须使用 HTTPS,否则浏览器会拦截 HTTP API 请求并提示 Mixed Content。可使用 Nginx、Caddy 等反向代理,让 `/ui/` 和 Mihomo API 使用同一个 HTTPS 域名。

## 相关文档

- 环境变量参考:[`../configuration/environment-variables.md`](../configuration/environment-variables.md)
- 故障排查:[`../operations/troubleshooting.md`](../operations/troubleshooting.md)