"""Category mutation services. Used by REST routes (routes/categories.py) AND
MCP write tools (mcp_server.py). Single source of truth for the SQL.

All functions return the affected row (or rows for delete) as a dict, so the
caller — whether it's an HTTP handler or the chat AI — can confirm the new
state without re-querying.
"""

from __future__ import annotations

import sqlite3
from typing import Any

from ..db import (
    CATEGORY_PATHS_CTE,
    category_id_for_path,
    connect,
)


# ── Errors ────────────────────────────────────────────────────────────────────


class ServiceError(Exception):
    """Base class — service layer surfaces these for routes/tools to translate
    into HTTP status codes or tool error responses."""

    code: str = "service_error"
    http_status: int = 400

    def __init__(self, message: str, code: str | None = None):
        super().__init__(message)
        if code:
            self.code = code


class NotFound(ServiceError):
    code = "not_found"
    http_status = 404


class Conflict(ServiceError):
    code = "conflict"
    http_status = 409


# ── Read helpers (used by routes; reads from MCP layer mostly delegate here) ──


def get_category(conn: sqlite3.Connection, category_id: int) -> dict | None:
    row = conn.execute(
        f"""
        {CATEGORY_PATHS_CTE}
        SELECT cp.id, cp.name, cp.description, cp.parent_id, cp.is_unknown,
               cp.path,
               (SELECT COUNT(*) FROM categories c WHERE c.parent_id = cp.id) AS child_count
          FROM category_paths cp
         WHERE cp.id = ?
        """,
        (category_id,),
    ).fetchone()
    if row is None:
        return None
    return _row_to_dict(row)


def get_root_id(conn: sqlite3.Connection) -> int:
    row = conn.execute(
        "SELECT id FROM categories WHERE parent_id IS NULL"
    ).fetchone()
    if row is None:
        raise ServiceError("database has no root category — reseed required",
                           code="missing_root")
    return row["id"]


def list_categories_with_ids(conn: sqlite3.Connection) -> list[dict]:
    rows = conn.execute(
        f"""
        {CATEGORY_PATHS_CTE}
        SELECT cp.id, cp.name, cp.description, cp.parent_id, cp.is_unknown,
               cp.path,
               (SELECT COUNT(*) FROM categories c WHERE c.parent_id = cp.id) AS child_count
          FROM category_paths cp
         ORDER BY cp.path
        """,
    ).fetchall()
    return [_row_to_dict(r) for r in rows]


# ── Mutations ────────────────────────────────────────────────────────────────


def create_category(
    name: str,
    description: str | None,
    parent_id: int | None = None,
) -> dict:
    """Create a new category. `parent_id=None` makes it a top-level group
    (a child of the root "Budget" node)."""
    name = (name or "").strip()
    if not name:
        raise ServiceError("name is required", code="validation_error")

    with connect() as conn:
        if parent_id is None:
            parent_id = get_root_id(conn)
        else:
            parent = conn.execute(
                "SELECT id FROM categories WHERE id = ?",
                (parent_id,),
            ).fetchone()
            if parent is None:
                raise NotFound(f"parent_id {parent_id} does not exist")

        cur = conn.execute(
            "INSERT INTO categories (name, description, parent_id, is_unknown) "
            "VALUES (?, ?, ?, 0)",
            (name, description, parent_id),
        )
        new_id = cur.lastrowid
        return get_category(conn, new_id)  # type: ignore[return-value]


def update_category(
    category_id: int,
    *,
    name: str | None = None,
    description: str | None = None,
    parent_id: int | None = None,
    description_explicit: bool = False,
    parent_explicit: bool = False,
) -> dict:
    """Partial update. Pass `description_explicit=True` to allow setting
    description to NULL; otherwise None means "no change". Same for
    parent_explicit. (Pydantic with .model_dump(exclude_unset=True) gives the
    routes a clean way to compute these flags.)
    """
    with connect() as conn:
        # Reject root *before* the CTE lookup (the CTE excludes root).
        if category_id == get_root_id(conn):
            raise Conflict("cannot edit the root category")

        existing = get_category(conn, category_id)
        if existing is None:
            raise NotFound(f"category {category_id} not found")

        if existing["is_unknown"]:
            # Symbolic Unknown row — don't let it be edited.
            raise Conflict("cannot edit the Unknown category")

        updates: list[str] = []
        params: list[Any] = []

        if name is not None:
            n = name.strip()
            if not n:
                raise ServiceError("name cannot be empty", code="validation_error")
            updates.append("name = ?")
            params.append(n)

        if description_explicit:
            updates.append("description = ?")
            params.append(description)

        if parent_explicit:
            new_parent = parent_id
            if new_parent is None:
                new_parent = get_root_id(conn)
            else:
                # Cannot move into self or any descendant
                if new_parent == category_id:
                    raise Conflict("cannot move a category into itself")
                if _is_descendant(conn, candidate_id=new_parent, ancestor_id=category_id):
                    raise Conflict("cannot move a category into one of its own descendants")
                if conn.execute(
                    "SELECT 1 FROM categories WHERE id = ?", (new_parent,)
                ).fetchone() is None:
                    raise NotFound(f"parent_id {new_parent} does not exist")
            updates.append("parent_id = ?")
            params.append(new_parent)

        if not updates:
            return existing

        params.append(category_id)
        conn.execute(
            f"UPDATE categories SET {', '.join(updates)} WHERE id = ?",
            params,
        )
        return get_category(conn, category_id)  # type: ignore[return-value]


def delete_category(category_id: int) -> dict:
    """Delete a category. Every transaction with this category (or any
    descendant) gets `category_id = NULL` — moves to "needs review" semantics
    that match the UI's existing behaviour. Returns `{deleted_id, descendants_deleted, transactions_unassigned}`.
    """
    with connect() as conn:
        if category_id == get_root_id(conn):
            raise Conflict("cannot delete the root category")

        existing = get_category(conn, category_id)
        if existing is None:
            raise NotFound(f"category {category_id} not found")
        if existing["is_unknown"]:
            raise Conflict("cannot delete the Unknown category")

        # Collect every id in the subtree so we can null transactions and
        # delete the rows in one shot.
        ids = _subtree_ids(conn, category_id)
        placeholders = ",".join("?" for _ in ids)

        cur = conn.execute(
            f"UPDATE transactions SET category_id = NULL WHERE category_id IN ({placeholders})",
            ids,
        )
        nullified = cur.rowcount

        conn.execute(
            f"DELETE FROM categories WHERE id IN ({placeholders})",
            ids,
        )

        return {
            "deleted_id": category_id,
            "descendants_deleted": len(ids) - 1,
            "transactions_unassigned": nullified,
        }


# ── Internal helpers ─────────────────────────────────────────────────────────


def _is_descendant(
    conn: sqlite3.Connection, *, candidate_id: int, ancestor_id: int
) -> bool:
    """True if `candidate_id` is in the subtree rooted at `ancestor_id`."""
    rows = conn.execute(
        """
        WITH RECURSIVE subtree(id) AS (
            SELECT id FROM categories WHERE id = ?
            UNION ALL
            SELECT c.id FROM categories c JOIN subtree s ON c.parent_id = s.id
        )
        SELECT 1 FROM subtree WHERE id = ?
        """,
        (ancestor_id, candidate_id),
    ).fetchall()
    return bool(rows)


def _subtree_ids(conn: sqlite3.Connection, root_id: int) -> list[int]:
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


def _row_to_dict(row) -> dict:
    return {
        "id": row["id"],
        "name": row["name"],
        "description": row["description"],
        "parent_id": row["parent_id"],
        "path": row["path"],
        "is_leaf": row["child_count"] == 0,
        "is_unknown": bool(row["is_unknown"]),
    }


# ── Path-based wrappers (used by MCP write tools) ─────────────────────────────


def create_category_by_path(name: str, description: str | None,
                             parent_path: str | None = None) -> dict:
    """MCP-friendly wrapper: takes a parent path string instead of an id."""
    parent_id: int | None = None
    if parent_path:
        with connect() as conn:
            resolved = category_id_for_path(conn, parent_path)
        if resolved is None:
            raise NotFound(f"parent_path {parent_path!r} does not resolve")
        parent_id = resolved
    return create_category(name, description, parent_id)


def update_category_by_path(path: str, *, new_name: str | None = None,
                             new_description: str | None = None,
                             new_parent_path: str | None = None,
                             description_explicit: bool = False,
                             parent_explicit: bool = False) -> dict:
    with connect() as conn:
        cid = category_id_for_path(conn, path)
    if cid is None:
        raise NotFound(f"category path {path!r} does not resolve")
    parent_id: int | None = None
    if parent_explicit and new_parent_path:
        with connect() as conn:
            parent_id = category_id_for_path(conn, new_parent_path)
        if parent_id is None:
            raise NotFound(f"new_parent_path {new_parent_path!r} does not resolve")
    return update_category(
        cid,
        name=new_name,
        description=new_description,
        parent_id=parent_id,
        description_explicit=description_explicit,
        parent_explicit=parent_explicit,
    )


def delete_category_by_path(path: str) -> dict:
    with connect() as conn:
        cid = category_id_for_path(conn, path)
    if cid is None:
        raise NotFound(f"category path {path!r} does not resolve")
    return delete_category(cid)


# ── Default tree (shipped via POST /categories/seed_defaults) ────────────────


# Expenses-only default tree offered to first-time users from the empty
# Categories panel. Independent of seed.py::CATEGORY_TREE (which keeps a
# Savings group for backward-compat in tests). Budget Trace tracks spend
# only — savings transfers, payments to credit cards, and refunds are
# already skipped at parse time, so a Savings group here would be misleading.
DEFAULT_CATEGORY_TREE: list[dict] = [
    {
        "name": "House",
        "description": "Costs of keeping a roof over your head — housing payments and home services.",
        "children": [
            {
                "name": "Rent",
                "description": "Recurring monthly payment for the home itself.",
                "children": [
                    {"name": "Mortgage",   "description": "Bank or lender mortgage payment for the primary residence."},
                    {"name": "Strata Fee", "description": "Condo, HOA, or strata fees for shared building maintenance."},
                ],
            },
            {"name": "Utilities", "description": "Electricity, gas, water, and other recurring home utilities."},
            {"name": "Internet",  "description": "Home internet service and mobile phone bills."},
        ],
    },
    {
        "name": "Living",
        "description": "Day-to-day spending — transport, food, and everyday personal expenses.",
        "children": [
            {"name": "Car Insurance", "description": "Auto insurance premiums."},
            {"name": "Gas",           "description": "Fuel for personal vehicles (gas stations, EV charging)."},
            {"name": "Grocery",       "description": "Supermarket and grocery-store food shopping for the household."},
            {"name": "Dining Out",    "description": "Restaurants, takeout, delivery, coffee shops, cafes."},
            {"name": "Subscriptions", "description": "Recurring software / streaming / membership charges (Netflix, Spotify, gym, etc.)."},
            {"name": "Fun",           "description": "Entertainment outside of food and subscriptions — concerts, shows, hobbies, going out."},
            {"name": "Shopping",      "description": "Discretionary retail purchases — clothes, electronics, household goods."},
            {"name": "Travel",        "description": "Trip expenses — flights, hotels, transit, vacation spending."},
        ],
    },
]


def seed_default_tree(conn: sqlite3.Connection) -> list[dict]:
    """Walk DEFAULT_CATEGORY_TREE and create every node under the existing
    Budget root. Caller is expected to have verified the tree is empty
    (see routes/categories.py::seed_defaults). Returns the freshly-created
    categories as a flat list, in the same shape as `list_categories_with_ids`."""
    root_id = get_root_id(conn)
    created_ids: list[int] = []

    def walk(nodes: list[dict], parent_id: int) -> None:
        for n in nodes:
            cur = conn.execute(
                "INSERT INTO categories (name, description, parent_id, is_unknown) "
                "VALUES (?, ?, ?, 0)",
                (n["name"], n.get("description"), parent_id),
            )
            new_id = cur.lastrowid
            created_ids.append(new_id)
            children = n.get("children") or []
            if children:
                walk(children, new_id)

    walk(DEFAULT_CATEGORY_TREE, root_id)

    return [get_category(conn, cid) for cid in created_ids]  # type: ignore[misc]
