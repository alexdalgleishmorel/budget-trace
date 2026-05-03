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
| `ANTHROPIC_API_KEY` | — required for `/chat` and AI imports | Picked up by the Anthropic SDK. |
| `ANTHROPIC_MODEL` | `claude-sonnet-4-6` | Override the model used in the chat orchestrator and the AI parser. |
| `BUDGET_TRACE_DB` | `<repo>/backend/data/budget_trace.db` | Override the SQLite path (used by tests). |
| `BUDGET_TRACE_FEATURES` | unset | Comma-separated flag names (e.g. `ai_import,ai_mutations`) that override the DB-stored feature flags for local dev. |

## Layout

```
backend/
  pyproject.toml                       # PEP 621 — installable with `pip install -e .`
  README.md                            # quick-start version of this doc
  src/budget_trace_backend/
    __init__.py
    main.py                            # FastAPI app, /chat, /healthz, mounts routers
    chat.py                            # orchestrator (Anthropic loop, present_to_user, write-tool gating)
    mcp_server.py                      # READ_TOOLS + WRITE_TOOLS + stdio MCP entry point
    db.py                              # sqlite3 connect + CATEGORY_PATHS_CTE + schema
    seed.py                            # 12-month seasonal mock generator
    features.py                        # per-user feature flag helpers
    models.py                          # pydantic ChartSpec / ChatRequest / ChatResponse
    services/
      categories.py                    # category mutation services (used by routes + MCP)
      transactions.py                  # transaction mutation services
    routes/
      categories.py                    # CRUD HTTP handlers
      transactions.py                  # CRUD + bulk_rename
      imports.py                       # POST /transactions/import (CSV + AI)
      features.py                      # GET /me/features
    importers/
      common.py                        # ImportedRow, source_hash, insert_rows
      csv_parser.py                    # CSV header detection + parsing
      ai_parser.py                     # Anthropic-driven parsing (gated)
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
