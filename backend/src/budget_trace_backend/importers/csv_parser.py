"""CSV parser. Best-effort header detection across the common bank export
shapes. Out of scope: anything bank-specific. If detection fails we surface
a clear error suggesting the AI parser (premium).
"""

from __future__ import annotations

import csv
import io
from typing import Iterable

from .common import ImportedRow, parse_date

# Header aliases. The first match wins; matching is case-insensitive.
_DATE_HEADERS = ["date", "transaction date", "post date", "posted", "posted date"]
_MERCHANT_HEADERS = ["description", "merchant", "payee", "name", "details"]
_AMOUNT_HEADERS = ["amount", "value"]
_DEBIT_HEADERS = ["debit", "withdrawal", "spend"]
_CREDIT_HEADERS = ["credit", "deposit", "refund"]


class CsvParseError(Exception):
    pass


def _normalise(s: str) -> str:
    return s.strip().lower()


def _pick_column(headers: list[str], aliases: list[str]) -> int | None:
    norm = [_normalise(h) for h in headers]
    for alias in aliases:
        for i, h in enumerate(norm):
            if h == alias:
                return i
    return None


def parse_csv(content: bytes) -> tuple[list[ImportedRow], list[dict]]:
    """Return `(rows, errors)`. Errors are per-row {row, reason} dicts. The
    caller decides whether a non-empty `rows` is "good enough" given the
    error count.
    """
    text = content.decode("utf-8-sig", errors="replace")
    sample = text[:4096]
    try:
        dialect = csv.Sniffer().sniff(sample)
    except csv.Error:
        dialect = csv.excel  # fall back to defaults
    reader = csv.reader(io.StringIO(text), dialect=dialect)
    try:
        headers = next(reader)
    except StopIteration:
        raise CsvParseError("file is empty")

    date_col = _pick_column(headers, _DATE_HEADERS)
    if date_col is None:
        raise CsvParseError(
            "couldn't find a date column. Expected one of: "
            + ", ".join(_DATE_HEADERS)
        )

    merchant_col = _pick_column(headers, _MERCHANT_HEADERS)
    if merchant_col is None:
        raise CsvParseError(
            "couldn't find a merchant/description column. Expected one of: "
            + ", ".join(_MERCHANT_HEADERS)
        )

    amount_col = _pick_column(headers, _AMOUNT_HEADERS)
    debit_col = _pick_column(headers, _DEBIT_HEADERS)
    credit_col = _pick_column(headers, _CREDIT_HEADERS)

    if amount_col is None and debit_col is None:
        raise CsvParseError(
            "couldn't find an amount column. Expected 'amount' or 'debit'."
        )

    rows: list[ImportedRow] = []
    errors: list[dict] = []
    line_no = 1  # header is line 1; data starts at line 2

    for raw in reader:
        line_no += 1
        if not raw or all(not c.strip() for c in raw):
            continue
        try:
            # If a credit column exists and is populated, this row is a
            # refund/transfer — out of scope.
            if credit_col is not None and len(raw) > credit_col:
                credit = raw[credit_col].strip()
                if credit and _to_float(credit) > 0:
                    continue

            d = parse_date(raw[date_col])
            merchant = raw[merchant_col]

            if amount_col is not None:
                amount = _to_float(raw[amount_col])
                # Some exports use negative amounts for spend — flip them.
                if amount < 0:
                    amount = -amount
            else:
                # debit-only path
                amount = _to_float(raw[debit_col])  # type: ignore[index]

            rows.append(ImportedRow(date=d, merchant=merchant, amount=amount))
        except Exception as e:
            errors.append({"row": line_no, "reason": str(e)})

    return rows, errors


def _to_float(s: str) -> float:
    s = s.strip().replace("$", "").replace(",", "")
    if s in ("", "-"):
        raise ValueError("empty amount")
    return float(s)
