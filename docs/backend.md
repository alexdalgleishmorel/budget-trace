# Backend

Python FastAPI app. Owns the SQLite expense store, the MCP tool surface, and the chat orchestrator that talks to the selected AI provider (Anthropic, OpenAI, or Google Gemini today) via LiteLLM.

## Run it

From `backend/`:

```sh
python3 -m venv .venv
. .venv/bin/activate
pip install -e '.[dev]'

# Optional — only needed if you skip setting keys via the in-app
# Account screen. DB-stored keys win over these env vars. Set whichever
# providers you'll use; the default model is Anthropic Sonnet 4.6.
export ANTHROPIC_API_KEY=sk-ant-...
export OPENAI_API_KEY=sk-...
export GEMINI_API_KEY=...

uvicorn budget_trace_backend.main:app --reload --port 8000
# First boot creates data/budget_trace.db with the schema, the symbolic
# Budget root, and the default user row. To wipe back to first-time-user
# state: stop the server, `rm data/budget_trace.db`, start it again.
```

Health check: `curl http://localhost:8000/healthz`.

## Env vars

| Name | Default | What it does |
|------|---------|--------------|
| `ANTHROPIC_API_KEY` | optional | Fallback when no Anthropic key is stored via `PATCH /me`. Required for any Anthropic model when the stored key is empty. |
| `OPENAI_API_KEY` | optional | Fallback when no OpenAI key is stored. Required for any OpenAI model when the stored key is empty. |
| `GEMINI_API_KEY` | optional | Fallback when no Google key is stored. Required for any Gemini model when the stored key is empty. |
| `SELECTED_MODEL` | `claude-sonnet-4-6` | Override the model used by the chat orchestrator, AI parser, and auto-categorizer. Anything in the registry is fair game (e.g. `gpt-4o`, `gemini-2.5-flash`). |
| `BUDGET_TRACE_DB` | `<repo>/backend/data/budget_trace.db` | Override the SQLite path (used by tests). |
| `BUDGET_TRACE_FEATURES` | unset | Comma-separated flag names (`ai`, `widgets`) that force a flag on for the running process. Wins over the DB. Useful for tests and CI. |

## Layout

```
backend/
  pyproject.toml                       # PEP 621 — installable with `pip install -e .`
  README.md                            # quick-start version of this doc
  src/budget_trace_backend/
    __init__.py
    main.py                            # FastAPI app, /chat, /healthz, mounts routers
    chat.py                            # orchestrator (LiteLLM tool-call loop, present_to_user)
    mcp_server.py                      # READ_TOOLS + WRITE_TOOLS + stdio MCP entry point
    db.py                              # sqlite3 connect + CATEGORY_PATHS_CTE + schema
    seed.py                            # 12-month seasonal mock generator
    features.py                        # per-user settings (flags, theme, selected model, provider keys)
    help_text.py                       # /chat/help markdown (introspects tool registries)
    models.py                          # pydantic ChartSpec / ChatRequest / ChatResponse
    services/
      ai/
        registry.py                    # PROVIDERS + MODEL_REGISTRY + pricing
        client.py                      # chat() — key resolution + LiteLLM dispatch
      ai_usage.py                      # per-call cost snapshot + cumulative spend reads
      categories.py                    # category mutation services (used by routes + MCP)
      chat_sessions.py                 # session + message persistence (widget_json)
      dashboards.py                    # dashboards/widgets services + save-chat-to-dashboard
      ai_widget_audit.py               # snapshot-fallback audit log
      transactions.py                  # transaction mutation services
      widget_metrics.py                # curated metric registry + time-range resolution
    routes/
      categories.py                    # CRUD HTTP handlers
      chat_sessions.py                 # /chat/sessions, /chat/help (gated by `ai`)
      dashboards.py                    # /dashboards, /widget-metrics, /chat/messages/{id}/save-to-dashboard, /ai-widget-audit (gated by `widgets`)
      transactions.py                  # CRUD + bulk_rename
      imports.py                       # POST /transactions/import (CSV + AI + auto-categorize)
      me.py                            # GET/PATCH /me — features, theme, model, provider keys
    importers/
      common.py                        # ImportedRow, source_hash, insert_rows
      csv_parser.py                    # CSV header detection + parsing
      ai_parser.py                     # AI-driven parsing (gated by `ai`)
      categorizer.py                   # post-import auto-categorize (gated by `ai`)
  data/
    budget_trace.db                    # gitignored; created by seed
  tests/
    fixtures/                          # CSV fixtures
    test_data_tools.py                 # read tools (aggregate, forecast, etc.)
    test_categories.py                 # CRUD + MCP write tools
    test_dashboards.py                 # dashboards/widgets + save-chat-to-dashboard + metric registry
    test_transactions.py               # CRUD + MCP write tools
    test_importer.py                   # CSV parsing + dedupe + import route
    test_features.py                   # feature flags + AI gate
```

## Schema

```sql
CREATE TABLE categories (
    id           INTEGER PRIMARY KEY,
    parent_id    INTEGER REFERENCES categories(id),
    name         TEXT NOT NULL,
    description  TEXT,
    is_unknown   INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE transactions (
    id           INTEGER PRIMARY KEY,
    date         TEXT NOT NULL,                          -- ISO 'YYYY-MM-DD'
    merchant     TEXT NOT NULL,
    amount       REAL NOT NULL,                          -- positive = spend
    category_id  INTEGER REFERENCES categories(id)       -- NULL = uncategorised
);
```

Indexes on `transactions(date)`, `transactions(category_id)`, `transactions(merchant)`.

The recursive CTE `CATEGORY_PATHS_CTE` in `db.py` joins the integer-id world to the path-string world. It excludes the root "Budget" category so AI-facing paths look like `"Living / Grocery"`, never `"Budget / Living / Grocery"`.

See [data-model.md](data-model.md) for what the seed actually generates and the path-string conventions.

## Standalone MCP server

```sh
budget-trace-mcp         # stdio entry point — for Claude Desktop, etc.
```

In a Claude Desktop config:

```json
{
  "mcpServers": {
    "budget-trace": {
      "command": "/abs/path/to/.venv/bin/budget-trace-mcp"
    }
  }
}
```

The same `TOOL_FUNCTIONS` dictionary backs both the stdio server and the in-process orchestrator. There is no chance the two surfaces drift.

## Tests

```sh
pytest                    # all hit a tmp DB seeded fresh per module
```

Tests use `BUDGET_TRACE_DB` to redirect the connection to a tmp path, then call the seed + tool functions directly. They monkeypatch `services.ai.client.chat` rather than hitting any provider's API.

## Ports

The backend listens on `8000` by default. The Flutter side reads `API_BASE_URL` (see [frontend.md](frontend.md)).
