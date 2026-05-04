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
| `GET` | `/me` | — | `{ features: { ai }, theme, anthropic_api_key_set }` |
| `PATCH` | `/me` | partial: `{ features?, theme?, anthropic_api_key? }` | same as GET |

The key value itself is **never** echoed — only `anthropic_api_key_set` is. PATCH is partial: omit a field to leave it unchanged. Pass `anthropic_api_key: null` to clear the key; an empty string is a 422 (use null instead). `theme` is one of `system`, `light`, `dark`. `features` is a partial dict — today the only flag is `ai`.

Single-user dev today (id=1). The `BUDGET_TRACE_FEATURES=ai` env var still wins over the DB on the read path, useful for tests / CI. See [account.md](account.md) for the auth-TODO.

## Chat

Routes documented in [insights-ai.md](insights-ai.md). `POST /chat/sessions/{id}/messages` is the only Anthropic-hitting route — it returns `403 feature_disabled` when `ai` is off, and `400 ai_key_missing` when `ai` is on but no key is configured. Historical `GET`s and `GET /chat/help` stay open regardless.

## What's *not* here

- No auth. Single-user. All requests act as user id 1.
- No pagination beyond `?limit=`. If you need page 2 of transactions today, narrow the date window. Cursor-based pagination is a follow-up if/when the seed grows past 500 rows in a window.
- No bulk transaction operations beyond `bulk_rename`. Categorising every Netflix charge at once is an MCP write tool (`bulk_categorise_merchant`); add a REST endpoint if a UI ever needs it.
