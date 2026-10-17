# 本地开发与验证

在本地修改项目代码后的语法、测试、镜像构建与容器烟雾测试步骤。

## Shell 语法检查

```bash
for script in start.sh lib/glash/*.sh tests/*.sh; do bash -n "$script"; done
```

## 回归测试

```bash
bash tests/test_mode.sh
bash tests/test_reload.sh
bash tests/test_modules.sh
```

## 构建镜像

```bash
docker build -t clash4docker-local .
```

## 容器烟雾测试

```bash
bash tests/test_container.sh clash4docker-local
```

## CI 与 PR 流程

Pull Request 会运行 Shell 测试、AMD64 容器烟雾测试和多架构构建检查,详情见 [`./ci.md`](./ci.md)。

## 相关文档

- 运行时结构:[`./runtime-structure.md`](./runtime-structure.md)
- CI 检查:[`./ci.md`](./ci.md)