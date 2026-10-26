#!/usr/bin/env bash
# 用例:交互式构建脚本的输出与校验。
#
# 仅跑 --dry-run / --help,断言关键 build-arg 出现,不做实际构建。
# 任何非 TTY 校验路径(命令行覆盖、错误校验)都覆盖到。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
SCRIPT="${REPO_DIR}/scripts/build-interactive.sh"

[ -x "${SCRIPT}" ] || { echo "FAIL: 缺少可执行 ${SCRIPT}"; exit 1; }

pass()  { printf '  OK %s\n' "$*"; }
fail()  { printf '  FAIL %s\n' "$*" >&2; exit 1; }

echo "==== 1. --help ===="
out=$("${SCRIPT}" --help 2>&1)
echo "${out}" | grep -q "build-interactive.sh" || fail "--help 缺少标题"
echo "${out}" | grep -q -- "--ui"                 || fail "--help 缺少 --ui"
echo "${out}" | grep -q -- "--advanced"           || fail "--help 缺少 --advanced"
echo "${out}" | grep -q -- "--dry-run"            || fail "--help 缺少 --dry-run"
echo "${out}" | grep -q -- "--mihomo-short-sha-smart" || fail "--help 缺少 --mihomo-short-sha-smart"
pass "--help 输出完整"

echo "==== 2. --dry-run 关键 build-arg ===="
out=$("${SCRIPT}" --dry-run 2>&1)
for arg in UI MIHOMO_REPO_SMART MIHOMO_TAG_SMART MIHOMO_SHORT_SHA_SMART METACUBEXD_VERSION ZASHBOARD_VERSION; do
    echo "${out}" | grep -q -- "--build-arg ${arg}=" || fail "缺少 --build-arg ${arg}"
done
echo "${out}" | grep -q "干跑模式" || fail "缺少干跑提示"
pass "默认参数都出现在 dry-run 输出中"

echo "==== 3. FLAVORS 已移除 ===="
out=$("${SCRIPT}" --dry-run 2>&1)
echo "${out}" | grep -q "FLAVORS" && fail "FLAVORS 仍出现在输出中"
out=$("${SCRIPT}" --flavors smart --dry-run 2>&1 || true)
echo "${out}" | grep -q "ERROR" || fail "--flavors 未被拦截"
pass "FLAVORS 相关参数已完全移除"

echo "==== 4. --ui 覆盖 ===="
out=$("${SCRIPT}" --ui zashboard --dry-run 2>&1)
echo "${out}" | grep -q "UI=zashboard" || fail "--ui zashboard 未生效"
pass "--ui 覆盖生效"

echo "==== 5. --push + --user 拼接 tag ===="
out=$("${SCRIPT}" --ui metacubexd --tag my:dev --push --user myaccount --dry-run 2>&1)
echo "${out}" | grep -q "myaccount/my:dev" || fail "未拼接 --user 前缀"
echo "${out}" | grep -q " --push "        || fail "未生成 --push"
pass "--push + --user 拼接正确"

echo "==== 6. 平台多选 ===="
out=$("${SCRIPT}" --platform "linux/amd64,linux/arm64" --dry-run 2>&1)
echo "${out}" | grep -q "linux/amd64,linux/arm64" || fail "多平台未透传"
pass "多平台参数透传"

echo "==== 7. 非法 platform 报错 ===="
out=$("${SCRIPT}" --platform "linux/mips" 2>&1 || true)
echo "${out}" | grep -q "ERROR" || fail "未报错"
pass "非法 platform 校验失败"

echo "==== 8. 非法 short SHA 报错 ===="
out=$("${SCRIPT}" --mihomo-short-sha-smart abc 2>&1 || true)
echo "${out}" | grep -q "ERROR" || fail "未报错"
echo "${out}" | grep -q "7 位 hex" || fail "错误信息不明确"
pass "非法 short SHA 校验失败"

echo "==== 9. 非法 semver 报错 ===="
out=$("${SCRIPT}" --metacubexd-version "1.273.1" 2>&1 || true)
echo "${out}" | grep -q "ERROR" || fail "未报错(v 前缀缺失)"
pass "非法 semver 校验失败"

echo "==== 10. 非法 UI 报错 ===="
out=$("${SCRIPT}" --ui "yaclash" 2>&1 || true)
echo "${out}" | grep -q "ERROR" || fail "未报错"
pass "非法 UI 校验失败"

echo "==== 11. --advanced 全部 build-arg 走默认值 ===="
out=$("${SCRIPT}" --advanced --dry-run 2>&1)
for arg in UI=metacubexd MIHOMO_REPO_SMART=vernesong/mihomo MIHOMO_TAG_SMART=Prerelease-Alpha METACUBEXD_VERSION=v1.273.1 ZASHBOARD_VERSION=v3.29.1; do
    echo "${out}" | grep -q -- "--build-arg ${arg}" || fail "缺少默认 --build-arg ${arg}"
done
pass "高级模式默认值都出现"

echo "==== 12. 默认 tag 由 UI 生成 ===="
out=$("${SCRIPT}" --dry-run 2>&1)
echo "${out}" | grep -q "glash-dev:metacubexd" || fail "默认 tag 未按 UI 生成"
pass "默认 tag 正确"

echo "==== 13. tag 含 / 与 : 不被拒 ===="
out=$("${SCRIPT}" --tag "registry.example.com/team/myapp:1.2.3" --dry-run 2>&1)
echo "${out}" | grep -q "registry.example.com/team/myapp:1.2.3" || fail "复杂 tag 被拒"
pass "复杂 tag 通过"

echo "==== 14. 未知参数报错 ===="
out=$("${SCRIPT}" --foo 2>&1 || true)
echo "${out}" | grep -q "ERROR" || fail "未报错"
echo "${out}" | grep -q -- "--foo" || fail "未提及未知参数名"
pass "未知参数拦截"

echo
echo "OK test_build_interactive.sh"
