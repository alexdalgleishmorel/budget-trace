"""User-settings routes.

`GET /me`   → features + theme + per-provider key status + selected model +
              the resolved provider for that model + whether its key is
              available + the full model catalog for the Settings dropdown +
              cumulative AI spend (estimated from token usage).
              Key values themselves are never returned.
`PATCH /me` → partial update. Each field is independently optional. Set a
              provider's key via `provider_keys: {"<provider>": "..."}`;
              clear with `provider_keys: {"<provider>": null}`. Set a model
              with `selected_model: "<id>"`; pass `null` to reset to env/default.
              Empty-string key values are 422 — use `null` to clear.

Single-user dev today (id=1). When auth lands, the user_id will come from
the request session; the route shape stays the same.
"""

from __future__ import annotations

import os
from typing import Literal

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel, ConfigDict, Field

from .. import features
from ..services import ai_usage
from ..services.ai import client as ai_client
from ..services.ai.registry import (
    DEFAULT_MODEL,
    MODEL_REGISTRY,
    known_providers,
)

router = APIRouter(prefix="/me", tags=["me"])


Theme = Literal["system", "light", "dark"]


class FeaturesPatch(BaseModel):
    model_config = ConfigDict(extra="forbid")
    ai: bool | None = None


class ModelOption(BaseModel):
    id: str
    provider: str
    display_name: str
    input_per_mtok: float
    output_per_mtok: float


class ProviderStatus(BaseModel):
    id: str
    display_name: str
    env_var: str
    api_key_set: bool
    env_fallback: bool


class MeOut(BaseModel):
    features: dict[str, bool]
    theme: Theme
    providers: list[ProviderStatus]
    selected_model: str
    selected_model_provider: str
    selected_model_key_available: bool
    available_models: list[ModelOption]
    ai_spent_usd: float


# Sentinel for "field not provided" in PATCH. JSON has no `undefined`; the
# frontend sends an explicit `null` to clear the selected model.
_UNSET = "__BT_UNSET__"


class MePatch(BaseModel):
    model_config = ConfigDict(extra="forbid")
    features: FeaturesPatch | None = None
    theme: Theme | None = None
    selected_model: str | None = Field(default=_UNSET)
    # Partial dict: only the providers you include get changed. Value None
    # clears that provider's key; non-empty string sets it.
    provider_keys: dict[str, str | None] | None = None


@router.get("", response_model=MeOut)
def get_me() -> MeOut:
    return _build_me_out()


@router.patch("", response_model=MeOut)
def patch_me(body: MePatch) -> MeOut:
    kwargs: dict = {}

    if body.features is not None:
        flags = {k: v for k, v in body.features.model_dump().items() if v is not None}
        if flags:
            kwargs["features"] = flags

    if body.theme is not None:
        kwargs["theme"] = body.theme

    if body.selected_model != _UNSET:
        if body.selected_model == "":
            raise HTTPException(
                status_code=422,
                detail={"code": "validation_error",
                        "message": "selected_model may not be empty; pass null to reset."},
            )
        kwargs["selected_model"] = body.selected_model

    if body.provider_keys is not None:
        for provider_id, value in body.provider_keys.items():
            if value == "":
                raise HTTPException(
                    status_code=422,
                    detail={"code": "validation_error",
                            "message": f"provider_keys[{provider_id!r}] may not be empty; "
                                       "pass null to clear."},
                )
        kwargs["provider_keys"] = body.provider_keys

    try:
        features.update_me(**kwargs)
    except ValueError as e:
        raise HTTPException(
            status_code=422,
            detail={"code": "validation_error", "message": str(e)},
        )

    return _build_me_out()


def _build_me_out() -> MeOut:
    me = features.get_me()
    stored_keys = me.get("provider_keys") or {}

    # Resolved model — same fallback chain that get_selected_model() uses,
    # surfaced so the Settings UI can highlight the current effective value
    # even when the user hasn't picked one explicitly.
    resolved_model = (
        me.get("selected_model")
        or os.environ.get("SELECTED_MODEL")
        or DEFAULT_MODEL
    )
    resolved_provider = MODEL_REGISTRY[resolved_model].provider

    providers: list[ProviderStatus] = []
    for p in known_providers():
        api_key_set = bool(stored_keys.get(p.id))
        env_fallback = ai_client.provider_env_present(p.id)
        providers.append(ProviderStatus(
            id=p.id,
            display_name=p.display_name,
            env_var=p.env_var,
            api_key_set=api_key_set,
            env_fallback=env_fallback,
        ))

    selected_key_available = bool(stored_keys.get(resolved_provider)) or \
        ai_client.provider_env_present(resolved_provider)

    return MeOut(
        features=me["features"],
        theme=me["theme"],
        providers=providers,
        selected_model=resolved_model,
        selected_model_provider=resolved_provider,
        selected_model_key_available=selected_key_available,
        available_models=[ModelOption(**m) for m in ai_usage.available_models()],
        ai_spent_usd=ai_usage.total_spent_local_usd(),
    )
