"""Chat orchestrator — the loop that turns one user message into one response.

We bridge two tool surfaces:

1. **Data tools** — defined in ``mcp_server.TOOL_FUNCTIONS``. The same Python
   functions back the standalone MCP server *and* the in-process Anthropic
   tool-use loop here. Single source of truth.

2. **One inline output tool — ``present_to_user``**. The system prompt forces
   the model to call this tool exactly once at the end. Its arguments *are*
   the HTTP response body. This is how we get structured output (text +
   optional chart) without parsing freeform model text.

Loop:
  - Build tool definitions + system prompt.
  - Send to Anthropic Messages API.
  - While the response has tool_use blocks: dispatch each, append a
    tool_result, send back.
  - When the response has a `present_to_user` tool_use, capture its args and
    return as the response. Cap iterations to keep runaway loops in check.
"""

from __future__ import annotations

import inspect
import json
import logging
from datetime import date
from typing import Any, get_type_hints

from .mcp_server import READ_TOOLS, WRITE_TOOLS
from .models import ChartSpec, ChatRequest, ChatResponse
from .services import ai_usage
from .services.anthropic_client import get_client, get_model

log = logging.getLogger(__name__)

MAX_TOOL_ITERATIONS = 12

_SYSTEM_PROMPT_TEMPLATE = """You are the Insights assistant inside the Budget Trace app. The user asks free-form questions about their spending; you answer using the data tools provided.

Rules:
- Use the MCP-style data tools (list_categories, list_transactions, aggregate_spending, top_merchants, compare_periods, forecast) to fetch whatever you need. The tools operate on the user's actual SQLite-backed transaction store.
- All dates are ISO format ("YYYY-MM-DD"). Category paths use " / " as the separator (e.g. "Living / Grocery"). When the user names a category informally, call list_categories first and match against the descriptions.
- Today's date is {today}. When the user mentions a relative period ("April", "last month", "this quarter"), resolve it to an ISO date range using today's date and pass `start_date` / `end_date` to the data tools.
- Your final action MUST be exactly one call to `present_to_user`. Do NOT emit text outside of that tool call. The `text` argument is what the user will read; keep it concise (2-4 short sentences). Use a `chart` argument only when a time-series visualisation would meaningfully strengthen your answer (trends across months, period-over-period comparisons, forecasts). For one-off totals, top-N lists, or yes/no answers, omit the chart.
- When you do return a chart: pick `solid` for observed/historical data and `dashed` for forecasts. Set `x_tick_labels` to human-readable period labels matching the points (e.g. ["Feb '26", "Mar '26", "Apr '26"]).

You also have write tools for editing categories and transactions (create_category, rename_category, update_category_description, move_category, delete_category, set_transaction_category, bulk_categorise_merchant, rename_merchant, update_transaction, delete_transaction). When the user asks you to make changes, perform them, then briefly summarise what you did in the `text` argument of `present_to_user`. For destructive operations (delete_category, delete_transaction), state explicitly that the change is done and not reversible from the chat. Never call write tools speculatively — only when the user has clearly asked for a change.
"""


def _system_prompt() -> str:
    return _SYSTEM_PROMPT_TEMPLATE.format(today=date.today().isoformat())


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
    """Inspect a Python function signature and emit an Anthropic tool schema."""
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
        "name": name,
        "description": (fn.__doc__ or "").strip(),
        "input_schema": {
            "type": "object",
            "properties": properties,
            "required": required,
        },
    }


def _build_tool_definitions() -> list[dict]:
    tools = {**READ_TOOLS, **WRITE_TOOLS}
    return [_build_tool_definition(name, fn) for name, fn in tools.items()] + [PRESENT_TOOL]


PRESENT_TOOL: dict = {
    "name": "present_to_user",
    "description": (
        "Output channel. Call exactly once at the end of your turn. The text "
        "field is what the user reads; the optional chart field renders as a "
        "time-series chart pinned above the chat."
    ),
    "input_schema": {
        "type": "object",
        "properties": {
            "text": {"type": "string"},
            "chart": {
                "type": "object",
                "description": "Optional time-series chart spec.",
                "properties": {
                    "title": {"type": "string"},
                    "y_axis_label": {"type": "string"},
                    "x_axis_label": {"type": "string"},
                    "x_tick_labels": {
                        "type": "array",
                        "items": {"type": "string"},
                        "description": "Optional list of x-axis tick labels.",
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
}


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


# ── Public entry point ──────────────────────────────────────────────────────


def run_chat(request: ChatRequest) -> ChatResponse:
    client = get_client()
    model = get_model()
    tools = _build_tool_definitions()
    system_prompt = _system_prompt()
    messages: list[dict] = [
        {"role": m.role, "content": m.content} for m in request.messages
    ]

    # Sum usage across every messages.create call in this turn — the tool-use
    # loop typically emits 2-4 of them. We persist a single ai_usage row at
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
        resp = client.messages.create(
            model=model,
            max_tokens=2048,
            system=system_prompt,
            tools=tools,
            messages=messages,
        )
        _accumulate(totals, resp.usage)

        # If the model emits a present_to_user call we're done.
        for block in resp.content:
            if getattr(block, "type", None) == "tool_use" and block.name == "present_to_user":
                args = block.input or {}
                chart = None
                if args.get("chart"):
                    try:
                        chart = ChartSpec(**args["chart"])
                    except Exception:
                        log.exception("invalid chart spec from model: %r", args.get("chart"))
                return _finalize(ChatResponse(text=str(args.get("text", "")), chart=chart))

        # Otherwise, dispatch any data-tool calls and continue.
        tool_uses = [b for b in resp.content if getattr(b, "type", None) == "tool_use"]
        if not tool_uses:
            # Model said something but didn't call present_to_user. Salvage any
            # plain text and bail.
            text_blocks = [b.text for b in resp.content if getattr(b, "type", None) == "text"]
            return _finalize(
                ChatResponse(text="\n".join(text_blocks).strip() or _FALLBACK, chart=None)
            )

        # Append the assistant turn and the tool_result entries, then re-loop.
        messages.append({"role": "assistant", "content": [b.model_dump() for b in resp.content]})
        tool_results = []
        for tu in tool_uses:
            result = _dispatch(tu.name, tu.input or {})
            tool_results.append({
                "type": "tool_result",
                "tool_use_id": tu.id,
                "content": json.dumps(result, default=str),
            })
        messages.append({"role": "user", "content": tool_results})

    return _finalize(ChatResponse(text=_FALLBACK, chart=None))


def _accumulate(totals: dict, usage: Any) -> None:
    if usage is None:
        return
    for f in totals:
        totals[f] += int(getattr(usage, f, 0) or 0)


_FALLBACK = "Sorry, I couldn't put that together — try rephrasing the question."
