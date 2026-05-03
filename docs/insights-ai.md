# Insights AI loop

This is the document to read before touching the chat flow. It captures *why* the architecture is shaped the way it is — design choices that aren't obvious from reading the code.

## Three tool surfaces, on purpose

The orchestrator gives Claude **MCP read tools + MCP write tools (gated) + one inline output tool**:

### Read tools (always available)

| Tool | What it does |
|------|--------------|
| `list_categories` | Returns the full category tree as `[{path, description, is_leaf, is_unknown}]`. |
| `list_transactions` | Filtered transaction list. Use the literal string `"Unknown"` as `category_path` to query uncategorised. |
| `aggregate_spending` | Day/week/month buckets. Set `by_category=true` (without `category_path`) for one series per top-level group. |
| `top_merchants` | Top-N merchants by spend in a window. |
| `compare_periods` | Total + abs/pct delta between two windows. Period A is the baseline (older). |
| `forecast` | Trailing-average or least-squares projection. Returns `{historical, forecast}` ready for the solid/dashed series convention. |

### Write tools (gated by the `ai_mutations` feature flag)

| Tool | What it does |
|------|--------------|
| `create_category(name, description, parent_path?)` | Creates a new category, returns the new path. |
| `rename_category(path, new_name)` | Renames the leaf component of a path. |
| `update_category_description(path, new_description)` | Replaces the AI-classification hint. |
| `move_category(path, new_parent_path?)` | Moves a subtree. Cannot move into self/descendants. |
| `delete_category(path)` | Deletes a category; transactions assigned to it auto-NULL. |
| `set_transaction_category(transaction_id, category_path?)` | Assign / re-assign / unassign one transaction. |
| `bulk_categorise_merchant(merchant, category_path?)` | "Every Netflix txn → Fun." Returns `{updated: N}`. |
| `rename_merchant(from_merchant, to_merchant)` | Bulk rename across all matching rows. |
| `update_transaction(transaction_id, ...)` | Single-row edit (date / merchant / amount / category). |
| `delete_transaction(transaction_id)` | Hard delete. |

When `ai_mutations` is off, write tools are not registered and the system prompt's "you can also write" addendum is omitted. Every write-tool call is logged at INFO level so anything the AI did is recoverable from the backend log.

### Output tool

| Tool | What it does |
|------|--------------|
| `present_to_user` | **Inline only.** The structured-output channel. Args: `text: str` (required), `chart: ChartSpec?` (optional). |

The MCP tools (read + write) are portable — point any MCP client at the same server and they keep working. `present_to_user` is *this app's* output schema and lives in the orchestrator. Splitting them keeps the read API clean.

Categories use **paths** (`"Living / Grocery"`) as the AI-facing identifier; transactions use integer ids the AI fetches via `list_transactions`. Path-based wrappers in `services/categories.py` and `services/transactions.py` resolve paths to ids server-side so the model never has to thread integers through its reasoning.

## The contract

System prompt ([chat.py](../backend/src/budget_trace_backend/chat.py)) tells Claude:

> Your final action MUST be exactly one call to `present_to_user`. Do NOT emit text outside of that tool call. Use a `chart` argument only when a time-series visualisation would meaningfully strengthen your answer.

The orchestrator loop is dumb: dispatch tool calls, append `tool_result`s, send back to Claude, repeat. The **only exit conditions** are:
1. Claude calls `present_to_user` → those args become the HTTP response.
2. Claude emits text without any tool call → fallback message returned.
3. Iteration cap reached (`MAX_TOOL_ITERATIONS = 12`) → fallback message returned.

This is stricter than letting the model reply with freeform text. It guarantees the response is structured and avoids the "AI says it ran a query but actually hallucinated the numbers" failure mode.

## ChartSpec shape

Backend ([backend/src/budget_trace_backend/models.py](../backend/src/budget_trace_backend/models.py)):

```python
class ChartSpec(BaseModel):
    title: str
    y_axis_label: str | None = None
    x_axis_label: str | None = None
    x_tick_labels: list[str] | None = None
    series: list[ChartSeriesSpec]   # each has label, style, points

class ChartSeriesSpec(BaseModel):
    label: str
    style: Literal["solid", "dashed"] = "solid"
    points: list[ChartPoint]        # x and y both float
```

Frontend ([frontend/lib/models/chart_spec.dart](../frontend/lib/models/chart_spec.dart)) mirrors this in camelCase and includes `buildChart()` to render it as a `TimeseriesChart`.

**Conventions the AI must follow** (encoded in the system prompt):

- `solid` for observed/historical data, `dashed` for forecasts.
- `x_tick_labels` should be human-readable labels (e.g. `["Feb '26", "Mar '26", "Apr '26"]`) when x represents time periods.
- `x` values just need to be monotonic — the chart auto-scales the axis. The AI typically uses 0…N-1 indices.

## Why no streaming yet

The orchestrator may run several tool-call rounds before getting to `present_to_user`. Streaming each round to the client is doable but adds complexity (multiple `ChatMessage` updates per turn, partial chart rendering). The MVP keeps it synchronous and shows "Thinking…" until the resolved message arrives. Add streaming when "Thinking…" feels too slow in practice.

## Where the chart shows

`InsightsScreen._latestChart` walks the message list backwards and returns the first chart it finds. That chart is rendered in the sticky `_ChartPanel` slot between the header and the transcript. When the user asks a new question and the next response has its own chart, the slot updates. Old charts scroll out of the chat but their text stays in the transcript.

## Common pitfalls

- **Tool argument names** must exactly match Python signatures — the JSON schema is auto-generated from `inspect.signature` in `chat.py::_build_tool_definition`. Renaming a parameter changes the schema.
- **"Unknown" path** is overloaded. The string literal `"Unknown"` filters for `category_id IS NULL` (uncategorised transactions). The actual `Unknown` category row in the DB has no transactions assigned to it. Don't change this without updating both the SQL filters and the system prompt.
- **Date strings** are always ISO `YYYY-MM-DD`. Path strings always use ` / ` with spaces around the separator. See [conventions.md](conventions.md).
