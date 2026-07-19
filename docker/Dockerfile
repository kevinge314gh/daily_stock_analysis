FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=Asia/Shanghai

# 清华 apt 源
RUN sed -i \
        -e 's|archive.ubuntu.com|mirrors.tuna.tsinghua.edu.cn|g' \
        -e 's|security.ubuntu.com|mirrors.tuna.tsinghua.edu.cn|g' \
        /etc/apt/sources.list.d/ubuntu.sources 2>/dev/null || \
    sed -i \
        -e 's|archive.ubuntu.com|mirrors.tuna.tsinghua.edu.cn|g' \
        -e 's|security.ubuntu.com|mirrors.tuna.tsinghua.edu.cn|g' \
        /etc/apt/sources.list

RUN apt-get update && apt-get install -y --no-install-recommends \
        python3 \
        python3-pip \
        python3-venv \
        python-is-python3 \
        gcc \
        curl \
        git \
        gosu \
        openvpn \
        iproute2 \
        iputils-ping \
        wkhtmltopdf \
        fontconfig \
        libjpeg-turbo8 \
        libxrender1 \
        libxext6 \
        tzdata \
        ca-certificates \
    && ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone \
    && rm -rf /var/lib/apt/lists/*

# Node.js 22 + Claude Code CLI
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && npm config set registry https://registry.npmmirror.com/ \
    && npm install -g @anthropic-ai/claude-code \
    && rm -rf /var/lib/apt/lists/*

# 创建非 root 用户（ubuntu:24.04 默认已有 uid/gid 1000，先清理再建）
RUN if getent group 1000 >/dev/null; then groupmod -n dsa "$(getent group 1000 | cut -d: -f1)"; else groupadd -g 1000 dsa; fi \
    && if getent passwd 1000 >/dev/null; then usermod -l dsa -d /home/dsa -m "$(getent passwd 1000 | cut -d: -f1)" 2>/dev/null || true; else useradd -u 1000 -g dsa -m dsa; fi

WORKDIR /app

# Python 依赖
COPY requirements.txt .
RUN pip3 install --break-system-packages -r requirements.txt 2>/dev/null || \
    pip3 install -r requirements.txt

# 破坏缓存，确保每次部署都更新代码层与前端产物
ARG CACHEBUST=1

# 前端静态文件（本地预构建，直接复制）
# 放在 CACHEBUST 之后：前端每次部署必更新，且前端改动不再让上面的依赖层缓存失效
COPY static/ ./static/

# 应用代码
COPY *.py ./
COPY api/ ./api/
COPY data_provider/ ./data_provider/
COPY bot/ ./bot/
COPY src/ ./src/
COPY strategies/ ./strategies/
COPY docker/entrypoint.sh /usr/local/bin/docker-entrypoint.sh
COPY docker/openvpn-up.sh /usr/local/bin/openvpn-up.sh

# Verify AlphaSift adapter
RUN python -c "import alphasift.dsa_adapter"

# 目录权限
RUN mkdir -p /app/data /app/logs /app/reports && \
    chown -R dsa:dsa /app && \
    chmod +x /usr/local/bin/docker-entrypoint.sh /usr/local/bin/openvpn-up.sh

# efinance 缓存目录属主修复
RUN EF_DATA_DIR="$(python -c 'import efinance, pathlib; print(pathlib.Path(efinance.__file__).parent / "data")')" && \
    mkdir -p "$EF_DATA_DIR" && chown -R dsa:dsa "$EF_DATA_DIR"

ENV PYTHONUNBUFFERED=1
ENV LOG_DIR=/app/logs
ENV DATABASE_PATH=/app/data/stock_analysis.db
ENV WEBUI_HOST=0.0.0.0
ENV API_PORT=8000

EXPOSE 8000
VOLUME ["/app/data", "/app/logs", "/app/reports"]

HEALTHCHECK --interval=30s --timeout=10s --start-period=10s --retries=3 \
    CMD curl -f http://localhost:8000/api/health || curl -f http://localhost:8000/health \
    || python -c "import sys; sys.exit(0)"

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
CMD ["python", "main.py", "--schedule"]
