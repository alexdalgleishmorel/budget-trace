"""AI spend tracking — pricing table + per-call recording.

Every Anthropic call (chat orchestrator, AI parser, auto-categorizer) ends in
a `record_usage(...)` here. We snapshot the per-call cost using `MODEL_PRICES`
at insert time so changing rates later doesn't retroactively rewrite history.

`MODEL_PRICES` is the only source of truth for what models the app supports.
The Settings dropdown is built from `available_models()`, and `PATCH /me`
rejects model IDs that aren't in here so the spend chip always has a price
to compute against.

Verify rates against the published Anthropic pricing page when you bump them.
"""

from __future__ import annotations

from datetime import datetime
from typing import Any

from ..db import connect, init_schema

# Per-MTok USD rates (input / output / cache write / cache read). `display_name`
# drives the Settings UI; `id` matches the Anthropic model identifier.
MODEL_PRICES: dict[str, dict[str, Any]] = {
    "claude-opus-4-7": {
        "display_name": "Opus 4.7",
        "input": 15.00,
        "output": 75.00,
        "cache_write": 18.75,
        "cache_read": 1.50,
    },
    "claude-sonnet-4-6": {
        "display_name": "Sonnet 4.6",
        "input": 3.00,
        "output": 15.00,
        "cache_write": 3.75,
        "cache_read": 0.30,
    },
    "claude-haiku-4-5-20251001": {
        "display_name": "Haiku 4.5",
        "input": 1.00,
        "output": 5.00,
        "cache_write": 1.25,
        "cache_read": 0.10,
    },
}

DEFAULT_MODEL = "claude-sonnet-4-6"


def _now_iso() -> str:
    return datetime.utcnow().isoformat(timespec="seconds") + "Z"


def _ensure_schema() -> None:
    with connect() as conn:
        init_schema(conn)


def is_known_model(model: str) -> bool:
    return model in MODEL_PRICES


def available_models() -> list[dict]:
    """For the Settings dropdown. Frontend consumes this verbatim."""
    return [
        {
            "id": mid,
            "display_name": price["display_name"],
            "input_per_mtok": price["input"],
            "output_per_mtok": price["output"],
        }
        for mid, price in MODEL_PRICES.items()
    ]


def compute_cost_usd(model: str, usage: dict) -> float:
    """Compute the dollar cost of one call from token counts. Falls back to
    Sonnet rates for unknown models so we still record a (best-effort) row."""
    price = MODEL_PRICES.get(model) or MODEL_PRICES[DEFAULT_MODEL]
    input_t = int(usage.get("input_tokens") or 0)
    output_t = int(usage.get("output_tokens") or 0)
    cache_w = int(usage.get("cache_creation_input_tokens") or 0)
    cache_r = int(usage.get("cache_read_input_tokens") or 0)
    return (
        input_t * price["input"]
        + output_t * price["output"]
        + cache_w * price["cache_write"]
        + cache_r * price["cache_read"]
    ) / 1_000_000.0


def _usage_to_dict(usage: Any) -> dict:
    """Accept either an Anthropic `Usage` object or a plain dict."""
    if usage is None:
        return {}
    if isinstance(usage, dict):
        return usage
    out = {}
    for f in (
        "input_tokens",
        "output_tokens",
        "cache_creation_input_tokens",
        "cache_read_input_tokens",
    ):
        out[f] = getattr(usage, f, 0) or 0
    return out


def record_usage(
    *,
    source: str,
    model: str,
    usage: Any,
    chat_session_id: int | None = None,
) -> dict:
    """Persist a row and return the snapshot. Tolerant of missing cache fields."""
    _ensure_schema()
    u = _usage_to_dict(usage)
    cost = compute_cost_usd(model, u)
    now = _now_iso()
    with connect() as conn:
        conn.execute(
            """
            INSERT INTO ai_usage
                (created_at, source, chat_session_id, model,
                 input_tokens, output_tokens,
                 cache_creation_input_tokens, cache_read_input_tokens,
                 cost_usd)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (
                now,
                source,
                chat_session_id,
                model,
                int(u.get("input_tokens") or 0),
                int(u.get("output_tokens") or 0),
                int(u.get("cache_creation_input_tokens") or 0),
                int(u.get("cache_read_input_tokens") or 0),
                cost,
            ),
        )
    return {
        "cost_usd": cost,
        "input_tokens": int(u.get("input_tokens") or 0),
        "output_tokens": int(u.get("output_tokens") or 0),
    }


def total_spent_local_usd() -> float:
    _ensure_schema()
    with connect() as conn:
        row = conn.execute(
            "SELECT COALESCE(SUM(cost_usd), 0.0) AS total FROM ai_usage"
        ).fetchone()
    return float(row["total"] or 0.0)


def spent_for_session_local_usd(session_id: int) -> float:
    _ensure_schema()
    with connect() as conn:
        row = conn.execute(
            "SELECT COALESCE(SUM(cost_usd), 0.0) AS total "
            "  FROM ai_usage WHERE chat_session_id = ?",
            (session_id,),
        ).fetchone()
    return float(row["total"] or 0.0)


def earliest_recorded_at() -> str | None:
    _ensure_schema()
    with connect() as conn:
        row = conn.execute(
            "SELECT MIN(created_at) AS earliest FROM ai_usage"
        ).fetchone()
    return row["earliest"] if row and row["earliest"] else None
