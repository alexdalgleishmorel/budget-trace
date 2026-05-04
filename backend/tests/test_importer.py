"""CSV importer tests. The fixtures live alongside this file under
`fixtures/`. Each test uses a fresh tmp DB."""

from __future__ import annotations

import os
from pathlib import Path

import pytest
from fastapi.testclient import TestClient

from budget_trace_backend import db as db_module
from budget_trace_backend import seed
from budget_trace_backend.importers.common import (
    ImportedRow,
    insert_rows,
    source_hash,
)
from budget_trace_backend.importers.ai_parser import (
    UnsupportedFileType,
    _build_user_content,
)
from budget_trace_backend.importers.csv_parser import CsvParseError, parse_csv
from budget_trace_backend.main import app

FIXTURES = Path(__file__).parent / "fixtures"


@pytest.fixture()
def seeded_db(tmp_path: Path) -> Path:
    target = tmp_path / "test.db"
    os.environ["BUDGET_TRACE_DB"] = str(target)
    seed.main(target)
    yield target
    os.environ.pop("BUDGET_TRACE_DB", None)


@pytest.fixture()
def client(seeded_db: Path) -> TestClient:
    return TestClient(app)


# ── Hashing ──────────────────────────────────────────────────────────────────


def test_source_hash_is_deterministic() -> None:
    r = ImportedRow(date="2026-04-15", merchant="Trader Joes", amount=42.10)
    a = source_hash(r)
    b = source_hash(r)
    assert a == b
    assert len(a) == 64


def test_source_hash_depends_on_normalised_merchant() -> None:
    r1 = ImportedRow(date="2026-04-15", merchant="trader joes", amount=42.10)
    r2 = ImportedRow(date="2026-04-15", merchant="TRADER JOES", amount=42.10)
    # Both normalise to "TRADER JOES" → same hash.
    assert source_hash(r1) == source_hash(r2)


# ── CSV parsing ──────────────────────────────────────────────────────────────


def test_csv_parses_basic_format() -> None:
    rows, errors = parse_csv((FIXTURES / "sample.csv").read_bytes())
    assert len(rows) == 3  # 3 valid + 1 errored
    assert any(r.merchant == "TRADER JOES #142" for r in rows)
    assert len(errors) == 1
    assert errors[0]["row"] == 5  # the malformed row


def test_csv_handles_debit_credit_split() -> None:
    rows, errors = parse_csv((FIXTURES / "debit_credit.csv").read_bytes())
    # Refund row (credit) is silently dropped.
    assert len(rows) == 2
    assert {r.merchant for r in rows} == {"COSTCO WHSE", "UBER *TRIP"}
    assert errors == []


def test_csv_missing_columns_raises() -> None:
    with pytest.raises(CsvParseError):
        parse_csv(b"foo,bar\n1,2\n")


def test_csv_skips_negative_amounts_as_credits() -> None:
    # Single Amount column, negative = credit-card payment / refund. Skip.
    csv_bytes = (
        b"Date,Description,Amount\n"
        b"2026-04-15,STARBUCKS,5.50\n"
        b"2026-04-16,PAYMENT FROM ACCOUNT,-200.00\n"
        b"2026-04-17,IKEA,42.10\n"
    )
    rows, errors = parse_csv(csv_bytes)
    assert {r.merchant for r in rows} == {"STARBUCKS", "IKEA"}
    assert errors == []


def test_csv_truncated_row_is_surfaced_as_error() -> None:
    # Network-drop scenario: file ends mid-row, no closing newline.
    csv_bytes = (
        b"Date,Description,Amount\n"
        b"2026-04-15,STARBUCKS,5.50\n"
        b"2026-04-16,IKEA,42.10\n"
        b'2026-04-17,"truncated-merch'
    )
    rows, errors = parse_csv(csv_bytes)
    assert len(rows) == 2
    assert len(errors) == 1
    assert errors[0]["row"] == 4  # header is row 1


# ── Real Scotia statements ───────────────────────────────────────────────────


REAL_FIXTURES = FIXTURES / "real"


def test_real_scotia_csv_parses_only_spend() -> None:
    """61 spend rows + 12 negative-amount Credit rows that get skipped."""
    rows, errors = parse_csv(
        (REAL_FIXTURES / "scotia_visa_april_2026.csv").read_bytes()
    )
    assert len(rows) == 61
    assert errors == []
    # No negatives should leak through.
    assert all(r.amount > 0 for r in rows)
    # Sample known-good merchants survived the parse.
    merchants = {r.merchant for r in rows}
    assert "EQ3 LTD" in merchants
    assert "STARBUCKS 8007827282" in merchants
    # No payment-to-card rows leaked through as fake spend.
    assert not any("PAYMENT FROM" in r.merchant for r in rows)


def test_real_scotia_truncated_csv_parses_what_it_can() -> None:
    """Truncated mid-row at byte 4610. csv.reader recovers, the partial last
    row IndexErrors on amount lookup and is surfaced as a parse error."""
    rows, errors = parse_csv(
        (REAL_FIXTURES / "scotia_visa_april_2026-corrupted.csv").read_bytes()
    )
    assert len(rows) == 41
    assert len(errors) == 1


# ── Insert + dedupe ──────────────────────────────────────────────────────────


def test_insert_rows_dedupes_duplicates(seeded_db: Path) -> None:
    rows = [
        ImportedRow(date="2026-04-20", merchant="NEW MERCHANT", amount=10.00),
        ImportedRow(date="2026-04-20", merchant="NEW MERCHANT", amount=10.00),
    ]
    with db_module.connect(seeded_db) as conn:
        result = insert_rows(conn, rows)
    assert result.rows_parsed == 2
    assert result.rows_inserted == 1
    assert result.rows_skipped_duplicate == 1


def test_reimport_same_csv_produces_zero_inserts(seeded_db: Path) -> None:
    rows, _ = parse_csv((FIXTURES / "sample.csv").read_bytes())

    with db_module.connect(seeded_db) as conn:
        first = insert_rows(conn, rows)
    assert first.rows_inserted == 3

    with db_module.connect(seeded_db) as conn:
        second = insert_rows(conn, rows)
    assert second.rows_inserted == 0
    assert second.rows_skipped_duplicate == 3


# ── Route ────────────────────────────────────────────────────────────────────


def test_post_import_csv(client: TestClient) -> None:
    sample = (FIXTURES / "sample.csv").read_bytes()
    resp = client.post(
        "/transactions/import",
        files={"file": ("sample.csv", sample, "text/csv")},
    )
    assert resp.status_code == 200
    body = resp.json()
    assert body["format_detected"] == "csv"
    assert body["rows_inserted"] == 3
    assert body["rows_failed"] == 1
    assert body["ai_usage"] is None
    assert "job_id" in body


def test_post_import_ai_returns_403_when_flag_off(client: TestClient) -> None:
    resp = client.post(
        "/transactions/import",
        data={"parser": "ai"},
        files={"file": ("x.pdf", b"fake", "application/pdf")},
    )
    assert resp.status_code == 403
    assert resp.json()["detail"]["code"] == "feature_disabled"


def test_post_import_ai_unblocked_when_flag_on(
    client: TestClient, monkeypatch
) -> None:
    monkeypatch.setenv("BUDGET_TRACE_FEATURES", "ai")

    # Stub both the parser and the categorizer — neither should hit the network.
    from budget_trace_backend.importers import ai_parser
    from budget_trace_backend.routes import imports as imports_route

    def fake_parse(content, *, mime, filename=None):
        return (
            [ImportedRow(date="2026-04-15", merchant="FAKE AI MERCHANT", amount=12.34)],
            [],
            {"input_tokens": 100, "output_tokens": 20},
        )

    def fake_categorize(ids):
        return {"attempted": len(ids), "categorized": len(ids),
                "skipped_no_match": 0, "ai_usage": {"input_tokens": 1, "output_tokens": 1}}

    monkeypatch.setattr(ai_parser, "parse_with_ai", fake_parse)
    monkeypatch.setattr(imports_route, "categorize_rows", fake_categorize)

    resp = client.post(
        "/transactions/import",
        data={"parser": "ai"},
        files={"file": ("x.pdf", b"%PDF\n(fake)", "application/pdf")},
    )
    assert resp.status_code == 200
    body = resp.json()
    assert body["format_detected"] == "ai"
    assert body["rows_inserted"] == 1
    assert body["ai_usage"] == {"input_tokens": 100, "output_tokens": 20}
    assert body["categorization"]["categorized"] == 1


def test_post_import_ai_missing_key_returns_400(
    client: TestClient, monkeypatch
) -> None:
    monkeypatch.setenv("BUDGET_TRACE_FEATURES", "ai")
    monkeypatch.delenv("ANTHROPIC_API_KEY", raising=False)

    resp = client.post(
        "/transactions/import",
        data={"parser": "ai"},
        files={"file": ("x.pdf", b"%PDF\n(fake)", "application/pdf")},
    )
    assert resp.status_code == 400
    assert resp.json()["detail"]["code"] == "ai_key_missing"


def test_post_import_unknown_parser_returns_422(client: TestClient) -> None:
    resp = client.post(
        "/transactions/import",
        data={"parser": "ofx"},
        files={"file": ("x.ofx", b"fake", "text/plain")},
    )
    assert resp.status_code == 422


# ── ai_parser content detection ──────────────────────────────────────────────


def test_ai_parser_detects_pdf_via_magic_bytes() -> None:
    # %PDF- signature wins even when mime + filename are missing/wrong.
    block = _build_user_content(
        b"%PDF-1.7\n...binary stream...",
        mime="application/octet-stream",
        filename=None,
    )[0]
    assert block["type"] == "document"
    assert block["source"]["media_type"] == "application/pdf"


def test_ai_parser_detects_pdf_via_filename_when_mime_unknown() -> None:
    # No magic bytes, no useful mime, but filename ends in .pdf.
    block = _build_user_content(
        b"x" * 32,
        mime="application/octet-stream",
        filename="statement.pdf",
    )[0]
    assert block["type"] == "document"


def test_ai_parser_detects_text_csv() -> None:
    block = _build_user_content(
        b"Date,Merchant,Amount\n2026-04-15,FOO,1.00\n",
        mime="text/csv",
        filename="x.csv",
    )[0]
    assert block["type"] == "text"
    assert "Date,Merchant,Amount" in block["text"]


def test_ai_parser_refuses_unknown_bytes_to_avoid_billing() -> None:
    # No magic bytes, no useful mime, no filename. Must NOT call Anthropic.
    with pytest.raises(UnsupportedFileType):
        _build_user_content(
            b"\x00\x01\x02\x03random binary\xff\xfe",
            mime="application/octet-stream",
            filename=None,
        )


def test_import_route_unsupported_file_returns_400(
    client: TestClient, monkeypatch
) -> None:
    monkeypatch.setenv("BUDGET_TRACE_FEATURES", "ai")
    # Random binary, default Content-Type, no filename hint.
    resp = client.post(
        "/transactions/import",
        data={"parser": "ai"},
        files={"file": (
            "mystery", b"\x00\x01\x02\x03binary\xff",
            "application/octet-stream",
        )},
    )
    assert resp.status_code == 400
    assert resp.json()["detail"]["code"] == "unsupported_file_type"
