# ficlash_docker 项目记忆

## 项目概况
- **用途**: FlClash 的 Docker 容器化项目，基于 multi-stage build（Ubuntu 提取 → Ubuntu 运行）
- **镜像基础**: `jlesage/baseimage-gui:ubuntu-24.04-v4.11.3`（提供 noVNC/VNC GUI）
- **CI/CD**: GitHub Actions workflow，每周一自动检查新版本构建，推送至 ghcr.io
- **版本追踪**: `.last-built-version` 文件记录上次构建的 FlClash 版本

## 关键技术细节
- FlClash deb 的 Depends 字段声明的是 **-dev 包**：`libayatana-appindicator3-dev`, `libkeybinder-3.0-dev`（不是运行时库 -1/-0）
- apt-get install .deb 必须精确匹配 deb 声明的依赖包名，否则 exit code 2
- FlClash deb 安装路径：二进制在 `/usr/share/FlClash/FlClash`，postinst 创建符号链接 `/usr/bin/FlClash`
- 跨 stage COPY 时不能复制符号链接，必须复制实际二进制 `/usr/share/FlClash/FlClash`
- FlClash 是 glibc 编译的 GTK/Flutter 应用，**Alpine 的 musl libc 不兼容**（exec 报 "not found"，exit 127）
- Flutter 启动时在 GSK 渲染器初始化之前先 dlopen libEGL.so.1，**即使设了 GSK_RENDERER=cairo 也必须装 libegl1**，否则 SIGABRT
- `connectivity_plus` 插件通过 D-Bus NetworkManager 检测网络，**容器内无 system bus socket 会导致无限重试吃满 CPU**，必须安装 dbus 包并启动 dbus-daemon --system
- 仅挂载宿主机 `/run/dbus/system_bus_socket` 不够，群晖 DSM 上 NetworkManager 不运行，connectivity_plus 连上 D-Bus 后找不到 NM 服务仍会重试。**必须在容器内自建 dbus-daemon + NetworkManager**
- 容器内 NetworkManager 无需 NET_ADMIN 也可启动，会在 D-Bus 上注册服务
- `/dist` 目录需显式 `mkdir -p` 创建
- control.tar.zst 需用 zstandard 库解压，非 gzip
- FlClash 目录包含资源文件（不只是二进制），必须整体复制 `/usr/share/FlClash`

## 修复历史
- 2026-04-18: 修复 Dockerfile 构建失败（exit code 2），根因是 Stage 1 缺少 FlClash 运行时依赖 + 未在安装 deb 前 apt-get update 恢复索引
- 2026-04-18: 修复 curl 下载 GitHub release 失败（exit code 77），根因是 ubuntu:24.04 基础镜像未安装 ca-certificates，导致 HTTPS 证书验证失败
- 2026-04-18: 修复容器运行 FlClash 报 "not found" exit 127，根因是 FlClash 为 glibc 编译，Alpine musl 不兼容；将运行层从 Alpine 改为 Ubuntu
- 2026-04-18: 修复 SIGABRT（缺 libGL + locale），添加 libgl1、locale-gen zh_CN.UTF-8、GSK_RENDERER=cairo
- 2026-04-18: 修复 SIGABRT（缺 libEGL.so.1），添加 libegl1、libatk-adaptor；Flutter 即使 GSK_RENDERER=cairo 也需 libegl1
- 2026-04-18: 修复 CPU 占用过高，根因是 connectivity_plus 无 D-Bus system bus 进入无限重试；安装 dbus 包 + 启动 dbus-daemon --system
