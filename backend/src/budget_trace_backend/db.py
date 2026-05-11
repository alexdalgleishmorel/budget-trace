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
    is_unknown   INTEGER NOT NULL DEFAULT 0
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

-- Per-user settings. Single-user dev today: id=1; auth lands later.
-- `features` is a JSON blob ({"ai": true}) so we can add new flags without
-- migrations. `theme` is one of 'system' | 'light' | 'dark'.
-- `selected_model` is a model id from services/ai/registry.py — null falls
-- back to SELECTED_MODEL env, then the registry's DEFAULT_MODEL.
-- Per-provider API keys live in `ai_provider_keys` (one row per provider).
CREATE TABLE IF NOT EXISTS users (
    id              INTEGER PRIMARY KEY,
    features        TEXT NOT NULL DEFAULT '{}',
    theme           TEXT NOT NULL DEFAULT 'system',
    selected_model  TEXT
);

-- One row per (user, provider). API key is plaintext (acceptable for local
-- dev, documented in docs/account.md). When auth lands, we'll wrap this in
-- a per-user encryption envelope.
CREATE TABLE IF NOT EXISTS ai_provider_keys (
    user_id   INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    provider  TEXT    NOT NULL,
    api_key   TEXT    NOT NULL,
    PRIMARY KEY (user_id, provider)
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
-- placed on a free-form grid (layout_{x,y,w,h} in grid units). A widget pulls
-- its data from either a curated metric (server-resolved live aggregation) or
-- a saved_insight (a frozen ChartSpec snapshot captured from the Insights
-- chat — no AI replay on refresh).
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
    created_at        TEXT    NOT NULL,
    updated_at        TEXT    NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_widgets_dashboard ON widgets(dashboard_id);

-- Frozen widget snapshot saved off an assistant chat message. `widget_json`
-- is the polymorphic payload (any widget type); `chart_json` is the legacy
-- timeseries-only column kept nullable for backward compatibility.
CREATE TABLE IF NOT EXISTS saved_insights (
    id                 INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id            INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    title              TEXT    NOT NULL,
    source_message_id  INTEGER REFERENCES chat_messages(id) ON DELETE SET NULL,
    chart_json         TEXT,
    created_at         TEXT    NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_saved_insights_user ON saved_insights(user_id, created_at DESC);
"""


def db_path() -> Path:
    """Resolve the active DB path. Override via env if you need to."""
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
    conn.executescript(SCHEMA)
    # Forward-compat for any DB created before `selected_model` existed.
    _add_column_if_missing(conn, "users", "selected_model", "TEXT")
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
    # Generalised widget payload on assistant chat messages and saved
    # insights. The legacy `chart_json` column carries a ChartSpec
    # (timeseries-only); `widget_json` carries a richer `{type, title,
    # data}` payload that can describe any widget type. On read we prefer
    # widget_json and synthesise one from chart_json if absent.
    _add_column_if_missing(conn, "chat_messages", "widget_json", "TEXT")
    _add_column_if_missing(conn, "saved_insights", "widget_json", "TEXT")
    # The original `saved_insights.chart_json` column was declared NOT
    # NULL; with the generic `widget_json` column now carrying the
    # canonical payload, chart_json needs to be nullable. SQLite has no
    # ALTER COLUMN, so we rebuild the table if a legacy DB still has
    # the constraint.
    _relax_saved_insights_chart_json(conn)
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


def _relax_saved_insights_chart_json(conn: sqlite3.Connection) -> None:
    """SQLite has no ALTER COLUMN to drop a NOT NULL. Detect a legacy
    NOT NULL `chart_json` column on `saved_insights` and rebuild the
    table without it. No-op when the column is already nullable."""
    info = conn.execute("PRAGMA table_info(saved_insights)").fetchall()
    chart_col = next((c for c in info if c["name"] == "chart_json"), None)
    if chart_col is None or not chart_col["notnull"]:
        return
    # `widget_json` may already have been added by the previous call;
    # detect it so we copy it into the rebuilt table.
    has_widget = any(c["name"] == "widget_json" for c in info)
    cols = "id, user_id, title, source_message_id, chart_json, created_at"
    if has_widget:
        cols += ", widget_json"
    new_widget_col = ",\n            widget_json        TEXT" if has_widget else ""
    conn.executescript(f"""
        CREATE TABLE saved_insights_new (
            id                 INTEGER PRIMARY KEY AUTOINCREMENT,
            user_id            INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
            title              TEXT    NOT NULL,
            source_message_id  INTEGER REFERENCES chat_messages(id) ON DELETE SET NULL,
            chart_json         TEXT,
            created_at         TEXT    NOT NULL{new_widget_col}
        );
        INSERT INTO saved_insights_new ({cols})
            SELECT {cols} FROM saved_insights;
        DROP TABLE saved_insights;
        ALTER TABLE saved_insights_new RENAME TO saved_insights;
        CREATE INDEX IF NOT EXISTS idx_saved_insights_user
            ON saved_insights(user_id, created_at DESC);
    """)


def ensure_root_category(conn: sqlite3.Connection) -> None:
    """Idempotent. The recursive category-path CTE assumes exactly one row
    with `parent_id IS NULL` ("Budget"); without it `services/categories.py`
    can't resolve a parent for newly-created top-level categories."""
    existing = conn.execute(
        "SELECT id FROM categories WHERE parent_id IS NULL"
    ).fetchone()
    if existing is None:
        conn.execute(
            "INSERT INTO categories (name, description, parent_id, is_unknown) "
            "VALUES ('Budget', 'Top-level container for all spending and savings.', NULL, 0)"
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
WITH RECURSIVE category_paths(id, parent_id, name, description, is_unknown, path) AS (
    SELECT id, parent_id, name, description, is_unknown, name AS path
      FROM categories
     WHERE parent_id = (SELECT id FROM categories WHERE parent_id IS NULL)
    UNION ALL
    SELECT c.id, c.parent_id, c.name, c.description, c.is_unknown,
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
        SELECT cp.path, cp.description, cp.is_unknown,
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
        }
        for r in rows
    ]
