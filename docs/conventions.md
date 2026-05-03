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
- Write tools are only registered when `ai_mutations` is true (per-request, in `chat.py::run_chat`).

## HTTP error envelope

FastAPI wraps `HTTPException(detail=...)` payloads under `detail` on the wire. Routes raise:

```python
raise HTTPException(status_code=409, detail={"code": "conflict", "message": "..."})
```

Frontend's `decodeOrThrow` ([api_base.dart](../frontend/lib/services/api_base.dart)) unwraps the `detail` and throws an `ApiException(statusCode, code, message)`.

## Feature flags

- `ai_import` — gates `POST /transactions/import?parser=ai`. Off → 403.
- `ai_mutations` — gates registration of MCP write tools in the chat orchestrator. Off → AI is read-only.

Per-user (single user today, id=1). DB-backed JSON in `users.features`. The `BUDGET_TRACE_FEATURES` env var (comma-separated names) overrides the DB for local dev.

## Money

- Backend `transactions.amount` is `REAL`, in dollars, **positive for spend**.
- Aggregations use `ROUND(SUM(amount), 2)` to avoid float drift in the wire format.
- The frontend's `Transaction.amount` is also `double` and positive — same convention.

## Determinism

- The seed (`seed.py`) is reproducible: `random.seed(42)` + idempotent (re-running clears + reseeds). Never rely on transaction IDs across re-seeds — only `(date, merchant, amount, category_id)` is stable.

## Linting / formatting

- Backend: no formatter configured yet. Reasonable PEP 8 by hand.
- Frontend: `flutter analyze` must pass with zero issues before considering anything done. `dart format lib/` for layout.
