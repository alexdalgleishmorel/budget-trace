# Running end to end

Spin up the backend (Python) in one terminal, the Flutter app in another, then talk to the Insights tab. The whole stack is local-only — no auth, no remote services besides the Anthropic API.

Each section below explains *why* its commands exist, then gives you the lines to run.

## Prerequisites

- **Python 3.11+** with `pip` and `venv`. Check: `python3 --version`.
- **Flutter** (Dart SDK ≥ 3.11). Check: `flutter --version`.
- **Anthropic API key.** Get one at <https://console.anthropic.com/>.

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

# Generate the SQLite database (data/budget_trace.db) with 12 months of
# deterministic mock transactions. Idempotent — re-running wipes and reseeds.
budget-trace-seed
```

You only need to redo `pip install -e '.[dev]'` when `pyproject.toml` changes. You only need to redo `budget-trace-seed` if you want to reset the data or after a schema change.

## 2. Backend — start the server

The FastAPI app needs your Anthropic API key in its environment, then `uvicorn` runs it on port 8000.

```sh
# Re-activate the venv if this is a fresh shell.
cd backend && . .venv/bin/activate

# Make the Anthropic SDK pick up your key. Don't commit this anywhere.
export ANTHROPIC_API_KEY=sk-ant-...

# Start the API. --reload makes uvicorn restart on source edits, --port pins
# the URL the Flutter app will call.
uvicorn budget_trace_backend.main:app --reload --port 8000
```

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
Tests `compare_periods`. Chart optional — Claude decides.

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
# Doesn't touch the Anthropic API.
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
- **Backend errors with `ANTHROPIC_API_KEY` missing.** Set the env var in the same shell *before* `uvicorn`.
- **Categories show stale data after editing the seed.** Categories tab reads `MockData` in Flutter, *not* the backend. Edit `frontend/lib/data/mock_data.dart` to change what the Categories/Expenses tabs see. The AI's view is independent — see [data-model.md](data-model.md).
- **`budget-trace-seed` says "command not found".** You need the venv active (`. .venv/bin/activate`) and `pip install -e '.[dev]'` to have run successfully — the script is registered as a console entry point.
