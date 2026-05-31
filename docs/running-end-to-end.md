# Running end to end

Two ways to run: **Docker** (one container, the V1 way to ship it to someone) or the **dev setup** (backend + Flutter as separate processes, for hacking on the code). The whole stack is local-only — no auth, no remote services besides whichever AI provider you've configured (Anthropic, OpenAI, or Google Gemini).

## Quick start — Docker (recommended for just running it)

One image builds the Flutter web bundle and serves it from the FastAPI backend on a single port. Your data — transactions, categories, settings, and API keys — lives in a named Docker volume (`ev_data`) and survives restarts.

```sh
# From the repo root:
docker compose up --build
# then open http://localhost:8000
```

That's the whole setup. There is no separate database step — the backend creates `/data/budget_trace.db` (schema + Budget root + the single user row) on first boot.

- **AI keys:** set them in-app on the Account screen (they persist in the volume), or pass them as environment variables in `docker-compose.yml` (uncomment the `ANTHROPIC_API_KEY` / `OPENAI_API_KEY` / `GEMINI_API_KEY` lines).
- **Reset to a clean slate:** `docker compose down -v` removes the volume (and all your data).
- **Without compose:** `docker build -t expense-visualizer . && docker run -p 8000:8000 -v ev_data:/data expense-visualizer`.

### Developer mode (live reload, in Docker)

`docker compose -f docker-compose.dev.yml up --build` runs both halves with the source bind-mounted and **auto-reload on save**: the API on `:8000` (uvicorn `--reload`) and the Flutter dev server on `:8080` (a container-side `inotify` watcher hot-restarts the app on every `.dart` save — see [`scripts/dev-web.sh`](../scripts/dev-web.sh)). The dev DB is a separate `ev_dev_data` volume. The first web compile is slow (~30–60s); later saves hot-restart in seconds. The `backend-dev` / `web-dev` image stages live in the [`Dockerfile`](../Dockerfile).

The rest of this doc covers the **dev setup**: running the backend and Flutter app as separate processes for fast iteration. Each section explains *why* its commands exist, then gives you the lines to run.

## Prerequisites

- **Python 3.11+** with `pip` and `venv`. Check: `python3 --version`.
- **Flutter** (Dart SDK ≥ 3.11). Check: `flutter --version`.
- **At least one AI provider API key.** The default model is Anthropic Sonnet 4.6, but you can pick OpenAI or Gemini models in the Account screen and use those instead. Get keys at <https://console.anthropic.com/>, <https://platform.openai.com/api-keys>, or <https://aistudio.google.com/app/apikey>.

## 1. Backend — first time only

You need a virtual environment and the project installed editable so changes to the source apply without re-installing.

```sh
# From the repo root, drop into the backend directory.
cd backend

# Create an isolated Python environment so we don't pollute system packages.
python3 -m venv .venv

# Activate the venv. From this point, `python` and `pip` use the venv's copies.
. .venv/bin/activate

# Install the backend package in editable mode along with its dev extras
# (pytest, httpx). Editable means edits in src/ are picked up live.
pip install -e '.[dev]'
```

You only need to redo `pip install -e '.[dev]'` when `pyproject.toml` changes. There's no manual database step — the server auto-creates `data/budget_trace.db` (schema + symbolic Budget root + default user row) on its first boot via the FastAPI lifespan.

## 2. Backend — start the server

```sh
# Re-activate the venv if this is a fresh shell.
cd backend && . .venv/bin/activate

# Optional — only required if you want AI features without setting keys
# via the in-app Account screen. DB-stored keys win over these env vars.
# Set whichever providers you'll use.
export ANTHROPIC_API_KEY=sk-ant-...
export OPENAI_API_KEY=sk-...
export GEMINI_API_KEY=...

# Start the API. --reload makes uvicorn restart on source edits, --port pins
# the URL the Flutter app will call. The lifespan hook auto-initializes the
# DB on first boot, so a brand-new clone with no data file just works.
uvicorn budget_trace_backend.main:app --reload --port 8000
```

To wipe back to first-time-user state at any point: stop the server, `rm backend/data/budget_trace.db`, then start the server again.

Sanity check from a third terminal:

```sh
# Should return {"ok": true} — confirms the server is up.
curl http://localhost:8000/healthz
```

Leave this terminal running.

## 3. Frontend — first time only

Flutter needs to fetch the `http` package (and any others in `pubspec.yaml`).

```sh
# In a new terminal, from the repo root.
cd frontend

# Resolve and download dependencies into .dart_tool/. Re-run after pubspec
# edits.
flutter pub get
```

## 4. Frontend — start the app

The app reads the backend URL from a `--dart-define`, so you don't have to hardcode `localhost:8000` in source.

```sh
cd frontend

# -d chrome runs in the browser (fastest hot reload). Swap for `-d macos`,
# `-d ios`, or a device id if you prefer.
# --dart-define injects API_BASE_URL into the compiled app — that's where
# ChatClient (lib/services/chat_client.dart) sends POST /chat.
flutter run -d chrome --dart-define=API_BASE_URL=http://localhost:8000
```

The app opens. Click the Insights tab (magnifying glass) and start asking questions.

## 5. Try it

Some prompts that exercise different code paths:

```text
What's my biggest expense category in the last 3 months?
```
Tests `aggregate_spending` + a text-only response (no chart needed for a single answer).

```text
Show me my eating-out spending the last 3 months
```
Tests `aggregate_spending` over a 3-month window. Expect text + a 3-point chart in the sticky slot above the chat.

```text
What does my grocery spending look like over the past year, and what's the trend?
```
Tests `forecast`. Expect a 12-point solid line plus a dashed forecast continuation.

```text
Where am I overspending compared to last quarter?
```
Tests `compare_periods`. Chart optional — the model decides.

## 6. Stopping

```sh
# In the Flutter terminal, press q to quit hot reload, then Ctrl-C if needed.
# In the backend terminal, Ctrl-C to stop uvicorn.
# In any venv-active shell, deactivate when done.
deactivate
```

## Tests (run any time)

```sh
# Backend — exercises seed + every MCP data tool against a tmp DB.
# Tests monkeypatch services.ai.client.chat, so no real provider calls are made.
cd backend && . .venv/bin/activate && pytest

# Frontend — analyzer must be clean before merging anything.
cd frontend && flutter analyze && flutter test
```

## Standalone MCP server (optional)

If you want to point Claude Desktop or another MCP client at the same data tools:

```sh
# Stdio entry point. The MCP client launches this as a subprocess.
budget-trace-mcp
```

In a Claude Desktop `claude_desktop_config.json`:

```json
{
  "mcpServers": {
    "budget-trace": {
      "command": "/abs/path/to/backend/.venv/bin/budget-trace-mcp"
    }
  }
}
```

## Troubleshooting

- **Flutter shows "Network error" on every prompt.** The backend isn't running, or you forgot `--dart-define=API_BASE_URL=...`. Check `curl http://localhost:8000/healthz`.
- **AI features 400 with `ai_key_missing`.** No API key is configured for the selected model's provider. Either set the matching env var (`ANTHROPIC_API_KEY` / `OPENAI_API_KEY` / `GEMINI_API_KEY`) in the same shell *before* `uvicorn`, or paste a key into the Account screen.
- **Categories show stale data after editing the seed.** Categories tab reads `MockData` in Flutter, *not* the backend. Edit `frontend/lib/data/mock_data.dart` to change what the Categories/Expenses tabs see. The AI's view is independent — see [data-model.md](data-model.md).
- **First-run boot fails to find tables.** The schema, Budget root, and default user row are created by the FastAPI startup lifespan. If you ran a query through `python -m budget_trace_backend...` against a fresh DB without going through the server, init won't have happened — start the server once to bootstrap, or call `budget_trace_backend.db.bootstrap_db()` from your script.
