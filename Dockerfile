# syntax=docker/dockerfile:1
#
# zcode-hub 镜像（含 Chromium）：Python 运行时 + Node.js + Chromium。
# 支持 Z.AI JWT(Plan) 通道的免浏览器验证码求解（captcha_node/solver_pw.js：
# puppeteer-core + 系统 Chromium，--single-process 跑官方阿里云无痕 SDK）。
#
# 说明：相较纯 API-Key 的轻量镜像，本镜像体积大很多（Chromium + 运行库 ≈1GB+）。
# 若只需 zai apiKey / bigmodel（免验证码），可删去下面的 apt 段与 npm 段得到轻量版。
#
# 构建：docker compose build    运行：docker compose up -d

FROM python:3.11-slim

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PIP_NO_CACHE_DIR=1 \
    ZCODE_HOST=0.0.0.0 \
    ZCODE_PORT=3000 \
    ZCODE_DATA_DIR=data \
    ZCODE_NODE_PATH=node \
    ZCODE_CHROMIUM_PATH=/usr/bin/chromium

# 系统依赖：Chromium + Node.js（验证码求解）+ 中文字体 + 证书
RUN apt-get update && apt-get install -y --no-install-recommends \
        chromium \
        nodejs \
        npm \
        fonts-liberation \
        fonts-noto-cjk \
        ca-certificates \
    && rm -rf /var/lib/apt/lists/* \
    && ln -sf /usr/bin/chromium /usr/local/bin/chromium \
    && node --version && npm --version

WORKDIR /app

# Python 依赖层：仅 requirements.txt 变更时才重装
COPY requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt

# Node 依赖层（验证码求解器）：仅 package*.json 变更时才重装
COPY captcha_node/package.json captcha_node/package-lock.json ./captcha_node/
RUN cd captcha_node && npm install --omit=dev --no-audit --no-fund

# 应用代码
COPY cli.py ./
COPY app/ ./app/
COPY frontend/ ./frontend/
COPY captcha_node/ ./captcha_node/

# 数据目录（运行时由 ./data 卷覆盖）
RUN mkdir -p /app/data

EXPOSE 3000

# 探活：内置 Python 请求 GET /meta（无需额外安装 curl）
HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3 \
    CMD ["python", "-c", "import os,urllib.request,sys; p=os.getenv('ZCODE_PORT','3000'); sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:'+p+'/meta', timeout=4).status==200 else 1)"]

CMD ["python", "cli.py", "serve"]
