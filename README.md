# offline-registry

一个**离线依赖仓库自动构建平台**。提交一个开源项目的 GitHub 地址，GitHub Actions 自动解析项目里
Maven / npm / Go / Cargo 的依赖，生成一份「离线数据包」；配合一个通用 Docker 服务镜像，在
**内网/离线环境**一条命令启动，即可作为 Maven、npm、Go、Cargo 的依赖下载源使用。

```
用户提交仓库地址 ──► GitHub Actions 自动播种依赖 ──► 生成 数据包 + 通用镜像
                                                          │
                             内网用户 docker pull 通用镜像 + 下载数据包 ──► docker run ──► 依赖下载源
```

## 支持的语言生态

| 生态 | 探测文件 | 离线源形态 | 消费方配置 |
|---|---|---|---|
| Java (Maven) | `pom.xml` | 静态 Maven 仓库 | Maven `settings.xml` mirror |
| Node.js | `package.json` | Verdaccio 缓存 | npm registry |
| Go | `go.mod` | Go module proxy（GOMODCACHE cache/download） | `GOPROXY` |
| Rust | `Cargo.toml` | `cargo vendor` 离线源 | `.cargo/config.toml` replace-with |

> 说明：Rust 没有内建「远程 proxy 下载源」协议，离线构建的标准做法是 `cargo vendor`
> 生成 `vendored-sources` 替换源，本工具按该方式产出并附配置模板。
>
> **monorepo 支持**：探测与播种均递归扫描子目录（自动排除 `node_modules`、`vendor`、`target` 等），
> 项目根没有清单文件、只有嵌套子工程也能识别。
> **分包机制**：数据包超过 1.8GB 会自动 `split` 分卷上传（GitHub Release 单文件上限 2GB），
> 还原命令见 Release 内 `data-package.README.txt`。

## 快速开始

### 方式 A：用 GitHub Actions 自动构建（推荐）

1. 把这个仓库 **Fork 到你自己的账号**下（数据包和镜像会发到你的 fork）。
2. 到你 fork 的 **Actions** 页，选择 **build-offline-registry** 工作流 → **Run workflow**。
3. 填写 `repo_url`（开源项目地址），点运行。
4. 工作流完成后：
   - **通用服务镜像** → 推送到 `ghcr.io/<你的账号>/offline-registry:latest`
   - **离线数据包** → 自动创建一个 Release，内含 `data-package.tar.gz`
     （超限时为多个 `.part-*` 分卷文件，还原方法见 `data-package.README.txt`）

> 克隆**私有仓库**：先在 fork 仓库的 Settings → Secrets and variables → Actions 添加
> secret `REPO_TOKEN`（需对该私有仓库有读权限的 PAT），工作流会自动用它克隆。

### 方式 B：本地手动构建（调试）

```bash
# 需要本机装好 JDK21+Maven、Node、Go、Rust、Docker
bash build.sh https://github.com/owner/repo ./data      # 只播种数据
PACK_TARBALL=1 bash build.sh https://github.com/owner/repo ./data   # 播种并打包 tar.gz
docker build -t offline-registry:local registry/
```

## 内网使用

### 1. 下载并启动

```bash
# 拉取通用服务镜像（或 docker load 导入你保存的 tar）
docker pull ghcr.io/<你的账号>/offline-registry:latest

# 下载 Release 里的 data-package.tar.gz，解压出 ./data 目录
# （若 Release 内是 .part-* 分卷，先拼接：cat data-package.tar.gz.part-* > data-package.tar.gz）
mkdir -p data && tar -xzf data-package.tar.gz -C data

# 启动（建议用仓库里的 registry/docker-compose.yml，或直接）：
docker run -d --name offline-registry -p 8081:8081 -p 4873:4873 \
  -v "$PWD/data/maven:/data/maven" \
  -v "$PWD/data/go:/data/go" \
  -v "$PWD/data/node-dist:/data/node-dist" \
  -v "$PWD/data/cargo:/data/cargo" \
  -v "$PWD/data/verdaccio-storage:/opt/verdaccio/storage" \
  ghcr.io/<你的账号>/offline-registry:latest
```

> `registry/docker-compose.yml` 已写好全部挂载，把 `OWNER` 换成你的账号后 `docker compose up -d` 即可。

假设服务地址为 `http://<IP>:8081`（Maven/Go/Node/Cargo）、`http://<IP>:4873`（npm）：

### 2. Maven（Java）

在 `~/.m2/settings.xml` 加一个 mirror：

```xml
<mirror>
  <id>offline-registry</id>
  <url>http://<IP>:8081/maven</url>
  <mirrorOf>*</mirrorOf>
</mirror>
```

### 3. npm（Node）

```bash
export NPM_CONFIG_REGISTRY=http://<IP>:4873/
# 或写入 ~/.npmrc：registry=http://<IP>:4873/
```

### 4. Go

```bash
export GOPROXY=http://<IP>:8081/go/cache/download,off
# 校验和仍由项目 go.sum 校验，无需改动
```

### 5. Cargo（Rust）

把 Release 里 `data/cargo/vendor` 目录拷到项目根，并把 `data/cargo/cargo-config.toml` 内容写入项目的 `.cargo/config.toml`：

```toml
[source.crates-io]
replace-with = "vendored-sources"

[source.vendored-sources]
directory = "<vendor 绝对路径>"
```

## 批量提交多个项目

编辑根目录 `projects.json`（参考 `projects.example.json`），列出一个或多个仓库地址，然后运行
`build.sh` 时传入，或按你的 CI 流程循环调用 `build.sh <url>`。数据可合并进同一个 `data/` 目录后
挂载到同一容器，一套镜像服务多个项目。

## 目录结构

```
├── .github/workflows/build.yml   # Actions：解析→播种→推镜像→发数据包
├── build.sh                      # 主构建（克隆→探测→逐源播种→打包）
├── detect.sh                     # 探测语言生态
├── seeders/
│   ├── seed-maven.sh             # Maven 依赖 → 静态仓库
│   ├── seed-npm.sh               # npm 依赖 → Verdaccio 缓存
│   ├── seed-go.sh                # Go 依赖 → module proxy
│   └── seed-cargo.sh             # Cargo 依赖 → vendor 离线源
├── registry/                     # 通用服务镜像（nginx + Verdaccio）
└── docs/使用手册.md              # 详细说明
```

## 许可

本项目仅为工具，与 DataEase 无关。使用前请遵守各目标开源项目的许可证。
