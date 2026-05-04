"""Per-user settings: feature flags, theme, API key.

Today: single hardcoded user (id=1). The `users` table holds:
- `features` — JSON blob of flags. Currently just `{"ai": bool}`.
- `theme`    — 'system' | 'light' | 'dark'.
- `anthropic_api_key` — plaintext, optional. Falls back to the
  `ANTHROPIC_API_KEY` env var when unset (see services/anthropic_client.py).

The `BUDGET_TRACE_FEATURES` env var (comma-separated flag names) overrides the
DB for local dev / tests — handy for forcing `ai` on without writing to the DB.

Known flags:
- `ai` — master AI toggle. Gates PDF/AI parsing on import, the Insights chat
         (message append), and auto-categorization on import.
"""

from __future__ import annotations

import json
import os
from typing import Any, Literal

from .db import connect

DEFAULT_USER_ID = 1

KNOWN_FLAGS = ("ai",)

Theme = Literal["system", "light", "dark"]
_VALID_THEMES: tuple[Theme, ...] = ("system", "light", "dark")


# Sentinel for `update_me` — distinguishes "not provided" from "set to None".
class _Unset:
    def __repr__(self) -> str:  # pragma: no cover
        return "<unset>"


UNSET: Any = _Unset()


def _env_overrides() -> set[str]:
    raw = os.environ.get("BUDGET_TRACE_FEATURES", "")
    return {p.strip() for p in raw.split(",") if p.strip()}


def ensure_default_user(conn) -> None:
    """Idempotent — call from seed and at FastAPI startup."""
    conn.execute(
        "INSERT OR IGNORE INTO users (id, features, anthropic_api_key, theme) "
        "VALUES (?, '{}', NULL, 'system')",
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
    """Update one flag in the DB. Env overrides still apply on read.

    Useful for tests and the `BUDGET_TRACE_FEATURES`-style dev-loop. The
    public PATCH /me route uses `update_me(features={...})`.
    """
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


def get_me(user_id: int = DEFAULT_USER_ID) -> dict:
    """Full user row, with env-override applied to flags. Used by GET /me and
    by services/anthropic_client.py to read the API key."""
    with connect() as conn:
        ensure_default_user(conn)
        row = conn.execute(
            "SELECT features, anthropic_api_key, theme FROM users WHERE id = ?",
            (user_id,),
        ).fetchone()
    return {
        "features": get_flags(user_id),
        "theme": row["theme"],
        "anthropic_api_key": row["anthropic_api_key"],
    }


def update_me(
    user_id: int = DEFAULT_USER_ID,
    *,
    features: Any = UNSET,
    theme: Any = UNSET,
    anthropic_api_key: Any = UNSET,
) -> dict:
    """Partial update of the user row. Pass `UNSET` (or omit) to leave a
    field alone; pass `None` to clear `anthropic_api_key`.

    `features` is a partial dict like `{"ai": True}` — merged into the
    existing JSON blob. Unknown flag keys raise ValueError.
    """
    with connect() as conn:
        ensure_default_user(conn)
        row = conn.execute(
            "SELECT features FROM users WHERE id = ?", (user_id,)
        ).fetchone()
        stored = json.loads(row["features"]) if row else {}

        if features is not UNSET:
            if not isinstance(features, dict):
                raise ValueError("features must be a dict")
            for k, v in features.items():
                if k not in KNOWN_FLAGS:
                    raise ValueError(f"unknown feature flag: {k}")
                stored[k] = bool(v)
            conn.execute(
                "UPDATE users SET features = ? WHERE id = ?",
                (json.dumps(stored), user_id),
            )

        if theme is not UNSET:
            if theme not in _VALID_THEMES:
                raise ValueError(f"invalid theme: {theme!r}")
            conn.execute(
                "UPDATE users SET theme = ? WHERE id = ?", (theme, user_id),
            )

        if anthropic_api_key is not UNSET:
            # None clears, str sets. Empty string is rejected at the route layer.
            conn.execute(
                "UPDATE users SET anthropic_api_key = ? WHERE id = ?",
                (anthropic_api_key, user_id),
            )

    return get_me(user_id)
