"""Feature flag routes — `/me/features` for the frontend to read on startup."""

from __future__ import annotations

from fastapi import APIRouter

from .. import features

router = APIRouter(prefix="/me", tags=["features"])


@router.get("/features")
def get_features() -> dict[str, bool]:
    return features.get_flags()
