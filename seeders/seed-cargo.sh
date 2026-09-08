#!/usr/bin/env bash
# 播种 Cargo 依赖：cargo vendor 生成标准离线源 + .cargo/config.toml 模板
# 说明: Rust 无内建 "proxy 下载源" 协议，离线构建标准做法是 cargo vendor（vendored-sources 替换源）。
# 用法: seed-cargo.sh <项目目录> <输出根目录>
set -euo pipefail

PROJECT="${1:?项目目录必填}"
OUT="${2:?输出根目录必填}"
[ -f "$PROJECT/Cargo.toml" ] || { echo "==> [cargo] 未检测到 Cargo.toml，跳过"; exit 0; }

echo "==> [cargo] 检测到 Rust 工程，cargo vendor ..."
OUT_CARGO="$OUT/cargo/vendor"
mkdir -p "$(dirname "$OUT_CARGO")"

# 多 crate 场景：在项目根执行 vendor 通常已覆盖 workspace
(cd "$PROJECT" && cargo vendor --versioned-dirs "$OUT_CARGO") || \
  (cd "$PROJECT" && cargo vendor "$OUT_CARGO") || { echo "WARN: cargo vendor 失败，跳过"; exit 0; }

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
