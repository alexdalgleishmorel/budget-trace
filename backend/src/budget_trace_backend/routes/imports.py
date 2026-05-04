"""Statement upload route. CSV path is always on; AI parser and
auto-categorization are gated by the single `ai` feature flag."""

from __future__ import annotations

import secrets

from fastapi import APIRouter, File, Form, HTTPException, UploadFile

from .. import features
from ..db import connect
from ..importers.categorizer import categorize_rows
from ..importers.common import insert_rows
from ..importers.csv_parser import CsvParseError, parse_csv
from ..services.anthropic_client import AiKeyMissing

router = APIRouter(prefix="/transactions", tags=["transactions"])


@router.post("/import")
async def upload_transactions(
    file: UploadFile = File(...),
    parser: str = Form(default="csv"),
):
    if parser not in ("csv", "ai"):
        raise HTTPException(
            status_code=422,
            detail={"code": "validation_error",
                    "message": f"unsupported parser: {parser!r}"},
        )

    ai_enabled = features.get_flags().get("ai", False)

    if parser == "ai" and not ai_enabled:
        raise HTTPException(
            status_code=403,
            detail={"code": "feature_disabled",
                    "message": "AI features are not enabled. Turn them on in Account."},
        )

    content = await file.read()
    ai_usage = None

    if parser == "csv":
        try:
            rows, errors = parse_csv(content)
        except CsvParseError as e:
            raise HTTPException(
                status_code=400,
                detail={"code": "csv_parse_failed", "message": str(e)},
            )
        format_detected = "csv"
    else:
        # Lazy import — keeps anthropic out of the import path for CSV-only users.
        from ..importers.ai_parser import UnsupportedFileType, parse_with_ai
        try:
            rows, errors, ai_usage = parse_with_ai(
                content, mime=file.content_type, filename=file.filename,
            )
        except AiKeyMissing as e:
            raise HTTPException(
                status_code=400,
                detail={"code": e.code, "message": str(e)},
            )
        except UnsupportedFileType as e:
            # Pre-API-call refusal — we never billed the user for this.
            raise HTTPException(
                status_code=400,
                detail={"code": e.code, "message": str(e)},
            )
        format_detected = "ai"

    with connect() as conn:
        result = insert_rows(conn, rows, parse_errors=errors)

    # Categorize after the import connection has committed + closed.
    # `categorize_rows` opens its own connection to read the API key + the
    # category tree; running it inside the with-block above would deadlock
    # SQLite against the outer write transaction.
    categorization = categorize_rows(result.inserted_ids) if ai_enabled else None

    body = result.to_dict(format_detected=format_detected, ai_usage=ai_usage)
    if categorization is not None:
        body["categorization"] = categorization
    body["job_id"] = f"imp_{secrets.token_hex(6)}"
    return body
