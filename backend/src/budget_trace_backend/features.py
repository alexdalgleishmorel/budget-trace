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

KNOWN_FLAGS = ("ai", "widgets")

# Flags that default to ON when the user row doesn't explicitly set them.
# `ai` stays off-by-default — it requires a provider key to be useful.
# `widgets` is on-by-default so the Widgets tab is visible on first run.
DEFAULT_ON_FLAGS = ("widgets",)

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
        "INSERT OR IGNORE INTO users "
        "(id, features, theme, selected_provider, selected_model) "
        "VALUES (?, '{}', 'system', 'anthropic', NULL)",
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
        default = flag in DEFAULT_ON_FLAGS
        out[flag] = bool(stored.get(flag, default)) or (flag in overrides)
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
            "SELECT features, theme, selected_provider, selected_model, "
            "last_dashboard_id FROM users WHERE id = ?",
            (user_id,),
        ).fetchone()
        key_rows = conn.execute(
            "SELECT provider, api_key FROM ai_provider_keys WHERE user_id = ?",
            (user_id,),
        ).fetchall()
    return {
        "features": get_flags(user_id),
        "theme": row["theme"],
        "selected_provider": row["selected_provider"] or "anthropic",
        "selected_model": row["selected_model"],
        "last_dashboard_id": row["last_dashboard_id"],
        "provider_keys": {r["provider"]: r["api_key"] for r in key_rows},
    }


def set_last_dashboard(dashboard_id: int | None, user_id: int = DEFAULT_USER_ID) -> None:
    """Persist the user's last-viewed dashboard so the Widgets tab reopens
    on the same one. Pass None to clear (e.g. after the dashboard is deleted).
    """
    with connect() as conn:
        ensure_default_user(conn)
        conn.execute(
            "UPDATE users SET last_dashboard_id = ? WHERE id = ?",
            (dashboard_id, user_id),
        )


def update_me(
    user_id: int = DEFAULT_USER_ID,
    *,
    features: Any = UNSET,
    theme: Any = UNSET,
    selected_provider: Any = UNSET,
    selected_model: Any = UNSET,
    provider_keys: Any = UNSET,
) -> dict:
    """Partial update of the user row.

    - `features`: partial dict like `{"ai": True}`, merged into the JSON blob.
    - `theme`: 'system' | 'light' | 'dark'.
    - `selected_provider`: 'anthropic' | 'openai' | 'google'. Changing it to a
       different provider clears `selected_model` (the old model belonged to
       the previous provider).
    - `selected_model`: a fetched model id (in discovered_models), or None to
       clear. Unknown ids raise ValueError.
    - `provider_keys`: partial dict `{provider_id: api_key | None}`. None
       clears that provider's row; a string upserts it. Unknown provider
       ids raise ValueError. Empty strings are rejected at the route layer.
    """
    # Local imports to avoid circular deps. `is_known_model` resolves against
    # the fetched catalog (discovered_models).
    from .services.ai.discovery import is_known_model
    from .services.ai.registry import is_known_provider

    with connect() as conn:
        ensure_default_user(conn)
        row = conn.execute(
            "SELECT features, selected_provider FROM users WHERE id = ?",
            (user_id,),
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

        if selected_provider is not UNSET:
            if not is_known_provider(selected_provider):
                raise ValueError(f"unknown provider: {selected_provider!r}")
            conn.execute(
                "UPDATE users SET selected_provider = ? WHERE id = ?",
                (selected_provider, user_id),
            )
            # Switching providers invalidates the model — it belonged to the
            # old one. Clear it unless this same request also sets a model.
            if selected_model is UNSET and row["selected_provider"] != selected_provider:
                conn.execute(
                    "UPDATE users SET selected_model = NULL WHERE id = ?",
                    (user_id,),
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
