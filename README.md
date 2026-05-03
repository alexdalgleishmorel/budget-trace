# budget-trace

Personal expense categorisation + AI-powered insights.

- **Frontend** — Flutter app: Categories, Expenses, Insights tabs.
- **Backend** — Python FastAPI + MCP server: hosts the AI chat orchestrator and an SQLite-backed query surface.

See [`docs/`](docs/README.md) for architecture, setup, and conventions. The full Claude-facing pickup notes are in [CLAUDE.md](CLAUDE.md). For a step-by-step walkthrough with a comment above every command, see [`docs/running-end-to-end.md`](docs/running-end-to-end.md).

## Quick start

```sh
# Backend
cd backend
python3 -m venv .venv && . .venv/bin/activate
pip install -e '.[dev]'
export ANTHROPIC_API_KEY=sk-ant-...
budget-trace-seed
uvicorn budget_trace_backend.main:app --reload --port 8000

# Frontend (in another terminal)
cd frontend
flutter pub get
flutter run -d chrome --dart-define=API_BASE_URL=http://localhost:8000
```
