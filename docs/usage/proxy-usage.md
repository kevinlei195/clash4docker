# 代理端口使用

Mihomo 提供三个代理端口:HTTP、SOCKS5、Mixed(HTTP + SOCKS5 复用)。本文说明如何在宿主机、其他 Docker 容器中使用这些端口,以及如何启用认证。

## 宿主机或局域网设备

先设置 `ALLOW_LAN=true`,然后使用 Docker 宿主机 IP:

```text
HTTP:   http://192.168.1.10:7890
SOCKS5: socks5://192.168.1.10:7891
Mixed:  192.168.1.10:7892
```

可用 curl 验证:

```bash
curl -x http://192.168.1.10:7890 https://www.gstatic.com/generate_204
curl --proxy socks5h://192.168.1.10:7891 https://www.gstatic.com/generate_204
```

## 其他 Docker 容器

让两个容器加入同一个用户自定义 Docker 网络后,使用服务名连接,**不要**使用 `127.0.0.1`:

```text
HTTP_PROXY=http://glash:7890
HTTPS_PROXY=http://glash:7890
ALL_PROXY=socks5h://glash:7891
```

## 代理端口认证

`AUTHENTICATION` 会写入 Mihomo 的全局 `authentication`,适用于 HTTP、SOCKS5 和 Mixed 代理端口:

```yaml
environment:
  AUTHENTICATION: "alice:password,bob:another-password"
```

使用带认证的 HTTP 代理:

```bash
curl -x http://alice:password@192.168.1.10:7890 https://www.gstatic.com/generate_204
```

> ⚠️ 认证不是流量加密。不要只依靠用户名和密码把代理端口直接暴露到互联网,应同时使用防火墙、可信网络或 VPN。

## 端口映射规则

Docker 端口格式是 `宿主机端口:容器端口`,右侧必须与 Mihomo 最终配置一致。例如希望外部继续使用 7890,但容器内 HTTP 端口固定为 17890:

```yaml
ports:
  - "7890:17890"
environment:
  HTTP_PORT: "17890"
```

推荐直接把容器内端口固定为项目默认值,这样订阅即使携带其他端口也不会破坏映射:

```yaml
ports:
  - "7890:7890"
  - "7891:7891"
  - "7892:7892"
environment:
  HTTP_PORT: "7890"
  SOCKS_PORT: "7891"
  MIXED_PORT: "7892"
```

## 相关文档

- 环境变量参考:[`../configuration/environment-variables.md`](../configuration/environment-variables.md)
- 故障排查:[`../operations/troubleshooting.md`](../operations/troubleshooting.md)