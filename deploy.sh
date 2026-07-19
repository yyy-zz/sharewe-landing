#!/usr/bin/env bash
# 一键部署落地页到线上服务器
# 用法：./deploy.sh          （部署 + 备份上一版）
#       ./deploy.sh rollback （回滚到上一版）
set -euo pipefail

HOST="sharewe"                       # ~/.ssh/config 里的别名
SRC="$(cd "$(dirname "$0")" && pwd)/04-landing-page/index.html"
DEST="/var/www/sharewe/index.html"
BACKUP="/var/www/sharewe/index.html.prev"
URL="http://47.80.12.92/"

if [[ "${1:-}" == "rollback" ]]; then
  ssh "$HOST" "[ -f $BACKUP ] && cp $BACKUP $DEST && echo '已回滚到上一版' || { echo '没有可回滚的备份'; exit 1; }"
  curl -s -o /dev/null -w "线上状态: HTTP %{http_code}\n" "$URL"
  exit 0
fi

[[ -f "$SRC" ]] || { echo "找不到源文件: $SRC"; exit 1; }

# 上线前自检：不能有外链请求，不能残留占位符
if grep -qE '(src|href)="https?://' "$SRC"; then
  echo "❌ 检测到外部链接，微信内可能加载失败。中止。"; exit 1
fi
if grep -q "占位" "$SRC" | grep -v "已弃用" > /dev/null 2>&1; then
  echo "⚠️  文件里还有占位符，确认后再发。"; exit 1
fi

ssh "$HOST" "cp $DEST $BACKUP 2>/dev/null || true"
scp -q "$SRC" "$HOST:$DEST"
ssh "$HOST" "nginx -t > /dev/null 2>&1 && systemctl reload nginx"

echo "✅ 已部署 $(wc -c < "$SRC" | tr -d ' ') 字节"
curl -s -o /dev/null -w "线上状态: HTTP %{http_code}，耗时 %{time_total}s\n" "$URL"
echo "访问: $URL"
