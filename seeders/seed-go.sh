#!/usr/bin/env bash
# 播种 Go module 依赖：go mod download 到 GOMODCACHE，把 cache/download 作为 module proxy 源
# 用法: seed-go.sh <项目目录> <输出根目录>
set -euo pipefail

PROJECT="${1:?项目目录必填}"
OUT="${2:?输出根目录必填}"
[ -f "$PROJECT/go.mod" ] || { echo "==> [go] 未检测到 go.mod，跳过"; exit 0; }

GOMODCACHE_STAGE="$OUT/.gomodcache"
mkdir -p "$GOMODCACHE_STAGE"

echo "==> [go] 检测到 Go 工程，go mod download ..."
# 多模块场景：遍历项目内所有 go.mod
mapfile -t MODULES < <(find "$PROJECT" -name go.mod -not -path "*/vendor/*" | sort)
for mod in "${MODULES[@]}"; do
  dir="$(dirname "$mod")"
  echo "==> [go] 下载依赖: ${dir#$PROJECT/}"
  (cd "$dir" && GOMODCACHE="$GOMODCACHE_STAGE" GOFLAGS=-mod=mod go mod download) || \
    echo "WARN: 该模块下载不完整，已保留已下载部分"
done

# 生成 @v/list（proxy 协议需要版本列表；go mod download 可能不落盘 list）
DOWN="$GOMODCACHE_STAGE/cache/download"
if [ -d "$DOWN" ]; then
  find "$DOWN" -type d -path "*/@v" | while read -r vdir; do
    list="$vdir/list"
    [ -f "$list" ] || { [ -d "$list" ] && rm -rf "$list"; : > "$list"; }
    for f in "$vdir"/*.info; do
      [ -e "$f" ] || continue
      v="$(basename "$f" .info)"
      grep -qxF "$v" "$list" 2>/dev/null || echo "$v" >> "$list"
    done
    sort -u -o "$list" "$list"
  done
fi

# 产出到 /data/go（含 cache/download 布局）
OUT_GO="$OUT/go"
rm -rf "$OUT_GO"
mkdir -p "$OUT_GO/cache"
[ -d "$DOWN" ] && cp -r "$DOWN" "$OUT_GO/cache/download"

chmod -R u+w "$GOMODCACHE_STAGE" 2>/dev/null || true
rm -rf "$GOMODCACHE_STAGE"
echo "==> [go] 完成: $(du -sh "$OUT_GO" | cut -f1)"
