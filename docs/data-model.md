# Data model

One store: **`backend/data/budget_trace.db`** (SQLite). Both the AI and the Flutter app's Categories + Expenses tabs read and write through it via the REST API documented in [rest-api.md](rest-api.md).

Earlier iterations had a separate in-memory `MockData` on the Flutter side; that's been removed. The seed in `backend/src/budget_trace_backend/seed.py` is the only mock data path.

## ERD

```mermaid
erDiagram
    categories ||--o{ categories     : "parent_id (self-ref tree)"
    categories ||--o{ transactions   : "category_id (NULL = uncategorised)"
    chat_sessions ||--o{ chat_messages : "session_id (ON DELETE CASCADE)"
    chat_sessions ||--o{ ai_usage      : "chat_session_id (ON DELETE SET NULL)"
    users ||--o{ ai_provider_keys : "user_id (ON DELETE CASCADE)"
    users {
        INTEGER id PK
        TEXT    features         JSON_blob_ai_bool
        TEXT    theme            system_light_dark
        TEXT    selected_model   model_id_NULL_falls_back_to_env_then_default
    }
    ai_provider_keys {
        INTEGER user_id PK
        TEXT    provider PK "anthropic|openai|google|..."
        TEXT    api_key      plaintext
    }
    categories {
        INTEGER id PK
        INTEGER parent_id FK "NULL only for root 'Budget' row"
        TEXT    name
        TEXT    description "AI classification hint; nullable"
        INTEGER is_unknown "1 for the symbolic Unknown row"
    }
    transactions {
        INTEGER id PK
        TEXT    date         "ISO YYYY-MM-DD"
        TEXT    merchant
        REAL    amount       "positive = spend"
        INTEGER category_id FK "NULL = uncategorised"
        TEXT    source_hash  "SHA256(date|merchant|amount); imports only"
    }
    chat_sessions {
        INTEGER id PK
        TEXT    title
        TEXT    created_at
        TEXT    updated_at
    }
    chat_messages {
        INTEGER id PK
        INTEGER session_id FK
        INTEGER sequence "order within session"
        TEXT    role     "'user' | 'assistant'"
        TEXT    text
        TEXT    chart_json "serialised ChartSpec; NULL for user turns"
        INTEGER errored
        TEXT    created_at
    }
    ai_usage {
        INTEGER id PK
        TEXT    created_at
        TEXT    source                       chat_ai_parser_or_auto_categorize
        INTEGER chat_session_id FK           NULL_unless_source_is_chat
        TEXT    model
        INTEGER input_tokens
        INTEGER output_tokens
        INTEGER cache_creation_input_tokens
        INTEGER cache_read_input_tokens
        REAL    cost_usd                     snapshot_at_insert_time
    }
```

`users` is logically standalone today (single-user dev, id=1) — no FK from anywhere else points at it, so feature flags are scoped per-process rather than per-row joined onto transactions/categories. `categories` is a self-referencing tree rooted at a single `parent_id IS NULL` "Budget" node that's filtered out of every AI-facing query (see the recursive CTE in [`db.py`](../backend/src/budget_trace_backend/db.py)).

## SQLite schema

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
    category_id  INTEGER REFERENCES categories(id),      -- NULL = uncategorised
    source_hash  TEXT                                    -- import dedupe; NULL for manual inserts
);

CREATE INDEX idx_txn_date     ON transactions(date);
CREATE INDEX idx_txn_category ON transactions(category_id);
CREATE INDEX idx_txn_merchant ON transactions(merchant);

-- Imports are deduped on this hash; manual POST /transactions skips it so two
-- genuine same-day-same-merchant-same-amount purchases can coexist.
CREATE UNIQUE INDEX idx_txn_source_hash
    ON transactions(source_hash) WHERE source_hash IS NOT NULL;

-- Per-user settings. Single-user dev today: id=1; auth lands later.
-- `features` is a JSON blob ({"ai": true}). `theme` is one of
-- 'system' | 'light' | 'dark'. `selected_model` is a model id from
-- services/ai/registry.py (NULL → SELECTED_MODEL env var → DEFAULT_MODEL).
CREATE TABLE users (
    id              INTEGER PRIMARY KEY,
    features        TEXT NOT NULL DEFAULT '{}',
    theme           TEXT NOT NULL DEFAULT 'system',
    selected_model  TEXT
);

-- One row per (user, provider). API key is plaintext (acceptable for local
-- dev). The model registry tells the runtime which provider's row to read
-- for any given model. Env vars (ANTHROPIC_API_KEY / OPENAI_API_KEY /
-- GEMINI_API_KEY) provide fallback when the row is missing.
CREATE TABLE ai_provider_keys (
    user_id   INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    provider  TEXT    NOT NULL,
    api_key   TEXT    NOT NULL,
    PRIMARY KEY (user_id, provider)
);

-- Insights chat history.
CREATE TABLE chat_sessions (
    id          INTEGER PRIMARY KEY,
    title       TEXT NOT NULL DEFAULT '',
    created_at  TEXT NOT NULL,
    updated_at  TEXT NOT NULL
);

CREATE TABLE chat_messages (
    id          INTEGER PRIMARY KEY,
    session_id  INTEGER NOT NULL REFERENCES chat_sessions(id) ON DELETE CASCADE,
    sequence    INTEGER NOT NULL,
    role        TEXT NOT NULL,                           -- 'user' | 'assistant'
    text        TEXT NOT NULL,
    chart_json  TEXT,                                    -- serialised ChartSpec; NULL for user turns
    errored     INTEGER NOT NULL DEFAULT 0,
    created_at  TEXT NOT NULL
);

CREATE INDEX idx_chat_msg_session     ON chat_messages(session_id, sequence);
CREATE INDEX idx_chat_session_updated ON chat_sessions(updated_at DESC);

-- One row per AI API call. Powers the global "$X.XX spent" chip and
-- per-chat estimates. `chat_session_id` is set only for chat calls so spend
-- can be bucketed per Insights session; ai_parser and auto_categorize calls
-- leave it NULL. `cost_usd` is a snapshot at insert time using the registry
-- in services/ai/registry.py — rerunning with new prices does NOT
-- retroactively rewrite existing rows.
CREATE TABLE ai_usage (
    id                            INTEGER PRIMARY KEY,
    created_at                    TEXT NOT NULL,
    source                        TEXT NOT NULL,            -- 'chat' | 'ai_parser' | 'auto_categorize'
    chat_session_id               INTEGER REFERENCES chat_sessions(id) ON DELETE SET NULL,
    model                         TEXT NOT NULL,
    input_tokens                  INTEGER NOT NULL DEFAULT 0,
    output_tokens                 INTEGER NOT NULL DEFAULT 0,
    cache_creation_input_tokens   INTEGER NOT NULL DEFAULT 0,
    cache_read_input_tokens       INTEGER NOT NULL DEFAULT 0,
    cost_usd                      REAL NOT NULL
);

CREATE INDEX idx_ai_usage_session    ON ai_usage(chat_session_id);
CREATE INDEX idx_ai_usage_created_at ON ai_usage(created_at);
```

`db.py::init_schema` is forward-compatible with older DBs: `_add_column_if_missing` adds `selected_model` if absent, and `_drop_column_if_present` strips the legacy `anthropic_api_key` / `anthropic_admin_api_key` / `anthropic_model` columns (SQLite ≥ 3.35) when migrating an older DB. Both helpers are idempotent.

## Path strings

The AI never sees integer IDs. Every category-bearing query takes/returns a path string:

```
"House"
"House / Rent"
"House / Rent / Mortgage"
"Living / Grocery"
"Unknown"             # the symbolic "needs review" category row
```

- Top-level groups (House, Living, Savings, Unknown) have path == name.
- Deeper paths join with the literal **` / `** (space + slash + space).
- The root "Budget" is **not** a valid path. It's filtered out of the recursive CTE so the AI doesn't get confused by it.

The string `"Unknown"` is special when passed as `category_path` to `list_transactions` or `aggregate_spending`: it filters for `category_id IS NULL` (uncategorised), not for the actual Unknown row. The seed never assigns transactions to the Unknown row's id; uncategorised always means NULL `category_id`.

## What the seed generates

`backend/src/budget_trace_backend/seed.py` writes 12 months of transactions ending **2026-04-30**:

- **Recurring monthly bills** (every month, fixed days):
  - Mortgage on the 15th — $1500 → `House / Rent`
  - Strata fee on the 5th — $300 → `House / Rent / Strata Fee`
  - Internet on the 29th (or last day) — ~$100-112 → `House / Internet`
  - Car insurance on the 4th — $320 → `Living / Car Insurance`
  - Retirement auto-invest on the 1st — $700 → `Savings / Retirement`
  - Emergency fund transfer on the 1st — $600 → `Savings / Emergency Fund`
  - Travel fund contribution — $200/mo, $400 in May-Aug & Dec → `Savings / Travel`
  - Utilities on the 3rd — variable, **higher in winter** (Nov-Feb), lower in summer
- **Variable** (per-month random count, fixed seed):
  - Grocery (4-6/mo, $45-$220)
  - Gas (2-4/mo, $32-$78)
  - Fun (4-9/mo, **8-14 in December**)
  - Shopping (2-5/mo, **5-9 in Nov-Dec**)
- **Lumpy travel actuals**: a real flight in July, December, and March each year.
- **Uncategorised** (6-12/mo): Amazon, Starbucks, Lyft, DoorDash, IKEA, etc. — left at `category_id IS NULL`.

`random.seed(42)` makes the output deterministic. Reseeding wipes the DB; identical input → identical output.

## Updating the schema

If you need to add a column or table:

1. Edit `db.py::SCHEMA`.
2. Delete `backend/data/budget_trace.db` and re-run `budget-trace-seed`.
3. Update the relevant tool function in `mcp_server.py` and add a test.

There is no migration system yet — the DB is throwaway. If/when this becomes real, swap to Alembic or similar.
