#
# FlClash Dockerfile
# Base: Alpine (minimal footprint, lower CPU overhead)
#

FROM jlesage/baseimage-gui:alpine-3.23-v4.11.3

# ── Build args（由 CI workflow 注入，本地构建时自动拉取最新版）──
ARG FLCLASH_VERSION=latest
ARG DOCKER_IMAGE_VERSION=unknown

# ── 工作目录 ────────────────────────────────────────────────
WORKDIR /tmp

# ── 确保 community 仓库已启用（字体包在此仓库中）──────────
RUN echo "https://dl-cdn.alpinelinux.org/alpine/v3.23/community" >> /etc/apk/repositories

# ── 安装依赖 ────────────────────────────────────────────────
# 注意：Alpine 3.23 中 appindicator 已迁移为 libayatana-appindicator
RUN add-pkg \
        socat \
        dbus \
        libayatana-appindicator \
        curl \
        wget \
        jq \
        font-noto-cjk \
        font-wqy-zenhei

# ── 区域设置（Alpine musl，无需 locale-gen）──────────────────
ENV LANG=zh_CN.UTF-8
ENV LC_ALL=zh_CN.UTF-8

# ── 下载并安装 FlClash ───────────────────────────────────────
# 优先使用 CI 注入的 FLCLASH_VERSION；若为 "latest" 则自动查询最新版
RUN set -ex; \
    if [ "$FLCLASH_VERSION" = "latest" ]; then \
        echo "未指定版本，自动获取最新 Release..."; \
        FLCLASH_VERSION=$(curl -s https://api.github.com/repos/chen08209/FlClash/releases/latest \
            | jq -r '.tag_name'); \
    fi; \
    echo "目标版本: $FLCLASH_VERSION"; \
    \
    # 尝试下载 tar.gz（Alpine 首选，无需 dpkg 依赖）
    URL_TGZ="https://github.com/chen08209/FlClash/releases/download/${FLCLASH_VERSION}/FlClash-${FLCLASH_VERSION#v}-linux-amd64.tar.gz"; \
    URL_DEB="https://github.com/chen08209/FlClash/releases/download/${FLCLASH_VERSION}/FlClash-${FLCLASH_VERSION#v}-linux-amd64.deb"; \
    \
    if wget -q --spider "$URL_TGZ" 2>/dev/null; then \
        echo "使用 tar.gz 安装: $URL_TGZ"; \
        wget -O /tmp/flclash.tar.gz "$URL_TGZ"; \
        mkdir -p /tmp/flclash-extract; \
        tar -xzf /tmp/flclash.tar.gz -C /tmp/flclash-extract/; \
        find /tmp/flclash-extract -name 'FlClash' -type f -exec mv {} /usr/local/bin/FlClash \;; \
        rm -rf /tmp/flclash.tar.gz /tmp/flclash-extract/; \
    else \
        echo "tar.gz 不可用，尝试 deb 安装（需要 dpkg）: $URL_DEB"; \
        add-pkg dpkg; \
        wget -O /tmp/flclash.deb "$URL_DEB"; \
        dpkg -x /tmp/flclash.deb /tmp/flclash-deb/; \
        find /tmp/flclash-deb -name 'FlClash' -type f -exec mv {} /usr/local/bin/FlClash \;; \
        rm -rf /tmp/flclash.deb /tmp/flclash-deb/; \
    fi; \
    chmod +x /usr/local/bin/FlClash; \
    echo "FlClash 安装完成: $(FlClash --version 2>/dev/null || echo '版本信息不可用')"

# ── 启动脚本 ────────────────────────────────────────────────
# socat 将宿主机可达的 9091 转发到 FlClash 内部 API 9090
RUN printf '#!/bin/sh\n\
socat TCP-LISTEN:9091,fork,reuseaddr TCP:127.0.0.1:9090 &\n\
exec FlClash\n' > /startapp.sh && chmod +x /startapp.sh

# ── baseimage-gui 应用元信息 ────────────────────────────────
RUN \
    set-cont-env APP_NAME "FlClash" && \
    set-cont-env APP_VERSION "$FLCLASH_VERSION" && \
    set-cont-env DOCKER_IMAGE_VERSION "$DOCKER_IMAGE_VERSION" && \
    true

# ── 持久化配置目录 ──────────────────────────────────────────
VOLUME ["/config"]

# ── 端口暴露 ────────────────────────────────────────────────
# 5800 = Web GUI (noVNC)
# 5900 = VNC
# 7890 = HTTP/HTTPS 代理
# 1053 = DNS（UDP）
# 9091 = FlClash 外部 API（socat 转发）
EXPOSE 5800 5900 7890/tcp 1053/udp 9091/tcp

# ── Metadata ────────────────────────────────────────────────
LABEL \
    org.label-schema.name="flclash" \
    org.label-schema.description="Docker container for FlClash (Alpine-based)" \
    org.label-schema.version="${DOCKER_IMAGE_VERSION:-unknown}" \
    org.label-schema.schema-version="1.0"
