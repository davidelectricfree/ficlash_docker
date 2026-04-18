# ficlash_docker 项目记忆

## 项目概况
- **用途**: FlClash 的 Docker 容器化项目，基于 multi-stage build（Ubuntu 提取 → Alpine 运行）
- **镜像基础**: `jlesage/baseimage-gui:alpine-3.23-v4.11.3`（提供 noVNC/VNC GUI）
- **CI/CD**: GitHub Actions workflow，每周一自动检查新版本构建，推送至 ghcr.io
- **版本追踪**: `.last-built-version` 文件记录上次构建的 FlClash 版本

## 关键技术细节
- FlClash deb 的 Depends 字段声明的是 **-dev 包**：`libayatana-appindicator3-dev`, `libkeybinder-3.0-dev`（不是运行时库 -1/-0）
- apt-get install .deb 必须精确匹配 deb 声明的依赖包名，否则 exit code 2
- FlClash deb 安装路径：二进制在 `/usr/share/FlClash/FlClash`，postinst 创建符号链接 `/usr/bin/FlClash`
- 跨 stage COPY 时不能复制符号链接，必须复制实际二进制 `/usr/share/FlClash/FlClash`
- `/dist` 目录需显式 `mkdir -p` 创建
- control.tar.zst 需用 zstandard 库解压，非 gzip

## 修复历史
- 2026-04-18: 修复 Dockerfile 构建失败（exit code 2），根因是 Stage 1 缺少 FlClash 运行时依赖 + 未在安装 deb 前 apt-get update 恢复索引
- 2026-04-18: 修复 curl 下载 GitHub release 失败（exit code 77），根因是 ubuntu:24.04 基础镜像未安装 ca-certificates，导致 HTTPS 证书验证失败
