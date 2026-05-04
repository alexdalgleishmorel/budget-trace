"""User-settings routes.

`GET /me`   → features + theme + a boolean "is an Anthropic key set?"
              (the key value itself is never returned).
`PATCH /me` → partial update. Each field is independently optional. Pass
              `anthropic_api_key: null` to clear the key; an empty string
              is a 422 (use null instead).

Single-user dev today (id=1). When auth lands, the user_id will come from
the request session; the route shape stays the same.
"""

from __future__ import annotations

from typing import Literal

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel, ConfigDict, Field

from .. import features

router = APIRouter(prefix="/me", tags=["me"])


Theme = Literal["system", "light", "dark"]


class FeaturesPatch(BaseModel):
    model_config = ConfigDict(extra="forbid")
    ai: bool | None = None


class MeOut(BaseModel):
    features: dict[str, bool]
    theme: Theme
    anthropic_api_key_set: bool


# Sentinel string for "field not provided." Pydantic distinguishes
# `field=None` (clear) from `field omitted` only via this kind of dance,
# because JSON has no `undefined`. The frontend sends an explicit `null`
# to clear the key.
_UNSET_KEY = "__BT_UNSET__"


class MePatch(BaseModel):
    model_config = ConfigDict(extra="forbid")
    features: FeaturesPatch | None = None
    theme: Theme | None = None
    anthropic_api_key: str | None = Field(default=_UNSET_KEY)


@router.get("", response_model=MeOut)
def get_me() -> MeOut:
    me = features.get_me()
    return MeOut(
        features=me["features"],
        theme=me["theme"],
        anthropic_api_key_set=bool(me["anthropic_api_key"]),
    )


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
        kwargs["anthropic_api_key"] = body.anthropic_api_key  # may be None (clear) or str (set)

    try:
        me = features.update_me(**kwargs)
    except ValueError as e:
        raise HTTPException(
            status_code=422,
            detail={"code": "validation_error", "message": str(e)},
        )

    return MeOut(
        features=me["features"],
        theme=me["theme"],
        anthropic_api_key_set=bool(me["anthropic_api_key"]),
    )
