#
# FlClash Dockerfile
# Multi-stage build: Ubuntu 提取 deb 二进制 → Alpine 运行（最小体积 + 最低 CPU 占用）
#

# ── Stage 1：从 deb 包提取二进制（Ubuntu apt-get 自动处理依赖）──
FROM ubuntu:24.04 AS extractor

ARG FLCLASH_VERSION=latest

# 一次性安装工具包 + FlClash 运行时依赖，再下载并安装 deb
# 关键：apt-get update 后不删除 lists，确保后续 apt-get install .deb 能解析依赖
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        wget jq curl \
        libkeybinder-3.0-0 \
        libayatana-appindicator3-1 \
        libgtk-3-0 \
        libblkid1 \
        liblzma5 \
        libsecret-1-0 && \
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
RUN apt-get update && \
    apt-get install -y /tmp/flclash.deb && \
    rm /tmp/flclash.deb && \
    rm -rf /var/lib/apt/lists/* && \
    mkdir -p /dist && \
    ls -la /usr/bin/flclash && \
    cp /usr/bin/flclash /dist/flclash && \
    chmod +x /dist/flclash && \
    echo "二进制提取完成"

# ── Stage 2：Alpine 运行层（镜像体积小、CPU 占用低）────────
FROM jlesage/baseimage-gui:alpine-3.23-v4.11.3

ARG DOCKER_IMAGE_VERSION=unknown

# ── 从 Stage 1 复制提取好的二进制 ──────────────────────────
COPY --from=extractor /dist/flclash /usr/local/bin/FlClash

# ── 安装必要依赖 ────────────────────────────────────────────
RUN echo "https://dl-cdn.alpinelinux.org/alpine/v3.23/community" >> /etc/apk/repositories && \
    add-pkg \
        socat \
        dbus \
        libayatana-appindicator \
        font-noto-cjk \
        font-wqy-zenhei

# ── 区域设置 ────────────────────────────────────────────────
ENV LANG=zh_CN.UTF-8
ENV LC_ALL=zh_CN.UTF-8

# ── 启动脚本 ────────────────────────────────────────────────
# socat: 宿主机 9091 → FlClash 内部 API 9090
RUN printf '#!/bin/sh\n\
socat TCP-LISTEN:9091,fork,reuseaddr TCP:127.0.0.1:9090 &\n\
exec FlClash\n' > /startapp.sh && chmod +x /startapp.sh

# ── baseimage-gui 应用元信息 ────────────────────────────────
RUN \
    set-cont-env APP_NAME "FlClash" && \
    set-cont-env DOCKER_IMAGE_VERSION "$DOCKER_IMAGE_VERSION" && \
    true

# ── 持久化配置目录 ──────────────────────────────────────────
VOLUME ["/config"]

# ── 端口暴露 ────────────────────────────────────────────────
# 5800 = Web GUI (noVNC)  5900 = VNC  7890 = HTTP 代理
# 1053 = DNS（UDP）  9091 = 外部 API（socat 转发）
EXPOSE 5800 5900 7890/tcp 1053/udp 9091/tcp

# ── Metadata ────────────────────────────────────────────────
LABEL \
    org.label-schema.name="flclash" \
    org.label-schema.description="Docker container for FlClash (Alpine-based, multi-stage)" \
    org.label-schema.version="${DOCKER_IMAGE_VERSION:-unknown}" \
    org.label-schema.schema-version="1.0"
