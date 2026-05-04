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

    def fake_parse(content, *, mime):
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
