#!/usr/bin/env bash
# 一键部署网站到线上服务器（支持多页面）
# 用法：./deploy.sh          （全站部署 + 备份上一版）
#       ./deploy.sh rollback （整站回滚到上一版）
set -euo pipefail

HOST="sharewe"                       # ~/.ssh/config 里的别名
DIR="$(cd "$(dirname "$0")" && pwd)/04-landing-page"
DEST="/var/www/sharewe"
BACKUP="/var/www/sharewe_prev"
URL="https://swagent.cn/"
GATE="$(cd "$(dirname "$0")" && pwd)/ops/check-words.sh"

# 要部署的页面（新增页面加到这里）
PAGES=(index.html standard.html privacy.html sample.html)

if [[ "${1:-}" == "rollback" ]]; then
  ssh "$HOST" "[ -d $BACKUP ] && cp -f $BACKUP/*.html $DEST/ && echo '已整站回滚到上一版' || { echo '没有可回滚的备份'; exit 1; }"
  curl -s -o /dev/null -w "线上状态: HTTP %{http_code}\n" "$URL"
  exit 0
fi

# ── 上线前自检：逐页检查外链、占位符、禁用词 ──
FOUND=()
for p in "${PAGES[@]}"; do
  f="$DIR/$p"
  [[ -f "$f" ]] || { echo "· 跳过（不存在）：$p"; continue; }

  if grep -qE '(src|href)="https?://' "$f"; then
    echo "❌ $p 有外部链接，微信内可能加载失败。中止。"; exit 1
  fi
  if grep "占位" "$f" | grep -qv "已弃用"; then
    echo "⚠️  $p 里还有占位符，确认后再发。中止。"; exit 1
  fi
  if [[ -x "$GATE" ]] && ! LC_ALL=en_US.UTF-8 bash "$GATE" "$f" >/dev/null 2>&1; then
    echo "❌ $p 未过禁用词门禁。跑 ops/check-words.sh 看详情。中止。"; exit 1
  fi
  FOUND+=("$p")
done

[[ ${#FOUND[@]} -gt 0 ]] || { echo "没有可部署的页面"; exit 1; }

# ── 备份 + 上传 ──
ssh "$HOST" "mkdir -p $BACKUP && cp -f $DEST/*.html $BACKUP/ 2>/dev/null || true"
for p in "${FOUND[@]}"; do
  scp -q "$DIR/$p" "$HOST:$DEST/$p"
done
ssh "$HOST" "nginx -t > /dev/null 2>&1 && systemctl reload nginx"

echo "✅ 已部署 ${#FOUND[@]} 个页面：${FOUND[*]}"

# ── 线上验收：逐页探活 ──
for p in "${FOUND[@]}"; do
  path="/${p%.html}"; [[ "$p" == "index.html" ]] && path="/"
  code=$(curl -s -o /dev/null -w "%{http_code}" "https://swagent.cn$path")
  printf "  %-16s %s → HTTP %s\n" "$p" "https://swagent.cn$path" "$code"
done
echo "访问: $URL"
