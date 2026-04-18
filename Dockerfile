#
# flclash Dockerfile
# Based on Alpine for minimal footprint
#

FROM jlesage/baseimage-gui:alpine-3.23-v4.11.3

# Docker image version is provided via build arg.
ARG DOCKER_IMAGE_VERSION=unknown

# ── 安装依赖 ────────────────────────────────────────────────
# Alpine 用 apk；libayatana-appindicator / libkeybinder 在 Alpine
# 社区仓库中名称略有不同，用 libappindicator-gtk3 替代
RUN add-pkg \
        socat \
        dbus \
        libappindicator-gtk3 \
        curl \
        wget \
        font-noto-cjk \
        font-wqy-zenhei

# ── 区域设置（Alpine musl 不用 locale-gen）─────────────────
ENV LANG=zh_CN.UTF-8
ENV LC_ALL=zh_CN.UTF-8

# ── 下载并安装最新 FlClash（linux-amd64.deb → 用 dpkg/alien 或直接用 .tar.gz）
# FlClash 官方同时提供 .tar.gz，Alpine 上推荐用 tar.gz 避免 deb 依赖问题
RUN set -ex; \
    # 获取最新 release 中 linux-amd64.tar.gz 的下载地址
    url=$(curl -s https://api.github.com/repos/chen08209/FlClash/releases/latest \
      | grep browser_download_url \
      | grep 'linux-amd64\.tar\.gz"' \
      | cut -d '"' -f 4); \
    echo "Downloading $url"; \
    wget -O /tmp/flclash.tar.gz "$url"; \
    tar -xzf /tmp/flclash.tar.gz -C /usr/local/bin/ --wildcards '*/FlClash' --strip-components=1; \
    chmod +x /usr/local/bin/FlClash; \
    rm /tmp/flclash.tar.gz

# ── 启动脚本 ────────────────────────────────────────────────
RUN printf '#!/bin/sh\n\
# 将 9091 端口转发到 FlClash 内置 API 9090\n\
socat TCP-LISTEN:9091,fork,reuseaddr TCP:127.0.0.1:9090 &\n\
# 启动 FlClash\n\
exec FlClash\n' > /startapp.sh && chmod +x /startapp.sh

# ── 应用元信息（baseimage-gui 通过环境变量识别应用）──────────
RUN \
    set-cont-env APP_NAME "FlClash" && \
    set-cont-env DOCKER_IMAGE_VERSION "$DOCKER_IMAGE_VERSION" && \
    true

# ── 持久化配置目录 ──────────────────────────────────────────
VOLUME ["/config"]

# ── 暴露端口 ────────────────────────────────────────────────
# 5800=Web GUI  5900=VNC  7890=HTTP代理  1053=DNS  9091=外部API
EXPOSE 5800 5900 7890/tcp 1053/udp 9091/tcp

# ── Metadata ────────────────────────────────────────────────
LABEL \
    org.label-schema.name="flclash" \
    org.label-schema.description="Docker container for FlClash (Alpine)" \
    org.label-schema.version="${DOCKER_IMAGE_VERSION:-unknown}" \
    org.label-schema.schema-version="1.0"
