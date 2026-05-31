# REST API

The Flutter app's Categories and Expenses tabs read and write through these endpoints. The Insights tab uses the same backend but goes through `POST /chat` instead.

Base URL is configurable via `--dart-define=API_BASE_URL=...` (default `http://localhost:8000`).

## Conventions

- All bodies and responses are **snake_case JSON**. Dart-side mirrors are camelCase via the `fromJson` constructors.
- Errors share an envelope:
  ```json
  { "detail": { "code": "string_code", "message": "human description" } }
  ```
  FastAPI wraps it under `detail`; the Flutter `decodeOrThrow` helper unwraps and throws an `ApiException`.
- Status codes: `409` for "rule violation" (e.g. delete root, duplicate hash), `404` for "not found", `422` for malformed input, `403` for "feature flag off". Anything else is a real bug.

## Categories

| Method | Path | Body | Returns |
|--------|------|------|---------|
| `GET` | `/categories` | — | `[CategoryOut]` — flat list with full path strings, ordered by path |
| `POST` | `/categories` | `CategoryCreate` | `CategoryOut` (201) |
| `GET` | `/categories/{id}` | — | `CategoryOut` |
| `PATCH` | `/categories/{id}` | `CategoryUpdate` | `CategoryOut` |
| `DELETE` | `/categories/{id}` | — | `CategoryDeleted` summary |

```jsonc
// CategoryOut
{
  "id": 7,
  "name": "Grocery",
  "description": "Supermarket and grocery-store food shopping",
  "parent_id": 3,
  "path": "Living / Grocery",
  "is_leaf": true,
  "is_unknown": false
}

// CategoryCreate
{ "name": "Subscriptions", "description": "...", "parent_id": 3 }

// CategoryUpdate — all optional. Including a key with `null` is meaningful
// (clears the field); omitting it means "no change".
{ "name": "Entertainment", "description": null, "parent_id": 12 }

// CategoryDeleted
{ "deleted_id": 7, "descendants_deleted": 0, "transactions_unassigned": 23 }
```

Edge cases that return `409`:
- Editing or deleting the root or the `Unknown` category.
- Moving a category into itself or one of its descendants.

## Transactions

| Method | Path | Body / query | Returns |
|--------|------|--------------|---------|
| `GET` | `/transactions` | query params below | `[TransactionOut]` |
| `POST` | `/transactions` | `TransactionCreate` | `TransactionOut` (201) |
| `PATCH` | `/transactions/{id}` | `TransactionUpdate` | `TransactionOut` |
| `DELETE` | `/transactions/{id}` | — | `{ "deleted_id": int }` |
| `POST` | `/transactions/bulk_rename` | `{ from_merchant, to_merchant }` | `{ "updated": int }` |
| `POST` | `/transactions/import` | multipart | see [upload.md](upload.md) |

```jsonc
// TransactionOut
{
  "id": 1024,
  "date": "2026-04-15",
  "merchant": "TRADER JOES #142",
  "amount": 84.21,
  "category_id": 7,
  "category_path": "Living / Grocery"
}
```

`GET /transactions` query parameters:

| Name | Type | Default |
|------|------|---------|
| `start_date` | ISO date | unbounded |
| `end_date` | ISO date | unbounded |
| `category_id` | int | — |
| `category_path` | string | — (`"Unknown"` filters for uncategorised) |
| `uncategorised` | bool | false |
| `merchant_query` | string | — |
| `limit` | int (1-500) | 100 |

`PATCH /transactions/{id}` is the **assign / unassign endpoint** as well as the general edit endpoint:

- Assign: `{ "category_id": 7 }`
- Unassign: `{ "category_id": null }` (key must be present — omitting it means "no change")
- Reassign: same body with a different id

The CategoryChip dropdown and the TransactionEditModal in the Expenses screen both call this exact shape.

## Me — settings

| Method | Path | Body | Returns |
|--------|------|------|---------|
| `GET` | `/me` | — | `{ features: { ai, widgets }, theme, providers: [...], selected_provider, selected_provider_key_available, selected_model, available_models: [...], ai_spent_usd, last_dashboard_id }` |
| `PATCH` | `/me` | partial: `{ features?, theme?, selected_provider?, selected_model?, provider_keys? }` | same as GET |
| `POST` | `/me/models/refresh` | — | `{ provider: { provider, ok, discovered_count, skipped, error }, available_models: [...] }` — fetches the selected provider's live models |

Key values themselves are **never** echoed — each entry in `providers` exposes only `api_key_set` (plus `env_fallback` when the matching env var is set). PATCH is partial: omit a field to leave it unchanged. Set or clear per-provider keys with `provider_keys: { "<provider>": "sk-..." | null }`; an empty string is a 422 (use `null` to clear). Provider-first model selection: set `selected_provider` (anthropic/openai/google — switching it clears the model), fetch that provider's models with `POST /me/models/refresh`, then set `selected_model` to any fetched id (`null` clears). There is no hardcoded model catalog. `theme` is one of `system`, `light`, `dark`. `features` is a partial dict — today the only flag is `ai`. Full schema in [account.md](account.md).

Single-user dev today (id=1). The `BUDGET_TRACE_FEATURES=ai` env var still wins over the DB on the read path, useful for tests / CI. See [account.md](account.md) for the auth-TODO.

## Chat

Routes documented in [insights-ai.md](insights-ai.md). `POST /chat/sessions/{id}/messages` is the only AI-calling route — it returns `403 feature_disabled` when `ai` is off, and `400 ai_key_missing` when `ai` is on but no API key is configured for the selected model's provider. Historical `GET`s and `GET /chat/help` stay open regardless.

Assistant turns may carry an optional `widget` field — a polymorphic `{type, title, data, metric_id?, metric_params?, fallback_reason?}` payload that the frontend renders inline in the transcript. See [widgets.md](widgets.md#widget-types) for the per-type `data` shape. The `metric_id` / `metric_params` fields, when present, mark the widget as re-runnable — saving it to a dashboard preserves the query rather than the bytes.

## Dashboards & widgets

All routes are gated behind the `widgets` feature flag (defaults on). 403 + `feature_disabled` when off. Full reference in [widgets.md](widgets.md).

| Method | Path | Body | Returns |
|--------|------|------|---------|
| `GET` | `/dashboards` | — | `[DashboardSummary]` |
| `POST` | `/dashboards` | `{ name }` | `DashboardSummary` (201) |
| `GET` | `/dashboards/{id}` | — | `DashboardOut` (and stamps `users.last_dashboard_id`) |
| `PATCH` | `/dashboards/{id}` | `{ name?, time_range? }` | `DashboardSummary` |
| `DELETE` | `/dashboards/{id}` | — | `{ deleted_id }` |
| `POST` | `/dashboards/{id}/widgets` | `WidgetCreate` | `WidgetOut` (201) |
| `PATCH` | `/dashboards/{id}/widgets/{wid}` | `WidgetUpdate` (any subset of title, layout, data_source, config) | `WidgetOut` |
| `DELETE` | `/dashboards/{id}/widgets/{wid}` | — | `{ deleted_id }` |
| `PUT` | `/dashboards/{id}/layout` | `{ layouts: [{id, x, y, w, h}] }` | `{ updated: N }` |
| `GET` | `/dashboards/{id}/widgets/{wid}/data` | — | `{ type, data, is_snapshot }` shaped per widget type |
| `GET` | `/widget-metrics` | — | `{ metrics: [...], widget_min_sizes: {...}, time_range_presets: [...] }` |
| `POST` | `/chat/messages/{id}/save-to-dashboard` | `{ dashboard_id, title? }` | `WidgetOut` (201) |
| `GET` | `/ai-widget-audit` | — | `{ rows: [{id, message_id, widget_type, fallback_reason, user_question, created_at}] }` |

Time range is a dashboard-level field that applies to every widget on it; per-widget date params don't exist. Presets (`last_30_days`, `last_3_months`, `last_6_months`, `last_12_months`, `month_to_date`, `year_to_date`, `all_time`, `custom`) resolve to concrete dates server-side at request time. Use `preset: "custom"` with `custom_start` / `custom_end` for an arbitrary window. Changing the range bumps every widget's `updated_at` so the frontend re-fetches.

Layout `PUT` validates each entry against the widget type's minimum size (`/widget-metrics → widget_min_sizes`). Layouts stored below the current minimum are auto-clamped on **read** so a min-size bump doesn't require a DB migration.

`WidgetCreate.data_source` accepts only `kind:"metric"` from external clients. Snapshot widgets (`kind:"snapshot"`) are exclusively created by `POST /chat/messages/{id}/save-to-dashboard` when the source message's widget has no `metric_id`. The data endpoint surfaces `is_snapshot: true` on those widgets so the frontend can badge them and disable refresh.

## What's *not* here

- No auth. Single-user. All requests act as user id 1.
- No pagination beyond `?limit=`. If you need page 2 of transactions today, narrow the date window. Cursor-based pagination is a follow-up if/when the seed grows past 500 rows in a window.
- No bulk transaction operations beyond `bulk_rename`. Categorising every Netflix charge at once is an MCP write tool (`bulk_categorise_merchant`); add a REST endpoint if a UI ever needs it.
