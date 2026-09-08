#!/usr/bin/env bash
# offline-registry 主构建：克隆项目 -> 探测生态 -> 逐源播种 -> 守卫 -> 打包（超限自动分卷）
# 用法: build.sh <repo_url|本地目录> [输出目录]
# 输出目录默认 ./data（含 maven/go/node-dist/cargo/verdaccio-storage）
# 环境变量:
#   PACK_TARBALL=1  打包 data-package.tar.gz（>1.8GB 自动 split 分卷，附 sha256 与还原说明）
#   REPO_TOKEN=xxx  克隆私有仓库用的 GitHub token（可选）
#   ALLOW_EMPTY=1   放行数据量过小的结果（默认播种量 <1MiB 判为失败）
set -euo pipefail

SRC="${1:?请传入 GitHub 地址或本地项目目录}"
OUT="${2:-$PWD/data}"
SEEDERS_DIR="$(cd "$(dirname "$0")/seeders" && pwd)"

# 克隆或使用本地目录
if [[ "$SRC" =~ ^(https?://|git@|ssh://) ]]; then
  TMP="$(mktemp -d)"
  trap 'rm -rf "$TMP"' EXIT
  echo "==> 克隆 $SRC"
  CLONE_URL="$SRC"
  if [[ -n "${REPO_TOKEN:-}" && "$SRC" =~ ^https://github\.com/ ]]; then
    CLONE_URL="https://x-access-token:${REPO_TOKEN}@github.com/${SRC#https://github.com/}"
  fi
  git clone --depth 1 --shallow-submodules --recurse-submodules --jobs 4 "$CLONE_URL" "$TMP/project"
  PROJECT="$TMP/project"
else
  PROJECT="$SRC"
fi

echo "==> 探测语言生态（递归含子目录）"
ECOSYSTEMS="$(bash "$SEEDERS_DIR/../detect.sh" "$PROJECT")"
echo "    检测到: ${ECOSYSTEMS:-（无已知生态）}"

if [ -z "$ECOSYSTEMS" ]; then
  echo "ERROR: 未检测到任何受支持的生态（Maven/npm/Go/Cargo 的 pom.xml、package.json、go.mod、Cargo.toml）。" >&2
  echo "       Python( pip ) 等暂不支持；monorepo 请确认子工程包含上述清单文件。" >&2
  exit 1
fi

mkdir -p "$OUT"

for eco in $ECOSYSTEMS; do
  echo ""
  echo "########## 播种: $eco ##########"
  bash "$SEEDERS_DIR/seed-$eco.sh" "$PROJECT" "$OUT"
done

# 守卫：播种总量过小视为异常，避免发出空数据包（ALLOW_EMPTY=1 放行）
TOTAL=$(du -sb "$OUT" | cut -f1)
if [ "$TOTAL" -lt 1048576 ] && [ -z "${ALLOW_EMPTY:-}" ]; then
  echo "ERROR: 播种数据仅 ${TOTAL} 字节，疑似播种失败。请检查上方各 seeder 的 WARN 日志；" >&2
  echo "       如确认放行请设 ALLOW_EMPTY=1。" >&2
  exit 1
fi

echo ""
echo "==> 数据包目录: $OUT"
du -sh "$OUT"/* 2>/dev/null | sed 's/^/    /' || true

# 打包（CI 用）：超过 1.8GB 自动 split 分卷（GitHub Release 单文件上限 2GB）
if [ -n "${PACK_TARBALL:-}" ]; then
  PACK_DIR="$(cd "$OUT/.." && pwd)"
  (
    cd "$PACK_DIR"
    rm -f data-package.tar.gz data-package.tar.gz.sha256 data-package.tar.gz.part-* data-package.README.txt
    tar -C "$OUT" -czf data-package.tar.gz .
    SIZE=$(stat -c%s data-package.tar.gz)
    HUMAN=$(du -sh data-package.tar.gz | cut -f1)
    WHOLE_SHA=$(sha256sum data-package.tar.gz | awk '{print $1}')
    MAX_PART=$((1800*1024*1024))
    if [ "$SIZE" -gt "$MAX_PART" ]; then
      split -b "$MAX_PART" -d data-package.tar.gz data-package.tar.gz.part-
      rm -f data-package.tar.gz
      sha256sum data-package.tar.gz.part-* > data-package.tar.gz.sha256
      cat > data-package.README.txt <<EOF
数据包体积 $HUMAN 超过 Release 单文件上限，已自动分卷发布。

还原步骤：
  1. 下载本 Release 全部 data-package.tar.gz.part-* 文件到同一目录
  2. cat data-package.tar.gz.part-* > data-package.tar.gz
  3. 校验整体 sha256 应为: $WHOLE_SHA
  4. mkdir -p data && tar -xzf data-package.tar.gz -C data
EOF
      echo "==> 数据包超限已分卷: $(ls data-package.tar.gz.part-* | wc -l) 个文件，整体 sha256: $WHOLE_SHA"
    else
      echo "$WHOLE_SHA  data-package.tar.gz" > data-package.tar.gz.sha256
      echo "==> 数据包已打包: $PACK_DIR/data-package.tar.gz ($HUMAN)"
    fi
  )
fi
