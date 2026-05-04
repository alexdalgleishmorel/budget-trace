# Conventions

Cross-cutting things that are easy to get wrong and cause half-hour debugging sessions. Read this before writing anything that crosses the Python ↔ Dart boundary.

## Dates

- **Always ISO `YYYY-MM-DD`.** No locale-specific formats anywhere.
- The backend stores `transactions.date` as a TEXT column in this format. SQLite sorts and compares it correctly because the format is lexicographically ordered.
- The frontend's existing `Transaction.date` field is a *display* string like `"Mar 01"` (legacy from the original mock). It does **not** cross the wire to the backend. The backend's seed has its own ISO dates; the frontend doesn't see them today.
- When the AI returns dates inside a `ChartSpec` (e.g. `x_tick_labels`), they're already human-formatted ("Feb '26"). Don't second-guess.

## Category paths

- Separator is exactly `" / "` (space + slash + space). Defined as `PATH_SEPARATOR` in `db.py`.
- Top-level groups are `"House"`, `"Living"`, `"Savings"`, `"Unknown"`.
- The root "Budget" is **not** a valid path — the recursive CTE excludes it.
- The string `"Unknown"` is overloaded: as a `category_path` filter it means "uncategorised" (`category_id IS NULL`), not the actual Unknown row. See [data-model.md](data-model.md#path-strings).

## JSON casing across the wire

- **Backend → wire: snake_case.** Pydantic's default. Field names like `y_axis_label`, `x_tick_labels`, `period_start`.
- **Dart side: camelCase.** The `fromJson` constructors in `chart_spec.dart` translate manually. There's no auto-codegen; if you add a field, add it in both places.

| Backend (snake_case) | Dart (camelCase) |
|----------------------|------------------|
| `y_axis_label` | `yAxisLabel` |
| `x_axis_label` | `xAxisLabel` |
| `x_tick_labels` | `xTickLabels` |

## Tool naming

- MCP tool function names are exactly the keys of `READ_TOOLS` and `WRITE_TOOLS` in `mcp_server.py`.
- The Anthropic tool schema is auto-generated from `inspect.signature` in `chat.py::_build_tool_definition`. Renaming a Python parameter renames the JSON-schema property.
- Don't rename `present_to_user` — the orchestrator's exit condition matches on this exact string.
- Write tools are always registered when chat is reachable. The single `ai` flag gates the chat as a whole — when it's on, the AI gets every read + write tool.

## HTTP error envelope

FastAPI wraps `HTTPException(detail=...)` payloads under `detail` on the wire. Routes raise:

```python
raise HTTPException(status_code=409, detail={"code": "conflict", "message": "..."})
```

Frontend's `decodeOrThrow` ([api_base.dart](../frontend/lib/services/api_base.dart)) unwraps the `detail` and throws an `ApiException(statusCode, code, message)`.

## Feature flags

One master flag: **`ai`**. When on, all of these turn on together:
- `POST /transactions/import?parser=ai` returns 200 instead of 403.
- `POST /chat/sessions/{id}/messages` (the only Anthropic-hitting chat route) returns 200 instead of 403; historical reads stay open regardless.
- Every successful import (CSV or AI) triggers auto-categorization on the freshly inserted rows. CSV-only flows still work with `ai` off.

Per-user (single user today, id=1). DB-backed JSON in `users.features`. Flip it via the Account screen (`PATCH /me`) or the `BUDGET_TRACE_FEATURES=ai` env var (which still wins for local dev / tests). See [account.md](account.md).

## Same-merchant → same category

Whenever a non-null category is assigned to a transaction (manual UI edit, REST `PATCH /transactions/{id}`, or the auto-categorizer), the assignment cascades to every other transaction with the exact same `merchant` string — including rows that were previously assigned to a different category. The invariant: the same merchant text always maps to the same category. Implementation: `_cascade_category_to_same_merchant` in [services/transactions.py](../backend/src/budget_trace_backend/services/transactions.py), called from `update_transaction`; the auto-categorizer in [importers/categorizer.py](../backend/src/budget_trace_backend/importers/categorizer.py) achieves the same effect by running per-merchant bulk UPDATEs (and deduping the model's output by merchant — first assignment wins on conflicts). Unassign (setting category to NULL) is *not* part of the invariant — it touches only the one row.

## Money

- Backend `transactions.amount` is `REAL`, in dollars, **positive for spend**.
- Aggregations use `ROUND(SUM(amount), 2)` to avoid float drift in the wire format.
- The frontend's `Transaction.amount` is also `double` and positive — same convention.

## Determinism

- The seed (`seed.py`) is reproducible: `random.seed(42)` + idempotent (re-running clears + reseeds). Never rely on transaction IDs across re-seeds — only `(date, merchant, amount, category_id)` is stable.

## Linting / formatting

- Backend: no formatter configured yet. Reasonable PEP 8 by hand.
- Frontend: `flutter analyze` must pass with zero issues before considering anything done. `dart format lib/` for layout.
