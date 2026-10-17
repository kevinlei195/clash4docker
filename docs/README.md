# 文档目录

> Clash for Docker(glash)完整文档导航。README 提供门面与速调指南,详细内容按用户场景拆分到下文目录。

## 用户文档

### 安装与快速开始

- [订阅模式快速开始](./install/quickstart-subscription.md) — 订阅 URL + docker compose / docker run
- [本地配置模式](./install/quickstart-local.md) — 挂载自维护的 `config.yaml`

### 日常使用

- [Dashboard 使用](./usage/dashboard.md) — MetacubexD 访问与配置
- [代理端口使用与认证](./usage/proxy-usage.md) — 宿主机、其他 Docker 容器、代理认证

### 配置参考

- [环境变量完整参考](./configuration/environment-variables.md) — 运行环境、订阅、持久覆写、端口映射
- [订阅更新机制](./configuration/subscription-update.md) — 启动流程、定时更新、手动更新
- [TUN 模式](./configuration/tun-mode.md) — TUN 启用与网络边界
- [订阅后自定义 Hook](./configuration/hooks.md) — 在订阅配置上执行自定义脚本

### 运维与故障排查

- [运维命令](./operations/operations-commands.md) — 状态、日志、配置校验常用命令
- [故障排查](./operations/troubleshooting.md) — 按现象归类的排查步骤
- [升级与版本固定](./operations/upgrade.md) — latest 升级、固定镜像标签、当前版本

## 开发者文档

- [运行时结构](./development/runtime-structure.md) — `start.sh` / `lib/glash/` 模块划分
- [本地开发与验证](./development/local-development.md) — Shell 检查、回归测试、本地构建
- [国内构建指南](./development/build-in-china.md) — 国内网络环境下的镜像构建、推送与 Git 推送方案
- [CI 检查](./development/ci.md) — Pull Request CI 层级、文档-only 策略、合并门禁
- [项目规划](./plans/) — 重大变更的实现规划文档