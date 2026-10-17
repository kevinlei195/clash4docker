# 订阅后自定义 Hook

订阅模式可以把可执行脚本挂载到 `/app/hooks.d`。每个脚本收到候选配置路径作为第一个参数,按文件名顺序执行;任一 Hook 失败都会取消本次更新,不覆盖当前配置。

## 挂载 Hook 目录

```yaml
volumes:
  - ./config:/root/.config/mihomo
  - ./hooks.d:/app/hooks.d:ro
```

> Hook 只对订阅下载和更新生效,不会修改纯本地模式的配置。

## 示例:让 PT 端口直连

创建 `hooks.d/10-direct-pt-ports.sh`:

```bash
#!/bin/bash
set -e

config_file="$1"
temp_file="${config_file}.hook.$$"
trap 'rm -f "${temp_file}"' EXIT

awk '
    function add_rules() {
        print "  - SRC-PORT,6881,DIRECT"
        print "  - DST-PORT,6881,DIRECT"
        print "  - SRC-PORT,51413,DIRECT"
        print "  - DST-PORT,51413,DIRECT"
    }
    !inserted && /^rules:[[:space:]]*$/ {
        print
        add_rules()
        inserted = 1
        next
    }
    !inserted && /^rules:[[:space:]]*\[\][[:space:]]*$/ {
        print "rules:"
        add_rules()
        inserted = 1
        next
    }
    !inserted && /^rules:/ {
        print "不支持内联 rules,请改为 YAML 列表格式" > "/dev/stderr"
        exit 2
    }
    { print }
    END {
        if (!inserted) {
            print "rules:"
            add_rules()
        }
    }
' "${config_file}" > "${temp_file}"

mv "${temp_file}" "${config_file}"
```

赋予执行权限并重建容器:

```bash
chmod +x hooks.d/10-direct-pt-ports.sh
docker compose up -d --force-recreate
docker exec glash /app/update_sub.sh
```

## 进阶:按源 IP 直连

如果 qBittorrent 或 Transmission 独占一个容器 IP/局域网 IP,使用 `SRC-IP-CIDR,<IP>/32,DIRECT` 通常比端口规则更完整,因为 BitTorrent 会连接大量不同目标端口。

## 相关文档

- 订阅更新机制:[`./subscription-update.md`](./subscription-update.md)
- 环境变量参考:[`./environment-variables.md`](./environment-variables.md)