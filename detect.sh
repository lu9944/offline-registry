#!/usr/bin/env bash
# 探测项目包含的语言生态（递归扫描子目录/monorepo，排除 node_modules、vendor、target 等构建产物）
# 输出以空格分隔的 seeders 名（maven/npm/go/cargo）
# 用法: detect.sh <项目目录>
set -euo pipefail

PROJECT="${1:?项目目录必填}"
PROJECT="$(cd "$PROJECT" && pwd)"
DETECTED=""

PRUNE=(-name .git -o -name node_modules -o -name vendor -o -name target -o -name dist -o -name .venv -o -name venv -o -name __pycache__)

# Java: Maven / Gradle（Gradle 仅识别，播种时提示暂不支持离线源）
if find "$PROJECT" \( "${PRUNE[@]}" \) -prune -o -type f \( -name pom.xml -o -name build.gradle -o -name build.gradle.kts \) -print 2>/dev/null | grep -q .; then
  DETECTED="$DETECTED maven"
fi
# Node.js
if find "$PROJECT" \( "${PRUNE[@]}" \) -prune -o -type f -name package.json -print 2>/dev/null | grep -q .; then
  DETECTED="$DETECTED npm"
fi
# Go
if find "$PROJECT" \( "${PRUNE[@]}" \) -prune -o -type f -name go.mod -print 2>/dev/null | grep -q .; then
  DETECTED="$DETECTED go"
fi
# Rust
if find "$PROJECT" \( "${PRUNE[@]}" \) -prune -o -type f -name Cargo.toml -print 2>/dev/null | grep -q .; then
  DETECTED="$DETECTED cargo"
fi

echo "$DETECTED" | xargs
