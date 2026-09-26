#!/usr/bin/env bash
# 从锁定的上游基线重建补丁版面板，产物覆盖本仓库根目录的 management.html。
#
# 用法： bash scripts/build.sh
#
# 可用环境变量：
#   WORK   构建工作目录（默认自动创建临时目录）
set -euo pipefail

HERE=$(cd "$(dirname "$0")/.." && pwd)
BASELINE=4530da271ba2e89810d4dccebc57f3091afa590a
UPSTREAM_URL="https://codeload.github.com/router-for-me/Cli-Proxy-API-Management-Center/tar.gz"
WORK=${WORK:-$(mktemp -d)}

command -v npm >/dev/null || { echo "需要 Node/npm" >&2; exit 1; }

echo "⇒ 下载上游基线 $BASELINE"
curl -fL --retry 3 --retry-delay 2 -o "$WORK/panel.tar.gz" "$UPSTREAM_URL/$BASELINE"
if command -v sha256sum >/dev/null; then
  echo "  下载包 sha256: $(sha256sum "$WORK/panel.tar.gz" | cut -d' ' -f1)"
elif command -v shasum >/dev/null; then
  echo "  下载包 sha256: $(shasum -a 256 "$WORK/panel.tar.gz" | cut -d' ' -f1)"
fi

echo "⇒ 解包"
tar -xzf "$WORK/panel.tar.gz" -C "$WORK"
SRC_DIR=$(find "$WORK" -maxdepth 1 -type d -name 'Cli-Proxy-API-Management-Center-*' | head -1)
[ -n "$SRC_DIR" ] || { echo "解包后找不到源码目录" >&2; exit 1; }
cd "$SRC_DIR"

echo "⇒ 套用补丁"
if command -v git >/dev/null && git apply --check -p1 < "$HERE/panel-plugin-quota.patch" 2>/dev/null; then
  git apply -p1 < "$HERE/panel-plugin-quota.patch"
else
  echo "  （git apply 不可用或上下文有差异，改用 patch）"
  patch -p1 < "$HERE/panel-plugin-quota.patch"
fi

echo "⇒ 构建（npm install && npm run build）"
npm install --no-audit --no-fund
npm run build

OUT="$SRC_DIR/dist/index.html"
[ -f "$OUT" ] || { echo "构建产物缺失：$OUT" >&2; exit 1; }

COUNT=$(grep -c plugin_quota "$OUT" || true)
if [ "$COUNT" -lt 1 ]; then
  echo "产物里没有 plugin_quota 标记，补丁可能没套上" >&2
  exit 1
fi

cp -a "$OUT" "$HERE/management.html"
SIZE=$(wc -c < "$HERE/management.html" | tr -d ' ')
echo
echo "✓ 已生成 $HERE/management.html（$SIZE 字节，plugin_quota=$COUNT）"
echo "  部署： bash scripts/deploy.sh"
