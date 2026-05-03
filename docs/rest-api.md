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

## Features

| Method | Path | Body | Returns |
|--------|------|------|---------|
| `GET` | `/me/features` | — | `{ ai_import: bool, ai_mutations: bool }` |

Single-user dev today; this returns the flags for user id 1. The `BUDGET_TRACE_FEATURES` env var (comma-separated flag names) overrides the DB for local dev — handy for flipping `ai_import` on without touching the DB.

## Chat

`POST /chat` is documented in [insights-ai.md](insights-ai.md). The contract there hasn't changed; what *did* change in this iteration is that the orchestrator gates write tools behind `ai_mutations`.

## What's *not* here

- No auth. Single-user. All requests act as user id 1.
- No pagination beyond `?limit=`. If you need page 2 of transactions today, narrow the date window. Cursor-based pagination is a follow-up if/when the seed grows past 500 rows in a window.
- No bulk transaction operations beyond `bulk_rename`. Categorising every Netflix charge at once is an MCP write tool (`bulk_categorise_merchant`); add a REST endpoint if a UI ever needs it.
