"""AI spend tracking — per-call recording + per-call cost estimation.

Every AI call (chat orchestrator, AI parser, auto-categorizer) ends in a
`record_usage(...)` here. We snapshot the per-call cost at insert time using
the pricing carried on the selected (fetched) model — resolved via
`services/ai/discovery.py` from LiteLLM's bundled cost table — so changing
rates later doesn't retroactively rewrite history.

There is no hardcoded model catalog: models come from the provider the user
picked in Account. A model with no known pricing records a zero-cost row (the
spend chip then under-counts; surfaced in the UI as "pricing n/a").
"""

from __future__ import annotations

from datetime import datetime
from typing import Any

from ..db import connect, init_schema
from .ai import discovery


def _now_iso() -> str:
    return datetime.utcnow().isoformat(timespec="seconds") + "Z"


def _ensure_schema() -> None:
    with connect() as conn:
        init_schema(conn)


def is_known_model(model: str) -> bool:
    return discovery.is_known_model(model)


def available_models(provider_id: str | None = None) -> list[dict]:
    """Fetched models for the Settings dropdown. Frontend consumes this
    verbatim; pass a provider id to scope it to that provider."""
    return discovery.available_models(provider_id)


def compute_cost_usd(model: str, usage: dict) -> float:
    """Compute the dollar cost of one call from token counts. Returns 0.0 when
    the model's pricing is unknown (unfetched or absent from the cost table)
    so we still record a best-effort row."""
    info = discovery.model_pricing(model)
    if info is None:
        return 0.0
    input_t = int(usage.get("input_tokens") or 0)
    output_t = int(usage.get("output_tokens") or 0)
    cache_w = int(usage.get("cache_creation_input_tokens") or 0)
    cache_r = int(usage.get("cache_read_input_tokens") or 0)
    cache_w_rate = info.cache_write_per_mtok or 0.0
    cache_r_rate = info.cache_read_per_mtok or 0.0
    return (
        input_t * info.input_per_mtok
        + output_t * info.output_per_mtok
        + cache_w * cache_w_rate
        + cache_r * cache_r_rate
    ) / 1_000_000.0


def _usage_to_dict(usage: Any) -> dict:
    """Accept either an object with token attrs (e.g. LiteLLM's Usage) or a
    plain dict. Tolerant of missing cache fields."""
    if usage is None:
        return {}
    if isinstance(usage, dict):
        return usage
    out = {}
    # LiteLLM uses prompt_tokens/completion_tokens; older Anthropic-style
    # code used input_tokens/output_tokens. Accept either.
    out["input_tokens"] = (
        getattr(usage, "input_tokens", None)
        or getattr(usage, "prompt_tokens", 0)
        or 0
    )
    out["output_tokens"] = (
        getattr(usage, "output_tokens", None)
        or getattr(usage, "completion_tokens", 0)
        or 0
    )
    out["cache_creation_input_tokens"] = (
        getattr(usage, "cache_creation_input_tokens", 0) or 0
    )
    out["cache_read_input_tokens"] = (
        getattr(usage, "cache_read_input_tokens", 0) or 0
    )
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
