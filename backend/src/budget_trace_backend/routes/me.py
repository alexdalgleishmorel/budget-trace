"""User-settings routes.

Provider-first model selection: the user picks a generic provider (Anthropic /
OpenAI / Google), sets its key, then fetches that provider's live model list and
picks one. There is no hardcoded model catalog.

`GET /me`   → features + theme + per-provider key status + the selected provider
              and whether its key is available + the selected model (may be
              empty until one is picked) + the fetched models for the selected
              provider + cumulative AI spend. Key values are never returned.
`PATCH /me` → partial update. Each field is independently optional:
              `selected_provider: "<id>"` (switching it clears the model),
              `selected_model: "<id>"` (a fetched model; `null` clears),
              `provider_keys: {"<provider>": "..."|null}` (set/clear a key),
              plus `features` / `theme`. Empty strings are 422 — use `null`.
`POST /me/models/refresh` → fetch the *selected provider's* live model list
              (using its key) and return the result + that provider's models.

This is a local single-user app (id=1); there is no auth.
"""

from __future__ import annotations

import os
from typing import Literal

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel, ConfigDict, Field

from .. import features
from ..services import ai_usage
from ..services.ai import client as ai_client
from ..services.ai import discovery
from ..services.ai.registry import DEFAULT_PROVIDER, known_providers

router = APIRouter(prefix="/me", tags=["me"])


Theme = Literal["system", "light", "dark"]


class FeaturesPatch(BaseModel):
    model_config = ConfigDict(extra="forbid")
    ai: bool | None = None
    widgets: bool | None = None


class ModelOption(BaseModel):
    id: str
    provider: str
    display_name: str
    input_per_mtok: float
    output_per_mtok: float
    discovered: bool = True
    # False when the model's rates aren't in LiteLLM's cost table (spend then
    # under-counts) — surfaced in the UI as "pricing n/a".
    pricing_available: bool = True


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
    selected_provider: str
    selected_provider_key_available: bool
    selected_model: str            # "" when none picked yet
    available_models: list[ModelOption]  # for the selected provider
    ai_spent_usd: float
    last_dashboard_id: int | None = None


# Sentinel for "field not provided" in PATCH. JSON has no `undefined`; the
# frontend sends an explicit `null` to clear the selected model.
_UNSET = "__BT_UNSET__"


class MePatch(BaseModel):
    model_config = ConfigDict(extra="forbid")
    features: FeaturesPatch | None = None
    theme: Theme | None = None
    selected_provider: str | None = None
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

    if body.selected_provider is not None:
        kwargs["selected_provider"] = body.selected_provider

    if body.selected_model != _UNSET:
        if body.selected_model == "":
            raise HTTPException(
                status_code=422,
                detail={"code": "validation_error",
                        "message": "selected_model may not be empty; pass null to clear."},
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


class ProviderRefreshResult(BaseModel):
    provider: str
    ok: bool
    discovered_count: int = 0
    skipped: bool = False  # true when the provider has no key configured
    error: str | None = None


class ModelsRefreshOut(BaseModel):
    provider: ProviderRefreshResult
    available_models: list[ModelOption]


@router.post("/models/refresh", response_model=ModelsRefreshOut)
def refresh_models() -> ModelsRefreshOut:
    """Fetch the live model list for the *selected* provider, using its key,
    and persist it (replacing that provider's previous models). A provider
    being down / missing a key / rejecting the key is reported, never a 500."""
    selected_provider = features.get_me().get("selected_provider") or DEFAULT_PROVIDER
    result = discovery.refresh_provider(selected_provider)
    return ModelsRefreshOut(
        provider=ProviderRefreshResult(**result["provider"]),
        available_models=[ModelOption(**m) for m in result["available_models"]],
    )


def _build_me_out() -> MeOut:
    me = features.get_me()
    stored_keys = me.get("provider_keys") or {}

    selected_provider = me.get("selected_provider") or DEFAULT_PROVIDER
    # Selected model: the stored pick, or an env pin; "" when none chosen yet.
    selected_model = me.get("selected_model") or os.environ.get("SELECTED_MODEL") or ""

    providers: list[ProviderStatus] = []
    for p in known_providers():
        providers.append(ProviderStatus(
            id=p.id,
            display_name=p.display_name,
            env_var=p.env_var,
            api_key_set=bool(stored_keys.get(p.id)),
            env_fallback=ai_client.provider_env_present(p.id),
        ))

    selected_key_available = bool(stored_keys.get(selected_provider)) or \
        ai_client.provider_env_present(selected_provider)

    return MeOut(
        features=me["features"],
        theme=me["theme"],
        providers=providers,
        selected_provider=selected_provider,
        selected_provider_key_available=selected_key_available,
        selected_model=selected_model,
        available_models=[
            ModelOption(**m) for m in ai_usage.available_models(selected_provider)
        ],
        ai_spent_usd=ai_usage.total_spent_local_usd(),
        last_dashboard_id=me.get("last_dashboard_id"),
    )
