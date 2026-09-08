#!/usr/bin/env bash
# 播种 npm 依赖：启动临时 Verdaccio（npmmirror 上游），项目 npm install 全量缓存
# 用法: seed-npm.sh <项目目录> <输出根目录>
set -euo pipefail

PROJECT="${1:?项目目录必填}"
OUT="${2:?输出根目录必填}"
[ -f "$PROJECT/package.json" ] || { echo "==> [npm] 未检测到 package.json，跳过"; exit 0; }

STORAGE="$OUT/verdaccio-storage"
CONF="$(cd "$(dirname "$0")/../registry/conf" && pwd)/verdaccio-seed.yaml"
SEED_PORT="${SEED_PORT:-14873}"
mkdir -p "$STORAGE"

# 找出 npm 子工程（含 package.json 的目录，跳过 node_modules）
mapfile -t NPM_PROJECTS < <(find "$PROJECT" -name package.json -not -path "*/node_modules/*" | sort)
echo "==> [npm] 检测到 ${#NPM_PROJECTS[@]} 个 package.json"

echo "==> [npm] 启动临时 Verdaccio（npmmirror 上游）"
docker rm -f de-seed-verdaccio >/dev/null 2>&1 || true
docker run -d --name de-seed-verdaccio -p "$SEED_PORT:4873" --user "$(id -u):$(id -g)" \
  -v "$STORAGE:/verdaccio/storage" \
  -v "$CONF:/verdaccio/conf/config.yaml:ro" \
  verdaccio/verdaccio:6 >/dev/null
trap 'docker rm -f de-seed-verdaccio >/dev/null 2>&1 || true' EXIT

ok=""
for i in $(seq 1 60); do
  if curl -sf "http://127.0.0.1:$SEED_PORT/" >/dev/null 2>&1; then ok=1; break; fi
  sleep 1
done
[ -n "$ok" ] || { echo "Verdaccio 启动超时"; exit 1; }

REG="http://127.0.0.1:$SEED_PORT/"
for dir in "${NPM_PROJECTS[@]}"; do
  sub="$(realpath --relative-to="$PROJECT" "$(dirname "$dir")")"
  echo "==> [npm] 缓存: ${sub:-.}"
  (cd "$(dirname "$dir")" \
    && rm -rf node_modules package-lock.json \
    && npm install --registry "$REG" --no-audit --no-fund)
done

echo "==> [npm] 完成: $(du -sh "$STORAGE" | cut -f1)"
