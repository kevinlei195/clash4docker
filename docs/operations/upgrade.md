# 升级与版本固定

## 升级 latest

```bash
docker compose pull
docker compose up -d --force-recreate
```

## 固定镜像标签

生产环境建议固定镜像标签,并在验证后主动升级:

```yaml
image: gangz1o/glash:x.y.z
```

## 当前源码构建参数

当前源码构建参数见 [`Dockerfile`](../../Dockerfile):

| 组件 | 当前版本 |
| --- | --- |
| Alpine | 3.19 |
| Mihomo | v1.19.30 |
| MetacubexD | v1.273.0 |

> 镜像内页面显示的版本取决于所使用的镜像标签,不一定与 `master` 分支当前值相同。

## 相关文档

- 运维命令:[`./operations-commands.md`](./operations-commands.md)
- 故障排查:[`./troubleshooting.md`](./troubleshooting.md)