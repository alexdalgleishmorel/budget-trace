"""AI-driven statement parser. Premium feature, gated by the master `ai` flag.

Sends the file contents to Claude with a single tool, `parse_transactions`,
whose schema is the same `ImportedRow` shape the CSV path produces. Claude
extracts rows, the orchestrator returns them. Same downstream dedupe + insert.

For PDFs we pre-extract text with pdfplumber when available; otherwise we
hand the raw bytes off as base64 (vision input). Image MIME types likewise
go through vision input.
"""

from __future__ import annotations

import base64
import json
import logging

from ..services.anthropic_client import get_client, get_model
from .common import ImportedRow

log = logging.getLogger(__name__)

PARSE_TOOL = {
    "name": "parse_transactions",
    "description": (
        "Return every spend transaction extracted from the file. Skip "
        "credits, refunds, transfers, opening balances, fees that aren't "
        "actual purchases, and any non-transaction text. Dates must be ISO "
        "(YYYY-MM-DD). Amounts must be positive floats in dollars."
    ),
    "input_schema": {
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
}

SYSTEM_PROMPT = (
    "You parse personal-banking statements into structured transaction rows. "
    "Call `parse_transactions` exactly once with everything you find; do not "
    "emit any free text. Skip credits, refunds, payments-to-card, transfers, "
    "and anything that isn't an actual purchase the user made."
)


def parse_with_ai(content: bytes, *, mime: str | None) -> tuple[list[ImportedRow], list[dict], dict]:
    """Returns `(rows, errors, ai_usage)` to feed into `insert_rows` and the
    response body. Raises `AiKeyMissing` if no Anthropic key is configured."""
    client = get_client()
    user_content = _build_user_content(content, mime=mime)

    resp = client.messages.create(
        model=get_model(),
        max_tokens=4096,
        system=SYSTEM_PROMPT,
        tools=[PARSE_TOOL],
        messages=[{"role": "user", "content": user_content}],
    )

    rows: list[ImportedRow] = []
    errors: list[dict] = []

    for block in resp.content:
        if getattr(block, "type", None) != "tool_use" or block.name != "parse_transactions":
            continue
        raw_rows = (block.input or {}).get("rows", [])
        for i, raw in enumerate(raw_rows, start=1):
            try:
                rows.append(ImportedRow(**raw))
            except Exception as e:
                errors.append({"row": i, "reason": f"AI returned bad row: {e}; raw={json.dumps(raw)}"})
        break  # only honour the first call

    usage = {
        "input_tokens": getattr(resp.usage, "input_tokens", 0),
        "output_tokens": getattr(resp.usage, "output_tokens", 0),
    }
    return rows, errors, usage


def _build_user_content(content: bytes, *, mime: str | None) -> list[dict]:
    """Pick the right content block shape for the file. Text where possible
    (cheaper); base64-encoded document/image otherwise."""
    if mime and mime.startswith("text/"):
        return [{"type": "text", "text": content.decode("utf-8", errors="replace")}]

    if mime == "application/pdf":
        text = _extract_pdf_text(content)
        if text:
            return [{"type": "text", "text": text}]
        # Fall through to document-input below.

    if mime and mime.startswith("image/"):
        return [{
            "type": "image",
            "source": {
                "type": "base64",
                "media_type": mime,
                "data": base64.b64encode(content).decode(),
            },
        }]

    if mime == "application/pdf":
        return [{
            "type": "document",
            "source": {
                "type": "base64",
                "media_type": "application/pdf",
                "data": base64.b64encode(content).decode(),
            },
        }]

    # Unknown — best-effort decode as text.
    return [{"type": "text", "text": content.decode("utf-8", errors="replace")}]


def _extract_pdf_text(content: bytes) -> str | None:
    try:
        import pdfplumber
    except Exception:
        return None
    try:
        import io
        with pdfplumber.open(io.BytesIO(content)) as pdf:
            return "\n".join((page.extract_text() or "") for page in pdf.pages)
    except Exception:
        log.exception("pdfplumber failed")
        return None
