# syntax=docker/dockerfile:1

# ---- build: resolve dependencies into a venv --------------------------------
FROM ghcr.io/astral-sh/uv:python3.11-bookworm-slim AS build
WORKDIR /app

# git is needed to fetch the appkit dependency (see [tool.uv.sources]).
RUN apt-get update \
    && apt-get install -y --no-install-recommends git \
    && rm -rf /var/lib/apt/lists/*

ENV UV_COMPILE_BYTECODE=1 \
    UV_LINK_MODE=copy \
    UV_PYTHON_DOWNLOADS=never

COPY pyproject.toml README.md ./
COPY app ./app
RUN uv sync --no-dev

# ---- runtime: slim image, non-root, managed identity ------------------------
FROM python:3.11-slim AS runtime
WORKDIR /app

RUN useradd --create-home --uid 10001 appuser
COPY --from=build /app/.venv /app/.venv
COPY app ./app

ENV PATH="/app/.venv/bin:$PATH" \
    PYTHONUNBUFFERED=1 \
    APPKIT_BACKEND=azure

USER appuser
EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD python -c "import urllib.request,sys; sys.exit(0 if urllib.request.urlopen('http://localhost:8080/health').status==200 else 1)"

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8080"]
