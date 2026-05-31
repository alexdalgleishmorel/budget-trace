"""SQLite layer.

The database lives at `backend/data/budget_trace.db`. Schema + the symbolic
"Budget" root + the default user row are created on backend startup via
`bootstrap_db` (called from the FastAPI lifespan in `main.py`). Two domain
tables: `categories` (recursive tree, single root) and `transactions` (flat,
time-indexed). The AI never sees integer IDs — every query that returns a
category surfaces it as a `path` string like `"Living / Grocery"`, built via
a recursive CTE.
"""

from __future__ import annotations

import sqlite3
from contextlib import contextmanager
from pathlib import Path
from typing import Iterator

DEFAULT_DB_PATH = Path(__file__).resolve().parents[2] / "data" / "budget_trace.db"

PATH_SEPARATOR = " / "

SCHEMA = """
CREATE TABLE IF NOT EXISTS categories (
    id           INTEGER PRIMARY KEY,
    parent_id    INTEGER REFERENCES categories(id),
    name         TEXT NOT NULL,
    description  TEXT,
    is_unknown   INTEGER NOT NULL DEFAULT 0,
    color        TEXT NOT NULL DEFAULT 'stone'
);

CREATE TABLE IF NOT EXISTS transactions (
    id           INTEGER PRIMARY KEY,
    date         TEXT NOT NULL,
    merchant     TEXT NOT NULL,
    amount       REAL NOT NULL,
    category_id  INTEGER REFERENCES categories(id),
    source_hash  TEXT
);

CREATE INDEX IF NOT EXISTS idx_txn_date     ON transactions(date);
CREATE INDEX IF NOT EXISTS idx_txn_category ON transactions(category_id);
CREATE INDEX IF NOT EXISTS idx_txn_merchant ON transactions(merchant);

-- Dedupe key for imports. Manual single-row inserts (POST /transactions)
-- skip the hash so two genuine same-day-same-merchant-same-amount purchases
-- can coexist. Imports always set it.
CREATE UNIQUE INDEX IF NOT EXISTS idx_txn_source_hash
    ON transactions(source_hash) WHERE source_hash IS NOT NULL;

-- Settings for the single local user (id=1). This is a local single-user
-- app; there is no auth.
-- `features` is a JSON blob ({"ai": true}) so we can add new flags without
-- migrations. `theme` is one of 'system' | 'light' | 'dark'.
-- `selected_provider` is which generic provider the user picked (anthropic |
-- openai | google) — defaults to 'anthropic'. `selected_model` is a model id
-- fetched live from that provider (see discovered_models); null until the user
-- fetches a catalog and picks one. There is no hardcoded default model.
-- Per-provider API keys live in `ai_provider_keys` (one row per provider).
CREATE TABLE IF NOT EXISTS users (
    id                INTEGER PRIMARY KEY,
    features          TEXT NOT NULL DEFAULT '{}',
    theme             TEXT NOT NULL DEFAULT 'system',
    selected_provider TEXT NOT NULL DEFAULT 'anthropic',
    selected_model    TEXT
);

-- One row per (user, provider). API key is plaintext — this is a local
-- single-user app, so the key lives only in the user's own database file
-- (documented in docs/account.md).
CREATE TABLE IF NOT EXISTS ai_provider_keys (
    user_id   INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    provider  TEXT    NOT NULL,
    api_key   TEXT    NOT NULL,
    PRIMARY KEY (user_id, provider)
);

-- The model catalog. There is no hardcoded model list — these rows are pulled
-- live from each provider's "list models" API (the Account screen's "Fetch
-- models" button) and are the only source of selectable models. `provider` is
-- recorded at fetch time (the list call knows it). Pricing comes from LiteLLM's
-- bundled cost table when known; `pricing_available = 0` means we couldn't
-- price it (spend then records the call at zero cost). A provider's rows are
-- replaced wholesale on each fetch — see services/ai/discovery.py.
CREATE TABLE IF NOT EXISTS discovered_models (
    id                    TEXT PRIMARY KEY,
    provider              TEXT    NOT NULL,
    display_name          TEXT    NOT NULL,
    input_per_mtok        REAL,
    output_per_mtok       REAL,
    cache_write_per_mtok  REAL,
    cache_read_per_mtok   REAL,
    pricing_available     INTEGER NOT NULL DEFAULT 0,
    discovered_at         TEXT    NOT NULL
);

-- One row per AI API call. Powers the global "$X.XX spent" chip and
-- per-chat estimates. `chat_session_id` is set only for chat calls (so we can
-- bucket spend per Insights conversation); ai_parser and auto_categorize
-- calls leave it NULL. `cost_usd` is a snapshot computed at insert time from
-- the registry in services/ai/registry.py; rerunning with new prices does
-- NOT retroactively update existing rows.
CREATE TABLE IF NOT EXISTS ai_usage (
    id                            INTEGER PRIMARY KEY,
    created_at                    TEXT NOT NULL,
    source                        TEXT NOT NULL,
    chat_session_id               INTEGER REFERENCES chat_sessions(id) ON DELETE SET NULL,
    model                         TEXT NOT NULL,
    input_tokens                  INTEGER NOT NULL DEFAULT 0,
    output_tokens                 INTEGER NOT NULL DEFAULT 0,
    cache_creation_input_tokens   INTEGER NOT NULL DEFAULT 0,
    cache_read_input_tokens       INTEGER NOT NULL DEFAULT 0,
    cost_usd                      REAL NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_ai_usage_session    ON ai_usage(chat_session_id);
CREATE INDEX IF NOT EXISTS idx_ai_usage_created_at ON ai_usage(created_at);

-- Insights chat history. One row per conversation.
CREATE TABLE IF NOT EXISTS chat_sessions (
    id          INTEGER PRIMARY KEY,
    title       TEXT NOT NULL DEFAULT '',
    created_at  TEXT NOT NULL,
    updated_at  TEXT NOT NULL
);

-- One row per turn (user or assistant) within a session. `chart_json` is the
-- serialised ChartSpec from the assistant; NULL for user turns or chart-less
-- assistant replies. `sequence` orders messages within a session.
CREATE TABLE IF NOT EXISTS chat_messages (
    id          INTEGER PRIMARY KEY,
    session_id  INTEGER NOT NULL REFERENCES chat_sessions(id) ON DELETE CASCADE,
    sequence    INTEGER NOT NULL,
    role        TEXT NOT NULL,
    text        TEXT NOT NULL,
    chart_json  TEXT,
    errored     INTEGER NOT NULL DEFAULT 0,
    created_at  TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_chat_msg_session ON chat_messages(session_id, sequence);
CREATE INDEX IF NOT EXISTS idx_chat_session_updated ON chat_sessions(updated_at DESC);

-- Widgets feature. A user owns N dashboards; each dashboard owns N widgets
-- placed on a free-form grid (layout_{x,y,w,h} in grid units). A widget
-- pulls its data from either a curated metric (server-resolved live
-- aggregation that follows the dashboard's time range) or a snapshot
-- (frozen bytes stored inline on the widget via `snapshot_json` —
-- ignores the dashboard's time range).
CREATE TABLE IF NOT EXISTS dashboards (
    id                  INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id             INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    name                TEXT    NOT NULL,
    -- Dashboard-level time range applied to every widget that takes a
    -- date window. `preset` is one of: last_30_days, last_3_months,
    -- last_6_months, last_12_months, month_to_date, year_to_date, all_time,
    -- custom. When 'custom', `custom_start` and `custom_end` are honored.
    time_range_preset   TEXT    NOT NULL DEFAULT 'last_3_months',
    time_range_start    TEXT,
    time_range_end      TEXT,
    created_at          TEXT    NOT NULL,
    updated_at          TEXT    NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_dashboards_user ON dashboards(user_id, updated_at DESC);

-- A widget pulls its data from either a curated metric (server-resolved
-- live aggregation that follows the dashboard's time range) or a snapshot
-- (frozen bytes lifted from an Insights chat answer that no registry
-- metric could express). Snapshot widgets store their payload inline in
-- `snapshot_json` and ignore the dashboard time range.
CREATE TABLE IF NOT EXISTS widgets (
    id                INTEGER PRIMARY KEY AUTOINCREMENT,
    dashboard_id      INTEGER NOT NULL REFERENCES dashboards(id) ON DELETE CASCADE,
    type              TEXT    NOT NULL,
    title             TEXT    NOT NULL,
    layout_x          INTEGER NOT NULL,
    layout_y          INTEGER NOT NULL,
    layout_w          INTEGER NOT NULL,
    layout_h          INTEGER NOT NULL,
    data_source_json  TEXT    NOT NULL,
    config_json       TEXT    NOT NULL,
    snapshot_json     TEXT,
    via_chat          INTEGER NOT NULL DEFAULT 0,
    created_at        TEXT    NOT NULL,
    updated_at        TEXT    NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_widgets_dashboard ON widgets(dashboard_id);

-- One row per AI assistant message that emitted a snapshot-only widget
-- (no registry metric could express the answer). Read it back to find
-- gaps in the curated-metric registry. The `fallback_reason` field is
-- what the AI told us about why it had to go novel.
CREATE TABLE IF NOT EXISTS ai_widget_audit (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    message_id      INTEGER REFERENCES chat_messages(id) ON DELETE CASCADE,
    widget_type     TEXT    NOT NULL,
    fallback_reason TEXT,
    user_question   TEXT,
    created_at      TEXT    NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_ai_widget_audit_created_at
    ON ai_widget_audit(created_at DESC);
"""


def db_path() -> Path:
    """Resolve the active DB path. Override via the `BUDGET_TRACE_DB` env var
    — the Docker image points it at the mounted `/data` volume so the SQLite
    file persists across container restarts."""
    import os
    env = os.environ.get("BUDGET_TRACE_DB")
    return Path(env) if env else DEFAULT_DB_PATH


@contextmanager
def connect(path: Path | None = None) -> Iterator[sqlite3.Connection]:
    p = path or db_path()
    p.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(p)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA foreign_keys = ON")
    try:
        yield conn
        conn.commit()
    finally:
        conn.close()


def init_schema(conn: sqlite3.Connection) -> None:
    # Hard cutover: the saved_insights table was a frozen-bytes inbox for
    # chat-saved widgets; the model now stores snapshots inline on the
    # widget row itself. Drop the legacy table on every boot so leftover
    # rows from earlier dev sessions can't be referenced.
    conn.executescript("DROP TABLE IF EXISTS saved_insights;")
    conn.executescript(SCHEMA)
    # Forward-compat for any DB created before `selected_model` existed.
    _add_column_if_missing(conn, "users", "selected_model", "TEXT")
    # Provider-first model selection: which generic provider the user picked.
    _add_column_if_missing(
        conn, "users", "selected_provider",
        "TEXT NOT NULL DEFAULT 'anthropic'",
    )
    # Last-viewed dashboard so the Widgets tab lands on the same dashboard
    # across sessions. Nullable; no FK enforced (would require post-create
    # column add).
    _add_column_if_missing(conn, "users", "last_dashboard_id", "INTEGER")
    # Time-range columns on dashboards — forward-compat for any DB
    # bootstrapped before they landed.
    _add_column_if_missing(
        conn, "dashboards", "time_range_preset",
        "TEXT NOT NULL DEFAULT 'last_3_months'",
    )
    _add_column_if_missing(conn, "dashboards", "time_range_start", "TEXT")
    _add_column_if_missing(conn, "dashboards", "time_range_end", "TEXT")
    # Generalised widget payload on assistant chat messages. The legacy
    # `chart_json` column carries a ChartSpec (timeseries-only);
    # `widget_json` carries a richer `{type, title, data, metric_id?,
    # metric_params?}` payload that can describe any widget type and
    # capture its re-runnable query when one exists.
    _add_column_if_missing(conn, "chat_messages", "widget_json", "TEXT")
    # Snapshot payload for widgets backed by a frozen chat answer. NULL
    # for kind:metric widgets.
    _add_column_if_missing(conn, "widgets", "snapshot_json", "TEXT")
    # 1 when the widget was created via the Insights chat
    # save-to-dashboard flow (regardless of metric vs. snapshot kind).
    # Surfaced in the UI as a small green "from Insights" footer so the
    # user can tell where the widget came from.
    _add_column_if_missing(conn, "widgets", "via_chat", "INTEGER NOT NULL DEFAULT 0")
    # Hard cutover: drop legacy Anthropic-specific columns if they exist.
    # SQLite >= 3.35 supports DROP COLUMN. The check is idempotent so this
    # is safe to run on already-migrated DBs and on fresh ones.
    _drop_column_if_present(conn, "users", "anthropic_api_key")
    _drop_column_if_present(conn, "users", "anthropic_admin_api_key")
    _drop_column_if_present(conn, "users", "anthropic_model")


def _add_column_if_missing(
    conn: sqlite3.Connection, table: str, column: str, definition: str
) -> None:
    """SQLite has no `ADD COLUMN IF NOT EXISTS`; check pragma first."""
    cols = {r["name"] for r in conn.execute(f"PRAGMA table_info({table})").fetchall()}
    if column not in cols:
        conn.execute(f"ALTER TABLE {table} ADD COLUMN {column} {definition}")


def _drop_column_if_present(
    conn: sqlite3.Connection, table: str, column: str
) -> None:
    """Idempotent counterpart for `_add_column_if_missing`. Requires SQLite
    >= 3.35 (released March 2021). The check keeps reruns cheap."""
    cols = {r["name"] for r in conn.execute(f"PRAGMA table_info({table})").fetchall()}
    if column in cols:
        conn.execute(f"ALTER TABLE {table} DROP COLUMN {column}")


def ensure_root_category(conn: sqlite3.Connection) -> None:
    """Idempotent. The recursive category-path CTE assumes exactly one row
    with `parent_id IS NULL` ("Budget"); without it `services/categories.py`
    can't resolve a parent for newly-created top-level categories."""
    existing = conn.execute(
        "SELECT id FROM categories WHERE parent_id IS NULL"
    ).fetchone()
    if existing is None:
        conn.execute(
            "INSERT INTO categories (name, description, parent_id, is_unknown, color) "
            "VALUES ('Budget', 'Top-level container for all spending and savings.', NULL, 0, 'stone')"
        )


def bootstrap_db() -> None:
    """One-shot init: schema + Budget root + default user row. Called from
    the FastAPI startup lifespan so a fresh `rm data/budget_trace.db` plus a
    server start is the entire first-run experience."""
    from .features import ensure_default_user
    with connect() as conn:
        init_schema(conn)
        ensure_root_category(conn)
        ensure_default_user(conn)


# ── Path helpers ──────────────────────────────────────────────────────────────

# This recursive CTE builds the full path string for every category. The root
# "Budget" node is *excluded* — top-level groups (House, Living, Savings,
# Unknown) have path == name, and deeper paths stack from there using the
# " / " separator. The AI sees paths like "Living / Grocery", never "Budget /
# Living / Grocery".
CATEGORY_PATHS_CTE = f"""
WITH RECURSIVE category_paths(id, parent_id, name, description, is_unknown, color, path) AS (
    SELECT id, parent_id, name, description, is_unknown, color, name AS path
      FROM categories
     WHERE parent_id = (SELECT id FROM categories WHERE parent_id IS NULL)
    UNION ALL
    SELECT c.id, c.parent_id, c.name, c.description, c.is_unknown, c.color,
           cp.path || '{PATH_SEPARATOR}' || c.name AS path
      FROM categories c
      JOIN category_paths cp ON c.parent_id = cp.id
)
"""


def category_id_for_path(conn: sqlite3.Connection, path: str) -> int | None:
    """Resolve an AI-facing path string back to a category id."""
    row = conn.execute(
        f"{CATEGORY_PATHS_CTE} SELECT id FROM category_paths WHERE path = ?",
        (path,),
    ).fetchone()
    return row["id"] if row else None


def descendant_category_ids(conn: sqlite3.Connection, path: str) -> list[int]:
    """All category ids rooted at `path` (inclusive). For roll-ups: e.g. asking
    for "Living" returns Grocery, Gas, Fun, etc. as well."""
    root_id = category_id_for_path(conn, path)
    if root_id is None:
        return []
    rows = conn.execute(
        """
        WITH RECURSIVE subtree(id) AS (
            SELECT id FROM categories WHERE id = ?
            UNION ALL
            SELECT c.id FROM categories c JOIN subtree s ON c.parent_id = s.id
        )
        SELECT id FROM subtree
        """,
        (root_id,),
    ).fetchall()
    return [r["id"] for r in rows]


def fetch_category_tree(conn: sqlite3.Connection) -> list[dict]:
    """All categories with their full paths, in a stable depth-first order."""
    rows = conn.execute(
        f"""
        {CATEGORY_PATHS_CTE}
        SELECT cp.path, cp.description, cp.is_unknown, cp.color,
               (SELECT COUNT(*) FROM categories c WHERE c.parent_id = cp.id) AS child_count
          FROM category_paths cp
         ORDER BY cp.path
        """,
    ).fetchall()
    return [
        {
            "path": r["path"],
            "description": r["description"],
            "is_leaf": r["child_count"] == 0,
            "is_unknown": bool(r["is_unknown"]),
            "color": r["color"],
        }
        for r in rows
    ]
