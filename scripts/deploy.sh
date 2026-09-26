#!/usr/bin/env bash
# 把补丁版面板部署到本地 CPA 的静态目录：备份 → 安装 → 校验。
#
# 用法：
#   bash scripts/deploy.sh [补丁版 management.html 路径]
#
# 可用环境变量：
#   CFG    CPA 配置目录（默认 ~/.config/cliproxyapi）
#   PORT   CPA 监听端口（默认 1235，仅用于校验）
set -euo pipefail

HERE=$(cd "$(dirname "$0")/.." && pwd)
CFG=${CFG:-$HOME/.config/cliproxyapi}
PORT=${PORT:-1235}
SRC=${1:-$HERE/management.html}
DEST="$CFG/static/management.html"

[ -f "$SRC" ] || { echo "找不到补丁版面板：$SRC" >&2; exit 1; }
[ -f "$DEST" ] || { echo "找不到 CPA 现有面板：$DEST（用 CFG 指定配置目录）" >&2; exit 1; }

BAK="$DEST.bak-$(date +%Y%m%d-%H%M%S)"
cp -a "$DEST" "$BAK"
cp -a "$SRC" "$DEST"
echo "已备份旧面板 → $BAK"
echo "已安装补丁版面板 → $DEST"

if grep -qE '^[[:space:]]*disable-auto-update-panel:[[:space:]]*true' "$CFG/config.yaml" 2>/dev/null; then
  echo "✓ disable-auto-update-panel: true（面板不会被上游自动更新覆盖）"
else
  echo "⚠ 没在 $CFG/config.yaml 里看到 disable-auto-update-panel: true"
  echo "  建议加上，否则上游发布新面板时补丁会被覆盖："
  echo "    remote-management:"
  echo "      disable-auto-update-panel: true"
fi

echo
echo "CPA 每次请求都从磁盘读面板，不需要重启。校验是否生效："
if curl -s -m 15 -o /tmp/panel-served.html -w "  http=%{http_code} size=%{size_download}\n" "http://127.0.0.1:$PORT/management.html"; then
  # 面板是压缩过的多行文件，grep -c 数的是行数（会得到 2），必须数出现次数。
  printf "  plugin_quota 出现次数（期望 14）: "
  grep -o plugin_quota /tmp/panel-served.html | wc -l
fi

echo
echo "浏览器请用 Ctrl+Shift+R 硬刷新（CPA 不给面板发 Cache-Control，普通 F5 可能无效）。"
echo "回滚： mv $BAK $DEST"
