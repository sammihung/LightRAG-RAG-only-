# syntax=docker/dockerfile:1

# ==========================================
# 1. Frontend Builder (已修復 Cache & Lockfile 問題)
# ==========================================
FROM oven/bun:1 AS frontend-builder
WORKDIR /app

# 👇 [步驟 1] 只複製 package.json (如果此檔案沒變，Docker 會直接用 Cache 跳過下面那行 install)
COPY lightrag_webui/package.json ./lightrag_webui/

# 👇 [步驟 2] 安裝依賴 (拿掉了 --frozen-lockfile，保證能跑)
RUN cd lightrag_webui \
    && bun install

# 👇 [步驟 3] 這時候才複製剩下的源代碼
COPY lightrag_webui/ ./lightrag_webui/

# 👇 [步驟 4] 開始 Build (改代碼只會重跑這一步，超快！)
RUN cd lightrag_webui && bun run build

# ==========================================
# 2. Python Builder (保持完美的狀態)
# ==========================================
FROM ghcr.io/astral-sh/uv:python3.10-bookworm-slim AS builder

ENV DEBIAN_FRONTEND=noninteractive
ENV UV_SYSTEM_PYTHON=1
ENV UV_HTTP_TIMEOUT=500
ENV UV_CONCURRENT_DOWNLOADS=4

WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends \
    curl build-essential pkg-config \
    && rm -rf /var/lib/apt/lists/* \
    && curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y

ENV PATH="/root/.cargo/bin:/root/.local/bin:${PATH}"
RUN mkdir -p /root/.local/share/uv

COPY pyproject.toml setup.py uv.lock ./

RUN --mount=type=cache,target=/root/.local/share/uv \
    uv sync --frozen --no-dev --extra api --extra offline --no-install-project --no-editable

# 安裝 MinerU 全家桶 (含 Table & Formula)
RUN --mount=type=cache,target=/root/.local/share/uv \
    uv pip install \
        --python /app/.venv \
        "raganything[all]" \
        huggingface_hub \
        magic-pdf \
        opencv-python-headless \
        ultralytics \
        doclayout-yolo \
        paddlepaddle \
        paddleocr \
        rapid-table \
        unimernet

RUN echo "🔧 Patching RAGAnything import bug..." \
    && sed -i 's/from lightrag.mineru_parser import MineruParser/from .mineru_parser import MineruParser/g' \
       $(find /app/.venv -name "raganything.py")

COPY lightrag/ ./lightrag/
COPY --from=frontend-builder /app/lightrag/api/webui ./lightrag/api/webui

RUN uv pip install --python /app/.venv --no-deps .

RUN mkdir -p /app/data/tiktoken \
    && uv run lightrag-download-cache --cache-dir /app/data/tiktoken || status=$?; \
    if [ -n "${status:-}" ] && [ "$status" -ne 0 ] && [ "$status" -ne 2 ]; then exit "$status"; fi

# ==========================================
# 3. Final Stage (Runtime)
# ==========================================
FROM python:3.10-slim

WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends \
    libgl1 libglib2.0-0 poppler-utils tesseract-ocr \
    git git-lfs dos2unix \
    && rm -rf /var/lib/apt/lists/* \
    && git lfs install

COPY --from=ghcr.io/astral-sh/uv:latest /uv /usr/local/bin/uv
ENV UV_SYSTEM_PYTHON=1

ENV MINERU_MODEL_DIR="/app/data/mineru_models" \
    MINERU_REPO_ID="opendatalab/PDF-Extract-Kit" \
    LIGHTRAG_WORKER_TIMEOUT=1800 \
    MAGIC_PDF_CONFIG_JSON="/app/magic-pdf.json"

COPY --from=builder /root/.local /root/.local
COPY --from=builder /app/.venv /app/.venv
COPY --from=builder /app/lightrag ./lightrag
COPY pyproject.toml setup.py uv.lock ./

ENV PATH=/app/.venv/bin:/root/.local/bin:$PATH

COPY entrypoint.sh /app/entrypoint.sh
RUN dos2unix /app/entrypoint.sh && chmod +x /app/entrypoint.sh

RUN mkdir -p /app/data/rag_storage /app/data/inputs /app/data/tiktoken /app/data/mineru_models
COPY --from=builder /app/data/tiktoken /app/data/tiktoken

ENV TIKTOKEN_CACHE_DIR=/app/data/tiktoken
ENV WORKING_DIR=/app/data/rag_storage
ENV INPUT_DIR=/app/data/inputs

EXPOSE 9621

ENTRYPOINT ["/app/entrypoint.sh"]