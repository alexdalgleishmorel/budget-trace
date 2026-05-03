"""Builds the user-facing `/help` Markdown by introspecting the same tool
registries the AI uses. Adding a new tool to ``READ_TOOLS`` or ``WRITE_TOOLS``
in ``mcp_server.py`` automatically flows into this help text — no manual
maintenance of a parallel list."""

from __future__ import annotations

import inspect
import textwrap
import types
import typing
from typing import Any, Callable, get_type_hints

from .mcp_server import READ_TOOLS, WRITE_TOOLS


def build_help_markdown(*, with_writes: bool) -> str:
    parts: list[str] = []
    parts.append("# Insights help")
    parts.append("")
    parts.append(
        "I'm the Insights assistant. Ask any free-form question about your "
        "spending — categories, merchants, trends, forecasts — and I'll pull "
        "the answer from your local transaction store. When a chart helps, "
        "I'll render one inline."
    )
    parts.append("")
    parts.append("## How to use me")
    parts.append("")
    parts.append(
        "- Ask anything in plain English: *“How much did I spend on groceries "
        "last month?”*, *“Where am I overspending?”*, *“Forecast my Living "
        "spend through July.”*"
    )
    parts.append("- Tap **+** in the header to start a fresh conversation.")
    parts.append("- Tap **menu** in the header to browse and reopen past chats.")
    parts.append("- Type `help` or `/help` any time to see this message again.")
    parts.append("")
    parts.append("## What I can read")
    parts.append("")
    parts.append(
        "Under the hood I call these data tools against your local SQLite "
        "store (the same data the Categories and Expenses tabs show)."
    )
    parts.append("")
    for name, fn in READ_TOOLS.items():
        parts.extend(_describe_tool(name, fn))

    if with_writes:
        parts.append("## What I can change")
        parts.append("")
        parts.append(
            "Mutations are gated behind the `ai_mutations` feature flag. When "
            "you ask me to change something, I'll do it and tell you what I "
            "did. Destructive changes (delete) are not reversible from chat."
        )
        parts.append("")
        for name, fn in WRITE_TOOLS.items():
            parts.extend(_describe_tool(name, fn))
    else:
        parts.append("## Editing your data")
        parts.append("")
        parts.append(
            "AI-driven edits (creating/renaming/deleting categories, "
            "recategorising transactions, etc.) are currently **off**. Enable "
            "the `ai_mutations` feature flag in Settings to turn them on."
        )
        parts.append("")

    return "\n".join(parts).rstrip() + "\n"


def _describe_tool(name: str, fn: Callable[..., Any]) -> list[str]:
    summary = (fn.__doc__ or "").strip()
    summary = textwrap.dedent(summary)
    out: list[str] = [f"### `{name}`", ""]
    if summary:
        out.append(summary)
        out.append("")
    params = _describe_params(fn)
    if params:
        out.append("**Parameters:**")
        out.append("")
        out.extend(params)
        out.append("")
    return out


def _describe_params(fn: Callable[..., Any]) -> list[str]:
    sig = inspect.signature(fn)
    try:
        hints = get_type_hints(fn)
    except Exception:  # noqa: BLE001
        hints = {}
    lines: list[str] = []
    for pname, param in sig.parameters.items():
        type_str = _format_type(hints.get(pname, str))
        required = param.default is inspect.Parameter.empty
        default_str = (
            "" if required else f", default `{_format_default(param.default)}`"
        )
        flag = "required" if required else "optional"
        lines.append(f"- `{pname}` — *{type_str}* ({flag}{default_str})")
    return lines


def _format_default(value: Any) -> str:
    if isinstance(value, str):
        return repr(value)
    if value is None:
        return "None"
    return str(value)


def _format_type(tp: Any) -> str:
    origin = typing.get_origin(tp)
    args = typing.get_args(tp)

    if origin in (typing.Union, types.UnionType):
        non_none = [a for a in args if a is not type(None)]
        if len(non_none) == 1:
            return f"{_format_type(non_none[0])} or null"
        return " or ".join(_format_type(a) for a in non_none)

    if origin is list:
        inner = _format_type(args[0]) if args else "any"
        return f"list of {inner}"

    if origin is typing.Literal:
        return "one of " + ", ".join(repr(a) for a in args)

    if tp is str:
        return "string"
    if tp is int:
        return "integer"
    if tp is float:
        return "number"
    if tp is bool:
        return "boolean"
    if tp is dict:
        return "object"
    if tp is list:
        return "list"

    name = getattr(tp, "__name__", None)
    return name or repr(tp)
