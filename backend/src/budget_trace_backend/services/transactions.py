"""Transaction mutation services. Used by REST routes and MCP write tools.

The dedupe rules (source_hash UNIQUE) only kick in once Phase 3 lands. Until
then, single-row creates (`create_transaction`) and edits (`update_transaction`)
just write whatever the caller passed. Bulk operations don't touch the hash.
"""

from __future__ import annotations

import sqlite3
from typing import Any

from ..db import (
    CATEGORY_PATHS_CTE,
    category_id_for_path,
    connect,
    descendant_category_ids,
)
from .categories import Conflict, NotFound, ServiceError

# Re-exported for callers that want to handle these uniformly.
__all__ = [
    "create_transaction",
    "delete_transaction",
    "get_transaction",
    "list_transactions",
    "set_category_by_id",
    "bulk_categorise_merchant",
    "bulk_rename_merchant",
    "update_transaction",
    "Conflict",
    "NotFound",
    "ServiceError",
]


# ── Reads ────────────────────────────────────────────────────────────────────


def _row_to_dict(row) -> dict:
    return {
        "id": row["id"],
        "date": row["date"],
        "merchant": row["merchant"],
        "amount": row["amount"],
        "category_id": row["category_id"],
        "category_path": row["category_path"],
    }


def get_transaction(conn: sqlite3.Connection, transaction_id: int) -> dict | None:
    row = conn.execute(
        f"""
        {CATEGORY_PATHS_CTE}
        SELECT t.id, t.date, t.merchant, t.amount, t.category_id,
               cp.path AS category_path
          FROM transactions t
          LEFT JOIN category_paths cp ON cp.id = t.category_id
         WHERE t.id = ?
        """,
        (transaction_id,),
    ).fetchone()
    return _row_to_dict(row) if row else None


def list_transactions(
    *,
    start_date: str | None = None,
    end_date: str | None = None,
    category_id: int | None = None,
    category_path: str | None = None,
    uncategorised: bool = False,
    merchant_query: str | None = None,
    limit: int = 100,
) -> list[dict]:
    if limit <= 0 or limit > 500:
        raise ServiceError("limit must be in (0, 500]", code="validation_error")

    where: list[str] = ["1=1"]
    params: list[Any] = []
    if start_date:
        where.append("t.date >= ?")
        params.append(start_date)
    if end_date:
        where.append("t.date <= ?")
        params.append(end_date)

    if uncategorised:
        where.append("t.category_id IS NULL")
    elif category_id is not None:
        with connect() as conn:
            ids = _subtree_ids_for_category_id(conn, category_id)
        if ids:
            where.append(f"t.category_id IN ({','.join('?' for _ in ids)})")
            params.extend(ids)
        else:
            return []
    elif category_path:
        if category_path == "Unknown":
            where.append("t.category_id IS NULL")
        else:
            with connect() as conn:
                ids = descendant_category_ids(conn, category_path)
            if ids:
                where.append(f"t.category_id IN ({','.join('?' for _ in ids)})")
                params.extend(ids)
            else:
                return []

    if merchant_query:
        where.append("LOWER(t.merchant) LIKE ?")
        params.append(f"%{merchant_query.lower()}%")

    sql = f"""
    {CATEGORY_PATHS_CTE}
    SELECT t.id, t.date, t.merchant, t.amount, t.category_id,
           cp.path AS category_path
      FROM transactions t
      LEFT JOIN category_paths cp ON cp.id = t.category_id
     WHERE {' AND '.join(where)}
     ORDER BY t.date, t.id
     LIMIT ?
    """
    with connect() as conn:
        rows = conn.execute(sql, (*params, limit)).fetchall()
    return [_row_to_dict(r) for r in rows]


def _subtree_ids_for_category_id(conn: sqlite3.Connection, root_id: int) -> list[int]:
    rows = conn.execute(
        """
        WITH RECURSIVE subtree(id) AS (
            SELECT id FROM categories WHERE id = ?
            UNION ALL
            SELECT c.id FROM categories c JOIN subtree s ON c.parent_id = s.id
        )
        SELECT id FROM subtree
        """,
        (root_id,),
    ).fetchall()
    return [r["id"] for r in rows]


# ── Mutations ────────────────────────────────────────────────────────────────


def create_transaction(
    *, date: str, merchant: str, amount: float, category_id: int | None = None
) -> dict:
    """Insert a single transaction. Validation is light; the importer is the
    canonical entry for normalisation."""
    if not date:
        raise ServiceError("date is required", code="validation_error")
    if not merchant or not merchant.strip():
        raise ServiceError("merchant is required", code="validation_error")
    if amount is None:
        raise ServiceError("amount is required", code="validation_error")

    with connect() as conn:
        if category_id is not None:
            if conn.execute(
                "SELECT 1 FROM categories WHERE id = ?", (category_id,)
            ).fetchone() is None:
                raise NotFound(f"category_id {category_id} does not exist")

        cur = conn.execute(
            "INSERT INTO transactions (date, merchant, amount, category_id) "
            "VALUES (?, ?, ?, ?)",
            (date, merchant.strip(), amount, category_id),
        )
        return get_transaction(conn, cur.lastrowid)  # type: ignore[return-value]


def update_transaction(
    transaction_id: int,
    *,
    date: str | None = None,
    merchant: str | None = None,
    amount: float | None = None,
    category_id: int | None = None,
    category_explicit: bool = False,
) -> dict:
    """Partial update. `category_explicit=True` lets the caller set
    category_id to NULL (unassign); otherwise None means "no change".

    If a non-null `category_id` is being set, the assignment cascades to
    every other transaction with the same merchant (see
    `_cascade_category_to_same_merchant`). Same-merchant rows share a
    category by invariant.
    """
    with connect() as conn:
        existing = get_transaction(conn, transaction_id)
        if existing is None:
            raise NotFound(f"transaction {transaction_id} not found")

        updates: list[str] = []
        params: list[Any] = []

        if date is not None:
            updates.append("date = ?")
            params.append(date)
        if merchant is not None:
            updates.append("merchant = ?")
            params.append(merchant.strip())
        if amount is not None:
            updates.append("amount = ?")
            params.append(amount)
        if category_explicit:
            if category_id is not None and conn.execute(
                "SELECT 1 FROM categories WHERE id = ?", (category_id,)
            ).fetchone() is None:
                raise NotFound(f"category_id {category_id} does not exist")
            updates.append("category_id = ?")
            params.append(category_id)

        if not updates:
            return existing

        params.append(transaction_id)
        conn.execute(
            f"UPDATE transactions SET {', '.join(updates)} WHERE id = ?",
            params,
        )

        if category_explicit and category_id is not None:
            _cascade_category_to_same_merchant(conn, transaction_id, category_id)

        return get_transaction(conn, transaction_id)  # type: ignore[return-value]


def _cascade_category_to_same_merchant(
    conn: sqlite3.Connection, transaction_id: int, category_id: int
) -> int:
    """After assigning `category_id` to `transaction_id`, mirror that
    category to every OTHER transaction with the same merchant. Maintains
    the invariant that same-merchant rows share a category. Returns the
    count of other rows actually changed (rows already on the same category
    are not counted)."""
    cur = conn.execute(
        """
        UPDATE transactions
           SET category_id = ?
         WHERE id != ?
           AND merchant = (SELECT merchant FROM transactions WHERE id = ?)
           AND (category_id IS NULL OR category_id != ?)
        """,
        (category_id, transaction_id, transaction_id, category_id),
    )
    return cur.rowcount


def delete_transaction(transaction_id: int) -> dict:
    with connect() as conn:
        existing = get_transaction(conn, transaction_id)
        if existing is None:
            raise NotFound(f"transaction {transaction_id} not found")
        conn.execute("DELETE FROM transactions WHERE id = ?", (transaction_id,))
    return {"deleted_id": transaction_id}


def set_category_by_id(transaction_id: int, category_id: int | None) -> dict:
    """Convenience wrapper used by the chip dropdown — assign or unassign in
    one call."""
    return update_transaction(
        transaction_id,
        category_id=category_id,
        category_explicit=True,
    )


def bulk_rename_merchant(from_merchant: str, to_merchant: str) -> dict:
    """Rename every transaction whose merchant matches `from_merchant` exactly.
    Returns the number affected.
    """
    if not to_merchant or not to_merchant.strip():
        raise ServiceError("to_merchant cannot be empty", code="validation_error")
    with connect() as conn:
        cur = conn.execute(
            "UPDATE transactions SET merchant = ? WHERE merchant = ?",
            (to_merchant.strip(), from_merchant),
        )
        return {"updated": cur.rowcount}


def bulk_categorise_merchant(merchant: str, category_id: int | None) -> dict:
    """Set the category for every transaction with the given merchant string."""
    with connect() as conn:
        if category_id is not None and conn.execute(
            "SELECT 1 FROM categories WHERE id = ?", (category_id,)
        ).fetchone() is None:
            raise NotFound(f"category_id {category_id} does not exist")
        cur = conn.execute(
            "UPDATE transactions SET category_id = ? WHERE merchant = ?",
            (category_id, merchant),
        )
        return {"updated": cur.rowcount}


# ── Path-based wrappers for MCP tools ────────────────────────────────────────


def _resolve_path(path: str | None) -> int | None:
    if path is None:
        return None
    with connect() as conn:
        cid = category_id_for_path(conn, path)
    if cid is None:
        raise NotFound(f"category path {path!r} does not resolve")
    return cid


def set_transaction_category_by_path(
    transaction_id: int, category_path: str | None
) -> dict:
    """MCP-friendly wrapper: takes a path string instead of a category id.
    Pass `category_path=None` to unassign."""
    cat_id = _resolve_path(category_path) if category_path else None
    return set_category_by_id(transaction_id, cat_id)


def bulk_categorise_merchant_by_path(merchant: str, category_path: str | None) -> dict:
    cat_id = _resolve_path(category_path) if category_path else None
    return bulk_categorise_merchant(merchant, cat_id)


def update_transaction_by_path(
    transaction_id: int,
    *,
    date: str | None = None,
    merchant: str | None = None,
    amount: float | None = None,
    category_path: str | None = None,
    category_explicit: bool = False,
) -> dict:
    cat_id = _resolve_path(category_path) if category_explicit and category_path else None
    return update_transaction(
        transaction_id,
        date=date,
        merchant=merchant,
        amount=amount,
        category_id=cat_id,
        category_explicit=category_explicit,
    )
