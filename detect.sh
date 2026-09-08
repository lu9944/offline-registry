#!/usr/bin/env bash
# 探测项目包含的语言生态，输出以空格分隔的 seeders 名（maven/npm/go/cargo）
# 用法: detect.sh <项目目录>
set -euo pipefail

PROJECT="${1:?项目目录必填}"
DETECTED=""

# Java: Maven / Gradle
if [ -f "$PROJECT/pom.xml" ] || [ -f "$PROJECT/build.gradle" ] || [ -f "$PROJECT/build.gradle.kts" ]; then
  DETECTED="$DETECTED maven"
fi
# Node.js
if [ -f "$PROJECT/package.json" ]; then
  DETECTED="$DETECTED npm"
fi
# Go
if [ -f "$PROJECT/go.mod" ]; then
  DETECTED="$DETECTED go"
fi
# Rust
if [ -f "$PROJECT/Cargo.toml" ]; then
  DETECTED="$DETECTED cargo"
fi

echo "$DETECTED" | xargs
