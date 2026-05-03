"""Statement upload route. CSV path is always on; AI parser is gated by the
`ai_import` feature flag."""

from __future__ import annotations

import secrets

from fastapi import APIRouter, File, Form, HTTPException, UploadFile

from .. import features
from ..db import connect
from ..importers.common import insert_rows
from ..importers.csv_parser import CsvParseError, parse_csv

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

    if parser == "ai" and not features.get_flags().get("ai_import", False):
        raise HTTPException(
            status_code=403,
            detail={"code": "feature_disabled",
                    "message": "ai_import is not enabled for this account."},
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
        from ..importers.ai_parser import parse_with_ai
        rows, errors, ai_usage = parse_with_ai(content, mime=file.content_type)
        format_detected = "ai"

    with connect() as conn:
        result = insert_rows(conn, rows, parse_errors=errors)

    body = result.to_dict(format_detected=format_detected, ai_usage=ai_usage)
    body["job_id"] = f"imp_{secrets.token_hex(6)}"
    return body
