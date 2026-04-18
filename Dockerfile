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
# 安装 dpkg-dev（提供 ar 命令）用于提取 deb 包
RUN add-pkg \
        socat \
        dbus \
        libayatana-appindicator \
        curl \
        wget \
        jq \
        font-noto-cjk \
        font-wqy-zenhei \
        dpkg-dev

# ── 区域设置（Alpine musl，无需 locale-gen）──────────────────
ENV LANG=zh_CN.UTF-8
ENV LC_ALL=zh_CN.UTF-8

# ── 下载并安装 FlClash ───────────────────────────────────────
# FlClash Release 只有 .AppImage 和 .deb 两种 Linux 包
# 直接使用 .deb + dpkg -x 提取安装（Alpine 下最可靠，无需 FUSE）
RUN set -ex; \
    if [ "$FLCLASH_VERSION" = "latest" ]; then \
        echo "未指定版本，自动获取最新 Release..."; \
        FLCLASH_VERSION=$(curl -s https://api.github.com/repos/chen08209/FlClash/releases/latest \
            | jq -r '.tag_name'); \
    fi; \
    echo "目标版本: $FLCLASH_VERSION"; \
    \
    # 文件名中的版本号不带前缀 v（如 tag=v0.8.92 → 文件名=0.8.92）
    VER="${FLCLASH_VERSION#v}"; \
    URL_DEB="https://github.com/chen08209/FlClash/releases/download/${FLCLASH_VERSION}/FlClash-${VER}-linux-amd64.deb"; \
    \
    echo "使用 deb 安装: $URL_DEB"; \
    wget -O /tmp/flclash.deb "$URL_DEB"; \
    mkdir -p /tmp/flclash-extract; \
    # deb 本质是 ar 压缩包，用 ar x 直接拆包（不依赖 dpkg）
    ar x /tmp/flclash.deb --output=/tmp/flclash-extract; \
    # 找到解压出来的 debian-binary / data.tar.xz，手动处理
    if [ -f /tmp/flclash-extract/data.tar.xz ]; then \
        tar -xJf /tmp/flclash-extract/data.tar.xz -C /tmp/flclash-extract/; \
    elif [ -f /tmp/flclash-extract/data.tar.gz ]; then \
        tar -xzf /tmp/flclash-extract/data.tar.gz -C /tmp/flclash-extract/; \
    fi; \
    # FlClash deb 安装后二进制位于 /usr/bin/flclash（小写）
    if [ -f /tmp/flclash-extract/usr/bin/flclash ]; then \
        mv /tmp/flclash-extract/usr/bin/flclash /usr/local/bin/FlClash; \
    else \
        # 兜底：递归查找任意 flclash 可执行文件
        find /tmp/flclash-extract -name 'flclash' -type f -executable \
            -exec mv {} /usr/local/bin/FlClash \;; \
    fi; \
    rm -rf /tmp/flclash.deb /tmp/flclash-extract/; \
    chmod +x /usr/local/bin/FlClash; \
    echo "FlClash 安装完成"

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
