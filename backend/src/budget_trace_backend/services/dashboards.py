"""Dashboards / widgets / saved-insights service layer.

Each function owns its own DB connection (matches the rest of the service
layer). All return dicts; routes wrap into Pydantic models. ServiceError
subclasses translate to HTTP status via the existing `_err` helper.

The widget data endpoint dispatches on `data_source.kind`:
  - "metric"  → widget_metrics.resolve_metric_data(metric_id, params, type)
  - "insight" → look up saved_insights row and return its frozen ChartSpec
The frontend reads `data` and branches on `widget.type`, never on kind.
"""

from __future__ import annotations

import json
import sqlite3
from datetime import datetime, timezone
from typing import Any

from .. import features
from ..db import connect
from . import widget_metrics
from .categories import Conflict, NotFound, ServiceError

__all__ = [
    "list_dashboards",
    "create_dashboard",
    "get_dashboard",
    "update_dashboard",
    "rename_dashboard",  # alias kept for any external callers
    "delete_dashboard",
    "create_widget",
    "update_widget",
    "delete_widget",
    "bulk_update_layout",
    "get_widget_data",
    "list_saved_insights",
    "get_saved_insight",
    "create_saved_insight",
    "delete_saved_insight",
]


# ── Time helper ──────────────────────────────────────────────────────────────


def _now_iso() -> str:
    # Microsecond precision so consecutive updates within the same second
    # surface distinct `updated_at` strings — the frontend WidgetCard keys
    # its refresh on that value.
    return datetime.now(timezone.utc).isoformat(timespec="microseconds")


# ── Dashboards ───────────────────────────────────────────────────────────────


_DASHBOARD_COLS = (
    "id, name, time_range_preset, time_range_start, time_range_end, "
    "created_at, updated_at"
)


def _dashboard_row_to_dict(row: sqlite3.Row) -> dict:
    return {
        "id": row["id"],
        "name": row["name"],
        "time_range": {
            "preset": row["time_range_preset"],
            "custom_start": row["time_range_start"],
            "custom_end": row["time_range_end"],
        },
        "created_at": row["created_at"],
        "updated_at": row["updated_at"],
    }


def list_dashboards(user_id: int) -> list[dict]:
    with connect() as conn:
        rows = conn.execute(
            f"SELECT {_DASHBOARD_COLS} FROM dashboards WHERE user_id = ? "
            "ORDER BY updated_at DESC",
            (user_id,),
        ).fetchall()
    return [_dashboard_row_to_dict(r) for r in rows]


def create_dashboard(user_id: int, name: str) -> dict:
    name = (name or "").strip()
    if not name:
        raise ServiceError("name is required", code="validation_error")
    now = _now_iso()
    with connect() as conn:
        features.ensure_default_user(conn)
        cur = conn.execute(
            "INSERT INTO dashboards "
            "(user_id, name, time_range_preset, time_range_start, time_range_end, created_at, updated_at) "
            "VALUES (?, ?, 'last_3_months', NULL, NULL, ?, ?)",
            (user_id, name, now, now),
        )
        new_id = cur.lastrowid
        row = conn.execute(
            f"SELECT {_DASHBOARD_COLS} FROM dashboards WHERE id = ?",
            (new_id,),
        ).fetchone()
    return _dashboard_row_to_dict(row)


def _get_dashboard_row(conn: sqlite3.Connection, user_id: int, dashboard_id: int) -> sqlite3.Row:
    row = conn.execute(
        f"SELECT {_DASHBOARD_COLS} FROM dashboards "
        "WHERE id = ? AND user_id = ?",
        (dashboard_id, user_id),
    ).fetchone()
    if row is None:
        raise NotFound(f"dashboard {dashboard_id} not found")
    return row


def get_dashboard(user_id: int, dashboard_id: int) -> dict:
    with connect() as conn:
        row = _get_dashboard_row(conn, user_id, dashboard_id)
        widget_rows = conn.execute(
            "SELECT id, dashboard_id, type, title, layout_x, layout_y, layout_w, layout_h, "
            "       data_source_json, config_json, created_at, updated_at "
            "FROM widgets WHERE dashboard_id = ? "
            "ORDER BY layout_y, layout_x, id",
            (dashboard_id,),
        ).fetchall()
    out = _dashboard_row_to_dict(row)
    out["widgets"] = [_widget_row_to_dict(r) for r in widget_rows]
    # Side-effect: track last-viewed for the user (consumed by the
    # frontend's Widgets tab to return to the same dashboard).
    features.set_last_dashboard(dashboard_id, user_id=user_id)
    return out


def update_dashboard(
    user_id: int,
    dashboard_id: int,
    *,
    name: str | None = None,
    time_range: dict | None = None,
) -> dict:
    """Partial update. `time_range` is a dict shaped like
    ``{"preset": "...", "custom_start": "...", "custom_end": "..."}``.
    Provide at least one of `name` / `time_range`."""
    with connect() as conn:
        _get_dashboard_row(conn, user_id, dashboard_id)

        updates: list[str] = []
        params: list[Any] = []

        if name is not None:
            n = name.strip()
            if not n:
                raise ServiceError("name cannot be empty",
                                   code="validation_error")
            updates.append("name = ?")
            params.append(n)

        if time_range is not None:
            preset = time_range.get("preset") or "last_3_months"
            if preset not in widget_metrics.TIME_RANGE_PRESETS:
                raise ServiceError(
                    f"unknown time_range preset: {preset!r}",
                    code="validation_error",
                )
            custom_start = time_range.get("custom_start") if preset == "custom" else None
            custom_end = time_range.get("custom_end") if preset == "custom" else None
            if preset == "custom" and (not custom_start or not custom_end):
                raise ServiceError(
                    "custom time range requires both custom_start and custom_end",
                    code="validation_error",
                )
            updates.extend([
                "time_range_preset = ?",
                "time_range_start = ?",
                "time_range_end = ?",
            ])
            params.extend([preset, custom_start, custom_end])

        if not updates:
            row = _get_dashboard_row(conn, user_id, dashboard_id)
            return _dashboard_row_to_dict(row)

        now = _now_iso()
        updates.append("updated_at = ?")
        params.append(now)
        params.append(dashboard_id)
        conn.execute(
            f"UPDATE dashboards SET {', '.join(updates)} WHERE id = ?",
            params,
        )
        # When the time range changes, every widget's effective data
        # changes too; bump their `updated_at` so the frontend's per-card
        # didUpdateWidget refresh triggers without an explicit re-fetch.
        if time_range is not None:
            conn.execute(
                "UPDATE widgets SET updated_at = ? WHERE dashboard_id = ?",
                (now, dashboard_id),
            )
        row = _get_dashboard_row(conn, user_id, dashboard_id)
    return _dashboard_row_to_dict(row)


# Backwards-compatible alias used in earlier code paths.
def rename_dashboard(user_id: int, dashboard_id: int, name: str) -> dict:
    return update_dashboard(user_id, dashboard_id, name=name)


def delete_dashboard(user_id: int, dashboard_id: int) -> dict:
    with connect() as conn:
        _get_dashboard_row(conn, user_id, dashboard_id)
        conn.execute("DELETE FROM dashboards WHERE id = ?", (dashboard_id,))
        # If the deleted dashboard was the last-viewed one, clear it so the
        # frontend falls back to the list view on next open.
        row = conn.execute(
            "SELECT last_dashboard_id FROM users WHERE id = ?", (user_id,),
        ).fetchone()
        if row and row["last_dashboard_id"] == dashboard_id:
            conn.execute(
                "UPDATE users SET last_dashboard_id = NULL WHERE id = ?", (user_id,),
            )
    return {"deleted_id": dashboard_id}


# ── Widgets ──────────────────────────────────────────────────────────────────


def _widget_row_to_dict(row: sqlite3.Row) -> dict:
    # Clamp width/height up to the current minimum for the widget's type
    # so layouts saved before a min-size bump still render without
    # overflow. The DB row stays as-is; the next layout PUT will persist
    # the normalised values.
    widget_type = row["type"]
    min_w, min_h = widget_metrics.WIDGET_MIN_SIZE.get(widget_type, (1, 1))  # type: ignore[arg-type]
    return {
        "id": row["id"],
        "dashboard_id": row["dashboard_id"],
        "type": widget_type,
        "title": row["title"],
        "layout": {
            "x": row["layout_x"],
            "y": row["layout_y"],
            "w": max(min_w, row["layout_w"]),
            "h": max(min_h, row["layout_h"]),
        },
        "data_source": json.loads(row["data_source_json"]),
        "config": json.loads(row["config_json"]) if row["config_json"] else {},
        "created_at": row["created_at"],
        "updated_at": row["updated_at"],
    }


def _validate_layout(widget_type: str, layout: dict) -> tuple[int, int, int, int]:
    try:
        x = int(layout.get("x", 0))
        y = int(layout.get("y", 0))
        w = int(layout.get("w", 0))
        h = int(layout.get("h", 0))
    except (TypeError, ValueError):
        raise ServiceError("layout must contain integer x, y, w, h",
                           code="validation_error")
    if x < 0 or y < 0:
        raise ServiceError("layout x/y must be non-negative",
                           code="validation_error")
    min_w, min_h = widget_metrics.WIDGET_MIN_SIZE.get(widget_type, (1, 1))  # type: ignore[arg-type]
    if w < min_w or h < min_h:
        raise ServiceError(
            f"widget type {widget_type!r} requires at least {min_w}×{min_h}",
            code="validation_error",
        )
    return x, y, w, h


def _validate_data_source(user_id: int, widget_type: str, data_source: dict) -> dict:
    if not isinstance(data_source, dict):
        raise ServiceError("data_source must be an object", code="validation_error")
    kind = data_source.get("kind")
    if kind == "metric":
        metric_id = data_source.get("metric_id")
        if not metric_id:
            raise ServiceError("data_source.metric_id is required",
                               code="validation_error")
        metric = widget_metrics.get_metric(metric_id)
        if widget_type not in metric.widget_types:
            raise ServiceError(
                f"metric {metric_id!r} is not compatible with widget type {widget_type!r}",
                code="incompatible_widget_type",
            )
        params = data_source.get("params") or {}
        if not isinstance(params, dict):
            raise ServiceError("data_source.params must be an object",
                               code="validation_error")
        return {"kind": "metric", "metric_id": metric_id, "params": params}
    if kind == "insight":
        insight_id = data_source.get("insight_id")
        if insight_id is None:
            raise ServiceError("data_source.insight_id is required",
                               code="validation_error")
        # Saved insights carry a widget of a specific type; the consuming
        # dashboard widget must match it so the frozen `data` shape lines
        # up with the renderer.
        insight = get_saved_insight(user_id, int(insight_id))
        saved_widget = insight.get("widget") or {}
        saved_type = saved_widget.get("type")
        if saved_type and widget_type != saved_type:
            raise ServiceError(
                f"saved insight is a {saved_type!r} widget; cannot populate "
                f"a {widget_type!r} widget",
                code="incompatible_widget_type",
            )
        return {"kind": "insight", "insight_id": int(insight_id)}
    raise ServiceError(
        f"unknown data_source.kind: {kind!r}",
        code="validation_error",
    )


def _validate_type(widget_type: str) -> str:
    if widget_type not in widget_metrics.ALL_WIDGET_TYPES:
        raise ServiceError(
            f"unknown widget type: {widget_type!r}", code="validation_error",
        )
    return widget_type


def create_widget(
    user_id: int, dashboard_id: int, payload: dict,
) -> dict:
    widget_type = _validate_type(payload.get("type") or "")
    title = (payload.get("title") or "").strip()
    if not title:
        raise ServiceError("title is required", code="validation_error")
    x, y, w, h = _validate_layout(widget_type, payload.get("layout") or {})
    data_source = _validate_data_source(user_id, widget_type, payload.get("data_source") or {})
    config = payload.get("config") or {}
    if not isinstance(config, dict):
        raise ServiceError("config must be an object", code="validation_error")

    now = _now_iso()
    with connect() as conn:
        _get_dashboard_row(conn, user_id, dashboard_id)
        cur = conn.execute(
            "INSERT INTO widgets (dashboard_id, type, title, "
            "  layout_x, layout_y, layout_w, layout_h, "
            "  data_source_json, config_json, created_at, updated_at) "
            "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
            (
                dashboard_id, widget_type, title,
                x, y, w, h,
                json.dumps(data_source), json.dumps(config),
                now, now,
            ),
        )
        conn.execute(
            "UPDATE dashboards SET updated_at = ? WHERE id = ?",
            (now, dashboard_id),
        )
        row = conn.execute(
            "SELECT id, dashboard_id, type, title, layout_x, layout_y, layout_w, layout_h, "
            "       data_source_json, config_json, created_at, updated_at "
            "FROM widgets WHERE id = ?",
            (cur.lastrowid,),
        ).fetchone()
    return _widget_row_to_dict(row)


def _get_widget_row(
    conn: sqlite3.Connection, user_id: int, dashboard_id: int, widget_id: int,
) -> sqlite3.Row:
    _get_dashboard_row(conn, user_id, dashboard_id)
    row = conn.execute(
        "SELECT id, dashboard_id, type, title, layout_x, layout_y, layout_w, layout_h, "
        "       data_source_json, config_json, created_at, updated_at "
        "FROM widgets WHERE id = ? AND dashboard_id = ?",
        (widget_id, dashboard_id),
    ).fetchone()
    if row is None:
        raise NotFound(f"widget {widget_id} not found on dashboard {dashboard_id}")
    return row


def update_widget(
    user_id: int, dashboard_id: int, widget_id: int, payload: dict,
) -> dict:
    with connect() as conn:
        row = _get_widget_row(conn, user_id, dashboard_id, widget_id)
        widget_type = row["type"]

        updates: list[str] = []
        params: list[Any] = []

        if "title" in payload:
            t = (payload.get("title") or "").strip()
            if not t:
                raise ServiceError("title cannot be empty", code="validation_error")
            updates.append("title = ?")
            params.append(t)

        if "layout" in payload:
            x, y, w, h = _validate_layout(widget_type, payload.get("layout") or {})
            updates.extend(["layout_x = ?", "layout_y = ?", "layout_w = ?", "layout_h = ?"])
            params.extend([x, y, w, h])

        if "data_source" in payload:
            ds = _validate_data_source(user_id, widget_type, payload.get("data_source") or {})
            updates.append("data_source_json = ?")
            params.append(json.dumps(ds))

        if "config" in payload:
            cfg = payload.get("config") or {}
            if not isinstance(cfg, dict):
                raise ServiceError("config must be an object", code="validation_error")
            updates.append("config_json = ?")
            params.append(json.dumps(cfg))

        if not updates:
            return _widget_row_to_dict(row)

        now = _now_iso()
        updates.append("updated_at = ?")
        params.append(now)
        params.append(widget_id)
        conn.execute(
            f"UPDATE widgets SET {', '.join(updates)} WHERE id = ?",
            params,
        )
        conn.execute(
            "UPDATE dashboards SET updated_at = ? WHERE id = ?",
            (now, dashboard_id),
        )
        new_row = conn.execute(
            "SELECT id, dashboard_id, type, title, layout_x, layout_y, layout_w, layout_h, "
            "       data_source_json, config_json, created_at, updated_at "
            "FROM widgets WHERE id = ?",
            (widget_id,),
        ).fetchone()
    return _widget_row_to_dict(new_row)


def delete_widget(user_id: int, dashboard_id: int, widget_id: int) -> dict:
    with connect() as conn:
        _get_widget_row(conn, user_id, dashboard_id, widget_id)
        conn.execute("DELETE FROM widgets WHERE id = ?", (widget_id,))
        conn.execute(
            "UPDATE dashboards SET updated_at = ? WHERE id = ?",
            (_now_iso(), dashboard_id),
        )
    return {"deleted_id": widget_id}


def bulk_update_layout(
    user_id: int, dashboard_id: int, layouts: list[dict],
) -> dict:
    """Single transaction: re-position/resize many widgets at once. Used
    after a drag/resize gesture so the frontend doesn't fire N PATCHes."""
    if not isinstance(layouts, list):
        raise ServiceError("layouts must be an array", code="validation_error")
    with connect() as conn:
        _get_dashboard_row(conn, user_id, dashboard_id)
        # Fetch all widgets up front so we can validate ownership in one shot.
        rows = conn.execute(
            "SELECT id, type FROM widgets WHERE dashboard_id = ?",
            (dashboard_id,),
        ).fetchall()
        types_by_id = {r["id"]: r["type"] for r in rows}

        now = _now_iso()
        for entry in layouts:
            if not isinstance(entry, dict):
                raise ServiceError("each layout entry must be an object",
                                   code="validation_error")
            try:
                wid = int(entry["id"])
            except (KeyError, TypeError, ValueError):
                raise ServiceError("layout entry missing id",
                                   code="validation_error")
            if wid not in types_by_id:
                raise NotFound(f"widget {wid} not found on dashboard {dashboard_id}")
            x, y, w, h = _validate_layout(types_by_id[wid], entry)
            conn.execute(
                "UPDATE widgets SET layout_x = ?, layout_y = ?, layout_w = ?, layout_h = ?, "
                "updated_at = ? WHERE id = ?",
                (x, y, w, h, now, wid),
            )
        conn.execute(
            "UPDATE dashboards SET updated_at = ? WHERE id = ?",
            (now, dashboard_id),
        )
    return {"updated": len(layouts)}


# ── Widget data resolution ───────────────────────────────────────────────────


def get_widget_data(user_id: int, dashboard_id: int, widget_id: int) -> dict:
    with connect() as conn:
        dash_row = _get_dashboard_row(conn, user_id, dashboard_id)
        row = _get_widget_row(conn, user_id, dashboard_id, widget_id)
    widget_type = row["type"]
    data_source = json.loads(row["data_source_json"])
    kind = data_source.get("kind")

    # The dashboard's time range is the single source of truth for every
    # widget on it (per spec: widget creation no longer collects dates).
    time_range = widget_metrics.resolve_time_range(
        dash_row["time_range_preset"],
        dash_row["time_range_start"],
        dash_row["time_range_end"],
    )

    if kind == "metric":
        data = widget_metrics.resolve_metric_data(
            data_source["metric_id"],
            data_source.get("params") or {},
            widget_type,  # type: ignore[arg-type]
            time_range=time_range,
        )
    elif kind == "insight":
        insight = get_saved_insight(user_id, int(data_source["insight_id"]))
        saved_widget = insight.get("widget") or {}
        # Frozen widget snapshot — its `data` is already in per-type shape
        # so we hand it back as-is; no AI replay, no re-aggregation.
        data = saved_widget.get("data") or {}
    else:
        raise ServiceError(
            f"unknown data_source kind: {kind!r}", code="validation_error",
        )

    return {"type": widget_type, "data": data}


# ── Saved insights (frozen ChartSpec) ────────────────────────────────────────


def _saved_insight_to_dict(row: sqlite3.Row) -> dict:
    # Prefer the new generic widget payload; synthesise a timeseries
    # widget from the legacy chart_json for rows written before the
    # widget-types upgrade.
    widget_raw = row["widget_json"] if "widget_json" in row.keys() else None
    if widget_raw:
        widget = json.loads(widget_raw)
    else:
        chart = json.loads(row["chart_json"]) if row["chart_json"] else None
        widget = (
            {
                "type": "timeseries",
                "title": chart.get("title", row["title"]),
                "data": {"chart": chart},
            }
            if chart else None
        )
    return {
        "id": row["id"],
        "title": row["title"],
        "widget": widget,
        "source_message_id": row["source_message_id"],
        "created_at": row["created_at"],
    }


def list_saved_insights(user_id: int) -> list[dict]:
    with connect() as conn:
        rows = conn.execute(
            "SELECT id, title, chart_json, widget_json, source_message_id, created_at "
            "FROM saved_insights WHERE user_id = ? "
            "ORDER BY created_at DESC",
            (user_id,),
        ).fetchall()
    return [_saved_insight_to_dict(r) for r in rows]


def get_saved_insight(user_id: int, insight_id: int) -> dict:
    with connect() as conn:
        row = conn.execute(
            "SELECT id, title, chart_json, widget_json, source_message_id, created_at "
            "FROM saved_insights WHERE id = ? AND user_id = ?",
            (insight_id, user_id),
        ).fetchone()
    if row is None:
        raise NotFound(f"saved insight {insight_id} not found")
    return _saved_insight_to_dict(row)


_VALID_WIDGET_TYPES = set(widget_metrics.ALL_WIDGET_TYPES)


def create_saved_insight(
    user_id: int, title: str, widget: dict, source_message_id: int | None = None,
) -> dict:
    """Persist a frozen widget rendering. `widget` is `{type, title,
    data}` matching `WidgetSpec`."""
    title = (title or "").strip()
    if not title:
        raise ServiceError("title is required", code="validation_error")
    if not isinstance(widget, dict):
        raise ServiceError("widget must be an object", code="validation_error")
    w_type = widget.get("type")
    if w_type not in _VALID_WIDGET_TYPES:
        raise ServiceError(
            f"widget type must be one of {sorted(_VALID_WIDGET_TYPES)!r}",
            code="validation_error",
        )
    if not isinstance(widget.get("data"), dict):
        raise ServiceError("widget.data must be an object",
                           code="validation_error")
    # Ensure the stored widget carries a title (default to the saved
    # insight's title if the model didn't pick one).
    widget_to_store = {
        "type": w_type,
        "title": widget.get("title") or title,
        "data": widget["data"],
    }
    now = _now_iso()
    with connect() as conn:
        features.ensure_default_user(conn)
        cur = conn.execute(
            "INSERT INTO saved_insights (user_id, title, source_message_id, widget_json, created_at) "
            "VALUES (?, ?, ?, ?, ?)",
            (user_id, title, source_message_id, json.dumps(widget_to_store), now),
        )
        row = conn.execute(
            "SELECT id, title, chart_json, widget_json, source_message_id, created_at "
            "FROM saved_insights WHERE id = ?",
            (cur.lastrowid,),
        ).fetchone()
    return _saved_insight_to_dict(row)


def delete_saved_insight(user_id: int, insight_id: int) -> dict:
    with connect() as conn:
        row = conn.execute(
            "SELECT id FROM saved_insights WHERE id = ? AND user_id = ?",
            (insight_id, user_id),
        ).fetchone()
        if row is None:
            raise NotFound(f"saved insight {insight_id} not found")
        # Widgets referencing this saved insight stop resolving — surface a
        # clear error then rather than orphan-cleanup here, so the user
        # notices and can re-pick a data source.
        conn.execute("DELETE FROM saved_insights WHERE id = ?", (insight_id,))
    return {"deleted_id": insight_id}


# Re-export for routes that want a single import.
__all__.extend(["Conflict", "NotFound", "ServiceError"])
