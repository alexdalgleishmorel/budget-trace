"""AI-driven statement parser. Premium feature, gated by the master `ai` flag.

Sends the file contents to the selected AI model with a single tool,
`parse_transactions`, whose schema is the same `ImportedRow` shape the CSV
path produces. The model extracts rows, the orchestrator returns them. Same
downstream dedupe + insert.

Content-type detection is paranoid on purpose. If we can't positively
identify the bytes as text, image, or PDF we **refuse** to call the model
rather than send it garbage and bill the user — that's how a single bad
upload can cost a user real money for zero rows back. See
`UnsupportedFileType`.

Note: PDF support depends on the selected model's provider. Anthropic and
Gemini accept PDF document blocks; OpenAI does not. Trying to upload a PDF
on an OpenAI model surfaces as `UnsupportedContent` from the AI client.
"""

from __future__ import annotations

import base64
import json
import logging

from ..services import ai_usage
from ..services.ai.client import chat as ai_chat
from ..services.ai.client import get_selected_model
from .common import ImportedRow

log = logging.getLogger(__name__)


class UnsupportedFileType(Exception):
    """Raised when we can't classify the upload as PDF / image / text. The
    route turns this into a 400 with a friendly message — no API call made,
    no tokens billed."""

    code = "unsupported_file_type"


PARSE_TOOL = {
    "type": "function",
    "function": {
        "name": "parse_transactions",
        "description": (
            "Return every spend transaction extracted from the file. Skip "
            "credits, refunds, transfers, opening balances, fees that aren't "
            "actual purchases, and any non-transaction text. Dates must be ISO "
            "(YYYY-MM-DD). Amounts must be positive floats in dollars."
        ),
        "parameters": {
            "type": "object",
            "properties": {
                "rows": {
                    "type": "array",
                    "items": {
                        "type": "object",
                        "properties": {
                            "date": {"type": "string", "description": "YYYY-MM-DD"},
                            "merchant": {"type": "string"},
                            "amount": {"type": "number", "description": "Positive dollars"},
                        },
                        "required": ["date", "merchant", "amount"],
                    },
                },
            },
            "required": ["rows"],
        },
    },
}

SYSTEM_PROMPT = (
    "You parse personal-banking statements into structured transaction rows. "
    "Call `parse_transactions` exactly once with everything you find; do not "
    "emit any free text. Skip credits, refunds, payments-to-card, transfers, "
    "and anything that isn't an actual purchase the user made."
)


def parse_with_ai(
    content: bytes,
    *,
    mime: str | None,
    filename: str | None = None,
) -> tuple[list[ImportedRow], list[dict], dict]:
    """Returns `(rows, errors, ai_usage)` to feed into `insert_rows` and the
    response body.

    Raises:
        AiKeyMissing — no API key for the selected model's provider.
        UnsupportedFileType — bytes don't look like PDF/image/text.
        UnsupportedContent — provider rejected the content (e.g. PDF on OpenAI).
    """
    user_content = _build_user_content(content, mime=mime, filename=filename)

    model = get_selected_model()
    resp = ai_chat(
        model=model,
        system=SYSTEM_PROMPT,
        messages=[{"role": "user", "content": user_content}],
        tools=[PARSE_TOOL],
        max_tokens=4096,
    )
    ai_usage.record_usage(source="ai_parser", model=model, usage=resp.get("usage") or {})

    rows: list[ImportedRow] = []
    errors: list[dict] = []

    for tc in resp.get("tool_calls") or []:
        if tc.get("name") != "parse_transactions":
            continue
        args = _parse_args(tc.get("arguments_json", ""))
        raw_rows = args.get("rows") or []
        for i, raw in enumerate(raw_rows, start=1):
            try:
                rows.append(ImportedRow(**raw))
            except Exception as e:
                errors.append({"row": i, "reason": f"AI returned bad row: {e}; raw={json.dumps(raw)}"})
        break  # only honour the first call

    usage_dict = resp.get("usage") or {}
    usage = {
        "input_tokens": int(usage_dict.get("input_tokens") or 0),
        "output_tokens": int(usage_dict.get("output_tokens") or 0),
    }
    return rows, errors, usage


def _parse_args(arguments_json: str) -> dict:
    if not arguments_json:
        return {}
    try:
        parsed = json.loads(arguments_json)
    except json.JSONDecodeError:
        return {}
    return parsed if isinstance(parsed, dict) else {}


def _build_user_content(
    content: bytes,
    *,
    mime: str | None,
    filename: str | None,
) -> list[dict]:
    """Classify [content] and return OpenAI/LiteLLM-shaped content blocks.

    Detection order: magic-byte sniff → mime header → filename extension.
    Magic bytes win because that's the only signal we trust unconditionally;
    the http-multipart Content-Type is whatever the client decided to send,
    and may be `application/octet-stream` when the client doesn't bother.

    PDFs are passed as a `file` content block (LiteLLM's document shape) so it
    routes to Anthropic's `document` source / Gemini inline_data — NOT as an
    `image_url`, which current LiteLLM maps to an image source block that
    rejects `application/pdf`. Images use `image_url` data URLs. PDF on OpenAI
    models bubbles up as `UnsupportedContent` from the chat call.
    """
    kind = _classify(content, mime=mime, filename=filename)

    if kind == "pdf":
        return [{
            "type": "file",
            "file": {
                "file_data": "data:application/pdf;base64,"
                + base64.b64encode(content).decode(),
                "filename": filename or "statement.pdf",
            },
        }]

    if kind.startswith("image/"):
        return [{
            "type": "image_url",
            "image_url": {
                "url": f"data:{kind};base64," + base64.b64encode(content).decode(),
            },
        }]

    if kind == "text":
        return [{"type": "text", "text": content.decode("utf-8", errors="replace")}]

    # Should be unreachable — _classify either returns one of the above or
    # raises. Belt-and-braces.
    raise UnsupportedFileType(
        "Couldn't identify the file type. Supported: PDF, image (PNG/JPEG/WebP/GIF), "
        "or plain text/CSV."
    )


_IMAGE_SIGNATURES: list[tuple[bytes, str]] = [
    (b"\x89PNG\r\n\x1a\n", "image/png"),
    (b"\xff\xd8\xff",      "image/jpeg"),
    (b"GIF87a",            "image/gif"),
    (b"GIF89a",            "image/gif"),
    (b"RIFF",              "image/webp"),  # webp also has WEBP at offset 8 — close enough
]


def _classify(
    content: bytes,
    *,
    mime: str | None,
    filename: str | None,
) -> str:
    """Returns 'pdf', 'text', or 'image/<subtype>'. Raises
    UnsupportedFileType for anything else — never sends bytes to the model
    unidentified."""
    head = content[:16]

    # Magic bytes — the only signal we trust unconditionally.
    if head.startswith(b"%PDF-"):
        return "pdf"
    for sig, kind in _IMAGE_SIGNATURES:
        if head.startswith(sig):
            return kind

    # Mime header from the upload — useful when the client did set one.
    if mime:
        if mime == "application/pdf":
            return "pdf"
        if mime.startswith("image/"):
            return mime
        if mime.startswith("text/"):
            return "text"

    # Filename extension as last resort. Useful when the client sent the
    # default application/octet-stream.
    if filename:
        lower = filename.lower()
        if lower.endswith(".pdf"):
            return "pdf"
        if lower.endswith((".png",)):
            return "image/png"
        if lower.endswith((".jpg", ".jpeg")):
            return "image/jpeg"
        if lower.endswith(".gif"):
            return "image/gif"
        if lower.endswith(".webp"):
            return "image/webp"
        if lower.endswith((".csv", ".txt", ".tsv")):
            return "text"

    raise UnsupportedFileType(
        "Couldn't identify the file type. Supported: PDF, image (PNG/JPEG/WebP/GIF), "
        "or plain text/CSV."
    )
