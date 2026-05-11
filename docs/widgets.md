# Widgets / Dashboards

The Widgets tab is the fourth top-level tab (between Expenses and Insights). It lets the user assemble Datadog-style dashboards — named, multi-page collections of widgets — driven by either curated server-side metrics or frozen snapshots lifted off the Insights chat.

This is the doc to read before touching anything in `routes/dashboards.py`, `services/dashboards.py`, `services/widget_metrics.py`, or `frontend/lib/widgets/dash_widgets/`. It captures the *why* of the data model and the AI integration.

## The two concepts

| Concept | What it is | Where it lives |
|---------|------------|----------------|
| **Dashboard** | A named container with a time range and N widgets. | `dashboards` table |
| **Widget** | A typed, sized, positioned tile on a dashboard. Knows its data source. | `widgets` table |

A widget's `data_source` is one of:

1. **`{kind: "metric", metric_id, params}`** — a live aggregation. Refresh re-runs the resolver server-side using the dashboard's current time range.
2. **`{kind: "snapshot"}`** — a frozen payload stored inline on the widget row in `snapshot_json`. Refresh re-renders the same bytes; no AI is involved, and the dashboard's time range is intentionally ignored. Only the chat "Save to dashboard…" flow creates these; the Add-widget drawer cannot.

The frontend renderer never branches on `data_source.kind`. It dispatches on **`widget.type`**, and the `GET /dashboards/:id/widgets/:wid/data` endpoint returns a payload already shaped for that type plus an `is_snapshot: bool` flag the chrome uses to show a "Snapshot" badge and disable refresh.

## Widget types

Six renderers, each with a minimum grid size and a per-type data shape:

| Type | When to use | `data` shape |
|------|-------------|--------------|
| `timeseries` | Trends over time, forecasts. | `{chart: ChartSpec}` |
| `bar` | Ranked horizontal bars — comparing buckets side-by-side. | `{categories: [{label, value}]}` |
| `pie` | A small total split into named groups. Donut with the total in the centre. | `{slices: [{label, value}], total}` |
| `query_value` | A single headline number with an optional comparison chip. | `{value, format: "currency"\|"number"\|"percent", comparison?: {value, delta_abs, delta_pct, label}}` |
| `table` | Rows of structured detail. | `{columns: [{key, label, align?, format?}], rows: [{...keyed by key}]}` |
| `treemap` | Many groups by proportion. Uses an opaque, contrast-safe palette. | `{nodes: [{label, value}]}` |

Minimum sizes live in [`WIDGET_MIN_SIZE`](../backend/src/budget_trace_backend/services/widget_metrics.py) and are enforced both on `bulk_update_layout` and at the frontend's drag/resize clamps. They also auto-snap on read: [`_widget_row_to_dict`](../backend/src/budget_trace_backend/services/dashboards.py) clamps stored layouts up to the current min, so widgets saved before a min-size bump still render without overflow.

Per-type data shapes match exactly what the AI must emit when populating an Insights `widget` and what `widget_metrics.resolve_metric_data` returns for a curated metric — that symmetry is intentional and lets the same renderer handle both.

## Dashboard-level time range

A dashboard owns one time range that applies to every widget on it. **Per-widget date params no longer exist** — that decision came from the user request to "have a single dashboard-level time range that applies to all widgets within it."

The range is stored on the dashboard as `{preset, custom_start, custom_end}` where `preset` is one of:

`last_30_days`, `last_3_months` (default), `last_6_months`, `last_12_months`, `month_to_date`, `year_to_date`, `all_time`, `custom`.

Presets resolve to concrete `(start, end)` at request time via [`widget_metrics.resolve_time_range`](../backend/src/budget_trace_backend/services/widget_metrics.py), so a `last_30_days` dashboard rolls with the calendar without a write. `custom` honours the stored `custom_start` / `custom_end`.

`PATCH /dashboards/:id` accepts a `time_range` payload. Changing it bumps every widget's `updated_at`, which the frontend uses as one of two cache-bust signals on `WidgetCard`:

- `widget.updatedAt` change → re-fetch (handles individual widget edits).
- `revalidationKey` change (the dashboard's `time_range.cacheKey` string) → re-fetch (handles time-range changes en masse).

`spend_forecast` is the one metric that **ignores** the dashboard time range — its `uses_time_range: false` flag is surfaced on `/widget-metrics` so the drawer can warn the user that this widget operates on a fixed 12-month history regardless of the dashboard's setting.

## Curated metric registry

`GET /widget-metrics` returns the catalogue used to populate the Add-widget drawer's metric picker. The registry lives in [`services/widget_metrics.py`](../backend/src/budget_trace_backend/services/widget_metrics.py); each entry is a `MetricDef` with:

- `id`, `label`, `description` — surfaced in the dropdown.
- `widget_types` — compatibility list. The drawer filters the dropdown to metrics that support the widget type the user just picked.
- `params_schema` — list of `{name, label, type, default?, options?, description?}`. Drives a generic param form (date pickers, category-path dropdown, enum, int, bool).
- `resolver(params, widget_type, *, time_range)` — Python callable. Calls underlying MCP read tools, normalises the result, and adapts it to the requested widget type via `_items_from_dispatch`.

Current starter set (every entry except `spend_forecast` honours the dashboard's `time_range`):

| `metric_id` | What it computes | Compatible types |
|---|---|---|
| `spend_over_time` | Bucketed spend (day/week/month) | timeseries, bar, table, query_value |
| `spend_by_category` | Top-level breakdown or drill into one category | pie, bar, treemap, table, query_value |
| `top_merchants` | Top-N merchants by spend | table, bar, query_value |
| `total_spend` | Grand total, optional vs-previous comparison | query_value, bar, table |
| `average_per_period` | Mean spend per bucket | query_value, table |
| `transaction_count` | How many transactions | query_value, table |
| `period_comparison` | Current dashboard range vs. `previous_period` or `prior_year` | query_value, bar, table |
| `spend_forecast` | Trailing-average or linear projection (fixed 12-month history) | timeseries |
| `recent_transactions` | N most-recent rows | table |

Adding a metric: write a resolver + `MetricDef` entry, restart the backend. No frontend release needed — the drawer's param form renders the new metric's `params_schema` generically.

## Saving a chat widget to a dashboard

When the Insights AI produces a widget that the user wants on a dashboard, the chat-side **"Save to dashboard…"** button takes the AI's `widget` payload and creates a dashboard widget directly. There is no intermediary inbox — the user picks the target dashboard (or creates a new one) and the widget lands on it.

Two paths, picked by what the AI emitted:

1. **Re-runnable** — the AI's widget carries `metric_id` + `metric_params`. The saved widget gets `data_source = {kind: "metric", metric_id, params}`. On every dashboard render it re-runs the metric server-side **using the dashboard's time range** — so the same widget can power different windows just by changing the dashboard's range. This is the path the user's directive specifies: *"the only snapshot should be for the historical view in the insights chat itself."*

2. **Snapshot fallback** — the AI couldn't express the answer as a curated metric (it told us so via `fallback_reason`). The saved widget gets `data_source = {kind: "snapshot"}` and the rendered `data` is stored inline on `widgets.snapshot_json`. The dashboard's time range is **ignored**; the bytes are returned verbatim. The chrome shows a "Snapshot" badge and disables refresh.

Snapshot fallbacks are an audit signal — every one of them writes a row to `ai_widget_audit` capturing the message id, the AI's `fallback_reason`, and the original user question, so the curated registry can be grown to cover the gap.

Mechanically:

1. The Insights chat AI emits a `widget` via `present_to_user`, preferring `metric_id` + `metric_params` + `time_range`. The chat orchestrator resolves the metric server-side to produce the chat-time snapshot — so the bytes the user sees in the chat are byte-identical to what re-running the same metric on a dashboard would produce.
2. The user clicks "Save to dashboard…" on a chat message → frontend `POST /chat/messages/{id}/save-to-dashboard {dashboard_id, title?}`.
3. Backend looks up the message, inspects its widget payload, and creates the appropriate widget on the chosen dashboard (`save_chat_widget_to_dashboard` in [services/dashboards.py](../backend/src/budget_trace_backend/services/dashboards.py)).

The Add-widget drawer is metric-only; there is no path to construct a snapshot widget from there. Editing an existing snapshot lets the user retitle but not change its data source or params.

## REST surface

All routes are gated behind the `widgets` feature flag (defaults **on**). 403 + `feature_disabled` when off.

| Method | Path | Returns |
|--------|------|---------|
| `GET` | `/dashboards` | `[DashboardSummary]` |
| `POST` | `/dashboards` `{name}` | `DashboardSummary` (201) |
| `GET` | `/dashboards/{id}` | `DashboardOut` (also marks as last-viewed) |
| `PATCH` | `/dashboards/{id}` `{name?, time_range?}` | `DashboardSummary` |
| `DELETE` | `/dashboards/{id}` | `{deleted_id}` |
| `POST` | `/dashboards/{id}/widgets` `WidgetCreate` | `WidgetOut` (201) |
| `PATCH` | `/dashboards/{id}/widgets/{wid}` `WidgetUpdate` | `WidgetOut` |
| `DELETE` | `/dashboards/{id}/widgets/{wid}` | `{deleted_id}` |
| `PUT` | `/dashboards/{id}/layout` `{layouts: [{id, x, y, w, h}]}` | `{updated: N}` |
| `GET` | `/dashboards/{id}/widgets/{wid}/data` | `{type, data, is_snapshot}` shaped per widget type |
| `GET` | `/widget-metrics` | `{metrics: [...], widget_min_sizes: {...}, time_range_presets: [...]}` |
| `POST` | `/chat/messages/{id}/save-to-dashboard` `{dashboard_id, title?}` | `WidgetOut` (201) |
| `GET` | `/ai-widget-audit` | `{rows: [{id, message_id, widget_type, fallback_reason, user_question, created_at}]}` |

```jsonc
// DashboardOut
{
  "id": 1, "name": "Monthly review",
  "time_range": { "preset": "last_3_months",
                  "custom_start": null, "custom_end": null },
  "created_at": "2026-05-10T18:23:01.234+00:00",
  "updated_at": "2026-05-10T18:23:01.234+00:00",
  "widgets": [/* WidgetOut */]
}

// WidgetOut
{
  "id": 17, "dashboard_id": 1, "type": "pie",
  "title": "April breakdown",
  "layout": { "x": 0, "y": 0, "w": 2, "h": 2 },
  "data_source": { "kind": "metric", "metric_id": "spend_by_category",
                   "params": { "parent_category": null } },
  "config": {},
  "created_at": "...", "updated_at": "..."
}

// WidgetDataOut (GET /dashboards/{id}/widgets/{wid}/data)
{
  "type": "pie",
  "data": { "slices": [...], "total": 412.10 },
  "is_snapshot": false
}
```

## Insights AI integration

The chat AI's output tool, `present_to_user`, takes:

- `text: str` — what the user reads.
- `widget: WidgetSpec?` — polymorphic `{type, title, data?, metric_id?, metric_params?, time_range?, fallback_reason?}`. The system prompt strongly encourages the AI to set `metric_id` + `metric_params` (re-runnable) and provide a `time_range` for the chat-time window. The orchestrator resolves the metric server-side so the data shown in chat is exactly what a dashboard with the same range would render. Snapshot fallback (with `fallback_reason`) is allowed when no registry metric fits.
- `chart: ChartSpec?` — **deprecated**, kept for backward compatibility. If present, it's auto-wrapped as a timeseries widget via [`widget_from_chart`](../backend/src/budget_trace_backend/models.py).

The system prompt (see [`chat.py::_SYSTEM_PROMPT_TEMPLATE`](../backend/src/budget_trace_backend/chat.py)) inlines the full metric catalogue (id, label, compatible widget types, params) so the AI can pick a metric and supply valid params without an extra tool call. It tells the model:

> Strongly prefer emitting `metric_id` + `metric_params` so the widget is savable to a dashboard. Only omit them when no registry metric can express the answer; include a short `fallback_reason` for audit.

The chat orchestrator parses `widget` first, falling back to `chart` → wrapped. For metric-backed widgets it calls `widget_metrics.resolve_metric_data` to produce the chat snapshot. The full payload (incl. `metric_id` / `metric_params` when present) is persisted on the assistant message (`chat_messages.widget_json`) and the frontend renders it inline in the transcript via the same `WidgetCard` used on dashboards (`previewData` short-circuits the data fetch).

Snapshot fallbacks trigger an `ai_widget_audit` row, written by the chat-session route after the assistant message is persisted. `GET /ai-widget-audit` surfaces these rows so the curated registry can be grown to cover recurring gaps.

## Frontend shape

- **Tab indices** — `0=Categories, 1=Expenses, 2=Widgets, 3=Insights`. Widgets is gated on `me.features.widgets`; when off, nav lists filter it out and the AppShell's `_buildScreen` redirects to Categories. See [app_shell.dart](../frontend/lib/widgets/app_shell.dart), [bottom_tabs.dart](../frontend/lib/widgets/bottom_tabs.dart), [side_nav.dart](../frontend/lib/widgets/side_nav.dart).
- **Tab root** ([widgets_screen.dart](../frontend/lib/screens/widgets_screen.dart)) — list / empty-state / auto-open. Reads `me.last_dashboard_id` to land on the last-viewed dashboard when there are ≥2.
- **Dashboard view** ([dashboard_screen.dart](../frontend/lib/screens/dashboard_screen.dart)) — header (back, dashboard switcher, time-range picker, "Add widget"), then a layout that branches on width:
  - **Desktop (≥600 dp)**: `DashboardGrid` — 6-column absolute-positioned grid with drag + corner-resize handles available at all times (no edit mode). The snap-grid overlay only appears while a gesture is in flight.
  - **Mobile (<600 dp)**: `_MobileDashboardList` — a vertical `ListView` of full-width 260 dp tiles ordered by `createdAt` ascending. No drag, no resize. The stored layout is preserved in the DB so opening the same dashboard on a wider screen restores the desktop arrangement.
- **Widget chrome** ([widget_card.dart](../frontend/lib/widgets/dash_widgets/widget_card.dart)) — titlebar (title, refresh `Icons.refresh`, edit, delete), `Expanded` body, loading / error / empty states. `revalidationKey` is an external bust-cache string passed by the parent.
- **Renderers** ([dash_widgets/](../frontend/lib/widgets/dash_widgets/)) — one file per widget type. Each consumes the per-type data shape and renders via theme-aware colours from `context.bt`.
- **Add-widget drawer** ([add_widget_drawer.dart](../frontend/lib/widgets/dash_widgets/add_widget_drawer.dart)) — modal bottom sheet on mobile, fractional sheet on desktop. Flow: pick type → see description → optional title → metric or saved-insight source → params form. Live preview is fetched by creating a draft widget, hitting its data endpoint, then deleting it. Cheap and reuses the same code path; debounced.

## Drag/resize machinery

The grid's drag handle and resize handle each use a `_DragHandle` widget that exposes three callbacks: `onStart`, `onUpdate(dx, dy)`, `onEnd()`. The old design carried a single `onDelta(dx, dy, end)` callback; sending `(0, 0, true)` on release was misinterpreted as "drag back to origin" because the handler recomputed the layout from a zero delta. The three-callback split makes the commit explicit and delta-free.

The handle's `GestureDetector` uses `HitTestBehavior.translucent` so pointer events still reach the titlebar buttons underneath. The Flutter gesture arena resolves a stationary press in favour of the `InkResponse` (tap recognizer beats pan), so refresh / edit / delete are clickable across their full hit area even though the drag handle visually overlaps them.

Resize is corner-only, bottom-right. The clamp uses `math.max(1, columns - base.x)` for the max width and `math.min(min.w, maxW)` for the lower bound so the operation never throws on out-of-bounds inputs (e.g. a too-wide saved widget being viewed at a narrower breakpoint).

## Data model

See [data-model.md](data-model.md) for the cross-table ERD. Just the widgets-feature pieces:

```sql
CREATE TABLE dashboards (
    id                  INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id             INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    name                TEXT    NOT NULL,
    time_range_preset   TEXT    NOT NULL DEFAULT 'last_3_months',
    time_range_start    TEXT,                   -- only meaningful when preset = 'custom'
    time_range_end      TEXT,
    created_at          TEXT    NOT NULL,
    updated_at          TEXT    NOT NULL
);

CREATE TABLE widgets (
    id                INTEGER PRIMARY KEY AUTOINCREMENT,
    dashboard_id      INTEGER NOT NULL REFERENCES dashboards(id) ON DELETE CASCADE,
    type              TEXT    NOT NULL,         -- 'timeseries'|'bar'|'pie'|'query_value'|'table'|'treemap'
    title             TEXT    NOT NULL,
    layout_x          INTEGER NOT NULL,
    layout_y          INTEGER NOT NULL,
    layout_w          INTEGER NOT NULL,
    layout_h          INTEGER NOT NULL,
    data_source_json  TEXT    NOT NULL,         -- {kind: "metric", metric_id, params} | {kind: "snapshot"}
    config_json       TEXT    NOT NULL,         -- per-type display options; usually {}
    snapshot_json     TEXT,                     -- frozen {type, title, data} payload when kind = 'snapshot'
    created_at        TEXT    NOT NULL,
    updated_at        TEXT    NOT NULL
);

CREATE TABLE ai_widget_audit (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    message_id      INTEGER REFERENCES chat_messages(id) ON DELETE CASCADE,
    widget_type     TEXT    NOT NULL,
    fallback_reason TEXT,
    user_question   TEXT,
    created_at      TEXT    NOT NULL
);
```

Also: `users.last_dashboard_id` (added via `_add_column_if_missing`) — the dashboard the user was last viewing, so the Widgets tab reopens on the same one. `GET /dashboards/{id}` has a side-effect of stamping it. `chat_messages.widget_json` carries the polymorphic payload (`{type, title, data, metric_id?, metric_params?, fallback_reason?}`) alongside the legacy `chart_json` (read prefers `widget_json`, falls back to wrapping `chart_json`). The legacy `saved_insights` table is dropped at every startup.

## Feature flag

`widgets` is a per-user boolean stored alongside `ai` in `users.features`. Default **on** (configured in [`features.py::DEFAULT_ON_FLAGS`](../backend/src/budget_trace_backend/features.py)) — flipping it off via `PATCH /me {features: {widgets: false}}` 403s every `/dashboards/*`, `/widget-metrics`, and `/saved-insights/*` route and removes the tab from the nav.

The env-var override (`BUDGET_TRACE_FEATURES=widgets`) still works for tests / CI.

## Common pitfalls

- **`category_path = "Unknown"`** is the literal string used by MCP tools to filter for `category_id IS NULL`. The drawer's category dropdown includes the path "Unknown" (the symbolic category row), but selecting it only makes sense as a *filter*, not as a real grouping. Same overload pitfall as in `list_transactions`.
- **`spend_forecast` ignores the dashboard time range.** Its `data` returns historical data for the trailing 12 months ending today, plus the projected horizon. If you add another metric with a similar self-contained window, set `uses_time_range=False` so the frontend can warn the user.
- **Snapshot widgets ignore the dashboard time range too** — that's the trade-off for letting the AI emit a one-off shape no metric covers. `WidgetDataOut.is_snapshot = true` is the signal for the chrome to badge the card and disable refresh. Don't add a code path that re-resolves a snapshot against the dashboard's range; the original query was never captured.
- **Snapshots are only built from chat saves.** `_validate_data_source` rejects `kind:"snapshot"` from external clients; only `save_chat_widget_to_dashboard` writes them.
- **Layout migrations.** Bumping a widget type's minimum size (e.g. `query_value` from 1×1 to 2×2) does *not* require a DB migration: `_widget_row_to_dict` clamps width and height up to current min on read. The DB row catches up the next time the layout is written.
- **Per-widget date params don't exist.** If you find yourself adding `start` / `end` to a metric's `params_schema`, stop — those live on the dashboard now, get passed via `time_range`, and the schema explicitly excludes them.
- **Drag-handle hit testing.** Don't switch the `_DragHandle`'s `HitTestBehavior` back to `opaque` — the titlebar buttons sit behind it and rely on `translucent` to receive taps.
- **Mobile is render-only.** Drag, resize, and edit-mode chrome only exist on the desktop branch. If you wire a new interactive affordance into a widget on `_MobileDashboardList`, expect the touch ergonomics to be poor and re-think it.
