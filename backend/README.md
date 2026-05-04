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

# Optional — set the Anthropic key here, or via the in-app Account screen.
export ANTHROPIC_API_KEY=sk-ant-...

uvicorn budget_trace_backend.main:app --reload --port 8000
# First boot auto-creates data/budget_trace.db (schema + Budget root +
# default user). To reset to a clean state: stop, `rm data/budget_trace.db`,
# start again.
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
