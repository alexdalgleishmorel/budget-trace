"""Anthropic Admin API — authoritative cost lookups.

When the user has set `anthropic_admin_api_key` (sk-ant-admin-...), the
`/me` route uses this to fetch actual billed spend from Anthropic's
`cost_report` endpoint instead of the locally-estimated token math.

Why a separate key: the regular workspace key can't read the cost-report
endpoint. The admin key is provisioned in the Claude Console by a user
with the admin role.

Anthropic recommends polling cost_report at most ~1/min; we keep a small
in-process TTL cache so repeated `/me` polls don't hammer the endpoint.
On any failure (missing key, 401, network, parse) we silently return
None and let the caller fall back to the local sum.
"""

from __future__ import annotations

import hashlib
import logging
import time
from datetime import datetime, timezone

import httpx

log = logging.getLogger(__name__)

_COST_REPORT_URL = "https://api.anthropic.com/v1/organizations/cost_report"
_API_VERSION = "2023-06-01"
_CACHE_TTL_SECONDS = 60.0
_REQUEST_TIMEOUT_SECONDS = 8.0

# (key_hash, since_iso) -> (value_or_none, expires_at_monotonic)
_cache: dict[tuple[str, str], tuple[float | None, float]] = {}


def _key_hash(key: str) -> str:
    return hashlib.sha256(key.encode()).hexdigest()[:16]


def _now_iso() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def fetch_admin_cost_usd(admin_key: str | None, since_iso: str | None) -> float | None:
    """Sum the cost_report for `[since_iso, now]`. Returns None on any failure
    so the caller can fall back to the local estimate."""
    if not admin_key or not since_iso:
        return None

    cache_key = (_key_hash(admin_key), since_iso)
    now_mono = time.monotonic()
    cached = _cache.get(cache_key)
    if cached and cached[1] > now_mono:
        return cached[0]

    total = _fetch(admin_key, since_iso)
    _cache[cache_key] = (total, now_mono + _CACHE_TTL_SECONDS)
    return total


def _fetch(admin_key: str, since_iso: str) -> float | None:
    headers = {
        "x-api-key": admin_key,
        "anthropic-version": _API_VERSION,
    }
    params = {
        "starting_at": since_iso,
        "ending_at": _now_iso(),
    }
    try:
        with httpx.Client(timeout=_REQUEST_TIMEOUT_SECONDS) as client:
            total = 0.0
            url: str | None = _COST_REPORT_URL
            while url:
                resp = client.get(url, params=params if url == _COST_REPORT_URL else None, headers=headers)
                if resp.status_code != 200:
                    log.warning(
                        "admin cost_report returned %s: %s",
                        resp.status_code,
                        resp.text[:200],
                    )
                    return None
                data = resp.json()
                total += _sum_amounts(data)
                # Pagination — Anthropic uses `has_more` + `next_page` style URLs.
                url = data.get("next_page") if data.get("has_more") else None
        return total
    except Exception:  # noqa: BLE001
        log.exception("admin cost_report fetch failed")
        return None


def _sum_amounts(payload: dict) -> float:
    """Walk the cost_report payload summing every dollar-amount cell.

    The endpoint groups by workspace_id/description and returns nested
    `results[].amounts[]` shapes; each amount has `currency` and a numeric
    `amount`. We sum any `currency == "USD"` entry. Be tolerant of shape
    drift — log and skip rather than raising."""
    total = 0.0
    for bucket in payload.get("data", []) or []:
        for result in bucket.get("results", []) or []:
            amounts = result.get("amount")
            if isinstance(amounts, list):
                for entry in amounts:
                    total += _amount_value(entry)
            else:
                total += _amount_value(amounts)
    return total


def _amount_value(entry) -> float:
    if not isinstance(entry, dict):
        return 0.0
    if entry.get("currency") and entry["currency"] != "USD":
        return 0.0
    raw = entry.get("amount")
    try:
        return float(raw)
    except (TypeError, ValueError):
        return 0.0
