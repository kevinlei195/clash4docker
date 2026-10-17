# 运行时结构

容器启动后,核心脚本与模块的层次结构:

```text
start.sh                         # 轻量入口
lib/glash/
├── app.sh                       # 启动流程编排
├── common.sh                    # 日志与文件操作
├── config.sh                    # 配置校验和变换
├── cron.sh                      # 手动/定时更新任务
├── environment.sh               # 环境变量规范化与校验
├── hooks.sh                     # 订阅后 Hook
├── mihomo.sh                    # Mihomo 进程和热加载
└── subscription.sh              # 下载、锁和更新事务
```

## 模块职责

| 文件 | 职责 |
| --- | --- |
| `start.sh` | 容器入口,转发到 `lib/glash/app.sh` |
| `app.sh` | 启动流程编排:订阅初始化 → 环境变量覆写 → 启动 Mihomo → 调度 cron |
| `common.sh` | 公共日志、文件锁、临时目录等基础工具 |
| `config.sh` | 配置读写、校验、变换(YAML 处理) |
| `cron.sh` | 定时与手动更新任务的入口与调度 |
| `environment.sh` | 环境变量规范化、默认值、合法性校验 |
| `hooks.sh` | 订阅候选配置处理脚本(`/app/hooks.d/*`)的调用与错误处理 |
| `mihomo.sh` | Mihomo 进程生命周期:启动、PID 文件、Controller 热加载 |
| `subscription.sh` | 订阅下载、文件锁、更新事务(初次/已有配置/失败恢复) |

## 相关文档

- 本地开发与验证:[`./local-development.md`](./local-development.md)
- CI 检查:[`./ci.md`](./ci.md)
- 订阅更新机制:[`../configuration/subscription-update.md`](../configuration/subscription-update.md)