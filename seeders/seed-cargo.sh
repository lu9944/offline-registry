#!/usr/bin/env bash
# 播种 Cargo 依赖：cargo vendor 生成标准离线源 + .cargo/config.toml 模板
# 说明: Rust 无内建 "proxy 下载源" 协议，离线构建标准做法是 cargo vendor（vendored-sources 替换源）。
# 支持 monorepo：所有 workspace 根与不被任何 workspace 覆盖的独立 crate 都会 vendor，
#               产物合并进同一 vendor 目录（多余 crate 对各项目无害）。
# 用法: seed-cargo.sh <项目目录> <输出根目录>
set -euo pipefail

PROJECT="${1:?项目目录必填}"
OUT="${2:?输出根目录必填}"

mapfile -t MANIFESTS < <(find "$PROJECT" -name Cargo.toml -not -path "*/vendor/*" -not -path "*/target/*" | sort)
if [ "${#MANIFESTS[@]}" -eq 0 ]; then
  echo "==> [cargo] 未检测到 Cargo.toml，跳过"
  exit 0
fi
echo "==> [cargo] 检测到 ${#MANIFESTS[@]} 个 Cargo.toml"

# 选出需要 vendor 的根：含 [workspace] 的 manifest；其余独立 crate 若位于某根之下则视为已覆盖
ROOTS=()
for m in ${MANIFESTS[@]+"${MANIFESTS[@]}"}; do
  grep -qE '^[[:space:]]*\[workspace\]' "$m" && ROOTS+=("$m")
done
for m in ${MANIFESTS[@]+"${MANIFESTS[@]}"}; do
  grep -qE '^[[:space:]]*\[workspace\]' "$m" && continue
  covered=0
  for r in ${ROOTS[@]+"${ROOTS[@]}"}; do
    case "$(dirname "$m")/" in "$(dirname "$r")"/*) covered=1; break;; esac
  done
  [ "$covered" -eq 0 ] && ROOTS+=("$m")
done

OUT_CARGO="$OUT/cargo/vendor"
mkdir -p "$(dirname "$OUT_CARGO")"

for r in ${ROOTS[@]+"${ROOTS[@]}"}; do
  dir="$(dirname "$r")"
  sub="$(realpath --relative-to="$PROJECT" "$dir")"
  echo "==> [cargo] cargo vendor: ${sub}"
  (cd "$dir" && cargo vendor --versioned-dirs "$OUT_CARGO") || \
    (cd "$dir" && cargo vendor "$OUT_CARGO") || \
    echo "WARN: ${sub} cargo vendor 失败，跳过"
done

# 生成替换源配置模板（用户拷贝到项目 .cargo/config.toml）
cat > "$OUT/cargo/cargo-config.toml" <<'EOF'
# 复制到项目根目录 .cargo/config.toml 即可离线构建
[source.crates-io]
replace-with = "vendored-sources"

[source.vendored-sources]
directory = "<vendor 绝对路径>"
EOF
echo "==> [cargo] 提示: 将 vendor 目录拷到项目根，并把 cargo-config.toml 内容写入 .cargo/config.toml"

echo "==> [cargo] 完成: $(du -sh "$OUT_CARGO" | cut -f1)"
