"""Auto-categorizer tests. Stubs `get_client()` so no network is hit."""

from __future__ import annotations

import os
from pathlib import Path
from types import SimpleNamespace

import pytest
from fastapi.testclient import TestClient

from budget_trace_backend import db as db_module
from budget_trace_backend import seed
from budget_trace_backend.importers import categorizer
from budget_trace_backend.importers.common import ImportedRow, insert_rows
from budget_trace_backend.main import app
from budget_trace_backend.services import anthropic_client
from budget_trace_backend.services import transactions as svc


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


def _fake_client_returning(assignments: list[dict]):
    """Build a stand-in for the Anthropic client that emits an
    `assign_categories` tool_use with the supplied assignments."""

    block = SimpleNamespace(
        type="tool_use",
        name="assign_categories",
        input={"assignments": assignments},
    )
    resp = SimpleNamespace(
        content=[block],
        usage=SimpleNamespace(input_tokens=10, output_tokens=5),
    )
    messages = SimpleNamespace(create=lambda **kw: resp)
    return SimpleNamespace(messages=messages)


def _insert_uncategorised(seeded_db: Path) -> list[int]:
    rows = [
        ImportedRow(date="2026-04-01", merchant="WHOLE FOODS", amount=42.10),
        ImportedRow(date="2026-04-02", merchant="SHELL", amount=58.00),
    ]
    with db_module.connect(seeded_db) as conn:
        result = insert_rows(conn, rows)
    return result.inserted_ids


def test_categorizer_assigns_via_fake_ai(seeded_db: Path, monkeypatch) -> None:
    ids = _insert_uncategorised(seeded_db)
    assert len(ids) == 2

    fake = _fake_client_returning([
        {"transaction_id": ids[0], "category_path": "Living / Grocery"},
        {"transaction_id": ids[1], "category_path": "Living / Gas"},
    ])
    monkeypatch.setattr(categorizer, "get_client", lambda: fake)

    result = categorizer.categorize_rows(ids)

    assert result["categorized"] == 2
    assert result["skipped_no_match"] == 0
    assert "error" not in result

    with db_module.connect(seeded_db) as conn:
        rows = conn.execute(
            "SELECT id, category_id FROM transactions WHERE id IN (?, ?)",
            ids,
        ).fetchall()
    assert all(r["category_id"] is not None for r in rows)


def test_categorizer_drops_invalid_paths(seeded_db: Path, monkeypatch) -> None:
    ids = _insert_uncategorised(seeded_db)

    fake = _fake_client_returning([
        # Hallucinated path — not in the leaf list.
        {"transaction_id": ids[0], "category_path": "Made Up / Imaginary"},
        # Non-leaf path — "Living" is a parent, not a leaf.
        {"transaction_id": ids[1], "category_path": "Living"},
    ])
    monkeypatch.setattr(categorizer, "get_client", lambda: fake)

    result = categorizer.categorize_rows(ids)

    assert result["categorized"] == 0
    assert result["skipped_no_match"] == 2
    assert "error" not in result


def test_categorizer_empty_ids_skips_ai_call(seeded_db: Path, monkeypatch) -> None:
    # If this test ever calls the AI, monkeypatch will explode loudly.
    def boom():
        raise AssertionError("AI must not be called for empty input")

    monkeypatch.setattr(categorizer, "get_client", boom)

    result = categorizer.categorize_rows([])

    assert result == {"attempted": 0, "categorized": 0, "skipped_no_match": 0, "ai_usage": None}


def test_categorizer_missing_key_degrades_gracefully(seeded_db: Path, monkeypatch) -> None:
    ids = _insert_uncategorised(seeded_db)

    def raise_missing():
        raise anthropic_client.AiKeyMissing()

    monkeypatch.setattr(categorizer, "get_client", raise_missing)

    result = categorizer.categorize_rows(ids)

    assert result["error"] == "ai_key_missing"
    assert result["categorized"] == 0
    assert result["skipped_no_match"] == len(ids)


def test_import_route_runs_categorizer_when_ai_on(
    client: TestClient, seeded_db: Path, monkeypatch
) -> None:
    monkeypatch.setenv("BUDGET_TRACE_FEATURES", "ai")

    csv = b"date,merchant,amount\n2026-04-15,WHOLE FOODS,42.10\n2026-04-16,SHELL,58.00\n"

    captured: dict = {}

    def fake_categorize(ids):
        captured["ids"] = list(ids)
        return {"attempted": len(ids), "categorized": len(ids),
                "skipped_no_match": 0, "ai_usage": {"input_tokens": 1, "output_tokens": 1}}

    # Patch the symbol the route imports, not the source module.
    from budget_trace_backend.routes import imports as imports_route
    monkeypatch.setattr(imports_route, "categorize_rows", fake_categorize)

    resp = client.post(
        "/transactions/import",
        files={"file": ("x.csv", csv, "text/csv")},
    )
    assert resp.status_code == 200
    body = resp.json()
    assert body["rows_inserted"] == 2
    assert body["categorization"]["categorized"] == 2
    assert len(captured["ids"]) == 2


def test_import_route_skips_categorizer_when_ai_off(client: TestClient, monkeypatch) -> None:
    csv = b"date,merchant,amount\n2026-04-17,SOMETHING,12.34\n"

    def boom(ids):
        raise AssertionError("categorizer must not be called when ai is off")

    from budget_trace_backend.routes import imports as imports_route
    monkeypatch.setattr(imports_route, "categorize_rows", boom)

    resp = client.post(
        "/transactions/import",
        files={"file": ("x.csv", csv, "text/csv")},
    )
    assert resp.status_code == 200
    assert "categorization" not in resp.json()


def test_categorizer_cascades_to_existing_same_merchant(seeded_db: Path, monkeypatch) -> None:
    # Pre-existing uncategorized row with merchant "WHOLE FOODS" already in DB.
    pre = svc.create_transaction(
        date="2026-03-15", merchant="WHOLE FOODS", amount=20.00,
    )

    # Now import a fresh row with the same merchant + run the categorizer
    # against just the new id. Cascade should pull the pre-existing row in.
    ids = _insert_uncategorised(seeded_db)  # adds WHOLE FOODS + SHELL
    grocery_ids = [i for i in ids
                   if next(t for t in svc.list_transactions(limit=500) if t["id"] == i)["merchant"] == "WHOLE FOODS"]

    fake = _fake_client_returning([
        {"transaction_id": grocery_ids[0], "category_path": "Living / Grocery"},
    ])
    monkeypatch.setattr(categorizer, "get_client", lambda: fake)

    result = categorizer.categorize_rows(grocery_ids)
    assert result["categorized"] == 1  # input batch only

    # The pre-existing row is now categorized too.
    fresh_pre = next(t for t in svc.list_transactions(limit=500) if t["id"] == pre["id"])
    assert fresh_pre["category_id"] is not None
    assert fresh_pre["category_path"] == "Living / Grocery"


def test_categorizer_first_assignment_wins_within_batch(seeded_db: Path, monkeypatch) -> None:
    # Two rows, same merchant. Model returns conflicting assignments.
    a = svc.create_transaction(date="2026-04-01", merchant="DUPE MERCH", amount=10.0)
    b = svc.create_transaction(date="2026-04-02", merchant="DUPE MERCH", amount=11.0)

    fake = _fake_client_returning([
        {"transaction_id": a["id"], "category_path": "Living / Grocery"},
        {"transaction_id": b["id"], "category_path": "Living / Gas"},  # conflicting
    ])
    monkeypatch.setattr(categorizer, "get_client", lambda: fake)

    result = categorizer.categorize_rows([a["id"], b["id"]])
    assert result["categorized"] == 2  # both rows categorized via cascade

    rows = {t["id"]: t for t in svc.list_transactions(merchant_query="dupe merch", limit=10)}
    # First wins: both end up Grocery, not Gas.
    assert rows[a["id"]]["category_path"] == "Living / Grocery"
    assert rows[b["id"]]["category_path"] == "Living / Grocery"
