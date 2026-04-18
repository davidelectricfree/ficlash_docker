#
# FlClash Dockerfile
# Multi-stage build: Ubuntu 提取 AppImage → Alpine 运行（最小体积 + 最低 CPU 占用）
#

# ── Stage 1：从 AppImage 提取真实二进制（Ubuntu 有 FUSE）──
FROM ubuntu:24.04 AS extractor

ARG FLCLASH_VERSION=latest

RUN apt-get update && \
    apt-get install -y wget jq && rm -rf /var/lib/apt/lists/*

WORKDIR /tmp

RUN if [ "$FLCLASH_VERSION" = "latest" ]; then \
        FLCLASH_VERSION=$(curl -s https://api.github.com/repos/chen08209/FlClash/releases/latest \
            | jq -r '.tag_name'); \
    fi && \
    echo "目标版本: $FLCLASH_VERSION"; \
    \
    VER="${FLCLASH_VERSION#v}"; \
    wget -q -O /tmp/flclash.AppImage \
        "https://github.com/chen08209/FlClash/releases/download/${FLCLASH_VERSION}/FlClash-${VER}-linux-amd64.AppImage"; \
    chmod +x /tmp/flclash.AppImage; \
    /tmp/flclash.AppImage --appimage-extract; \
    \
    # 找到提取后的 flclash 二进制（位于 squashfs-root 内）
    cp "$(find /tmp/squashfs-root -name 'flclash' -type f -executable ! -name '*.sh' | head -1)" /dist/flclash; \
    chmod +x /dist/flclash; \
    echo "FlClash 二进制提取完成"

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
ARG FLCLASH_VERSION=latest
RUN \
    set-cont-env APP_NAME "FlClash" && \
    set-cont-env APP_VERSION "$FLCLASH_VERSION" && \
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
