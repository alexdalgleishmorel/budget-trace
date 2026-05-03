"""Per-user feature flags.

Today: single hardcoded user (id=1). The `users` table holds a JSON blob in
`features`. The `BUDGET_TRACE_FEATURES` env var (comma-separated list of flag
names) overrides the DB for local dev — handy for flipping `ai_import` on
without writing to the DB.

Known flags:
- `ai_import`     — allow `POST /transactions/import?parser=ai`
- `ai_mutations`  — allow the chat AI to call MCP write tools
"""

from __future__ import annotations

import json
import os

from .db import connect

DEFAULT_USER_ID = 1

KNOWN_FLAGS = ("ai_import", "ai_mutations")


def _env_overrides() -> set[str]:
    raw = os.environ.get("BUDGET_TRACE_FEATURES", "")
    return {p.strip() for p in raw.split(",") if p.strip()}


def ensure_default_user(conn) -> None:
    """Idempotent — call from seed and at FastAPI startup."""
    conn.execute(
        "INSERT OR IGNORE INTO users (id, features) VALUES (?, '{}')",
        (DEFAULT_USER_ID,),
    )


def get_flags(user_id: int = DEFAULT_USER_ID) -> dict[str, bool]:
    """Returns `{flag: bool}` for every known flag, merging DB + env overrides."""
    overrides = _env_overrides()
    with connect() as conn:
        ensure_default_user(conn)
        row = conn.execute(
            "SELECT features FROM users WHERE id = ?", (user_id,)
        ).fetchone()
    stored: dict = json.loads(row["features"]) if row else {}
    out: dict[str, bool] = {}
    for flag in KNOWN_FLAGS:
        out[flag] = bool(stored.get(flag, False)) or (flag in overrides)
    return out


def set_flag(name: str, value: bool, user_id: int = DEFAULT_USER_ID) -> dict[str, bool]:
    """Update one flag in the DB. Env overrides still apply on read."""
    if name not in KNOWN_FLAGS:
        raise ValueError(f"unknown feature flag: {name}")
    with connect() as conn:
        ensure_default_user(conn)
        row = conn.execute(
            "SELECT features FROM users WHERE id = ?", (user_id,)
        ).fetchone()
        stored = json.loads(row["features"]) if row else {}
        stored[name] = bool(value)
        conn.execute(
            "UPDATE users SET features = ? WHERE id = ?",
            (json.dumps(stored), user_id),
        )
    return get_flags(user_id)
