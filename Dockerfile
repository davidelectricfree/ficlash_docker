#
# FlClash Dockerfile
# Multi-stage build: Ubuntu 提取 deb 二进制 → Ubuntu 运行（FlClash 依赖 glibc，不兼容 Alpine musl）
#

# ── Stage 1：从 deb 包提取完整安装 ──
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
# 复制整个 /usr/share/FlClash 目录（含二进制 + 资源文件）到 /dist
RUN apt-get update && \
    apt-get install -y /tmp/flclash.deb && \
    rm /tmp/flclash.deb && \
    rm -rf /var/lib/apt/lists/* && \
    mkdir -p /dist && \
    cp -a /usr/share/FlClash /dist/FlClash && \
    chmod +x /dist/FlClash/FlClash && \
    echo "二进制提取完成"

# ── Stage 2：Ubuntu 运行层 ──
# FlClash 是 glibc 编译的 GTK/Flutter 应用，Alpine 的 musl libc 不兼容
# 使用 jlesage/baseimage-gui 的 Ubuntu 变体（同样提供 noVNC/VNC GUI）
FROM jlesage/baseimage-gui:ubuntu-24.04-v4.11.3

ARG DOCKER_IMAGE_VERSION=unknown

# ── 从 Stage 1 复制 FlClash 安装目录 ──
COPY --from=extractor /dist/FlClash /usr/share/FlClash

# 创建符号链接让 FlClash 可在 PATH 中找到
RUN ln -sf /usr/share/FlClash/FlClash /usr/local/bin/FlClash

# ── 安装运行时依赖 ──
# libgl1: OpenGL 运行时（提供 libGL.so.1）
# libegl1: EGL 运行时（提供 libEGL.so.1，Flutter 启动时 dlopen 必需，否则 SIGABRT）
# libatk-adaptor: ATK 辅助功能桥接（消除 atk_socket_embed assertion 警告）
# dbus: 系统消息总线（connectivity_plus 通过 D-Bus/NetworkManager 检测网络，无 system bus 会 CPU 狂转）
# locales: 中文 locale 支持（否则 Gtk-WARNING locale not supported）
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        libkeybinder-3.0-0 \
        libayatana-appindicator3-1 \
        libgtk-3-0 \
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

# D-Bus system bus 支持
# connectivity_plus 通过 D-Bus 连接 NetworkManager 检测网络状态
# 容器内需有 dbus-daemon 提供 system bus socket，否则 connectivity_plus 无限重试吃满 CPU
# 方案：安装 dbus + network-manager（提供 NM 的 D-Bus 服务和 introspection 数据）
#       startapp.sh 中启动 dbus-daemon --system + NetworkManager
RUN mkdir -p /var/run/dbus && \
    dbus-uuidgen --ensure && \
    printf '<!DOCTYPE busconfig PUBLIC "-//freedesktop//DTD D-Bus Bus Configuration 1.0//EN"\n\
 "http://www.freedesktop.org/standards/dbus/1.0/busconfig.dtd">\n\
<busconfig>\n\
  <type>system</type>\n\
  <auth>ANONYMOUS</auth>\n\
  <allow_anonymous/>\n\
  <listen>unix:path=/var/run/dbus/system_bus_socket</listen>\n\
  <policy context="default">\n\
    <allow send_destination="*"/>\n\
    <allow receive_sender="*"/>\n\
    <allow own="*"/>\n\
    <allow user="*"/>\n\
  </policy>\n\
</busconfig>\n' > /etc/dbus-1/system.conf

# ── 区域设置 ──
ENV LANG=zh_CN.UTF-8
ENV LC_ALL=zh_CN.UTF-8

# ── Flutter/GTK 渲染设置 ──
# VNC 环境无 GPU，必须用 cairo 软件渲染（默认 GL 渲染会 SIGABRT）
ENV GSK_RENDERER=cairo

# ── 启动脚本 ──
# D-Bus system bus 策略：
#   若宿主机已挂载 /run/dbus/system_bus_socket，则直接使用（宿主机有完整 NetworkManager）
#   否则容器内自建 dbus-daemon + NetworkManager
# socat: 宿主机 9091 → FlClash 内部 API 9090
RUN printf '#!/bin/sh\n\
mkdir -p /var/run/dbus\n\
if [ -S /run/dbus/system_bus_socket ]; then\n\
  echo "检测到宿主机 D-Bus system bus，跳过容器内 dbus-daemon"\n\
else\n\
  echo "未检测到宿主机 D-Bus system bus，启动容器内 dbus-daemon"\n\
  rm -f /var/run/dbus/pid /var/run/dbus/system_bus_socket\n\
  dbus-daemon --system --config-file=/etc/dbus-1/system.conf\n\
  NetworkManager --no-daemon &\n\
  sleep 1\n\
fi\n\
socat TCP-LISTEN:9091,fork,reuseaddr TCP:127.0.0.1:9090 &\n\
exec FlClash\n' > /startapp.sh && chmod +x /startapp.sh

# ── baseimage-gui 应用元信息 ──
RUN \
    set-cont-env APP_NAME "FlClash" && \
    set-cont-env DOCKER_IMAGE_VERSION "$DOCKER_IMAGE_VERSION" && \
    true

# ── 持久化配置目录 ──
VOLUME ["/config"]

# ── 端口暴露 ──
# 5800 = Web GUI (noVNC)  5900 = VNC  7890 = HTTP 代理
# 1053 = DNS（UDP）  9091 = 外部 API（socat 转发）
EXPOSE 5800 5900 7890/tcp 1053/udp 9091/tcp

# ── Metadata ──
LABEL \
    org.label-schema.name="flclash" \
    org.label-schema.description="Docker container for FlClash (Ubuntu-based, multi-stage)" \
    org.label-schema.version="${DOCKER_IMAGE_VERSION:-unknown}" \
    org.label-schema.schema-version="1.0"
