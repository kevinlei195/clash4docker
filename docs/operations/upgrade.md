# 升级与版本固定

## 升级自建镜像

本仓库不发布官方镜像。升级时重新构建并推送你自己的镜像:

```bash
docker buildx build --builder glash-builder \
  --platform linux/amd64,linux/arm64,linux/arm/v7 \
  --tag <your-registry>/<your-namespace>/glash:latest \
  --push .

docker compose pull
docker compose up -d --force-recreate
```

> 上游 Smart 内核的 `Prerelease-Alpha` 是滚动 tag,重新构建会自动获取最新版本;需要固定版本时传 `--build-arg MIHOMO_SHORT_SHA_SMART=<sha>`。

## 固定镜像标签

生产环境建议固定镜像标签,并在验证后主动升级:

```yaml
image: <your-registry>/<your-namespace>/glash:x.y.z
```

## 当前源码构建参数

当前源码构建参数见 [`Dockerfile`](../../Dockerfile):

| 组件 | 当前版本 |
| --- | --- |
| Alpine | 3.19 |
| Mihomo | Smart fork,构建时自动解析上游最新(`vernesong/mihomo@Prerelease-Alpha`) |
| MetacubexD | v1.273.1 |

> 镜像内页面显示的版本取决于所使用的镜像标签,不一定与 `master` 分支当前值相同。

## 相关文档

- 运维命令:[`./operations-commands.md`](./operations-commands.md)
- 故障排查:[`./troubleshooting.md`](./troubleshooting.md)