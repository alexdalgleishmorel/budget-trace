"""Provider + model registry — single source of truth for what's supported.

The Settings dropdown is built from `available_models()`. `PATCH /me` rejects
model ids not in `MODEL_REGISTRY` so the spend chip always has a price to
compute against. Adding a new provider means adding a row to `PROVIDERS`
(plus any models it should offer to `MODEL_REGISTRY`); the frontend
automatically renders a new key row.

Verify per-MTok rates against each provider's published pricing page when
bumping them.
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
    id: str            # 'claude-sonnet-4-6' (canonical, provider-prefix added by client)
    provider: str      # matches ProviderInfo.id
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


# Per-MTok USD rates. Anthropic models have cache pricing; the others use
# input/output only (LiteLLM normalises usage so cache fields are 0 there).
MODEL_REGISTRY: dict[str, ModelInfo] = {
    # ── Anthropic ────────────────────────────────────────────────────────────
    "claude-opus-4-7": ModelInfo(
        id="claude-opus-4-7",
        provider="anthropic",
        display_name="Opus 4.7",
        input_per_mtok=15.00,
        output_per_mtok=75.00,
        cache_write_per_mtok=18.75,
        cache_read_per_mtok=1.50,
    ),
    "claude-sonnet-4-6": ModelInfo(
        id="claude-sonnet-4-6",
        provider="anthropic",
        display_name="Sonnet 4.6",
        input_per_mtok=3.00,
        output_per_mtok=15.00,
        cache_write_per_mtok=3.75,
        cache_read_per_mtok=0.30,
    ),
    "claude-haiku-4-5-20251001": ModelInfo(
        id="claude-haiku-4-5-20251001",
        provider="anthropic",
        display_name="Haiku 4.5",
        input_per_mtok=1.00,
        output_per_mtok=5.00,
        cache_write_per_mtok=1.25,
        cache_read_per_mtok=0.10,
    ),
    # ── OpenAI ───────────────────────────────────────────────────────────────
    # Pricing as published late-2025; verify against openai.com/pricing.
    "gpt-4o": ModelInfo(
        id="gpt-4o",
        provider="openai",
        display_name="GPT-4o",
        input_per_mtok=2.50,
        output_per_mtok=10.00,
    ),
    "gpt-4o-mini": ModelInfo(
        id="gpt-4o-mini",
        provider="openai",
        display_name="GPT-4o mini",
        input_per_mtok=0.15,
        output_per_mtok=0.60,
    ),
    "gpt-4.1": ModelInfo(
        id="gpt-4.1",
        provider="openai",
        display_name="GPT-4.1",
        input_per_mtok=2.00,
        output_per_mtok=8.00,
    ),
    # ── Google Gemini ────────────────────────────────────────────────────────
    "gemini-2.5-pro": ModelInfo(
        id="gemini-2.5-pro",
        provider="google",
        display_name="Gemini 2.5 Pro",
        input_per_mtok=1.25,
        output_per_mtok=10.00,
    ),
    "gemini-2.5-flash": ModelInfo(
        id="gemini-2.5-flash",
        provider="google",
        display_name="Gemini 2.5 Flash",
        input_per_mtok=0.30,
        output_per_mtok=2.50,
    ),
}


DEFAULT_MODEL = "claude-sonnet-4-6"


def is_known_model(model_id: str) -> bool:
    return model_id in MODEL_REGISTRY


def is_known_provider(provider_id: str) -> bool:
    return provider_id in PROVIDERS


def provider_for_model(model_id: str) -> ProviderInfo:
    """Resolve the provider of a model. Raises KeyError if unknown."""
    info = MODEL_REGISTRY[model_id]
    return PROVIDERS[info.provider]


def available_models() -> list[dict]:
    """For the Settings dropdown. Frontend consumes this verbatim."""
    return [
        {
            "id": m.id,
            "provider": m.provider,
            "display_name": m.display_name,
            "input_per_mtok": m.input_per_mtok,
            "output_per_mtok": m.output_per_mtok,
        }
        for m in MODEL_REGISTRY.values()
    ]


def known_providers() -> list[ProviderInfo]:
    return list(PROVIDERS.values())


def cheapest_model() -> ModelInfo:
    """Used as the fallback for cost computation when a model id isn't
    in the registry (e.g. an old `ai_usage` row whose model was removed)."""
    return min(
        MODEL_REGISTRY.values(),
        key=lambda m: m.input_per_mtok + m.output_per_mtok,
    )
