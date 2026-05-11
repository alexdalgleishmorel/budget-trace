"""Curated metric registry for the Widgets / Dashboards feature.

The frontend Add-widget drawer renders `params_schema` to a form, the user
picks a metric + supplies params, and the resulting widget calls
``GET /dashboards/{id}/widgets/{wid}/data``. That endpoint dispatches here
to ``resolve_metric_data(metric_id, params, widget_type, time_range=...)``
which:

  1. Calls the underlying MCP read tool(s) — these are the same functions
     the Insights AI uses, so the data path is unified.
  2. Adapts the result to the requested widget type's data shape.

Importantly, *no AI is involved here*: this is a plain REST aggregation
layer. The same metric called by the AI through MCP returns the same data
as called by the Widgets system through this module.

The date window is **dashboard-level**: every widget on a dashboard shares
its time range. Metrics that take a window read it from the
`time_range` argument; their `params_schema` does NOT include start/end.
"""

from __future__ import annotations

from datetime import date, datetime, timedelta
from typing import Any, Callable, Literal

from .. import mcp_server
from ..db import (
    CATEGORY_PATHS_CTE,
    connect,
    descendant_category_ids,
)
from .categories import ServiceError

WidgetType = Literal[
    "timeseries", "bar", "pie", "query_value",
    "table", "treemap",
]

ALL_WIDGET_TYPES: tuple[WidgetType, ...] = (
    "timeseries", "bar", "pie", "query_value",
    "table", "treemap",
)

TimeRangePreset = Literal[
    "last_30_days", "last_3_months", "last_6_months", "last_12_months",
    "month_to_date", "year_to_date", "all_time", "custom",
]

TIME_RANGE_PRESETS: tuple[TimeRangePreset, ...] = (
    "last_30_days", "last_3_months", "last_6_months", "last_12_months",
    "month_to_date", "year_to_date", "all_time", "custom",
)


class MetricDef:
    """Static description of one curated metric.

    `widget_types` is the set of widget types this metric can populate.
    `params_schema` excludes any date window — that comes from the
    dashboard's `time_range` and is resolved at request time.
    """

    def __init__(
        self,
        id: str,
        label: str,
        description: str,
        widget_types: tuple[WidgetType, ...],
        params_schema: list[dict],
        resolver: Callable[..., dict],
        uses_time_range: bool = True,
    ) -> None:
        self.id = id
        self.label = label
        self.description = description
        self.widget_types = widget_types
        self.params_schema = params_schema
        self.resolver = resolver
        # Some metrics (e.g. spend_forecast) have their own implicit window;
        # the dashboard time range doesn't apply. The frontend can use this
        # to label widgets that ignore the dashboard's time picker.
        self.uses_time_range = uses_time_range

    def to_dict(self) -> dict:
        return {
            "id": self.id,
            "label": self.label,
            "description": self.description,
            "widget_types": list(self.widget_types),
            "params_schema": self.params_schema,
            "uses_time_range": self.uses_time_range,
        }


# ── Param-schema helpers (date helpers are gone — dates live on dashboards) ──


def _enum(name: str, label: str, options: list[str], *, default: str | None = None,
          description: str | None = None) -> dict:
    return {
        "name": name, "label": label, "type": "enum",
        "options": options, "default": default or options[0],
        "description": description,
    }


def _category(name: str, label: str, *, required: bool = False,
              description: str | None = None) -> dict:
    return {
        "name": name, "label": label, "type": "category_path",
        "required": required,
        "description": description,
    }


def _int(name: str, label: str, *, default: int, min_: int = 1, max_: int = 100,
         description: str | None = None) -> dict:
    return {
        "name": name, "label": label, "type": "int",
        "default": default, "min": min_, "max": max_,
        "description": description,
    }


def _bool(name: str, label: str, *, default: bool = False,
          description: str | None = None) -> dict:
    return {
        "name": name, "label": label, "type": "bool", "default": default,
        "description": description,
    }


# ── Time-range resolution ────────────────────────────────────────────────────


_ALL_TIME_START = "2000-01-01"


def resolve_time_range(
    preset: str | None,
    custom_start: str | None = None,
    custom_end: str | None = None,
) -> tuple[str, str]:
    """Resolve a dashboard's stored time_range fields into a concrete
    (start, end) date pair. Today is the reference point — presets like
    `last_30_days` roll with the calendar each request.
    """
    today = date.today()
    p = preset or "last_3_months"
    if p == "custom":
        # Fall back to the rolling 3-month default if a custom range was
        # selected but no dates were saved.
        if not custom_start or not custom_end:
            return resolve_time_range("last_3_months")
        return custom_start, custom_end
    if p == "last_30_days":
        return (today - timedelta(days=29)).isoformat(), today.isoformat()
    if p == "last_3_months":
        return (today - timedelta(days=89)).isoformat(), today.isoformat()
    if p == "last_6_months":
        return (today - timedelta(days=179)).isoformat(), today.isoformat()
    if p == "last_12_months":
        return (today - timedelta(days=364)).isoformat(), today.isoformat()
    if p == "month_to_date":
        return today.replace(day=1).isoformat(), today.isoformat()
    if p == "year_to_date":
        return today.replace(month=1, day=1).isoformat(), today.isoformat()
    if p == "all_time":
        return _ALL_TIME_START, today.isoformat()
    # Unknown preset → fall back to the safe default.
    return resolve_time_range("last_3_months")


def _previous_window(start_iso: str, end_iso: str) -> tuple[str, str]:
    """Same-length window ending immediately before `start_iso`."""
    s = datetime.fromisoformat(start_iso).date()
    e = datetime.fromisoformat(end_iso).date()
    length = (e - s).days + 1
    prev_end = s - timedelta(days=1)
    prev_start = prev_end - timedelta(days=length - 1)
    return prev_start.isoformat(), prev_end.isoformat()


def _prior_year_window(start_iso: str, end_iso: str) -> tuple[str, str]:
    """Same calendar window, shifted one year back."""
    s = datetime.fromisoformat(start_iso).date()
    e = datetime.fromisoformat(end_iso).date()
    return (
        s.replace(year=s.year - 1).isoformat(),
        e.replace(year=e.year - 1).isoformat(),
    )


def _param(params: dict, name: str, default: Any = None) -> Any:
    v = params.get(name) if params else None
    return v if v not in (None, "") else default


# ── Shape adapters ───────────────────────────────────────────────────────────


def _wrap_timeseries_single(
    title: str,
    points: list[tuple[str, float]],
    y_label: str | None = None,
) -> dict:
    return {
        "chart": {
            "title": title,
            "y_axis_label": y_label,
            "x_axis_label": None,
            "x_tick_labels": [p[0] for p in points],
            "series": [
                {
                    "label": title,
                    "style": "solid",
                    "points": [
                        {"x": float(i), "y": float(v)} for i, (_, v) in enumerate(points)
                    ],
                },
            ],
        },
    }


def _wrap_bar_categories(items: list[tuple[str, float]]) -> dict:
    return {"categories": [{"label": lbl, "value": float(v)} for lbl, v in items]}


def _wrap_pie(items: list[tuple[str, float]]) -> dict:
    total = sum(v for _, v in items)
    return {
        "slices": [{"label": lbl, "value": float(v)} for lbl, v in items],
        "total": round(total, 2),
    }


def _wrap_treemap(items: list[tuple[str, float]]) -> dict:
    return {"nodes": [{"label": lbl, "value": float(v)} for lbl, v in items]}


def _wrap_table(columns: list[dict], rows: list[dict]) -> dict:
    return {"columns": columns, "rows": rows}


def _wrap_query_value(
    value: float,
    *,
    fmt: str = "currency",
    comparison: dict | None = None,
    sparkline: list[float] | None = None,
) -> dict:
    out: dict = {"value": float(round(value, 2)), "format": fmt}
    if comparison is not None:
        out["comparison"] = comparison
    if sparkline is not None:
        out["sparkline"] = [float(v) for v in sparkline]
    return out


def _items_from_dispatch(
    items: list[tuple[str, float]],
    widget_type: WidgetType,
    *,
    title: str,
    value_format: str = "currency",
    table_label: str = "Label",
    table_value: str = "Value",
) -> dict:
    if widget_type == "bar":
        return _wrap_bar_categories(items)
    if widget_type == "pie":
        return _wrap_pie(items)
    if widget_type == "treemap":
        return _wrap_treemap(items)
    if widget_type == "table":
        return _wrap_table(
            [
                {"key": "label", "label": table_label, "align": "left"},
                {"key": "value", "label": table_value, "align": "right",
                 "format": value_format},
            ],
            [{"label": lbl, "value": float(v)} for lbl, v in items],
        )
    if widget_type == "query_value":
        return _wrap_query_value(sum(v for _, v in items), fmt=value_format)
    if widget_type == "timeseries":
        return _wrap_timeseries_single(title, items)
    raise ServiceError(
        f"widget type {widget_type!r} is not supported by this metric",
        code="incompatible_widget_type",
    )


# ── Resolvers ────────────────────────────────────────────────────────────────


def _resolve_spend_over_time(params: dict, widget_type: WidgetType, *,
                              time_range: tuple[str, str]) -> dict:
    start, end = time_range
    bucket = _param(params, "bucket", "month")
    category = _param(params, "category_path")

    rows = mcp_server.aggregate_spending(start, end, bucket, category)
    points: list[tuple[str, float]] = [
        (r["period_label"], float(r["value"])) for r in rows
    ]
    title = "Spend over time" + (f" — {category}" if category else "")
    if widget_type == "timeseries":
        return _wrap_timeseries_single(title, points, y_label="USD")
    return _items_from_dispatch(
        points, widget_type, title=title,
        table_label="Period", table_value="Spend",
    )


def _resolve_spend_by_category(params: dict, widget_type: WidgetType, *,
                                time_range: tuple[str, str]) -> dict:
    start, end = time_range
    parent = _param(params, "parent_category")

    items: list[tuple[str, float]]
    if parent:
        items = _category_children_totals(start, end, parent)
        title = f"Spend within {parent}"
    else:
        items = _top_level_totals(start, end)
        title = "Spend by category"

    items.sort(key=lambda kv: kv[1], reverse=True)
    return _items_from_dispatch(
        items, widget_type, title=title,
        table_label="Category", table_value="Spend",
    )


def _resolve_top_merchants(params: dict, widget_type: WidgetType, *,
                            time_range: tuple[str, str]) -> dict:
    start, end = time_range
    category = _param(params, "category_path")
    limit = int(_param(params, "limit", 10))

    rows = mcp_server.top_merchants(start, end, category, limit)
    items: list[tuple[str, float]] = [(r["merchant"], float(r["total"])) for r in rows]
    title = "Top merchants" + (f" — {category}" if category else "")
    return _items_from_dispatch(
        items, widget_type, title=title,
        table_label="Merchant", table_value="Spend",
    )


def _resolve_total_spend(params: dict, widget_type: WidgetType, *,
                          time_range: tuple[str, str]) -> dict:
    start, end = time_range
    category = _param(params, "category_path")
    compare = bool(_param(params, "compare_to_previous", False))

    rows = mcp_server.aggregate_spending(start, end, "month", category)
    total = round(sum(float(r["value"]) for r in rows), 2)

    if widget_type == "query_value":
        comparison = None
        sparkline = [float(r["value"]) for r in rows] if rows else None
        if compare:
            prev_start, prev_end = _previous_window(start, end)
            prev_rows = mcp_server.aggregate_spending(prev_start, prev_end, "month", category)
            prev_total = round(sum(float(r["value"]) for r in prev_rows), 2)
            abs_delta = round(total - prev_total, 2)
            pct_delta = round((total - prev_total) / prev_total * 100, 2) if prev_total else None
            comparison = {
                "value": prev_total,
                "delta_abs": abs_delta,
                "delta_pct": pct_delta,
                "label": "vs. previous",
            }
        return _wrap_query_value(total, comparison=comparison, sparkline=sparkline)

    items = [(f"{start} → {end}", total)]
    return _items_from_dispatch(
        items, widget_type, title="Total spend",
        table_label="Window", table_value="Total",
    )


def _resolve_average_per_period(params: dict, widget_type: WidgetType, *,
                                 time_range: tuple[str, str]) -> dict:
    start, end = time_range
    bucket = _param(params, "bucket", "month")
    category = _param(params, "category_path")

    rows = mcp_server.aggregate_spending(start, end, bucket, category)
    values = [float(r["value"]) for r in rows]
    avg = round(sum(values) / len(values), 2) if values else 0.0

    if widget_type == "query_value":
        return _wrap_query_value(avg, sparkline=values or None)

    items = [(f"avg / {bucket}", avg)]
    return _items_from_dispatch(
        items, widget_type, title=f"Average per {bucket}",
        table_label="Metric", table_value="Average",
    )


def _resolve_transaction_count(params: dict, widget_type: WidgetType, *,
                                time_range: tuple[str, str]) -> dict:
    start, end = time_range
    category = _param(params, "category_path")

    rows = mcp_server.list_transactions(
        start_date=start, end_date=end,
        category_path=category, limit=500,
    )
    count = len(rows)

    if widget_type == "query_value":
        return _wrap_query_value(float(count), fmt="number")

    items = [(f"{start} → {end}", float(count))]
    return _items_from_dispatch(
        items, widget_type, title="Transactions",
        value_format="number",
        table_label="Window", table_value="Count",
    )


def _resolve_period_comparison(params: dict, widget_type: WidgetType, *,
                                time_range: tuple[str, str]) -> dict:
    """Compare the dashboard's current window against a baseline window
    chosen by `baseline_kind`. The current period is always the dashboard's
    time range — that's the "one time range per dashboard" rule."""
    current_start, current_end = time_range
    baseline_kind = _param(params, "baseline_kind", "previous_period")
    category = _param(params, "category_path")

    if baseline_kind == "prior_year":
        baseline_start, baseline_end = _prior_year_window(current_start, current_end)
    else:
        baseline_start, baseline_end = _previous_window(current_start, current_end)

    # period_a = baseline, period_b = current.
    result = mcp_server.compare_periods(
        baseline_start, baseline_end,
        current_start, current_end,
        category,
    )
    label = "vs. previous period" if baseline_kind == "previous_period" else "vs. prior year"

    if widget_type == "query_value":
        comparison = {
            "value": float(result["a_total"]),
            "delta_abs": float(result["abs_delta"]),
            "delta_pct": result.get("pct_delta"),
            "label": label,
        }
        return _wrap_query_value(float(result["b_total"]), comparison=comparison)

    items = [
        (f"baseline ({baseline_start} → {baseline_end})", float(result["a_total"])),
        (f"current ({current_start} → {current_end})", float(result["b_total"])),
    ]
    return _items_from_dispatch(
        items, widget_type, title="Period comparison",
        table_label="Window", table_value="Total",
    )


def _resolve_spend_forecast(params: dict, widget_type: WidgetType, *,
                             time_range: tuple[str, str]) -> dict:
    # Forecast deliberately ignores time_range — it operates on a fixed
    # trailing window ending today and projects forward by horizon_months.
    horizon = int(_param(params, "horizon_months", 3))
    category = _param(params, "category_path")
    method = _param(params, "method", "trailing_avg")

    result = mcp_server.forecast(horizon, category, method)
    historical = result.get("historical", [])
    forecast = result.get("forecast", [])

    h_labels = [r["period_label"] for r in historical]
    f_labels = [r["period_label"] for r in forecast]
    x_tick_labels = h_labels + f_labels

    n_h = len(historical)
    h_points = [
        {"x": float(i), "y": float(r["value"])} for i, r in enumerate(historical)
    ]
    f_points: list[dict] = []
    if n_h > 0:
        f_points.append({"x": float(n_h - 1), "y": float(historical[-1]["value"])})
    for i, r in enumerate(forecast):
        f_points.append({"x": float(n_h + i), "y": float(r["value"])})

    chart = {
        "title": "Spend forecast" + (f" — {category}" if category else ""),
        "y_axis_label": "USD",
        "x_axis_label": None,
        "x_tick_labels": x_tick_labels or None,
        "series": [
            {"label": "Historical", "style": "solid", "points": h_points},
            {"label": "Forecast",   "style": "dashed", "points": f_points},
        ],
    }
    if widget_type == "timeseries":
        return {"chart": chart}
    items = [(r["period_label"], float(r["value"])) for r in forecast]
    return _items_from_dispatch(
        items, widget_type, title="Forecast",
        table_label="Period", table_value="Forecast",
    )


def _resolve_recent_transactions(params: dict, widget_type: WidgetType, *,
                                  time_range: tuple[str, str]) -> dict:
    start, end = time_range
    category = _param(params, "category_path")
    limit = int(_param(params, "limit", 20))

    rows = mcp_server.list_transactions(
        start_date=start, end_date=end,
        category_path=category, limit=limit,
    )
    rows = sorted(rows, key=lambda r: r["date"], reverse=True)[:limit]

    if widget_type == "table":
        return _wrap_table(
            [
                {"key": "date",     "label": "Date",     "align": "left"},
                {"key": "merchant", "label": "Merchant", "align": "left"},
                {"key": "category", "label": "Category", "align": "left"},
                {"key": "amount",   "label": "Amount",   "align": "right", "format": "currency"},
            ],
            [
                {
                    "date": r["date"],
                    "merchant": r["merchant"],
                    "category": r.get("category_path") or "—",
                    "amount": float(r["amount"]),
                }
                for r in rows
            ],
        )
    items = [(r["merchant"], float(r["amount"])) for r in rows]
    return _items_from_dispatch(
        items, widget_type, title="Recent transactions",
        table_label="Merchant", table_value="Amount",
    )


# ── Tree helpers (specific to spend_by_category) ─────────────────────────────


def _top_level_totals(start: str, end: str) -> list[tuple[str, float]]:
    with connect() as conn:
        top_rows = conn.execute(
            """
            SELECT id, name FROM categories
             WHERE parent_id = (SELECT id FROM categories WHERE parent_id IS NULL)
               AND is_unknown = 0
             ORDER BY name
            """,
        ).fetchall()
        items: list[tuple[str, float]] = []
        for top in top_rows:
            ids = descendant_category_ids(conn, top["name"])
            if not ids:
                continue
            row = conn.execute(
                f"""
                SELECT COALESCE(SUM(amount), 0) AS total
                  FROM transactions
                 WHERE date >= ? AND date <= ?
                   AND category_id IN ({','.join('?' for _ in ids)})
                """,
                (start, end, *ids),
            ).fetchone()
            total = round(float(row["total"]), 2)
            if total != 0:
                items.append((top["name"], total))
        unassigned = conn.execute(
            "SELECT COALESCE(SUM(amount), 0) AS total FROM transactions "
            "WHERE date >= ? AND date <= ? AND category_id IS NULL",
            (start, end),
        ).fetchone()
        u = round(float(unassigned["total"]), 2)
        if u != 0:
            items.append(("Unassigned", u))
    return items


def _category_children_totals(start: str, end: str, parent_path: str) -> list[tuple[str, float]]:
    with connect() as conn:
        row = conn.execute(
            f"{CATEGORY_PATHS_CTE} SELECT id FROM category_paths WHERE path = ?",
            (parent_path,),
        ).fetchone()
        if row is None:
            return []
        parent_id = row["id"]
        children = conn.execute(
            "SELECT id, name FROM categories WHERE parent_id = ? AND is_unknown = 0 ORDER BY name",
            (parent_id,),
        ).fetchall()
        items: list[tuple[str, float]] = []
        for c in children:
            child_path = f"{parent_path} / {c['name']}"
            ids = descendant_category_ids(conn, child_path)
            if not ids:
                continue
            r = conn.execute(
                f"""
                SELECT COALESCE(SUM(amount), 0) AS total
                  FROM transactions
                 WHERE date >= ? AND date <= ?
                   AND category_id IN ({','.join('?' for _ in ids)})
                """,
                (start, end, *ids),
            ).fetchone()
            total = round(float(r["total"]), 2)
            if total != 0:
                items.append((c["name"], total))
    return items


# ── Registry ─────────────────────────────────────────────────────────────────


_BUCKETS = ["day", "week", "month"]
_FORECAST_METHODS = ["trailing_avg", "linear"]
_BASELINE_KINDS = ["previous_period", "prior_year"]


METRIC_REGISTRY: dict[str, MetricDef] = {
    "spend_over_time": MetricDef(
        id="spend_over_time",
        label="Spend over time",
        description="Total spend bucketed across the dashboard's time range. Pick a bucket size to control granularity.",
        widget_types=("timeseries", "bar", "table", "query_value"),
        params_schema=[
            _enum("bucket", "Bucket", _BUCKETS, default="month",
                  description="How wide each point on the chart is."),
            _category("category_path", "Category filter",
                      description="Optional — restrict to one category and its subcategories."),
        ],
        resolver=_resolve_spend_over_time,
    ),
    "spend_by_category": MetricDef(
        id="spend_by_category",
        label="Spend by category",
        description="Breakdown of spend by category over the dashboard's time range. Drill into a parent category to see its children.",
        widget_types=("pie", "bar", "treemap", "table", "query_value"),
        params_schema=[
            _category("parent_category", "Drill into",
                      description="Optional — leave blank to see the top-level breakdown."),
        ],
        resolver=_resolve_spend_by_category,
    ),
    "top_merchants": MetricDef(
        id="top_merchants",
        label="Top merchants",
        description="Highest-spend merchants in the dashboard's time range.",
        widget_types=("table", "bar", "query_value"),
        params_schema=[
            _category("category_path", "Category filter",
                      description="Optional — restrict to one category."),
            _int("limit", "Max merchants", default=10, min_=1, max_=50,
                 description="How many merchants to surface."),
        ],
        resolver=_resolve_top_merchants,
    ),
    "total_spend": MetricDef(
        id="total_spend",
        label="Total spend",
        description="Single grand total for the dashboard's time range. Optionally compare to the equivalent prior window.",
        widget_types=("query_value", "bar", "table"),
        params_schema=[
            _category("category_path", "Category filter",
                      description="Optional — restrict to one category."),
            _bool("compare_to_previous", "Compare to previous period", default=False,
                  description="Show a delta versus the same-length window immediately before."),
        ],
        resolver=_resolve_total_spend,
    ),
    "average_per_period": MetricDef(
        id="average_per_period",
        label="Average per period",
        description="Mean spend per bucket across the dashboard's time range.",
        widget_types=("query_value", "table"),
        params_schema=[
            _enum("bucket", "Bucket", _BUCKETS, default="month",
                  description="Average is taken across buckets of this size."),
            _category("category_path", "Category filter",
                      description="Optional — restrict to one category."),
        ],
        resolver=_resolve_average_per_period,
    ),
    "transaction_count": MetricDef(
        id="transaction_count",
        label="Transaction count",
        description="Number of transactions in the dashboard's time range.",
        widget_types=("query_value", "table"),
        params_schema=[
            _category("category_path", "Category filter",
                      description="Optional — restrict to one category."),
        ],
        resolver=_resolve_transaction_count,
    ),
    "period_comparison": MetricDef(
        id="period_comparison",
        label="Period comparison",
        description="Compare the dashboard's time range against a baseline window (previous period or prior year).",
        widget_types=("query_value", "bar", "table"),
        params_schema=[
            _enum("baseline_kind", "Baseline", _BASELINE_KINDS, default="previous_period",
                  description="What to compare against."),
            _category("category_path", "Category filter",
                      description="Optional — restrict to one category."),
        ],
        resolver=_resolve_period_comparison,
    ),
    "spend_forecast": MetricDef(
        id="spend_forecast",
        label="Spend forecast",
        description="Trailing-average or linear forecast over a horizon of months. Uses a fixed 12-month history ending today — independent of the dashboard's time range.",
        widget_types=("timeseries",),
        params_schema=[
            _int("horizon_months", "Horizon (months)", default=3, min_=1, max_=24,
                 description="How far into the future to project."),
            _category("category_path", "Category filter",
                      description="Optional — restrict to one category."),
            _enum("method", "Method", _FORECAST_METHODS, default="trailing_avg",
                  description="Trailing-average uses the last 6 months' mean; linear fits a line over the last 12."),
        ],
        resolver=_resolve_spend_forecast,
        uses_time_range=False,
    ),
    "recent_transactions": MetricDef(
        id="recent_transactions",
        label="Recent transactions",
        description="Most recent transactions in the dashboard's time range, newest first.",
        widget_types=("table",),
        params_schema=[
            _category("category_path", "Category filter",
                      description="Optional — restrict to one category."),
            _int("limit", "Max rows", default=20, min_=1, max_=100,
                 description="How many rows to show."),
        ],
        resolver=_resolve_recent_transactions,
    ),
}


WIDGET_MIN_SIZE: dict[WidgetType, tuple[int, int]] = {
    "timeseries":  (3, 2),
    "bar":         (2, 2),
    "pie":         (2, 2),
    # `query_value` shows the value + an optional comparison chip; both
    # need vertical room to render without overflow. 2×2 also keeps it
    # visually consistent with the other "card-style" widgets.
    "query_value": (2, 2),
    "table":       (3, 2),
    "treemap":     (2, 2),
}


def list_metric_defs() -> list[dict]:
    return [m.to_dict() for m in METRIC_REGISTRY.values()]


def get_metric(metric_id: str) -> MetricDef:
    m = METRIC_REGISTRY.get(metric_id)
    if m is None:
        raise ServiceError(
            f"unknown metric: {metric_id!r}", code="unknown_metric",
        )
    return m


def resolve_metric_data(
    metric_id: str,
    params: dict,
    widget_type: WidgetType,
    *,
    time_range: tuple[str, str],
) -> dict:
    metric = get_metric(metric_id)
    if widget_type not in metric.widget_types:
        raise ServiceError(
            f"metric {metric_id!r} cannot populate widget type {widget_type!r}",
            code="incompatible_widget_type",
        )
    return metric.resolver(params or {}, widget_type, time_range=time_range)
