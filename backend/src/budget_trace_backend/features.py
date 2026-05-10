"""Per-user settings: feature flags, theme, AI provider keys, selected model.

Today: single hardcoded user (id=1). The `users` table holds:
- `features` — JSON blob of flags. Currently just `{"ai": bool}`.
- `theme`    — 'system' | 'light' | 'dark'.
- `selected_model` — model id from services/ai/registry.py; resolves the
  provider whose key is used for every AI call (chat, parser, categorizer).

Per-provider API keys live in `ai_provider_keys` — one row per provider
(`anthropic`, `openai`, `google`). Falls back to the provider's env var
(see services/ai/registry.py::ProviderInfo.env_var) when unset.

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
        "INSERT OR IGNORE INTO users (id, features, theme, selected_model) "
        "VALUES (?, '{}', 'system', NULL)",
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


def get_me(user_id: int = DEFAULT_USER_ID) -> dict:
    """Full user row, with env-override applied to flags. Used by GET /me and
    by services/ai/client.py to read the API keys + selected model."""
    with connect() as conn:
        ensure_default_user(conn)
        row = conn.execute(
            "SELECT features, theme, selected_model FROM users WHERE id = ?",
            (user_id,),
        ).fetchone()
        key_rows = conn.execute(
            "SELECT provider, api_key FROM ai_provider_keys WHERE user_id = ?",
            (user_id,),
        ).fetchall()
    return {
        "features": get_flags(user_id),
        "theme": row["theme"],
        "selected_model": row["selected_model"],
        "provider_keys": {r["provider"]: r["api_key"] for r in key_rows},
    }


def update_me(
    user_id: int = DEFAULT_USER_ID,
    *,
    features: Any = UNSET,
    theme: Any = UNSET,
    selected_model: Any = UNSET,
    provider_keys: Any = UNSET,
) -> dict:
    """Partial update of the user row.

    - `features`: partial dict like `{"ai": True}`, merged into the JSON blob.
    - `theme`: 'system' | 'light' | 'dark'.
    - `selected_model`: model id from MODEL_REGISTRY, or None to clear.
    - `provider_keys`: partial dict `{provider_id: api_key | None}`. None
       clears that provider's row; a string upserts it. Unknown provider
       ids raise ValueError. Empty strings are rejected at the route layer.
    """
    # Local imports to avoid circular deps.
    from .services.ai.registry import is_known_model, is_known_provider

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

        if selected_model is not UNSET:
            if selected_model is not None and not is_known_model(selected_model):
                raise ValueError(f"unsupported model: {selected_model!r}")
            conn.execute(
                "UPDATE users SET selected_model = ? WHERE id = ?",
                (selected_model, user_id),
            )

        if provider_keys is not UNSET:
            if not isinstance(provider_keys, dict):
                raise ValueError("provider_keys must be a dict")
            for provider_id, value in provider_keys.items():
                if not is_known_provider(provider_id):
                    raise ValueError(f"unknown provider: {provider_id!r}")
                if value is None:
                    conn.execute(
                        "DELETE FROM ai_provider_keys "
                        "WHERE user_id = ? AND provider = ?",
                        (user_id, provider_id),
                    )
                elif isinstance(value, str) and value:
                    conn.execute(
                        "INSERT INTO ai_provider_keys (user_id, provider, api_key) "
                        "VALUES (?, ?, ?) "
                        "ON CONFLICT(user_id, provider) DO UPDATE SET api_key = excluded.api_key",
                        (user_id, provider_id, value),
                    )
                else:
                    raise ValueError(
                        f"provider_keys[{provider_id!r}] must be a non-empty string or null"
                    )

    return get_me(user_id)
