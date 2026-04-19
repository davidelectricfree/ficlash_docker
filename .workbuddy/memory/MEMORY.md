# ficlash_docker 项目记忆

## 项目概况
- **用途**: FlClash 的 Docker 容器化项目，基于 multi-stage build
- **镜像基础**: `jlesage/baseimage-gui`（提供 noVNC/VNC GUI）
- **CI/CD**: GitHub Actions workflow，每周一自动检查新版本构建，推送至 ghcr.io
- **版本追踪**: `.last-built-version` 文件记录上次构建的 FlClash 版本

## 关键技术细节
- FlClash deb 的 Depends 字段声明的是 **-dev 包**：`libayatana-appindicator3-dev`, `libkeybinder-3.0-dev`（不是运行时库 -1/-0）
- apt-get install .deb 必须精确匹配 deb 声明的依赖包名，否则 exit code 2
- FlClash deb 安装路径：二进制在 `/usr/share/FlClash/FlClash`，postinst 创建符号链接 `/usr/bin/FlClash`
- 跨 stage COPY 时不能复制符号链接，必须复制实际二进制 `/usr/share/FlClash/FlClash`
- `/dist` 目录需显式 `mkdir -p` 创建
- control.tar.zst 需用 zstandard 库解压，非 gzip

## jlesage/baseimage-gui 架构要点
- supervisor 管理 Xvnc/nginx/openbox/dbus/app 等服务
- cont-init.d 脚本以 root 在 supervisor 启动**之前**执行，此时 dbus-daemon 还没跑
- `/etc/services.d/<name>/run` 添加自定义 supervisor 服务，与 dbus 等并行启动
- dbus 服务由 supervisor 内置管理，system_bus_socket 在 supervisor 阶段才创建
- startapp.sh 以非 root 用户运行（app 服务降权），不能操作 /var/run/dbus 下的文件

## FlClash 容器化关键问题
- FlClash 是 glibc 编译的 GTK/Flutter 应用，**Alpine 的 musl libc 不兼容**（exec 报 "not found"，exit 127）
- Flutter 启动时在 GSK 渲染器初始化之前先 dlopen libEGL.so.1，**即使设了 GSK_RENDERER=cairo 也必须装 libegl1**，否则 SIGABRT
- VNC 无 GPU 环境，必须设 `GSK_RENDERER=cairo` 走软件渲染
- FlClash 目录包含资源文件（不只是二进制），必须整体复制 `/usr/share/FlClash`

## connectivity_plus CPU 占用问题（核心）
- `connectivity_plus` 插件通过 D-Bus 连接 NetworkManager 检测网络状态
- **容器内无 NM 服务 → 无限重试 → CPU 90%+**
- 仅挂载宿主机 `/run/dbus/system_bus_socket` 无效：群晖 DSM 不运行 NM，找不到 NM 服务仍会重试
- 仅启动 dbus-daemon 不够：连上 D-Bus 但找不到 `org.freedesktop.NetworkManager` 服务仍会重试
- **正确方案**：将 NM 作为 `/etc/services.d/networkmanager/run` supervisor 服务启动
  - cont-init.d 方案不行：执行时 dbus-daemon 尚未启动，NM 连不上 D-Bus
  - startapp.sh 方案不行：以非 root 运行，Permission denied
  - supervisor 服务方案：NM 和 dbus 并行启动，NM run 脚本等待 socket 就绪后再启动

## 修复历史
- 2026-04-18: 修复 Dockerfile 构建失败（exit code 2），根因是 Stage 1 缺少 FlClash 运行时依赖 + 未在安装 deb 前 apt-get update 恢复索引
- 2026-04-18: 修复 curl 下载 GitHub release 失败（exit code 77），根因是 ubuntu:24.04 基础镜像未安装 ca-certificates，导致 HTTPS 证书验证失败
- 2026-04-18: 修复容器运行 FlClash 报 "not found" exit 127，根因是 FlClash 为 glibc 编译，Alpine musl 不兼容；将运行层从 Alpine 改为 Ubuntu
- 2026-04-18: 修复 SIGABRT（缺 libGL + locale），添加 libgl1、locale-gen zh_CN.UTF-8、GSK_RENDERER=cairo
- 2026-04-18: 修复 SIGABRT（缺 libEGL.so.1），添加 libegl1、libatk-adaptor；Flutter 即使 GSK_RENDERER=cairo 也需 libegl1
- 2026-04-19: 修复 CPU 占用过高，将 NM 从 cont-init.d/startapp.sh 改为 /etc/services.d/ supervisor 服务；解决权限和启动时序问题
- 2026-04-19: 全面修复 Dockerfile：Alpine→Ubuntu 运行层、整体复制 FlClash 目录、补全所有运行时依赖（libgl1/libegl1/libatk-adaptor/dbus/NM）、D-Bus 宽松配置、NM supervisor 服务、GSK_RENDERER=cairo、compose 启用权限
