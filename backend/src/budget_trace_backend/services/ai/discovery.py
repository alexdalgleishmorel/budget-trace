"""Live model discovery — the only model store.

There is no hardcoded model catalog. The user picks a provider in the Account
screen and fetches its models; this module calls that provider's "list models"
API (anthropic/openai SDKs, Gemini REST), prices each model from LiteLLM's
bundled cost table where it can, and persists the result in the
`discovered_models` table. Everything that needs to know about a model —
validation, provider resolution, pricing — reads from that table via the
helpers here.

litellm and the provider SDKs are imported lazily inside the functions that
need them so `/me` reads, CSV-only imports, and tests stay free of that import
cost.
"""

from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime

from ...db import connect, init_schema
from .registry import PROVIDERS, ModelInfo


@dataclass(frozen=True)
class DiscoveredModel:
    id: str
    provider: str
    display_name: str
    input_per_mtok: float | None
    output_per_mtok: float | None
    cache_write_per_mtok: float | None
    cache_read_per_mtok: float | None
    pricing_available: bool


# OpenAI's models.list() mixes in embeddings/tts/whisper/image models. When a
# model id isn't in litellm's cost table (so we can't read its `mode`), fall
# back to these heuristics.
_OPENAI_CHAT_PREFIXES = ("gpt-", "o1", "o3", "o4", "chatgpt-")
_OPENAI_NON_CHAT_MARKERS = (
    "-audio", "-realtime", "-tts", "-transcribe", "-image",
    "-search", "-embedding", "embedding", "whisper", "dall-e", "tts-",
)

_LIST_TIMEOUT = 15.0


def _now_iso() -> str:
    return datetime.utcnow().isoformat(timespec="seconds") + "Z"


# ── Pricing (LiteLLM bundled cost table) ──────────────────────────────────────

def litellm_price_per_mtok(litellm_prefix: str, model_id: str) -> dict | None:
    """Resolve per-MTok pricing from litellm's bundled cost table.

    Tries the litellm-prefixed key first (`gemini/gemini-2.5-pro` carries the
    `gemini` provider's pricing; the bare id maps to vertex), then the bare id
    (matches anthropic/openai). Requires `mode == "chat"`. Returns a dict of
    per-MTok rates (cache fields present only when the table has them), or None
    when the model isn't priceable.
    """
    import litellm

    for key in (litellm_prefix + model_id, model_id):
        entry = litellm.model_cost.get(key)
        if (
            entry
            and entry.get("mode") == "chat"
            and entry.get("input_cost_per_token") is not None
        ):
            cw = entry.get("cache_creation_input_token_cost")
            cr = entry.get("cache_read_input_token_cost")
            return {
                "input_per_mtok": entry["input_cost_per_token"] * 1e6,
                "output_per_mtok": (entry.get("output_cost_per_token") or 0.0) * 1e6,
                "cache_write_per_mtok": cw * 1e6 if cw is not None else None,
                "cache_read_per_mtok": cr * 1e6 if cr is not None else None,
            }
    return None


# ── Per-provider list calls (each isolated; key resolved by the caller) ───────

def _list_anthropic(api_key: str) -> list[tuple[str, str]]:
    import anthropic

    client = anthropic.Anthropic(api_key=api_key, timeout=_LIST_TIMEOUT)
    out: list[tuple[str, str]] = []
    for m in client.models.list(limit=1000):
        mid = getattr(m, "id", None)
        if not mid:
            continue
        out.append((mid, getattr(m, "display_name", None) or mid))
    return out


def _openai_is_chat(model_id: str) -> bool:
    import litellm

    entry = litellm.model_cost.get(model_id)
    if entry and entry.get("mode"):
        return entry["mode"] == "chat"
    lower = model_id.lower()
    if any(marker in lower for marker in _OPENAI_NON_CHAT_MARKERS):
        return False
    return any(lower.startswith(p) for p in _OPENAI_CHAT_PREFIXES)


def _list_openai(api_key: str) -> list[tuple[str, str]]:
    import openai

    client = openai.OpenAI(api_key=api_key, timeout=_LIST_TIMEOUT)
    out: list[tuple[str, str]] = []
    for m in client.models.list():
        mid = getattr(m, "id", None)
        if not mid or not _openai_is_chat(mid):
            continue
        out.append((mid, mid))
    return out


def _list_gemini(api_key: str) -> list[tuple[str, str]]:
    import httpx

    base = "https://generativelanguage.googleapis.com/v1beta/models"
    out: list[tuple[str, str]] = []
    page_token: str | None = None
    with httpx.Client(timeout=_LIST_TIMEOUT) as http:
        while True:
            params: dict = {"key": api_key, "pageSize": 1000}
            if page_token:
                params["pageToken"] = page_token
            resp = http.get(base, params=params)
            resp.raise_for_status()
            data = resp.json()
            for m in data.get("models", []):
                methods = m.get("supportedGenerationMethods") or []
                if "generateContent" not in methods:
                    continue
                name = m.get("name", "")
                mid = name.split("/", 1)[1] if "/" in name else name
                if not mid:
                    continue
                out.append((mid, m.get("displayName") or mid))
            page_token = data.get("nextPageToken")
            if not page_token:
                break
    return out


_LISTERS = {
    "anthropic": _list_anthropic,
    "openai": _list_openai,
    "google": _list_gemini,
}


# ── Persistence ───────────────────────────────────────────────────────────────

def _row_to_discovered(row) -> DiscoveredModel:
    return DiscoveredModel(
        id=row["id"],
        provider=row["provider"],
        display_name=row["display_name"],
        input_per_mtok=row["input_per_mtok"],
        output_per_mtok=row["output_per_mtok"],
        cache_write_per_mtok=row["cache_write_per_mtok"],
        cache_read_per_mtok=row["cache_read_per_mtok"],
        pricing_available=bool(row["pricing_available"]),
    )


def discovered_models() -> dict[str, DiscoveredModel]:
    """Every persisted model, keyed by id (across all providers)."""
    with connect() as conn:
        init_schema(conn)
        rows = conn.execute(
            "SELECT id, provider, display_name, input_per_mtok, output_per_mtok, "
            "cache_write_per_mtok, cache_read_per_mtok, pricing_available "
            "FROM discovered_models"
        ).fetchall()
    return {r["id"]: _row_to_discovered(r) for r in rows}


def _replace_provider_models(provider_id: str, models: list[DiscoveredModel]) -> None:
    """Swap in a provider's fetched models: drop its old rows, insert the new
    set. Keeps the catalog in sync when a provider adds/removes models."""
    now = _now_iso()
    with connect() as conn:
        init_schema(conn)
        conn.execute(
            "DELETE FROM discovered_models WHERE provider = ?", (provider_id,)
        )
        if models:
            conn.executemany(
                """
                INSERT INTO discovered_models
                    (id, provider, display_name, input_per_mtok, output_per_mtok,
                     cache_write_per_mtok, cache_read_per_mtok, pricing_available,
                     discovered_at)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    provider = excluded.provider,
                    display_name = excluded.display_name,
                    input_per_mtok = excluded.input_per_mtok,
                    output_per_mtok = excluded.output_per_mtok,
                    cache_write_per_mtok = excluded.cache_write_per_mtok,
                    cache_read_per_mtok = excluded.cache_read_per_mtok,
                    pricing_available = excluded.pricing_available,
                    discovered_at = excluded.discovered_at
                """,
                [
                    (
                        m.id, m.provider, m.display_name,
                        m.input_per_mtok, m.output_per_mtok,
                        m.cache_write_per_mtok, m.cache_read_per_mtok,
                        int(m.pricing_available), now,
                    )
                    for m in models
                ],
            )


# ── Refresh one provider ──────────────────────────────────────────────────────

def refresh_provider(provider_id: str) -> dict:
    """Fetch a provider's live model list using its key, price each model, and
    persist (replacing that provider's previous rows). Never raises on a
    provider/network failure — returns a per-provider status instead.

    Returns `{"provider": {provider, ok, discovered_count, skipped, error},
              "available_models": [<that provider's model dicts>]}`.
    """
    # Local import to avoid a circular dependency (client imports discovery).
    from . import client as ai_client

    info = PROVIDERS.get(provider_id)
    lister = _LISTERS.get(provider_id)
    if info is None or lister is None:
        return {
            "provider": {"provider": provider_id, "ok": False,
                         "discovered_count": 0, "skipped": False,
                         "error": "unknown provider"},
            "available_models": [],
        }

    key = ai_client._resolve_key(provider_id)
    if not key:
        return {
            "provider": {"provider": provider_id, "ok": False,
                         "discovered_count": 0, "skipped": True, "error": None},
            "available_models": available_models(provider_id),
        }

    try:
        listed = lister(key)
    except Exception as e:  # noqa: BLE001 — surfaced, never 500
        return {
            "provider": {"provider": provider_id, "ok": False,
                         "discovered_count": 0, "skipped": False,
                         "error": _short_error(e)},
            "available_models": available_models(provider_id),
        }

    found: list[DiscoveredModel] = []
    for model_id, display_name in listed:
        price = litellm_price_per_mtok(info.litellm_prefix, model_id)
        found.append(DiscoveredModel(
            id=model_id,
            provider=provider_id,
            display_name=display_name,
            input_per_mtok=price["input_per_mtok"] if price else None,
            output_per_mtok=price["output_per_mtok"] if price else None,
            cache_write_per_mtok=price["cache_write_per_mtok"] if price else None,
            cache_read_per_mtok=price["cache_read_per_mtok"] if price else None,
            pricing_available=price is not None,
        ))

    _replace_provider_models(provider_id, found)
    return {
        "provider": {"provider": provider_id, "ok": True,
                     "discovered_count": len(found), "skipped": False,
                     "error": None},
        "available_models": available_models(provider_id),
    }


def _short_error(e: Exception) -> str:
    msg = str(e).strip() or e.__class__.__name__
    return msg if len(msg) <= 200 else msg[:197] + "…"


# ── Lookups ───────────────────────────────────────────────────────────────────

def is_known_model(model_id: str) -> bool:
    """True once the model has been fetched and persisted."""
    return model_id in discovered_models()


def provider_of(model_id: str) -> str | None:
    """The provider id for a fetched model. None if unknown."""
    d = discovered_models().get(model_id)
    return d.provider if d else None


def model_pricing(model_id: str) -> ModelInfo | None:
    """Pricing for a fetched model as a ModelInfo, or None when it's unknown or
    priced-as-unavailable (callers treat that as zero cost)."""
    d = discovered_models().get(model_id)
    if d is None or not d.pricing_available:
        return None
    return ModelInfo(
        id=d.id,
        provider=d.provider,
        display_name=d.display_name,
        input_per_mtok=d.input_per_mtok or 0.0,
        output_per_mtok=d.output_per_mtok or 0.0,
        cache_write_per_mtok=d.cache_write_per_mtok,
        cache_read_per_mtok=d.cache_read_per_mtok,
    )


def available_models(provider_id: str | None = None) -> list[dict]:
    """Fetched models for the Settings dropdown. Filtered to `provider_id` when
    given, else all providers. Sorted by display name for a stable UI."""
    rows = [d for d in discovered_models().values()
            if provider_id is None or d.provider == provider_id]
    rows.sort(key=lambda d: d.display_name.lower())
    return [
        {
            "id": d.id,
            "provider": d.provider,
            "display_name": d.display_name,
            "input_per_mtok": d.input_per_mtok or 0.0,
            "output_per_mtok": d.output_per_mtok or 0.0,
            "discovered": True,
            "pricing_available": d.pricing_available,
        }
        for d in rows
    ]
