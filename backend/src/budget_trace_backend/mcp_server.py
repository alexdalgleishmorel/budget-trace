"""MCP server exposing read-only data tools over the SQLite store.

Two exit points:

1. **Standalone stdio MCP server** — `python -m budget_trace_backend.mcp_server`
   or the `budget-trace-mcp` console script. Lets Claude Desktop or any MCP
   client connect to the same tool surface.

2. **In-process functions** — the chat orchestrator imports `TOOL_FUNCTIONS`
   directly to dispatch tool calls without going over a transport. The same
   functions back both code paths, so the AI sees identical behaviour either
   way.

If the SDK shape changes, `_register_tools` is the single place to update.
"""

from __future__ import annotations

import sqlite3
from datetime import date, datetime, timedelta
from typing import Any, Callable, Literal

from .db import (
    PATH_SEPARATOR,
    CATEGORY_PATHS_CTE,
    category_id_for_path,
    connect,
    descendant_category_ids,
    fetch_category_tree,
)
from .services import categories as cat_svc
from .services import transactions as txn_svc

# ── Tool implementations ─────────────────────────────────────────────────────


def list_categories() -> list[dict]:
    """Return the full category tree with paths and descriptions.

    Use this first whenever the user references a category by an informal name
    — match against the descriptions, then call other tools with the canonical
    `path` string (e.g. ``"Living / Grocery"``).
    """
    with connect() as conn:
        return fetch_category_tree(conn)


def list_transactions(
    start_date: str | None = None,
    end_date: str | None = None,
    category_path: str | None = None,
    merchant_query: str | None = None,
    limit: int = 100,
) -> list[dict]:
    """Filtered transaction list. Inclusive date range. Empty `category_path`
    treats *uncategorised* transactions as a separate filterable bucket if you
    pass the literal string ``"Unknown"``.
    """
    with connect() as conn:
        sql, params = _build_txn_query(
            conn,
            start_date=start_date,
            end_date=end_date,
            category_path=category_path,
            merchant_query=merchant_query,
            limit=limit,
        )
        rows = conn.execute(sql, params).fetchall()
        return [
            {
                "id": r["id"],
                "date": r["date"],
                "merchant": r["merchant"],
                "amount": r["amount"],
                "category_path": r["category_path"],
            }
            for r in rows
        ]


def aggregate_spending(
    start_date: str,
    end_date: str,
    bucket: Literal["day", "week", "month"],
    category_path: str | None = None,
    by_category: bool = False,
) -> list[dict]:
    """Sum spending across a date range, bucketed by day/week/month.

    The workhorse for time-series charts. The AI plugs the returned list
    directly into a `ChartSpec.series.points`.

    When ``by_category`` is true and ``category_path`` is None, returns one
    series per top-level category. Otherwise returns a single series.
    """
    with connect() as conn:
        if by_category and category_path is None:
            return _aggregate_by_top_level(conn, start_date, end_date, bucket)
        return [
            {"period_start": p, "period_label": _label_for(p, bucket), "value": v}
            for p, v in _aggregate_single(conn, start_date, end_date, bucket, category_path)
        ]


def top_merchants(
    start_date: str,
    end_date: str,
    category_path: str | None = None,
    limit: int = 10,
) -> list[dict]:
    """Top merchants by total spend in the window. Useful for "where am I
    spending on grocery" style questions.
    """
    where, params = _date_clauses(start_date, end_date)
    cat_filter = ""
    if category_path:
        with connect() as conn:
            ids = descendant_category_ids(conn, category_path)
        if ids:
            cat_filter = f" AND category_id IN ({','.join('?' for _ in ids)})"
            params = (*params, *ids)
    with connect() as conn:
        rows = conn.execute(
            f"""
            SELECT merchant,
                   ROUND(SUM(amount), 2) AS total,
                   COUNT(*) AS count
              FROM transactions
             WHERE {where}{cat_filter}
             GROUP BY merchant
             ORDER BY total DESC
             LIMIT ?
            """,
            (*params, limit),
        ).fetchall()
    return [{"merchant": r["merchant"], "total": r["total"], "count": r["count"]} for r in rows]


def compare_periods(
    period_a_start: str,
    period_a_end: str,
    period_b_start: str,
    period_b_end: str,
    category_path: str | None = None,
) -> dict:
    """Total spend in two windows + the absolute and percentage delta.

    Convention: ``period_a`` is the *baseline* (older), ``period_b`` is the
    *current* (newer). Positive delta = increased spending in period_b.
    """
    a = _total_for_window(period_a_start, period_a_end, category_path)
    b = _total_for_window(period_b_start, period_b_end, category_path)
    abs_delta = round(b - a, 2)
    pct_delta = round((b - a) / a * 100, 2) if a else None
    return {
        "a_total": a,
        "b_total": b,
        "abs_delta": abs_delta,
        "pct_delta": pct_delta,
    }


def forecast(
    horizon_months: int,
    category_path: str | None = None,
    method: Literal["trailing_avg", "linear"] = "trailing_avg",
) -> dict:
    """Cheap forecast — `trailing_avg` uses the last 6 months' mean monthly
    spend; `linear` fits a least-squares line over the last 12 months.

    Returns ``{historical, forecast}`` ready for the chart's solid/dashed
    series convention.
    """
    today = date.today()
    start = (today.replace(day=1) - timedelta(days=365)).isoformat()
    end = today.isoformat()
    historical = aggregate_spending(start, end, "month", category_path)

    values = [h["value"] for h in historical]
    if not values:
        return {"historical": historical, "forecast": []}

    if method == "linear" and len(values) >= 2:
        # y = a*x + b (least squares)
        n = len(values)
        xs = list(range(n))
        sx, sy = sum(xs), sum(values)
        sxy = sum(x * y for x, y in zip(xs, values))
        sxx = sum(x * x for x in xs)
        denom = n * sxx - sx * sx
        a = (n * sxy - sx * sy) / denom if denom else 0.0
        b = (sy - a * sx) / n
        proj = [round(a * (n + i) + b, 2) for i in range(horizon_months)]
    else:
        recent = values[-6:] if len(values) >= 6 else values
        avg = round(sum(recent) / len(recent), 2)
        proj = [avg] * horizon_months

    last_period = historical[-1]["period_start"] if historical else end[:7] + "-01"
    last_year, last_month = int(last_period[:4]), int(last_period[5:7])
    forecast_rows: list[dict] = []
    for i in range(1, horizon_months + 1):
        m = last_month + i
        y = last_year + (m - 1) // 12
        m = ((m - 1) % 12) + 1
        period_start = f"{y:04d}-{m:02d}-01"
        forecast_rows.append({
            "period_start": period_start,
            "period_label": _label_for(period_start, "month"),
            "value": proj[i - 1],
        })
    return {"historical": historical, "forecast": forecast_rows}


# ── SQL helpers ──────────────────────────────────────────────────────────────


def _date_clauses(start_date: str | None, end_date: str | None) -> tuple[str, tuple]:
    """Builds a WHERE clause + params for an inclusive date range.

    Returns ``("date >= ? AND date <= ?", (start, end))`` if both provided,
    or with one side dropped, or "1=1" if neither is set.
    """
    parts: list[str] = []
    params: list[str] = []
    if start_date:
        parts.append("date >= ?")
        params.append(start_date)
    if end_date:
        parts.append("date <= ?")
        params.append(end_date)
    return (" AND ".join(parts) if parts else "1=1", tuple(params))


def _build_txn_query(
    conn: sqlite3.Connection,
    *,
    start_date: str | None,
    end_date: str | None,
    category_path: str | None,
    merchant_query: str | None,
    limit: int,
) -> tuple[str, tuple]:
    where, params = _date_clauses(start_date, end_date)
    extras: list[str] = []
    extra_params: list[Any] = []

    if category_path == "Unknown":
        extras.append("t.category_id IS NULL")
    elif category_path:
        ids = descendant_category_ids(conn, category_path)
        if ids:
            extras.append(f"t.category_id IN ({','.join('?' for _ in ids)})")
            extra_params.extend(ids)
        else:
            extras.append("0=1")  # path didn't resolve → empty result

    if merchant_query:
        extras.append("LOWER(t.merchant) LIKE ?")
        extra_params.append(f"%{merchant_query.lower()}%")

    if extras:
        where = f"{where} AND {' AND '.join(extras)}"

    sql = f"""
    {CATEGORY_PATHS_CTE}
    SELECT t.id, t.date, t.merchant, t.amount,
           cp.path AS category_path
      FROM transactions t
      LEFT JOIN category_paths cp ON cp.id = t.category_id
     WHERE {where}
     ORDER BY t.date
     LIMIT ?
    """
    return sql, (*params, *extra_params, limit)


def _bucket_expr(bucket: str) -> str:
    """SQLite strftime expression that yields the bucket-start date string."""
    if bucket == "day":
        return "date"
    if bucket == "week":
        # Monday as week start. SQLite's weekday: 0=Sun..6=Sat.
        return "DATE(date, '-' || ((CAST(strftime('%w', date) AS INTEGER) + 6) % 7) || ' days')"
    if bucket == "month":
        return "strftime('%Y-%m-01', date)"
    raise ValueError(f"unsupported bucket: {bucket}")


def _aggregate_single(
    conn: sqlite3.Connection,
    start_date: str,
    end_date: str,
    bucket: str,
    category_path: str | None,
) -> list[tuple[str, float]]:
    where, params = _date_clauses(start_date, end_date)
    cat_filter = ""
    if category_path == "Unknown":
        cat_filter = " AND category_id IS NULL"
    elif category_path:
        ids = descendant_category_ids(conn, category_path)
        if ids:
            cat_filter = f" AND category_id IN ({','.join('?' for _ in ids)})"
            params = (*params, *ids)
        else:
            return []

    rows = conn.execute(
        f"""
        SELECT {_bucket_expr(bucket)} AS period, ROUND(SUM(amount), 2) AS value
          FROM transactions
         WHERE {where}{cat_filter}
         GROUP BY period
         ORDER BY period
        """,
        params,
    ).fetchall()
    return [(r["period"], r["value"]) for r in rows]


def _aggregate_by_top_level(
    conn: sqlite3.Connection,
    start_date: str,
    end_date: str,
    bucket: str,
) -> list[dict]:
    """Returns one series per top-level (immediate-child-of-root) category.

    Uncategorised transactions are surfaced as the synthetic series
    ``"Unassigned"``.
    """
    # Top-level categories: parent_id == root id. We treat root as the single
    # row with parent_id IS NULL.
    top_rows = conn.execute(
        """
        SELECT id, name FROM categories
         WHERE parent_id = (SELECT id FROM categories WHERE parent_id IS NULL)
           AND is_unknown = 0
         ORDER BY name
        """,
    ).fetchall()

    out: list[dict] = []
    for top in top_rows:
        sub_ids = descendant_category_ids(conn, top["name"])
        if not sub_ids:
            continue
        rows = conn.execute(
            f"""
            SELECT {_bucket_expr(bucket)} AS period,
                   ROUND(SUM(amount), 2) AS value
              FROM transactions
             WHERE date >= ? AND date <= ?
               AND category_id IN ({','.join('?' for _ in sub_ids)})
             GROUP BY period
             ORDER BY period
            """,
            (start_date, end_date, *sub_ids),
        ).fetchall()
        if rows:
            out.append({
                "category_path": top["name"],
                "points": [
                    {"period_start": r["period"], "period_label": _label_for(r["period"], bucket),
                     "value": r["value"]}
                    for r in rows
                ],
            })

    # Unassigned bucket
    rows = conn.execute(
        f"""
        SELECT {_bucket_expr(bucket)} AS period,
               ROUND(SUM(amount), 2) AS value
          FROM transactions
         WHERE date >= ? AND date <= ? AND category_id IS NULL
         GROUP BY period ORDER BY period
        """,
        (start_date, end_date),
    ).fetchall()
    if rows:
        out.append({
            "category_path": "Unassigned",
            "points": [
                {"period_start": r["period"], "period_label": _label_for(r["period"], bucket),
                 "value": r["value"]}
                for r in rows
            ],
        })
    return out


def _total_for_window(start: str, end: str, category_path: str | None) -> float:
    where, params = _date_clauses(start, end)
    cat_filter = ""
    if category_path == "Unknown":
        cat_filter = " AND category_id IS NULL"
    elif category_path:
        with connect() as conn:
            ids = descendant_category_ids(conn, category_path)
        if ids:
            cat_filter = f" AND category_id IN ({','.join('?' for _ in ids)})"
            params = (*params, *ids)
        else:
            return 0.0
    with connect() as conn:
        row = conn.execute(
            f"SELECT COALESCE(SUM(amount), 0) AS total FROM transactions WHERE {where}{cat_filter}",
            params,
        ).fetchone()
    return round(row["total"], 2)


_MONTHS_SHORT = ["Jan", "Feb", "Mar", "Apr", "May", "Jun",
                 "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]


def _label_for(period_start: str, bucket: str) -> str:
    """Render a human label for a bucket's period_start date."""
    d = datetime.fromisoformat(period_start).date()
    if bucket == "month":
        return f"{_MONTHS_SHORT[d.month - 1]} {str(d.year)[-2:]}"
    if bucket == "week":
        return f"Wk of {_MONTHS_SHORT[d.month - 1]} {d.day}"
    return f"{_MONTHS_SHORT[d.month - 1]} {d.day}"


# ── Write tools (mutations) ───────────────────────────────────────────────────
#
# These let the chat AI act on the user's request to edit categories or
# transactions. Tools take *paths* for categories (the AI-facing identifier),
# never integer ids. They return the new state of whatever they changed so
# the model can confirm the operation in `present_to_user`.
#
# Errors from the service layer are caught at the orchestrator level and
# surface to the model as `{error: "..."}` tool-result payloads.


def create_category(name: str, description: str | None = None,
                     parent_path: str | None = None,
                     color: str | None = None) -> dict:
    """Create a new category. ``parent_path`` is an existing category path
    like ``"Living"`` or ``"Living / Subscriptions"``; omit to create a
    top-level group. ``color`` is an optional palette key (e.g. ``"sage"``,
    ``"clay"``); omit to let the server pick the neutral default. Returns
    the created category with its full ``path``.
    """
    return cat_svc.create_category_by_path(name, description, parent_path, color)


def set_category_color(path: str, color: str) -> dict:
    """Change a category's tile color. ``color`` must be a palette key
    (e.g. ``"sage"``, ``"clay"``, ``"ochre"``). Returns the updated category.
    """
    return cat_svc.update_category_by_path(path, new_color=color)


def rename_category(path: str, new_name: str) -> dict:
    """Rename the leaf component of an existing category path. The category's
    descendants and any transactions assigned to it stay intact — only the
    name changes. Returns the updated category.
    """
    return cat_svc.update_category_by_path(path, new_name=new_name)


def update_category_description(path: str, new_description: str) -> dict:
    """Replace a category's description (the AI-classification hint). Pass an
    empty string to clear it. Returns the updated category.
    """
    return cat_svc.update_category_by_path(
        path,
        new_description=new_description if new_description else None,
        description_explicit=True,
    )


def move_category(path: str, new_parent_path: str | None = None) -> dict:
    """Move a category (and its subtree) under a new parent. Pass
    ``new_parent_path=None`` to make it a top-level group. Cannot move a
    category into itself or one of its own descendants.
    """
    return cat_svc.update_category_by_path(
        path,
        new_parent_path=new_parent_path,
        parent_explicit=True,
    )


def delete_category(path: str) -> dict:
    """Delete a category. Any transactions assigned to it (or any descendant)
    are moved to "needs review" (category_id = NULL). Returns
    ``{deleted_id, descendants_deleted, transactions_unassigned}``.
    """
    return cat_svc.delete_category_by_path(path)


def set_transaction_category(transaction_id: int,
                              category_path: str | None = None) -> dict:
    """Assign / re-assign / unassign a single transaction's category.
    Pass ``category_path=None`` to move it to "needs review".
    Returns the updated transaction row.
    """
    return txn_svc.set_transaction_category_by_path(transaction_id, category_path)


def bulk_categorise_merchant(merchant: str,
                               category_path: str | None = None) -> dict:
    """Set the category for every transaction whose merchant matches the
    given string exactly. Pass ``category_path=None`` to unassign them all.
    Returns ``{updated: N}``.
    """
    return txn_svc.bulk_categorise_merchant_by_path(merchant, category_path)


def rename_merchant(from_merchant: str, to_merchant: str) -> dict:
    """Rename every transaction whose merchant matches ``from_merchant``
    exactly. Returns ``{updated: N}``.
    """
    return txn_svc.bulk_rename_merchant(from_merchant, to_merchant)


def update_transaction(transaction_id: int,
                        date: str | None = None,
                        merchant: str | None = None,
                        amount: float | None = None,
                        category_path: str | None = None) -> dict:
    """Single-row edit. Only the supplied fields change. Pass
    ``category_path`` (or empty string for unassign) to also change category.
    """
    category_explicit = category_path is not None
    if category_path == "":
        category_path = None  # interpret empty string as "unassign"
    return txn_svc.update_transaction_by_path(
        transaction_id,
        date=date,
        merchant=merchant,
        amount=amount,
        category_path=category_path,
        category_explicit=category_explicit,
    )


def delete_transaction(transaction_id: int) -> dict:
    """Permanently delete a transaction. Not reversible from the chat."""
    return txn_svc.delete_transaction(transaction_id)


# ── MCP server registration + stdio entry point ──────────────────────────────


READ_TOOLS: dict[str, Callable[..., Any]] = {
    "list_categories": list_categories,
    "list_transactions": list_transactions,
    "aggregate_spending": aggregate_spending,
    "top_merchants": top_merchants,
    "compare_periods": compare_periods,
    "forecast": forecast,
}

WRITE_TOOLS: dict[str, Callable[..., Any]] = {
    # Categories
    "create_category": create_category,
    "rename_category": rename_category,
    "update_category_description": update_category_description,
    "move_category": move_category,
    "delete_category": delete_category,
    "set_category_color": set_category_color,
    # Transactions
    "set_transaction_category": set_transaction_category,
    "bulk_categorise_merchant": bulk_categorise_merchant,
    "rename_merchant": rename_merchant,
    "update_transaction": update_transaction,
    "delete_transaction": delete_transaction,
}

# Combined map; preserved for backward compat with the chat orchestrator until
# Phase 4 introduces per-request gating.
TOOL_FUNCTIONS: dict[str, Callable[..., Any]] = {**READ_TOOLS, **WRITE_TOOLS}


def build_server():
    """Construct an MCP server with all tools registered.

    Imports the SDK lazily so plain tool-function use doesn't pay the cost.
    """
    from mcp.server.fastmcp import FastMCP

    server = FastMCP("budget-trace")
    for name, fn in TOOL_FUNCTIONS.items():
        server.tool(name=name)(fn)
    return server


def run_stdio() -> None:
    """Console-script entry: serve MCP over stdio."""
    server = build_server()
    server.run(transport="stdio")


if __name__ == "__main__":
    run_stdio()
