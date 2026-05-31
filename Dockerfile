# Expense Visualizer — single-image build.
#
# Stage 1 builds the Flutter web bundle with an EMPTY API_BASE_URL so every
# request is same-origin (relative `/me`, `/categories`, …). Stage 2 is the
# FastAPI backend, which serves both the API and that static bundle on one
# port. The SQLite DB lives in /data — mount a volume there to persist it.
#
#   docker build -t expense-visualizer .
#   docker run -p 8000:8000 -v ev_data:/data expense-visualizer
#   # open http://localhost:8000

# ── Dev stage: backend with auto-reload ───────────────────────────────────────
# Used by docker-compose.dev.yml. Deps are baked in; the source is bind-mounted
# at runtime and uvicorn --reload restarts on every save. The package is
# installed editable and PYTHONPATH points at the (mounted) src so imports
# resolve to the live host files.
FROM python:3.11-slim AS backend-dev
RUN apt-get update \
    && apt-get install -y --no-install-recommends git \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /app/backend
COPY backend/ ./
RUN pip install --no-cache-dir -e '.[dev]'
ENV PYTHONPATH=/app/backend/src \
    BUDGET_TRACE_DB=/data/budget_trace.db \
    PORT=8000
EXPOSE 8000
CMD ["sh", "-c", "uvicorn budget_trace_backend.main:app --host 0.0.0.0 --port ${PORT:-8000} --reload --reload-dir /app/backend/src"]

# ── Dev stage: Flutter web with hot restart on save ───────────────────────────
# Adds inotify-tools to the Flutter image; scripts/dev-web.sh runs the web dev
# server and sends SIGUSR2 (hot restart) whenever a watched file changes. The
# frontend source is bind-mounted at runtime.
FROM ghcr.io/cirruslabs/flutter:stable AS web-dev
RUN apt-get update \
    && apt-get install -y --no-install-recommends inotify-tools \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /app/frontend
COPY scripts/dev-web.sh /usr/local/bin/dev-web.sh
RUN chmod +x /usr/local/bin/dev-web.sh
EXPOSE 8080
CMD ["/usr/local/bin/dev-web.sh"]

# ── Stage 1: Flutter web build ────────────────────────────────────────────────
FROM ghcr.io/cirruslabs/flutter:stable AS web

WORKDIR /app/frontend
# Resolve deps first for layer caching, then copy the source.
COPY frontend/pubspec.yaml frontend/pubspec.lock ./
RUN flutter pub get
COPY frontend/ ./
# Empty API_BASE_URL → relative requests → same origin as the backend.
RUN flutter build web --release --dart-define=API_BASE_URL=

# ── Stage 2: Python backend (serves API + the built web bundle) ───────────────
FROM python:3.11-slim AS runtime

# git is required: litellm imports it at runtime in some code paths.
RUN apt-get update \
    && apt-get install -y --no-install-recommends git \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app/backend
COPY backend/pyproject.toml ./
COPY backend/src ./src
RUN pip install --no-cache-dir .

# The compiled web app, served by FastAPI's StaticFiles mount (see main.py).
COPY --from=web /app/frontend/build/web /app/web

ENV BUDGET_TRACE_DB=/data/budget_trace.db \
    BUDGET_TRACE_WEB_DIR=/app/web \
    PORT=8000
VOLUME ["/data"]
EXPOSE 8000

CMD ["sh", "-c", "uvicorn budget_trace_backend.main:app --host 0.0.0.0 --port ${PORT:-8000}"]
