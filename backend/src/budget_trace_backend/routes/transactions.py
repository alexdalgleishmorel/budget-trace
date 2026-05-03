"""REST routes for transactions. Thin wrappers around services/transactions.py."""

from __future__ import annotations

from fastapi import APIRouter, HTTPException, Query
from pydantic import BaseModel, Field

from ..services import transactions as svc
from ..services.categories import ServiceError

router = APIRouter(prefix="/transactions", tags=["transactions"])


# ── Wire-format models ───────────────────────────────────────────────────────


class TransactionOut(BaseModel):
    id: int
    date: str
    merchant: str
    amount: float
    category_id: int | None = None
    category_path: str | None = None


class TransactionCreate(BaseModel):
    date: str
    merchant: str
    amount: float
    category_id: int | None = None


class TransactionUpdate(BaseModel):
    date: str | None = None
    merchant: str | None = None
    amount: float | None = None
    category_id: int | None = None


class BulkRenamePayload(BaseModel):
    from_merchant: str
    to_merchant: str


class BulkRenameResult(BaseModel):
    updated: int


class TransactionDeleted(BaseModel):
    deleted_id: int


# ── Helpers ──────────────────────────────────────────────────────────────────


def _err(e: ServiceError) -> HTTPException:
    return HTTPException(
        status_code=e.http_status,
        detail={"code": e.code, "message": str(e)},
    )


# ── Handlers ──────────────────────────────────────────────────────────────────


@router.get("", response_model=list[TransactionOut])
def list_all(
    start_date: str | None = Query(default=None),
    end_date: str | None = Query(default=None),
    category_id: int | None = Query(default=None),
    category_path: str | None = Query(default=None),
    uncategorised: bool = Query(default=False),
    merchant_query: str | None = Query(default=None),
    limit: int = Query(default=100, ge=1, le=500),
) -> list[TransactionOut]:
    try:
        rows = svc.list_transactions(
            start_date=start_date,
            end_date=end_date,
            category_id=category_id,
            category_path=category_path,
            uncategorised=uncategorised,
            merchant_query=merchant_query,
            limit=limit,
        )
    except ServiceError as e:
        raise _err(e)
    return [TransactionOut(**r) for r in rows]


@router.post("", response_model=TransactionOut, status_code=201)
def create(payload: TransactionCreate) -> TransactionOut:
    try:
        return TransactionOut(**svc.create_transaction(
            date=payload.date,
            merchant=payload.merchant,
            amount=payload.amount,
            category_id=payload.category_id,
        ))
    except ServiceError as e:
        raise _err(e)


@router.patch("/{transaction_id}", response_model=TransactionOut)
def update(transaction_id: int, payload: TransactionUpdate) -> TransactionOut:
    explicit = payload.model_fields_set
    try:
        return TransactionOut(**svc.update_transaction(
            transaction_id,
            date=payload.date,
            merchant=payload.merchant,
            amount=payload.amount,
            category_id=payload.category_id,
            category_explicit="category_id" in explicit,
        ))
    except ServiceError as e:
        raise _err(e)


@router.delete("/{transaction_id}", response_model=TransactionDeleted)
def delete(transaction_id: int) -> TransactionDeleted:
    try:
        return TransactionDeleted(**svc.delete_transaction(transaction_id))
    except ServiceError as e:
        raise _err(e)


@router.post("/bulk_rename", response_model=BulkRenameResult)
def bulk_rename(payload: BulkRenamePayload) -> BulkRenameResult:
    try:
        return BulkRenameResult(**svc.bulk_rename_merchant(
            payload.from_merchant, payload.to_merchant,
        ))
    except ServiceError as e:
        raise _err(e)
