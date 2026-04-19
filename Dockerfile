#
# FlClash Dockerfile
# Multi-stage build: Ubuntu 提取 deb 二进制 → Ubuntu 运行（glibc 原生兼容）
#

# ── Stage 1：从 deb 包提取二进制（Ubuntu apt-get 自动处理依赖）──
FROM ubuntu:24.04 AS extractor

ARG FLCLASH_VERSION=latest

# 一次性安装工具包 + FlClash deb 声明的依赖
# 注意：deb 的 Depends 字段声明的是 -dev 包，必须精确匹配
# ca-certificates: curl 下载 GitHub release 必需，否则 exit code 77
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        ca-certificates \
        wget jq curl \
        libkeybinder-3.0-dev \
        libayatana-appindicator3-dev && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /tmp

# 拉取最新版本号并下载 deb
RUN FLCLASH_VERSION=$(curl -s https://api.github.com/repos/chen08209/FlClash/releases/latest \
        | jq -r '.tag_name') && \
    echo "FlClash 版本: $FLCLASH_VERSION" && \
    VER="${FLCLASH_VERSION#v}" && \
    URL="https://github.com/chen08209/FlClash/releases/download/${FLCLASH_VERSION}/FlClash-${VER}-linux-amd64.deb" && \
    echo "下载: $URL" && \
    curl -fL -o /tmp/flclash.deb "$URL" && \
    ls -la /tmp/flclash.deb

# 安装 deb：先 apt-get update 恢复索引，再用 apt-get install 解析 deb 依赖
# deb postinst 创建符号链接 /usr/bin/FlClash → /usr/share/FlClash/FlClash
# 直接复制实际二进制 /usr/share/FlClash/FlClash（符号链接在跨 stage 时不生效）
RUN apt-get update && \
    apt-get install -y /tmp/flclash.deb && \
    rm /tmp/flclash.deb && \
    rm -rf /var/lib/apt/lists/* && \
    mkdir -p /dist && \
    cp -r /usr/share/FlClash /dist/FlClash && \
    chmod +x /dist/FlClash/FlClash && \
    echo "二进制提取完成"

# ── Stage 2：Ubuntu 运行层（glibc 原生兼容，无 musl 问题）────
FROM jlesage/baseimage-gui:ubuntu-24.04-v4

ARG DOCKER_IMAGE_VERSION=unknown

# ── 从 Stage 1 复制提取好的 FlClash 目录 ─────────────────────
# FlClash 目录包含二进制 + 资源文件，必须整体复制
COPY --from=extractor /dist/FlClash /usr/share/FlClash
RUN ln -sf /usr/share/FlClash/FlClash /usr/bin/FlClash

# ── 安装运行时依赖 ────────────────────────────────────────────
# libgtk-3-0/libkeybinder/libayatana-appindicator: FlClash deb 声明的运行时 GTK 依赖
# libgl1/libegl1: Flutter 启动时 dlopen libEGL.so.1，即使 GSK_RENDERER=cairo 也必须装
# libatk-adaptor: GTK at-spi 辅助功能桥接，缺失会导致断言失败
# dbus/network-manager: connectivity_plus 通过 D-Bus 查询 NM 网络状态
#   无 NM 服务时 connectivity_plus 无限重试，CPU 飙到 90%+
# socat: 端口转发（宿主机 9091 → FlClash 内部 API 9090）
# locales: 中文 locale 支持（否则 Gtk-WARNING locale not supported）
# fonts: 中文字体支持
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        libgtk-3-0 \
        libkeybinder-3.0-0 \
        libayatana-appindicator3-1 \
        libgl1 \
        libegl1 \
        libatk-adaptor \
        dbus \
        network-manager \
        socat \
        locales \
        fonts-noto-cjk \
        fonts-wqy-zenhei && \
    sed -i '/zh_CN.UTF-8/s/^# //g' /etc/locale.gen && \
    locale-gen zh_CN.UTF-8 && \
    rm -rf /var/lib/apt/lists/*

# ── D-Bus machine-id ─────────────────────────────────────────
# 确保 D-Bus machine-id 存在，NM 注册 D-Bus 服务时需要
RUN mkdir -p /var/run/dbus && \
    dbus-uuidgen --ensure

# ── NetworkManager supervisor 服务 ──────────────────────────────
# cont-init.d 脚本执行时 dbus-daemon 尚未启动（supervisor 还没接管）
# 所以必须将 NM 作为 supervisor 服务，与 dbus 并行启动
# NM run 脚本先轮询等待 system_bus_socket 就绪，再启动 NM
RUN mkdir -p /etc/services.d/networkmanager && \
    printf '#!/bin/sh\n\
# 等待 dbus system bus socket 就绪\n\
while [ ! -S /var/run/dbus/system_bus_socket ]; do\n\
  sleep 0.5\n\
done\n\
mkdir -p /run/NetworkManager\n\
exec NetworkManager --no-daemon\n' > /etc/services.d/networkmanager/run && \
    chmod +x /etc/services.d/networkmanager/run

# ── 区域设置 ──────────────────────────────────────────────────
ENV LANG=zh_CN.UTF-8
ENV LC_ALL=zh_CN.UTF-8

# ── GTK 渲染器 ────────────────────────────────────────────────
# VNC 无 GPU 环境，必须走软件渲染，否则 Flutter SIGABRT
ENV GSK_RENDERER=cairo

# ── 启动脚本 ──────────────────────────────────────────────────
# socat: 宿主机 9091 → FlClash 内部 API 9090
RUN printf '#!/bin/sh\n\
socat TCP-LISTEN:9091,fork,reuseaddr TCP:127.0.0.1:9090 &\n\
exec FlClash\n' > /startapp.sh && chmod +x /startapp.sh

# ── baseimage-gui 应用元信息 ──────────────────────────────────
RUN \
    set-cont-env APP_NAME "FlClash" && \
    set-cont-env DOCKER_IMAGE_VERSION "$DOCKER_IMAGE_VERSION" && \
    true

# ── 持久化配置目录 ────────────────────────────────────────────
VOLUME ["/config"]

# ── 端口暴露 ──────────────────────────────────────────────────
# 5800 = Web GUI (noVNC)  5900 = VNC  7890 = HTTP 代理
# 1053 = DNS（UDP）  9091 = 外部 API（socat 转发）
EXPOSE 5800 5900 7890/tcp 1053/udp 9091/tcp

# ── Metadata ──────────────────────────────────────────────────
LABEL \
    org.label-schema.name="flclash" \
    org.label-schema.description="Docker container for FlClash (Ubuntu-based, multi-stage)" \
    org.label-schema.version="${DOCKER_IMAGE_VERSION:-unknown}" \
    org.label-schema.schema-version="1.0"
