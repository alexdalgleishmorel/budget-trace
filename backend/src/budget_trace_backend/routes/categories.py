"""REST routes for categories. Thin wrappers around services/categories.py."""

from __future__ import annotations

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel, Field

from ..db import connect
from ..services import categories as svc

router = APIRouter(prefix="/categories", tags=["categories"])


# ── Wire-format models ───────────────────────────────────────────────────────


class CategoryOut(BaseModel):
    id: int
    name: str
    description: str | None = None
    parent_id: int | None
    path: str
    is_leaf: bool
    is_unknown: bool


class CategoryCreate(BaseModel):
    name: str
    description: str | None = None
    parent_id: int | None = None


class CategoryUpdate(BaseModel):
    """All fields optional. None for `description` actually clears the field —
    the route distinguishes "field omitted" from "field explicitly null" via
    pydantic's `model_fields_set`.
    """
    name: str | None = None
    description: str | None = None
    parent_id: int | None = None


class CategoryDeleted(BaseModel):
    deleted_id: int
    descendants_deleted: int
    transactions_unassigned: int


# ── Handlers ──────────────────────────────────────────────────────────────────


def _err(e: svc.ServiceError) -> HTTPException:
    return HTTPException(
        status_code=e.http_status,
        detail={"code": e.code, "message": str(e)},
    )


@router.get("", response_model=list[CategoryOut])
def list_all() -> list[CategoryOut]:
    with connect() as conn:
        return [CategoryOut(**c) for c in svc.list_categories_with_ids(conn)]


@router.post("", response_model=CategoryOut, status_code=201)
def create(payload: CategoryCreate) -> CategoryOut:
    try:
        return CategoryOut(**svc.create_category(
            payload.name, payload.description, payload.parent_id,
        ))
    except svc.ServiceError as e:
        raise _err(e)


@router.get("/{category_id}", response_model=CategoryOut)
def get_one(category_id: int) -> CategoryOut:
    with connect() as conn:
        row = svc.get_category(conn, category_id)
    if row is None:
        raise HTTPException(status_code=404, detail={"code": "not_found", "message": "category not found"})
    return CategoryOut(**row)


@router.patch("/{category_id}", response_model=CategoryOut)
def update(category_id: int, payload: CategoryUpdate) -> CategoryOut:
    explicit = payload.model_fields_set
    try:
        return CategoryOut(**svc.update_category(
            category_id,
            name=payload.name,
            description=payload.description,
            parent_id=payload.parent_id,
            description_explicit="description" in explicit,
            parent_explicit="parent_id" in explicit,
        ))
    except svc.ServiceError as e:
        raise _err(e)


@router.delete("/{category_id}", response_model=CategoryDeleted)
def delete(category_id: int) -> CategoryDeleted:
    try:
        return CategoryDeleted(**svc.delete_category(category_id))
    except svc.ServiceError as e:
        raise _err(e)
