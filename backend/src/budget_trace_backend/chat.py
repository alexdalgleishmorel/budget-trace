"""Chat orchestrator — the loop that turns one user message into one response.

We bridge two tool surfaces:

1. **Data tools** — defined in ``mcp_server.TOOL_FUNCTIONS``. The same Python
   functions back the standalone MCP server *and* the in-process tool-use
   loop here. Single source of truth.

2. **One inline output tool — ``present_to_user``**. The system prompt forces
   the model to call this tool exactly once at the end. Its arguments *are*
   the HTTP response body. This is how we get structured output (text +
   optional chart) without parsing freeform model text.

Loop:
  - Build OpenAI/LiteLLM-style tool definitions + system prompt.
  - Send to the selected model via services/ai/client.py::chat().
  - While the response has tool_calls: dispatch each, append a tool message,
    send back.
  - When the response has a `present_to_user` tool call, capture its args
    and return as the response. Cap iterations to keep runaway loops in check.
"""

from __future__ import annotations

import inspect
import json
import logging
from datetime import date
from typing import Any, get_type_hints

from .mcp_server import READ_TOOLS, WRITE_TOOLS
from .models import ChatRequest, ChatResponse, WidgetSpec, widget_from_chart
from .services import ai_usage, widget_metrics
from .services.ai.client import chat as ai_chat
from .services.ai.client import get_selected_model

log = logging.getLogger(__name__)

MAX_TOOL_ITERATIONS = 12

_SYSTEM_PROMPT_TEMPLATE = """You are the Insights assistant inside the Budget Trace app. The user asks free-form questions about their spending; you answer using the data tools provided.

Rules:
- Use the MCP-style data tools (list_categories, list_transactions, aggregate_spending, top_merchants, compare_periods, forecast) to fetch whatever you need. The tools operate on the user's actual SQLite-backed transaction store.
- All dates are ISO format ("YYYY-MM-DD"). Category paths use " / " as the separator (e.g. "Living / Grocery"). When the user names a category informally, call list_categories first and match against the descriptions.
- Today's date is %%TODAY%%. When the user mentions a relative period ("April", "last month", "this quarter"), resolve it to an ISO date range using today's date and pass `start_date` / `end_date` to the data tools.
- Your final action MUST be exactly one call to `present_to_user`. Do NOT emit text outside of that tool call. The `text` argument is what the user will read; keep it concise (2-4 short sentences).

Strongly prefer answering with a `widget` whenever the answer carries data the user can see. A widget paired with one or two sentences of context is almost always better than text alone. Only omit the widget for clarifications, write-tool confirmations, or simple yes/no answers.

Pick the most intuitive widget type for the question — match the shape of the data, not your habit:

- `timeseries` — a line chart over time. Use for trends, seasonality, period-over-period changes, forecasts. The `data.chart` field is a ChartSpec with `series` (solid for observed, dashed for forecasts) and `x_tick_labels` (e.g. ["Feb '26", "Mar '26", "Apr '26"]).
- `bar` — ranked horizontal bars. Use for comparing buckets (categories side-by-side, weekly spend, top merchants by total). `data.categories` is a list of `{label, value}` in the order you want shown.
- `pie` — donut chart of how a total breaks down. Use when there are 3–7 groups summing to a meaningful whole and proportion matters. `data.slices` is a list of `{label, value}`; `data.total` is the sum.
- `query_value` — single headline number with an optional delta chip. Use for KPIs ("how much did I spend in April?", "average monthly grocery"). `data.value` is the number, `data.format` is `currency` | `number` | `percent`. Optional `data.comparison` is `{value, delta_abs, delta_pct, label}` where label might be "vs. March".
- `table` — rows of structured detail. Use for transactions, merchants with multiple metrics, or anything that's a list of records. `data.columns` is `[{key, label, align: "left"|"right"|"center", format?: "currency"|"number"}]`; `data.rows` is a list of objects keyed by column key.
- `treemap` — nested rectangles sized by value. Use when there are many categories and the user wants to see proportion across all of them at once. `data.nodes` is a list of `{label, value}`.

Do not set `widget.title` — the dashboard and chat surfaces no longer display per-widget titles. The widget's identity comes from its configuration (metric + params) and the surrounding text.

## Re-runnable widgets (strongly preferred)

Whenever the answer can be expressed as a curated metric, set `widget.metric_id` and `widget.metric_params` so the user can save the widget to a dashboard and have it re-render against the dashboard's time range. When you set `metric_id`, also set `widget.time_range` to the start/end window you want shown in the chat — the backend resolves the metric server-side using that window and fills in `data` automatically (you can leave `data` as an empty object).

Curated metrics available:

%%METRIC_CATALOGUE%%

If you set `metric_id`, the `metric_params` shape MUST match that metric's params schema above (omit unspecified optional params; pass null/empty for "no filter"). Pick the widget type from the metric's compatibility list.

## Snapshot fallback (only when no metric fits)

If the answer is a novel pattern that none of the metrics above can express — e.g. a custom multi-bucket comparison, a hand-rolled drill the registry doesn't cover — emit `widget.data` directly (as today), leave `metric_id`/`metric_params`/`time_range` unset, and set `widget.fallback_reason` to one short sentence explaining what the answer needed that the registry couldn't provide. The widget will still render in chat, but a "Snapshot" badge will tell the user it's frozen — saving it to a dashboard preserves it as-is and it will not react to the dashboard's time range.

Prefer a registry metric over a snapshot whenever both are reasonable. Snapshots are an audit signal for growing the registry.

You also have write tools for editing categories and transactions (create_category, rename_category, update_category_description, move_category, delete_category, set_transaction_category, bulk_categorise_merchant, rename_merchant, update_transaction, delete_transaction). When the user asks you to make changes, perform them, then briefly summarise what you did in the `text` argument of `present_to_user` — for write-only operations the widget should typically be omitted. For destructive operations (delete_category, delete_transaction), state explicitly that the change is done and not reversible from the chat. Never call write tools speculatively — only when the user has clearly asked for a change.
"""


def _metric_catalogue_text() -> str:
    lines: list[str] = []
    for m in widget_metrics.METRIC_REGISTRY.values():
        types = ", ".join(m.widget_types)
        param_descs: list[str] = []
        for p in m.params_schema:
            desc = p.get("description") or ""
            default = p.get("default")
            extra = f" (default: {default!r})" if default is not None else ""
            param_descs.append(
                f"  - `{p['name']}` ({p['type']}){extra}: {desc}"
            )
        params_block = "\n".join(param_descs) if param_descs else "  - (no params)"
        time_note = (
            "" if m.uses_time_range
            else "  - NOTE: this metric ignores `time_range` (uses its own fixed window)\n"
        )
        lines.append(
            f"- `{m.id}` — {m.description} Compatible widget types: {types}.\n"
            f"{time_note}{params_block}"
        )
    return "\n".join(lines)


def _system_prompt() -> str:
    # Use `.replace()` rather than `.format()` — the template contains
    # literal `{label, value}` (and similar) examples in the per-type
    # widget data-shape guides. `.format()` would parse those as field
    # references and KeyError on `'label, value'`.
    return (
        _SYSTEM_PROMPT_TEMPLATE
        .replace("%%TODAY%%", date.today().isoformat())
        .replace("%%METRIC_CATALOGUE%%", _metric_catalogue_text())
    )


# ── Tool schema generation ──────────────────────────────────────────────────


def _python_type_to_jsonschema(tp: Any) -> dict:
    """Best-effort mapping of common Python type annotations to JSON Schema."""
    import types
    import typing

    origin = typing.get_origin(tp)
    args = typing.get_args(tp)

    # Optional / Union with None
    if origin in (typing.Union, types.UnionType):
        non_none = [a for a in args if a is not type(None)]
        if len(non_none) == 1:
            return _python_type_to_jsonschema(non_none[0])
        return {"anyOf": [_python_type_to_jsonschema(a) for a in non_none]}

    if origin is list:
        return {"type": "array", "items": _python_type_to_jsonschema(args[0]) if args else {}}

    if origin is typing.Literal:
        return {"type": "string", "enum": list(args)}

    if tp in (str,):
        return {"type": "string"}
    if tp in (int,):
        return {"type": "integer"}
    if tp in (float,):
        return {"type": "number"}
    if tp in (bool,):
        return {"type": "boolean"}
    return {}


def _build_tool_definition(name: str, fn) -> dict:
    """Inspect a Python function signature and emit an OpenAI/LiteLLM tool schema."""
    sig = inspect.signature(fn)
    hints = get_type_hints(fn)
    properties: dict = {}
    required: list[str] = []
    for pname, param in sig.parameters.items():
        annotation = hints.get(pname, str)
        properties[pname] = _python_type_to_jsonschema(annotation)
        if param.default is inspect.Parameter.empty:
            required.append(pname)
    return {
        "type": "function",
        "function": {
            "name": name,
            "description": (fn.__doc__ or "").strip(),
            "parameters": {
                "type": "object",
                "properties": properties,
                "required": required,
            },
        },
    }


def _build_tool_definitions() -> list[dict]:
    tools = {**READ_TOOLS, **WRITE_TOOLS}
    return [_build_tool_definition(name, fn) for name, fn in tools.items()] + [PRESENT_TOOL]


PRESENT_TOOL: dict = {
    "type": "function",
    "function": {
        "name": "present_to_user",
        "description": (
            "Output channel. Call exactly once at the end of your turn. `text` "
            "is what the user reads. Pair it with a `widget` whenever the answer "
            "contains data the user can see — pick the widget type that best "
            "fits the shape of the data (timeseries for trends, query_value for "
            "a single number, pie/bar for categorical breakdowns, table for "
            "rows of detail, treemap for many-category proportion)."
        ),
        "parameters": {
            "type": "object",
            "properties": {
                "text": {"type": "string"},
                "widget": {
                    "type": "object",
                    "description": (
                        "Optional widget to render alongside the text. Prefer "
                        "setting `metric_id` + `metric_params` + `time_range` so "
                        "the widget is re-runnable on a dashboard; fall back to "
                        "supplying `data` directly only when no curated metric "
                        "fits the answer (see the system prompt's metric "
                        "catalogue)."
                    ),
                    "properties": {
                        "type": {
                            "type": "string",
                            "enum": [
                                "timeseries", "bar", "pie",
                                "query_value", "table", "treemap",
                            ],
                            "description": "Widget renderer to use.",
                        },
                        "title": {
                            "type": "string",
                            "description": (
                                "Deprecated — widget titles are no longer "
                                "shown. Leave this empty."
                            ),
                        },
                        "data": {
                            "type": "object",
                            "description": (
                                "Per-type payload. Required for snapshot widgets "
                                "(no metric_id); ignored when metric_id is set "
                                "(the backend resolves it from the metric). "
                                "timeseries: {chart: ChartSpec}. "
                                "bar: {categories: [{label, value}]}. "
                                "pie: {slices: [{label, value}], total}. "
                                "query_value: {value, format: 'currency'|'number'|"
                                "'percent', comparison?: {value, delta_abs, "
                                "delta_pct, label}}. "
                                "table: {columns: [{key, label, align, format?}], "
                                "rows: [{...}]}. "
                                "treemap: {nodes: [{label, value}]}."
                            ),
                        },
                        "metric_id": {
                            "type": "string",
                            "description": (
                                "Curated metric id from the catalogue in the "
                                "system prompt. When set, the widget is "
                                "re-runnable: saving it to a dashboard creates "
                                "a kind:metric widget that follows the "
                                "dashboard's time range."
                            ),
                        },
                        "metric_params": {
                            "type": "object",
                            "description": (
                                "Parameters for `metric_id` matching its "
                                "params_schema (excludes any date window — that "
                                "is supplied via `time_range`)."
                            ),
                        },
                        "time_range": {
                            "type": "object",
                            "description": (
                                "Date window the chat snapshot should cover. "
                                "Required when `metric_id` is set (used to "
                                "resolve the metric server-side). Ignored when "
                                "the widget is a snapshot."
                            ),
                            "properties": {
                                "start_date": {"type": "string"},
                                "end_date": {"type": "string"},
                            },
                            "required": ["start_date", "end_date"],
                        },
                        "fallback_reason": {
                            "type": "string",
                            "description": (
                                "One short sentence — only when no `metric_id` "
                                "is set — explaining what the answer needed "
                                "that the curated registry could not express. "
                                "Logged to ai_widget_audit to inform registry "
                                "growth."
                            ),
                        },
                    },
                    "required": ["type"],
                },
                "chart": {
                    "type": "object",
                    "description": (
                        "Deprecated. Prefer `widget` with type='timeseries' "
                        "instead — this field is kept for backward compatibility "
                        "and is auto-wrapped server-side."
                    ),
                    "properties": {
                        "title": {"type": "string"},
                        "y_axis_label": {"type": "string"},
                        "x_axis_label": {"type": "string"},
                        "x_tick_labels": {
                            "type": "array",
                            "items": {"type": "string"},
                        },
                        "series": {
                            "type": "array",
                            "items": {
                                "type": "object",
                                "properties": {
                                    "label": {"type": "string"},
                                    "style": {"type": "string", "enum": ["solid", "dashed"]},
                                    "points": {
                                        "type": "array",
                                        "items": {
                                            "type": "object",
                                            "properties": {
                                                "x": {"type": "number"},
                                                "y": {"type": "number"},
                                            },
                                            "required": ["x", "y"],
                                        },
                                    },
                                },
                                "required": ["label", "points"],
                            },
                        },
                    },
                    "required": ["title", "series"],
                },
            },
            "required": ["text"],
        },
    },
}


# ── Widget construction ─────────────────────────────────────────────────────


def _build_widget(raw: dict) -> WidgetSpec | None:
    """Validate the AI's widget payload and resolve the metric server-side
    when one was specified.

    Two paths:

    1. **Re-runnable** — `metric_id` + `metric_params` + `time_range` are
       set. We call ``widget_metrics.resolve_metric_data`` with the AI's
       chat-time window so the snapshot shown in chat is byte-identical
       to what re-running the same metric on a dashboard would produce.
       The chat-time window is intentionally NOT persisted on the
       widget; only the metric_id + metric_params are, so the dashboard's
       time range governs on save.

    2. **Snapshot fallback** — the AI emitted `data` and (ideally) a
       `fallback_reason`. We pass `data` through as-is; the audit row is
       written later by the chat session route once it has the
       persisted message id.
    """
    if not isinstance(raw, dict):
        return None

    metric_id = raw.get("metric_id")
    if metric_id:
        return _build_metric_widget(raw, metric_id)

    # Snapshot path — `data` is required.
    if not isinstance(raw.get("data"), dict):
        log.warning("AI emitted widget without metric_id or data: %r", raw)
        return None
    try:
        return WidgetSpec(
            type=raw["type"],
            title=raw.get("title") or "",
            data=raw["data"],
            fallback_reason=raw.get("fallback_reason"),
        )
    except Exception:
        log.exception("invalid snapshot widget spec from model: %r", raw)
        return None


def _build_metric_widget(raw: dict, metric_id: str) -> WidgetSpec | None:
    widget_type = raw.get("type")
    title = raw.get("title") or ""
    params = raw.get("metric_params") or {}
    if not isinstance(params, dict):
        log.warning("AI emitted metric_params that is not an object: %r", params)
        params = {}

    metric = widget_metrics.METRIC_REGISTRY.get(metric_id)
    if metric is None:
        log.warning("AI picked unknown metric_id %r; ignoring widget", metric_id)
        return None
    if widget_type not in metric.widget_types:
        log.warning(
            "AI picked widget type %r incompatible with metric %r; ignoring widget",
            widget_type, metric_id,
        )
        return None

    tr = raw.get("time_range") or {}
    start = tr.get("start_date")
    end = tr.get("end_date")
    if not (isinstance(start, str) and isinstance(end, str)):
        # Fall back to a sensible default so we never reject a valid
        # metric pick just because the AI forgot the window.
        start, end = widget_metrics.resolve_time_range("last_3_months")
    try:
        data = widget_metrics.resolve_metric_data(
            metric_id, params, widget_type,  # type: ignore[arg-type]
            time_range=(start, end),
        )
    except Exception:
        log.exception(
            "metric resolution failed for AI-picked widget %r / params %r",
            metric_id, params,
        )
        return None

    try:
        return WidgetSpec(
            type=widget_type,
            title=title,
            data=data,
            metric_id=metric_id,
            metric_params=params,
        )
    except Exception:
        log.exception("metric-backed widget spec failed validation: %r", raw)
        return None


# ── Tool dispatch ────────────────────────────────────────────────────────────


def _dispatch(tool_name: str, tool_input: dict) -> Any:
    available = {**READ_TOOLS, **WRITE_TOOLS}
    fn = available.get(tool_name)
    if fn is None:
        return {"error": f"unknown tool: {tool_name}"}
    if tool_name in WRITE_TOOLS:
        log.info("AI write tool %s called with %r", tool_name, tool_input)
    try:
        return fn(**tool_input)
    except Exception as e:  # surface tool errors back to the model
        log.exception("tool %s failed", tool_name)
        return {"error": str(e)}


def _parse_args(arguments_json: str) -> dict:
    if not arguments_json:
        return {}
    try:
        parsed = json.loads(arguments_json)
    except json.JSONDecodeError:
        log.warning("tool call had invalid JSON arguments: %r", arguments_json)
        return {}
    return parsed if isinstance(parsed, dict) else {}


# ── Public entry point ──────────────────────────────────────────────────────


def run_chat(request: ChatRequest) -> ChatResponse:
    model = get_selected_model()
    tools = _build_tool_definitions()
    system_prompt = _system_prompt()
    messages: list[dict] = [
        {"role": m.role, "content": m.content} for m in request.messages
    ]

    # Sum usage across every chat() call in this turn — the tool-use loop
    # typically emits 2-4 of them. We persist a single ai_usage row at
    # the end so per-chat spend is one row per user prompt.
    totals = {
        "input_tokens": 0,
        "output_tokens": 0,
        "cache_creation_input_tokens": 0,
        "cache_read_input_tokens": 0,
    }

    def _finalize(response: ChatResponse) -> ChatResponse:
        if any(totals.values()):
            recorded = ai_usage.record_usage(
                source="chat",
                model=model,
                usage=totals,
                chat_session_id=request.chat_session_id,
            )
            response.cost_usd = recorded["cost_usd"]
        if request.chat_session_id is not None:
            response.session_spent_usd = ai_usage.spent_for_session_local_usd(
                request.chat_session_id
            )
        return response

    for _ in range(MAX_TOOL_ITERATIONS):
        resp = ai_chat(
            model=model,
            system=system_prompt,
            messages=messages,
            tools=tools,
            max_tokens=2048,
        )
        _accumulate(totals, resp.get("usage") or {})

        tool_calls = resp.get("tool_calls") or []

        # If the model emits a present_to_user call we're done.
        for tc in tool_calls:
            if tc.get("name") == "present_to_user":
                args = _parse_args(tc.get("arguments_json", ""))
                widget: WidgetSpec | None = None
                # `widget` is the preferred argument; `chart` is the legacy
                # form (timeseries-only) auto-wrapped into a widget.
                if args.get("widget"):
                    widget = _build_widget(args["widget"])
                if widget is None and args.get("chart"):
                    try:
                        widget = widget_from_chart(args["chart"])
                    except Exception:
                        log.exception(
                            "invalid chart spec from model: %r", args.get("chart"),
                        )
                return _finalize(ChatResponse(
                    text=str(args.get("text", "")), widget=widget,
                ))

        if not tool_calls:
            # Model said something but didn't call any tools. Salvage the
            # plain text and bail.
            return _finalize(
                ChatResponse(text=(resp.get("content") or _FALLBACK).strip() or _FALLBACK,
                             widget=None)
            )

        # Append the assistant turn (with its tool_calls) and one tool-result
        # message per call, then re-loop.
        messages.append({
            "role": "assistant",
            "content": resp.get("content") or "",
            "tool_calls": [
                {
                    "id": tc["id"],
                    "type": "function",
                    "function": {
                        "name": tc["name"],
                        "arguments": tc.get("arguments_json", "") or "{}",
                    },
                }
                for tc in tool_calls
            ],
        })
        for tc in tool_calls:
            args = _parse_args(tc.get("arguments_json", ""))
            result = _dispatch(tc["name"], args)
            messages.append({
                "role": "tool",
                "tool_call_id": tc["id"],
                "content": json.dumps(result, default=str),
            })

    return _finalize(ChatResponse(text=_FALLBACK, widget=None))


def _accumulate(totals: dict, usage: dict) -> None:
    if not usage:
        return
    for f in totals:
        totals[f] += int(usage.get(f, 0) or 0)


_FALLBACK = "Sorry, I couldn't put that together — try rephrasing the question."
