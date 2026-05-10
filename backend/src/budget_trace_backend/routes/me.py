"""User-settings routes.

`GET /me`   → features + theme + a boolean "is an Anthropic key set?" + AI
              spend total + selected model + admin-key flag + the list of
              models the Settings UI can offer.
              The key values themselves are never returned.
`PATCH /me` → partial update. Each field is independently optional. Pass
              `anthropic_api_key: null` (or the admin equivalent) to clear
              that key; pass `anthropic_model: null` to fall back to env /
              default. Empty strings are 422 — use null instead.

Single-user dev today (id=1). When auth lands, the user_id will come from
the request session; the route shape stays the same.
"""

from __future__ import annotations

from typing import Literal

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel, ConfigDict, Field

from .. import features
from ..services import ai_usage
from ..services.anthropic_admin import fetch_admin_cost_usd

router = APIRouter(prefix="/me", tags=["me"])


Theme = Literal["system", "light", "dark"]


class FeaturesPatch(BaseModel):
    model_config = ConfigDict(extra="forbid")
    ai: bool | None = None


class ModelOption(BaseModel):
    id: str
    display_name: str
    input_per_mtok: float
    output_per_mtok: float


class MeOut(BaseModel):
    features: dict[str, bool]
    theme: Theme
    anthropic_api_key_set: bool
    anthropic_admin_api_key_set: bool
    anthropic_model: str
    available_models: list[ModelOption]
    ai_spent_usd: float
    ai_spent_source: Literal["estimated", "authoritative"]


# Sentinel string for "field not provided." Pydantic distinguishes
# `field=None` (clear) from `field omitted` only via this kind of dance,
# because JSON has no `undefined`. The frontend sends an explicit `null`
# to clear keys / reset the model.
_UNSET_KEY = "__BT_UNSET__"


class MePatch(BaseModel):
    model_config = ConfigDict(extra="forbid")
    features: FeaturesPatch | None = None
    theme: Theme | None = None
    anthropic_api_key: str | None = Field(default=_UNSET_KEY)
    anthropic_admin_api_key: str | None = Field(default=_UNSET_KEY)
    anthropic_model: str | None = Field(default=_UNSET_KEY)


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

    if body.anthropic_api_key != _UNSET_KEY:
        if body.anthropic_api_key == "":
            raise HTTPException(
                status_code=422,
                detail={"code": "validation_error",
                        "message": "anthropic_api_key may not be empty; pass null to clear."},
            )
        kwargs["anthropic_api_key"] = body.anthropic_api_key

    if body.anthropic_admin_api_key != _UNSET_KEY:
        if body.anthropic_admin_api_key == "":
            raise HTTPException(
                status_code=422,
                detail={"code": "validation_error",
                        "message": "anthropic_admin_api_key may not be empty; pass null to clear."},
            )
        kwargs["anthropic_admin_api_key"] = body.anthropic_admin_api_key

    if body.anthropic_model != _UNSET_KEY:
        if body.anthropic_model == "":
            raise HTTPException(
                status_code=422,
                detail={"code": "validation_error",
                        "message": "anthropic_model may not be empty; pass null to reset."},
            )
        kwargs["anthropic_model"] = body.anthropic_model

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

    # Resolved model — same fallback chain that get_model() uses, surfaced so
    # the Settings UI can highlight the current effective value even when
    # the user hasn't picked one explicitly.
    import os
    resolved_model = (
        me.get("anthropic_model")
        or os.environ.get("ANTHROPIC_MODEL")
        or ai_usage.DEFAULT_MODEL
    )

    # Spend: try the Admin API when an admin key is set, fall back to the
    # local token-cost estimate. The frontend uses `ai_spent_source` to label
    # the chip with "(est.)" vs no suffix.
    local_spent = ai_usage.total_spent_local_usd()
    admin_spent: float | None = None
    if me.get("anthropic_admin_api_key"):
        admin_spent = fetch_admin_cost_usd(
            me["anthropic_admin_api_key"], ai_usage.earliest_recorded_at(),
        )

    if admin_spent is not None:
        spent = admin_spent
        source: Literal["estimated", "authoritative"] = "authoritative"
    else:
        spent = local_spent
        source = "estimated"

    return MeOut(
        features=me["features"],
        theme=me["theme"],
        anthropic_api_key_set=bool(me["anthropic_api_key"]),
        anthropic_admin_api_key_set=bool(me.get("anthropic_admin_api_key")),
        anthropic_model=resolved_model,
        available_models=[ModelOption(**m) for m in ai_usage.available_models()],
        ai_spent_usd=spent,
        ai_spent_source=source,
    )
