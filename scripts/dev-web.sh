#!/usr/bin/env bash
# Flutter web dev server with auto hot-restart.
#
# `flutter run` serves the app and responds to SIGUSR2 by hot-restarting (web
# doesn't support hot reload, only restart). We point it at a pid file, then
# watch the source with inotifywait and fire SIGUSR2 on every change — so
# saving a .dart file auto-rebuilds and the connected browser updates itself.
#
# Tuned by env vars (see docker-compose.dev.yml):
#   WEB_PORT       — port to serve on (default 8080)
#   API_BASE_URL   — backend the app calls (default http://localhost:8000)
set -euo pipefail

WEB_PORT="${WEB_PORT:-8080}"
API_BASE_URL="${API_BASE_URL:-http://localhost:8000}"
PID_FILE=/tmp/flutter-web.pid

cd /app/frontend

echo "[dev-web] flutter pub get…"
flutter pub get

echo "[dev-web] starting web dev server on :${WEB_PORT} (API_BASE_URL=${API_BASE_URL})"
flutter run -d web-server \
  --web-hostname 0.0.0.0 \
  --web-port "${WEB_PORT}" \
  --dart-define=API_BASE_URL="${API_BASE_URL}" \
  --pid-file "${PID_FILE}" &
RUN_PID=$!

# Stop the watcher (and flutter) cleanly on container stop.
cleanup() { kill "${RUN_PID}" 2>/dev/null || true; }
trap cleanup EXIT INT TERM

# Wait for flutter to write its pid file before watching.
echo "[dev-web] waiting for the dev server to come up (first compile is slow)…"
while [ ! -f "${PID_FILE}" ]; do
  # If flutter died during startup, surface it instead of looping forever.
  kill -0 "${RUN_PID}" 2>/dev/null || { echo "[dev-web] flutter exited during startup"; exit 1; }
  sleep 0.5
done
echo "[dev-web] watching lib/ web/ pubspec.yaml — saves trigger a hot restart."

# Hot-restart on any change under the watched paths. inotifywait blocks until
# an event, so this is a cheap event loop (no polling).
while inotifywait -r -q -e modify,create,delete,move \
    lib web pubspec.yaml >/dev/null 2>&1; do
  FPID="$(cat "${PID_FILE}" 2>/dev/null || true)"
  if [ -n "${FPID}" ]; then
    echo "[dev-web] change detected → hot restart"
    kill -USR2 "${FPID}" 2>/dev/null || true
  fi
done
