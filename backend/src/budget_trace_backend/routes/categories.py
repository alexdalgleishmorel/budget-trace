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
    color: str


class CategoryCreate(BaseModel):
    name: str
    description: str | None = None
    parent_id: int | None = None
    color: str | None = None


class CategoryUpdate(BaseModel):
    """All fields optional. None for `description` actually clears the field —
    the route distinguishes "field omitted" from "field explicitly null" via
    pydantic's `model_fields_set`. `color` is non-nullable, so omitting it
    means "no change"; sending a value updates the tile color.
    """
    name: str | None = None
    description: str | None = None
    parent_id: int | None = None
    color: str | None = None


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
            payload.name, payload.description, payload.parent_id, payload.color,
        ))
    except svc.ServiceError as e:
        raise _err(e)


@router.post("/seed_defaults", response_model=list[CategoryOut])
def seed_defaults() -> list[CategoryOut]:
    """One-tap shortcut for the empty-state panel: create the
    `DEFAULT_CATEGORY_TREE` under the existing Budget root. Refuses (409) if
    the tree already has any non-root categories — the seed is a strictly
    "from scratch" affordance, not a merge."""
    with connect() as conn:
        existing = conn.execute(
            "SELECT 1 FROM categories WHERE parent_id IS NOT NULL LIMIT 1"
        ).fetchone()
        if existing:
            raise HTTPException(
                status_code=409,
                detail={"code": "categories_exist",
                        "message": "Default categories can only be added when the tree is empty."},
            )
        rows = svc.seed_default_tree(conn)
    return [CategoryOut(**r) for r in rows]


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
            color=payload.color,
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
