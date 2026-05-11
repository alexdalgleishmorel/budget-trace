"""Dashboards / widgets service layer.

Each function owns its own DB connection (matches the rest of the service
layer). All return dicts; routes wrap into Pydantic models. ServiceError
subclasses translate to HTTP status via the existing `_err` helper.

The widget data endpoint dispatches on `data_source.kind`:
  - "metric"   → widget_metrics.resolve_metric_data(metric_id, params, type,
                   time_range=…) — live, re-runs against the dashboard's
                   current time range on every fetch.
  - "snapshot" → return the widget's inline `snapshot_json` payload as-is.
                   Snapshots are frozen — they ignore the dashboard's time
                   range. The frontend tags them with an `is_snapshot`
                   flag so a "Snapshot" badge can appear on the card.
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
    "save_chat_widget_to_dashboard",
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
            "       data_source_json, config_json, snapshot_json, via_chat, created_at, updated_at "
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
        "via_chat": bool(row["via_chat"]) if "via_chat" in row.keys() else False,
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


def _validate_data_source(widget_type: str, data_source: dict) -> dict:
    """Validate the data_source payload supplied on widget create/update.

    Two kinds are accepted:
      - "metric"   — re-runnable. `metric_id` + `params` describe a query
                     that the dashboard re-resolves against its own time
                     range on every fetch.
      - "snapshot" — frozen bytes. Reserved for internal use by the
                     save-from-chat endpoint; the payload is stored
                     server-side and the data_source itself only carries
                     the kind tag. We accept it here only when no
                     external client constructs it (the snapshot payload
                     is set by the chat-save path).
    """
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
    if kind == "snapshot":
        # Snapshots are only created by the chat-save path, which writes
        # `snapshot_json` directly. The external Add-widget drawer cannot
        # construct one, so reject it here.
        raise ServiceError(
            "snapshot widgets can only be created via the chat-save endpoint",
            code="validation_error",
        )
    raise ServiceError(
        f"unknown data_source.kind: {kind!r}",
        code="validation_error",
    )


# Frontend-facing labels for each widget renderer. Match what the
# Add-widget drawer shows in its type picker so the displayed title and
# the picker label stay consistent.
_WIDGET_TYPE_LABELS = {
    "timeseries": "Time series",
    "bar": "Bar",
    "pie": "Pie",
    "query_value": "Big number",
    "table": "Table",
    "treemap": "Treemap",
}


def _derive_title(widget_type: str, data_source: dict) -> str:
    """Format the displayed title as `{Widget type} : {Metric}` (or
    `{Widget type} : Snapshot` when the widget is a frozen snapshot).
    Metrics that take a `rollup_period` param have it appended in
    parens — e.g. `Time series : Spend over time (Day)` — since the
    same metric reads very differently at day vs. month granularity.
    The user-facing UI renders this verbatim — no further humanization."""
    type_label = _WIDGET_TYPE_LABELS.get(widget_type, widget_type)
    kind = (data_source or {}).get("kind")
    if kind == "metric":
        metric_id = data_source.get("metric_id") or ""
        metric = widget_metrics.METRIC_REGISTRY.get(metric_id)
        source_label = metric.label if metric is not None else (metric_id or "Unknown")
        params = data_source.get("params") or {}
        rollup = params.get("rollup_period")
        if rollup:
            source_label = f"{source_label} ({str(rollup).capitalize()})"
    elif kind == "snapshot":
        source_label = "Snapshot"
    else:
        source_label = "Unknown"
    return f"{type_label} : {source_label}"


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
    data_source = _validate_data_source(widget_type, payload.get("data_source") or {})
    config = payload.get("config") or {}
    if not isinstance(config, dict):
        raise ServiceError("config must be an object", code="validation_error")
    # Widget titles are no longer surfaced in the UI — they're derived
    # here from the data source so the DB column (still NOT NULL for
    # historical reasons) gets a sensible identifier.
    title = _derive_title(widget_type, data_source)

    now = _now_iso()
    with connect() as conn:
        _get_dashboard_row(conn, user_id, dashboard_id)
        layout_payload = payload.get("layout")
        if layout_payload:
            x, y, w, h = _validate_layout(widget_type, layout_payload)
        else:
            # Auto-place at the row below the current max y, with the
            # widget type's min size — avoids overlapping existing tiles.
            min_w, min_h = widget_metrics.WIDGET_MIN_SIZE.get(  # type: ignore[arg-type]
                widget_type, (2, 2),
            )
            max_y_row = conn.execute(
                "SELECT COALESCE(MAX(layout_y + layout_h), 0) AS next_y "
                "FROM widgets WHERE dashboard_id = ?",
                (dashboard_id,),
            ).fetchone()
            x, y, w, h = 0, int(max_y_row["next_y"] or 0), min_w, min_h
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
            "       data_source_json, config_json, snapshot_json, via_chat, created_at, updated_at "
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
        "       data_source_json, config_json, snapshot_json, via_chat, created_at, updated_at "
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

        # Pick up the new data_source (if any) up front — both layout
        # bounds and the title fallback need it.
        new_data_source: dict | None = None
        if "data_source" in payload:
            new_data_source = _validate_data_source(
                widget_type, payload.get("data_source") or {},
            )
            updates.append("data_source_json = ?")
            params.append(json.dumps(new_data_source))

        if "layout" in payload:
            x, y, w, h = _validate_layout(widget_type, payload.get("layout") or {})
            updates.extend(["layout_x = ?", "layout_y = ?", "layout_w = ?", "layout_h = ?"])
            params.extend([x, y, w, h])

        if "title" in payload:
            raw_title = (payload.get("title") or "").strip()
            # Empty string is the "reset to derived" signal — the user
            # cleared the rename field. Falls back to the data source they
            # just picked (if any) or the existing one.
            if raw_title:
                resolved_title = raw_title
            else:
                ds_for_title = new_data_source or json.loads(row["data_source_json"])
                resolved_title = _derive_title(widget_type, ds_for_title)
            updates.append("title = ?")
            params.append(resolved_title)

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
            "       data_source_json, config_json, snapshot_json, via_chat, created_at, updated_at "
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
    via_chat = bool(row["via_chat"]) if "via_chat" in row.keys() else False

    # The dashboard's time range is the single source of truth for every
    # metric-backed widget on it. Snapshot widgets ignore it.
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
        return {
            "type": widget_type, "data": data,
            "is_snapshot": False, "via_chat": via_chat,
        }
    if kind == "snapshot":
        snapshot_raw = row["snapshot_json"] if "snapshot_json" in row.keys() else None
        if not snapshot_raw:
            raise ServiceError(
                "snapshot widget is missing its snapshot payload",
                code="validation_error",
            )
        snapshot = json.loads(snapshot_raw)
        # Snapshot payload mirrors WidgetSpec — its `data` is already in
        # per-type shape so we hand it back as-is; no AI replay, no
        # re-aggregation. The dashboard's time_range is intentionally
        # ignored here.
        return {
            "type": widget_type,
            "data": snapshot.get("data") or {},
            "is_snapshot": True,
            "via_chat": via_chat,
        }
    raise ServiceError(
        f"unknown data_source kind: {kind!r}", code="validation_error",
    )


# ── Save chat widget to a dashboard ──────────────────────────────────────────


def save_chat_widget_to_dashboard(
    user_id: int, *, dashboard_id: int, chat_widget: dict,
) -> dict:
    """Create a dashboard widget from an AI assistant message's widget payload.

    `chat_widget` is the dict that lives on `chat_messages.widget_json` —
    keyed like a `WidgetSpec`: `{type, title, data, metric_id?,
    metric_params?, fallback_reason?}`.

    Two paths:

    1. Re-runnable — `metric_id` + `metric_params` are present. We create
       a `kind:"metric"` widget. The dashboard's time range will govern
       data resolution on every refresh; the chat-time window is
       intentionally discarded.

    2. Snapshot — no `metric_id`. We create a `kind:"snapshot"` widget
       whose payload lives inline in `snapshot_json`. The widget will
       ignore the dashboard's time range and always render the frozen
       `data`.
    """
    if not isinstance(chat_widget, dict):
        raise ServiceError("chat widget payload must be an object",
                           code="validation_error")
    widget_type = _validate_type(chat_widget.get("type") or "")

    metric_id = chat_widget.get("metric_id")
    snapshot_payload: dict | None = None
    if metric_id:
        metric = widget_metrics.get_metric(metric_id)
        if widget_type not in metric.widget_types:
            raise ServiceError(
                f"metric {metric_id!r} is not compatible with widget type {widget_type!r}",
                code="incompatible_widget_type",
            )
        params = chat_widget.get("metric_params") or {}
        if not isinstance(params, dict):
            raise ServiceError("metric_params must be an object",
                               code="validation_error")
        data_source = {"kind": "metric", "metric_id": metric_id, "params": params}
    else:
        if not isinstance(chat_widget.get("data"), dict):
            raise ServiceError(
                "snapshot widget requires `data` to save",
                code="validation_error",
            )
        data_source = {"kind": "snapshot"}
        snapshot_payload = {
            "type": widget_type,
            # The chat-time title is preserved on the frozen payload only
            # as metadata; the dashboard chrome does not surface it.
            "title": (chat_widget.get("title") or "").strip() or "Snapshot",
            "data": chat_widget["data"],
        }
    final_title = _derive_title(widget_type, data_source)

    # Layout: drop the widget into a sensible default tile at the bottom
    # of the existing grid so it doesn't overlap. Frontend can drag/resize
    # afterwards.
    min_w, min_h = widget_metrics.WIDGET_MIN_SIZE.get(widget_type, (2, 2))  # type: ignore[arg-type]

    now = _now_iso()
    with connect() as conn:
        _get_dashboard_row(conn, user_id, dashboard_id)
        # Place below the current max y.
        max_y_row = conn.execute(
            "SELECT COALESCE(MAX(layout_y + layout_h), 0) AS next_y "
            "FROM widgets WHERE dashboard_id = ?",
            (dashboard_id,),
        ).fetchone()
        next_y = int(max_y_row["next_y"] or 0)
        cur = conn.execute(
            "INSERT INTO widgets (dashboard_id, type, title, "
            "  layout_x, layout_y, layout_w, layout_h, "
            "  data_source_json, config_json, snapshot_json, via_chat, "
            "  created_at, updated_at) "
            "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 1, ?, ?)",
            (
                dashboard_id, widget_type, final_title,
                0, next_y, min_w, min_h,
                json.dumps(data_source), json.dumps({}),
                json.dumps(snapshot_payload) if snapshot_payload else None,
                now, now,
            ),
        )
        conn.execute(
            "UPDATE dashboards SET updated_at = ? WHERE id = ?",
            (now, dashboard_id),
        )
        row = conn.execute(
            "SELECT id, dashboard_id, type, title, layout_x, layout_y, layout_w, layout_h, "
            "       data_source_json, config_json, snapshot_json, via_chat, created_at, updated_at "
            "FROM widgets WHERE id = ?",
            (cur.lastrowid,),
        ).fetchone()
    return _widget_row_to_dict(row)


# Re-export for routes that want a single import.
__all__.extend(["Conflict", "NotFound", "ServiceError"])
