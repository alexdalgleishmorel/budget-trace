"""Provider registry — the single source of truth for *which providers* exist.

There is **no hardcoded model list**. The user picks a generic provider
(Anthropic / OpenAI / Google) in the Account screen; the actual models are
fetched live from that provider's "list models" API (see `discovery.py`) and
stored in the `discovered_models` table. Adding a provider means adding a row
to `PROVIDERS`.

`ModelInfo` survives only as a lightweight pricing carrier used by the spend
calculation — it is no longer a static catalog.
"""

from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True)
class ProviderInfo:
    id: str            # 'anthropic' | 'openai' | 'google'
    display_name: str  # 'Anthropic'
    env_var: str       # 'ANTHROPIC_API_KEY' — fallback when no DB key set
    litellm_prefix: str  # 'anthropic/' | 'openai/' | 'gemini/'
    supports_pdf: bool   # whether file/document content blocks are accepted
    supports_image: bool


@dataclass(frozen=True)
class ModelInfo:
    """Pricing snapshot for one model. Built from a fetched model + LiteLLM's
    cost table; consumed by `ai_usage.compute_cost_usd`."""
    id: str
    provider: str
    display_name: str
    input_per_mtok: float
    output_per_mtok: float
    cache_write_per_mtok: float | None = None
    cache_read_per_mtok: float | None = None


PROVIDERS: dict[str, ProviderInfo] = {
    "anthropic": ProviderInfo(
        id="anthropic",
        display_name="Anthropic",
        env_var="ANTHROPIC_API_KEY",
        litellm_prefix="anthropic/",
        supports_pdf=True,
        supports_image=True,
    ),
    "openai": ProviderInfo(
        id="openai",
        display_name="OpenAI",
        env_var="OPENAI_API_KEY",
        litellm_prefix="openai/",
        supports_pdf=False,
        supports_image=True,
    ),
    "google": ProviderInfo(
        id="google",
        display_name="Google",
        env_var="GEMINI_API_KEY",
        litellm_prefix="gemini/",
        supports_pdf=True,
        supports_image=True,
    ),
}


# The provider a brand-new user row defaults to. No model is selected until the
# user fetches a provider's catalog and picks one.
DEFAULT_PROVIDER = "anthropic"


def is_known_provider(provider_id: str) -> bool:
    return provider_id in PROVIDERS


def known_providers() -> list[ProviderInfo]:
    return list(PROVIDERS.values())
