# ficlash_docker 项目记忆

## 项目概况
- **用途**: FlClash 的 Docker 容器化项目，基于 multi-stage build（Ubuntu 提取 → Alpine 运行）
- **镜像基础**: `jlesage/baseimage-gui:alpine-3.23-v4.11.3`（提供 noVNC/VNC GUI）
- **CI/CD**: GitHub Actions workflow，每周一自动检查新版本构建，推送至 ghcr.io
- **版本追踪**: `.last-built-version` 文件记录上次构建的 FlClash 版本

## 关键技术细节
- FlClash deb 包依赖: `libkeybinder-3.0-0`, `libayatana-appindicator3-1`, `libgtk-3-0`, `libblkid1`, `liblzma5`, `libsecret-1-0`
- Docker Stage 1 (extractor) 必须预装这些依赖，否则 `apt-get install .deb` 会因 unmet dependencies 报 exit code 2
- 安装 deb 后需再 `apt-get update` 恢复索引，才能让 apt 解析 deb 的依赖声明
- `/dist` 目录需显式 `mkdir -p` 创建

## 修复历史
- 2026-04-18: 修复 Dockerfile 构建失败（exit code 2），根因是 Stage 1 缺少 FlClash 运行时依赖 + 未在安装 deb 前 apt-get update 恢复索引
- 2026-04-18: 修复 curl 下载 GitHub release 失败（exit code 77），根因是 ubuntu:24.04 基础镜像未安装 ca-certificates，导致 HTTPS 证书验证失败
