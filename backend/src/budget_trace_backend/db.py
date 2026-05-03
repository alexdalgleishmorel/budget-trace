"""SQLite layer.

The database lives at `backend/data/budget_trace.db` and is created/seeded by
`budget_trace_backend.seed`. Two tables: `categories` (recursive tree) and
`transactions` (flat, time-indexed). The AI never sees integer IDs — every
query that returns a category surfaces it as a `path` string like
`"Living / Grocery"`, built via a recursive CTE.
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

-- Per-user feature flags. Single-user dev today: id=1.
-- `features` is a JSON blob ({"ai_import": true, "ai_mutations": true}) so
-- we can add new flags without migrations.
CREATE TABLE IF NOT EXISTS users (
    id        INTEGER PRIMARY KEY,
    features  TEXT NOT NULL DEFAULT '{}'
);

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
