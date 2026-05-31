"""Provider-agnostic AI client.

`chat()` is the single entry every AI call site uses. It resolves the API key
for the selected model's provider, prefixes the model id for LiteLLM, and
dispatches one `litellm.completion()` call.

Key resolution order (per provider):
1. `ai_provider_keys.api_key` for the user (set via PATCH /me).
2. The provider's env var (`ANTHROPIC_API_KEY`, `OPENAI_API_KEY`,
   `GEMINI_API_KEY`).
3. Raise `AiKeyMissing(provider_id)`.

Message and tool shapes follow the OpenAI / LiteLLM convention so call sites
don't need to know which provider they're talking to. LiteLLM translates per
provider internally.
"""

from __future__ import annotations

import os
from typing import Any

from ...features import get_me
from . import discovery
from .registry import PROVIDERS


class NoModelSelected(RuntimeError):
    """Raised when an AI call is attempted but no model has been selected.

    There is no default model — the user picks a provider and fetches its
    models in Account settings, then selects one. The route layer turns this
    into a 400 with a friendly message."""

    code = "no_model_selected"

    def __init__(self) -> None:
        super().__init__(
            "No AI model selected. Open Account, choose a provider, fetch its "
            "models, and pick one."
        )


class AiKeyMissing(RuntimeError):
    """Raised when no API key is configured for the resolved provider."""

    code = "ai_key_missing"

    def __init__(self, provider_id: str) -> None:
        provider = PROVIDERS.get(provider_id)
        name = provider.display_name if provider else provider_id
        env_var = provider.env_var if provider else f"{provider_id.upper()}_API_KEY"
        self.provider = provider_id
        super().__init__(
            f"No API key configured for {name}. Add one in Account settings "
            f"(PATCH /me) or set the {env_var} environment variable."
        )


class UnsupportedContent(RuntimeError):
    """Raised when the selected model's provider rejects a content block
    (e.g. PDF document on an OpenAI model). The route layer turns this into
    a 400 with a friendly message."""

    code = "unsupported_content"

    def __init__(self, message: str, provider_id: str | None = None) -> None:
        self.provider = provider_id
        super().__init__(message)


def get_selected_model() -> str | None:
    """Resolution order: users.selected_model → SELECTED_MODEL env → None.

    There is no hardcoded default — returns None when the user hasn't picked a
    model yet. Callers pass the result to `chat()`, which raises
    `NoModelSelected` on a falsy value."""
    me = get_me()
    return me.get("selected_model") or os.environ.get("SELECTED_MODEL") or None


def _resolve_key(provider_id: str) -> str | None:
    """Stored key wins over env var. Returns None when neither is set."""
    me = get_me()
    stored = (me.get("provider_keys") or {}).get(provider_id)
    if stored:
        return stored
    provider = PROVIDERS.get(provider_id)
    if provider is None:
        return None
    return os.environ.get(provider.env_var)


def provider_env_present(provider_id: str) -> bool:
    """Is the provider's fallback env var set? Used by `/me` to render the
    'Env' status pill."""
    provider = PROVIDERS.get(provider_id)
    if provider is None:
        return False
    return bool(os.environ.get(provider.env_var))


def chat(
    *,
    model: str,
    system: str,
    messages: list[dict],
    tools: list[dict] | None = None,
    max_tokens: int = 2048,
) -> dict:
    """Send one request to the model. Returns a normalised dict — callers
    don't see the LiteLLM `ModelResponse` shape directly.

    Returns:
        {
          "content": <str | None>,                 # assistant text (may be empty when tool calls present)
          "tool_calls": [{"id", "name", "arguments_json"}],
          "usage": {"input_tokens", "output_tokens",
                    "cache_creation_input_tokens", "cache_read_input_tokens"},
          "finish_reason": <str>,
        }

    Raises:
        NoModelSelected — no model picked (or it's no longer in the fetched catalog).
        AiKeyMissing — no API key for the selected model's provider.
        UnsupportedContent — provider rejected a content block (e.g. PDF on OpenAI).
    """
    if not model:
        raise NoModelSelected()

    provider_id = discovery.provider_of(model)
    if provider_id is None:
        # The model isn't in the fetched catalog (never fetched, or the
        # provider dropped it). Treat it the same as "nothing selected".
        raise NoModelSelected()

    provider = PROVIDERS[provider_id]
    key = _resolve_key(provider.id)
    if not key:
        raise AiKeyMissing(provider.id)

    # Lazy import — keeps litellm out of the import path for everything that
    # doesn't actually call the model (CSV-only imports, /me reads, tests).
    import litellm
    from litellm.exceptions import BadRequestError

    prefixed = provider.litellm_prefix + model
    kwargs: dict[str, Any] = {
        "model": prefixed,
        "messages": [{"role": "system", "content": system}, *messages],
        "max_tokens": max_tokens,
        "api_key": key,
    }
    if tools:
        kwargs["tools"] = tools

    try:
        response = litellm.completion(**kwargs)
    except BadRequestError as e:
        # Most commonly: PDF/document content on a provider that doesn't accept it.
        raise UnsupportedContent(
            f"{provider.display_name} rejected the request: {e}. "
            "If you're uploading a PDF, switch to an Anthropic or Google "
            "model in Account settings.",
            provider_id=provider.id,
        ) from e

    choice = response.choices[0]
    msg = choice.message

    tool_calls_out: list[dict] = []
    for tc in (getattr(msg, "tool_calls", None) or []):
        fn = getattr(tc, "function", None)
        if fn is None:
            continue
        tool_calls_out.append({
            "id": getattr(tc, "id", "") or "",
            "name": getattr(fn, "name", "") or "",
            "arguments_json": getattr(fn, "arguments", "") or "",
        })

    usage = response.usage
    return {
        "content": getattr(msg, "content", None),
        "tool_calls": tool_calls_out,
        "usage": {
            "input_tokens": int(getattr(usage, "prompt_tokens", 0) or 0),
            "output_tokens": int(getattr(usage, "completion_tokens", 0) or 0),
            "cache_creation_input_tokens": int(
                getattr(usage, "cache_creation_input_tokens", 0) or 0
            ),
            "cache_read_input_tokens": int(
                getattr(usage, "cache_read_input_tokens", 0) or 0
            ),
        },
        "finish_reason": getattr(choice, "finish_reason", "") or "",
    }
