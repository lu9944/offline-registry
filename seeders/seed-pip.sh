#!/usr/bin/env bash
# 播种 pip 依赖：pip download 到 wheels 目录（离线消费用 --find-links）
# 说明: pip 无"远程 proxy 协议"，离线标准做法是本地 wheelhouse + find-links 静态索引。
# 支持 monorepo：递归收集全部 requirements*.txt；根 pyproject.toml 的 [project].dependencies
# 与 [tool.poetry.dependencies] 也会解析下载。
# 环境变量: PIP_INDEX_URL 覆盖下载源（默认清华 TUNA）
# 用法: seed-pip.sh <项目目录> <输出根目录>
set -euo pipefail

PROJECT="${1:?项目目录必填}"
OUT="${2:?输出根目录必填}"

PRUNE=(-name .git -o -name node_modules -o -name vendor -o -name target -o -name .venv -o -name venv -o -name __pycache__)
mapfile -t REQ_FILES < <(find "$PROJECT" \( "${PRUNE[@]}" \) -prune -o -type f -name 'requirements*.txt' -print 2>/dev/null | sort)
PYPROJECTS="$(find "$PROJECT" \( "${PRUNE[@]}" \) -prune -o -type f -name pyproject.toml -print 2>/dev/null | sort)"

if [ "${#REQ_FILES[@]}" -eq 0 ] && [ -z "$PYPROJECTS" ] && \
   [ -z "$(find "$PROJECT" \( "${PRUNE[@]}" \) -prune -o -type f -name setup.py -print -quit 2>/dev/null)" ]; then
  echo "==> [pip] 未检测到 requirements/pyproject.toml/setup.py，跳过"
  exit 0
fi

WHEELS="$OUT/pip/wheels"
mkdir -p "$WHEELS"
INDEX_URL="${PIP_INDEX_URL:-https://pypi.tuna.tsinghua.edu.cn/simple}"

# pyproject.toml -> 临时 requirements（[project].dependencies 与 [tool.poetry.dependencies]）
TMPDIR_SEED="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_SEED"' EXIT
while IFS= read -r pyproj; do
  [ -n "$pyproj" ] || continue
  req="$TMPDIR_SEED/pyproject-$(echo "${pyproj#"$PROJECT"/}" | tr '/' '-').txt"
  python3 - "$pyproj" "$req" <<'EOF' || true
import sys, tomllib
proj, req = sys.argv[1], sys.argv[2]
with open(proj, "rb") as f:
    data = tomllib.load(f)
lines = []
deps = (data.get("project") or {}).get("dependencies") or []
lines += [d for d in deps if isinstance(d, str)]
poetry = ((data.get("tool") or {}).get("poetry") or {}).get("dependencies") or {}
for name, ver in poetry.items():
    if name == "python":
        continue
    if isinstance(ver, str):
        lines.append(f"{name}{ver}")
    elif isinstance(ver, dict) and isinstance(ver.get("version"), str):
        lines.append(f"{name}{ver['version']}")
if lines:
    open(req, "w").write("\n".join(lines) + "\n")
EOF
  if [ -s "$req" ]; then
    sub="$(realpath --relative-to="$PROJECT" "$(dirname "$pyproj")")"
    echo "==> [pip] pyproject 依赖: ${sub}"
    pip download -r "$req" -d "$WHEELS" -i "$INDEX_URL" --quiet || \
      echo "WARN: ${sub} pyproject 依赖下载失败，已保留已下载部分"
  fi
done <<< "$PYPROJECTS"

for req in ${REQ_FILES[@]+"${REQ_FILES[@]}"}; do
  sub="$(realpath --relative-to="$PROJECT" "$(dirname "$req")")"
  echo "==> [pip] download -r: $sub/$(basename "$req")"
  pip download -r "$req" -d "$WHEELS" -i "$INDEX_URL" --quiet || \
    echo "WARN: ${sub}/$(basename "$req") 依赖下载失败，已保留已下载部分"
done

# setup.py 工程（无 requirements/pyproject 的兜底）
while IFS= read -r setup_py; do
  [ -n "$setup_py" ] || continue
  dir="$(dirname "$setup_py")"
  if ! find "$dir" -maxdepth 1 \( -name 'requirements*.txt' -o -name pyproject.toml \) -print -quit | grep -q .; then
    sub="$(realpath --relative-to="$PROJECT" "$dir")"
    echo "==> [pip] download 项目: ${sub}"
    pip download "$dir" -d "$WHEELS" -i "$INDEX_URL" --quiet || \
      echo "WARN: ${sub} setup.py 依赖下载失败，已保留已下载部分"
  fi
done < <(find "$PROJECT" \( "${PRUNE[@]}" \) -prune -o -type f -name setup.py -print 2>/dev/null | sort)

echo "==> [pip] 完成: $(du -sh "$WHEELS" | cut -f1)"
echo "==> [pip] 提示: 离线安装: pip install -r requirements.txt --find-links http://<IP>:8081/pip/wheels --no-index --trusted-host <IP>"
