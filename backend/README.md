# Budget Trace backend

Chat orchestrator + MCP server for the Insights tab of the Flutter app. See
`docs/insights-ai.md` at the repo root for the architecture and design
rationale.

## First run

Requires Python 3.11+. From `backend/`:

```sh
python3 -m venv .venv
. .venv/bin/activate
pip install -e '.[dev]'

export ANTHROPIC_API_KEY=sk-ant-...
budget-trace-seed                              # generates data/budget_trace.db
uvicorn budget_trace_backend.main:app --reload --port 8000
```

The Flutter app picks up the backend via `--dart-define=API_BASE_URL=http://localhost:8000`.

## Standalone MCP server

If you want to point Claude Desktop (or any MCP client) at the same data
tools, run the server on stdio:

```sh
budget-trace-mcp
```

In a Claude Desktop config:

```json
{
  "mcpServers": {
    "budget-trace": {
      "command": "/path/to/.venv/bin/budget-trace-mcp"
    }
  }
}
```

## Tests

```sh
pytest
```
