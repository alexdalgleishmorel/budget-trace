"""Centralised Anthropic client construction.

Every AI call site (chat orchestrator, AI parser, auto-categorizer) goes
through `get_client()`. The key resolution order:

1. The `anthropic_api_key` column on the user row (set via PATCH /me).
2. The `ANTHROPIC_API_KEY` environment variable.
3. Raise `AiKeyMissing` — the caller decides whether that's a 4xx, a graceful
   degrade, or a startup error.
"""

from __future__ import annotations

import os

from anthropic import Anthropic

from ..features import get_me


class AiKeyMissing(RuntimeError):
    """Raised when no Anthropic API key is configured anywhere."""

    code = "ai_key_missing"

    def __init__(self) -> None:
        super().__init__(
            "No Anthropic API key. Set one in the Account screen "
            "(PATCH /me) or via the ANTHROPIC_API_KEY env var."
        )


def get_client() -> Anthropic:
    me = get_me()
    key = me.get("anthropic_api_key") or os.environ.get("ANTHROPIC_API_KEY")
    if not key:
        raise AiKeyMissing()
    return Anthropic(api_key=key)


def get_model() -> str:
    """Resolution order: user row → env var → default. The user picks via
    the Settings dropdown (`PATCH /me anthropic_model: ...`); env wins for
    fresh DBs and tests; the default is the canonical Sonnet 4.x model."""
    me = get_me()
    return (
        me.get("anthropic_model")
        or os.environ.get("ANTHROPIC_MODEL")
        or "claude-sonnet-4-6"
    )
