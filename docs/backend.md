# Backend

Python FastAPI app. Owns the SQLite expense store, the MCP tool surface, and the chat orchestrator that talks to the Anthropic API.

## Run it

From `backend/`:

```sh
python3 -m venv .venv
. .venv/bin/activate
pip install -e '.[dev]'

export ANTHROPIC_API_KEY=sk-ant-...
budget-trace-seed                              # writes data/budget_trace.db
uvicorn budget_trace_backend.main:app --reload --port 8000
```

Health check: `curl http://localhost:8000/healthz`.

## Env vars

| Name | Default | What it does |
|------|---------|--------------|
| `ANTHROPIC_API_KEY` | optional | Fallback when no key is stored on the user (set via Account → API key, or `PATCH /me`). Required for any AI surface (chat, AI parser, auto-categorize) when the user-stored key is empty. |
| `ANTHROPIC_MODEL` | `claude-sonnet-4-6` | Override the model used in the chat orchestrator, the AI parser, and the auto-categorizer. |
| `BUDGET_TRACE_DB` | `<repo>/backend/data/budget_trace.db` | Override the SQLite path (used by tests). |
| `BUDGET_TRACE_FEATURES` | unset | Comma-separated flag names (just `ai` today) that force a flag on for the running process. Wins over the DB. Useful for tests and CI. |

## Layout

```
backend/
  pyproject.toml                       # PEP 621 — installable with `pip install -e .`
  README.md                            # quick-start version of this doc
  src/budget_trace_backend/
    __init__.py
    main.py                            # FastAPI app, /chat, /healthz, mounts routers
    chat.py                            # orchestrator (Anthropic loop, present_to_user)
    mcp_server.py                      # READ_TOOLS + WRITE_TOOLS + stdio MCP entry point
    db.py                              # sqlite3 connect + CATEGORY_PATHS_CTE + schema
    seed.py                            # 12-month seasonal mock generator
    features.py                        # per-user settings (flags, theme, API key)
    help_text.py                       # /chat/help markdown (introspects tool registries)
    models.py                          # pydantic ChartSpec / ChatRequest / ChatResponse
    services/
      anthropic_client.py              # get_client() / get_model() — single key + model resolver
      categories.py                    # category mutation services (used by routes + MCP)
      chat_sessions.py                 # session + message persistence
      transactions.py                  # transaction mutation services
    routes/
      categories.py                    # CRUD HTTP handlers
      chat_sessions.py                 # /chat/sessions, /chat/help (gated by `ai`)
      transactions.py                  # CRUD + bulk_rename
      imports.py                       # POST /transactions/import (CSV + AI + auto-categorize)
      me.py                            # GET/PATCH /me — features, theme, API key
    importers/
      common.py                        # ImportedRow, source_hash, insert_rows
      csv_parser.py                    # CSV header detection + parsing
      ai_parser.py                     # Anthropic-driven parsing (gated by `ai`)
      categorizer.py                   # post-import auto-categorize (gated by `ai`)
  data/
    budget_trace.db                    # gitignored; created by seed
  tests/
    fixtures/                          # CSV fixtures
    test_data_tools.py                 # read tools (aggregate, forecast, etc.)
    test_categories.py                 # CRUD + MCP write tools
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
pytest                    # 9 tests, all hit a tmp DB seeded fresh per module
```

Tests use `BUDGET_TRACE_DB` to redirect the connection to a tmp path, then call the seed + tool functions directly. They don't touch the Anthropic API.

## Ports

The backend listens on `8000` by default. The Flutter side reads `API_BASE_URL` (see [frontend.md](frontend.md)).
