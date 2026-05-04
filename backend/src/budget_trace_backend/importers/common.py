"""Common importer types — every parser produces a list of `ImportedRow`,
which is then deduped + persisted via `insert_rows`.

Adding a new parser (OFX, image, …) means: produce `ImportedRow`s. No need
to touch the dedupe path or the route handler.
"""

from __future__ import annotations

import hashlib
import sqlite3
from dataclasses import dataclass
from datetime import date, datetime
from typing import Iterable

from pydantic import BaseModel, Field, field_validator


class ImportedRow(BaseModel):
    date: date
    merchant: str
    amount: float

    @field_validator("merchant")
    @classmethod
    def _normalise_merchant(cls, v: str) -> str:
        # Stable for hashing: uppercase + collapsed whitespace.
        return " ".join(v.upper().split())

    @field_validator("amount")
    @classmethod
    def _positive_amount(cls, v: float) -> float:
        # Importer is for spend only — refunds/credits get filtered upstream.
        if v <= 0:
            raise ValueError(f"amount must be positive, got {v}")
        return round(v, 2)


def source_hash(row: ImportedRow) -> str:
    key = f"{row.date.isoformat()}|{row.merchant}|{row.amount:.2f}"
    return hashlib.sha256(key.encode()).hexdigest()


@dataclass
class ImportResult:
    rows_parsed: int
    rows_inserted: int
    rows_skipped_duplicate: int
    rows_failed: int
    inserted_preview: list[dict]
    inserted_ids: list[int]
    errors: list[dict]

    def to_dict(self, *, format_detected: str, ai_usage: dict | None = None) -> dict:
        return {
            "format_detected": format_detected,
            "rows_parsed": self.rows_parsed,
            "rows_inserted": self.rows_inserted,
            "rows_skipped_duplicate": self.rows_skipped_duplicate,
            "rows_failed": self.rows_failed,
            "preview": self.inserted_preview,
            "errors": self.errors,
            "ai_usage": ai_usage,
        }


def insert_rows(
    conn: sqlite3.Connection,
    rows: Iterable[ImportedRow],
    *,
    parse_errors: list[dict] | None = None,
) -> ImportResult:
    """Persist `rows` with `INSERT OR IGNORE` on `source_hash`. Returns counts
    + a small preview of what was inserted (for the import response body).
    """
    parsed_list = list(rows)
    parsed = len(parsed_list)
    inserted_ids: list[int] = []
    skipped = 0

    for r in parsed_list:
        h = source_hash(r)
        cur = conn.execute(
            # INSERT OR IGNORE works with partial unique indexes; a regular
            # ON CONFLICT clause does not.
            "INSERT OR IGNORE INTO transactions (date, merchant, amount, category_id, source_hash) "
            "VALUES (?, ?, ?, NULL, ?)",
            (r.date.isoformat(), r.merchant, r.amount, h),
        )
        if cur.rowcount == 0:
            skipped += 1
        else:
            inserted_ids.append(cur.lastrowid)

    preview: list[dict] = []
    if inserted_ids:
        placeholders = ",".join("?" for _ in inserted_ids[:20])
        preview_rows = conn.execute(
            f"SELECT id, date, merchant, amount FROM transactions WHERE id IN ({placeholders}) "
            f"ORDER BY date, id",
            inserted_ids[:20],
        ).fetchall()
        preview = [dict(r) for r in preview_rows]

    return ImportResult(
        rows_parsed=parsed,
        rows_inserted=len(inserted_ids),
        rows_skipped_duplicate=skipped,
        rows_failed=len(parse_errors or []),
        inserted_preview=preview,
        inserted_ids=inserted_ids,
        errors=parse_errors or [],
    )


# ── Date parsing helper, shared by CSV + future parsers ──────────────────────


_FORMATS = [
    "%Y-%m-%d",        # ISO
    "%m/%d/%Y",        # US
    "%d/%m/%Y",        # EU
    "%b %d, %Y",       # "Mar 14, 2026"
    "%b %d %Y",        # "Mar 14 2026"
    "%Y/%m/%d",
]


def parse_date(raw: str) -> date:
    raw = raw.strip()
    for fmt in _FORMATS:
        try:
            return datetime.strptime(raw, fmt).date()
        except ValueError:
            continue
    raise ValueError(f"unrecognised date format: {raw!r}")
