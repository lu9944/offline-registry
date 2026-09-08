#!/usr/bin/env bash
# 播种 Maven 依赖到 $2/maven（静态 Maven 仓库布局）
# 支持 monorepo：递归扫描全部 pom.xml，逐工程 go-offline；根工程额外完整构建抓取插件
# 用法: seed-maven.sh <项目目录> <输出根目录> [MAVEN_EXTRA_ARGS...]
set -euo pipefail

PROJECT="${1:?项目目录必填}"
OUT="${2:?输出根目录必填}"
shift 2

REPO="$OUT/maven"
mkdir -p "$REPO"

echo "==> [Maven] 探测构建文件 ..."
mapfile -t POMS < <(find "$PROJECT" -name pom.xml -not -path "*/target/*" | sort)
GRADLE="$(find "$PROJECT" \( -name build.gradle -o -name build.gradle.kts \) -print -quit 2>/dev/null || true)"

if [ "${#POMS[@]}" -eq 0 ] && [ -z "$GRADLE" ]; then
    echo "==> [Maven] 未检测到 Maven/Gradle 工程，跳过"
    exit 0
fi

if [ -z "$GRADLE" ] && [ "${#POMS[@]}" -gt 0 ]; then
    # reactor 根 = 没有其他 pom 作为祖先的 pom；子模块的依赖由其根统一 go-offline + install 覆盖
    ROOTS=()
    for pom in ${POMS[@]+"${POMS[@]}"}; do
        dir="$(dirname "$pom")"
        covered=0
        for other in ${POMS[@]+"${POMS[@]}"}; do
            odir="$(dirname "$other")"
            [ "$odir" = "$dir" ] && continue
            case "$dir/" in "$odir"/*) covered=1; break;; esac
        done
        [ "$covered" -eq 0 ] && ROOTS+=("$pom")
    done

    echo "==> [Maven] 检测到 ${#POMS[@]} 个 pom.xml（${#ROOTS[@]} 个 reactor 根），开始下载依赖到 $REPO"
    for pom in ${ROOTS[@]+"${ROOTS[@]}"}; do
        sub="$(realpath --relative-to="$PROJECT" "$(dirname "$pom")")"
        echo "==> [Maven] dependency:go-offline: ${sub}"
        mvn -q -f "$pom" -Dmaven.repo.local="$REPO" -Dmaven.test.skip=true dependency:go-offline "$@" || \
            echo "WARN: ${sub} 依赖下载失败，已保留已下载部分"
        # 真实构建：把 reactor 内部构件装入离线仓库，子模块互为依赖才能解析
        echo "==> [Maven] clean install: ${sub}"
        mvn -q -f "$pom" -Dmaven.repo.local="$REPO" -Dmaven.test.skip=true clean install "$@" || \
            echo "WARN: ${sub} 完整构建失败，已保留已下载依赖（某些项目需额外 profile/参数）"
    done
elif [ -n "$GRADLE" ]; then
    echo "==> [Maven] 检测到 Gradle 工程（Gradle 依赖走 Gradle 缓存，暂不纳入离线源）"
    echo "    提示: 本项目使用 Gradle，offline-registry 当前仅支持 Maven 工程的 Java 离线源。"
fi

echo "==> [Maven] 清理负缓存/元数据并归一化 version-range 所需的 maven-metadata.xml"
find "$REPO" -type f \( -name '*.lastUpdated' -o -name '_remote.repositories' \) -delete
find "$REPO" -type f -name 'maven-metadata-*.xml' ! -name 'maven-metadata.xml' | while read -r f; do
  cp -f "$f" "${f%maven-metadata-*.xml}maven-metadata.xml"
done
find "$REPO" -type f -name 'maven-metadata.xml' ! -name '*.sha1' | while read -r f; do
  [ -f "$f.sha1" ] || sha1sum "$f" | awk '{print $1}' > "$f.sha1"
done

echo "==> [Maven] 完成: $(du -sh "$REPO" | cut -f1)"
