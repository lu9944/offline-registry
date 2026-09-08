#!/usr/bin/env bash
# offline-registry 主构建：克隆项目 -> 探测生态 -> 逐源播种 -> 打包数据
# 用法: build.sh <repo_url|本地目录> [输出目录]
# 输出目录默认 ./data（含 maven/go/node-dist/cargo/verdaccio-storage）
set -euo pipefail

SRC="${1:?请传入 GitHub 地址或本地项目目录}"
OUT="${2:-$PWD/data}"
SEEDERS_DIR="$(cd "$(dirname "$0")/seeders" && pwd)"

# 克隆或使用本地目录
if [[ "$SRC" =~ ^(https?://|git@|ssh://) ]]; then
  TMP="$(mktemp -d)"
  trap 'rm -rf "$TMP"' EXIT
  echo "==> 克隆 $SRC"
  git clone --depth 1 --shallow-submodules --recurse-submodules --jobs 4 "$SRC" "$TMP/project"
  PROJECT="$TMP/project"
else
  PROJECT="$SRC"
fi

echo "==> 探测语言生态"
ECOSYSTEMS="$(bash "$(dirname "$0")/detect.sh" "$PROJECT")"
echo "    检测到: ${ECOSYSTEMS:-（无已知生态）}"

mkdir -p "$OUT"

for eco in $ECOSYSTEMS; do
  echo ""
  echo "########## 播种: $eco ##########"
  bash "$SEEDERS_DIR/seed-$eco.sh" "$PROJECT" "$OUT"
done

echo ""
echo "==> 数据包目录: $OUT"
du -sh "$OUT"/* 2>/dev/null | sed 's/^/    /' || true

# 打包（CI 用）
if [ -n "${PACK_TARBALL:-}" ]; then
  TARBALL="$OUT/../offline-registry-data.tar.gz"
  tar -C "$OUT" -czf "$TARBALL" .
  echo "==> 数据包已打包: $TARBALL ($(du -sh "$TARBALL" | cut -f1))"
fi
