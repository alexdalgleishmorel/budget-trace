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
from budget_trace_backend.services import categories as cat_svc
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

    assert result == {
        "attempted": 0, "categorized": 0, "pre_applied": 0,
        "skipped_no_match": 0, "ai_usage": None,
    }


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


def test_categorizer_pre_applies_known_merchants_skipping_ai(
    seeded_db: Path, monkeypatch
) -> None:
    """When every input merchant is already in history, Claude must NOT be
    called — the categorizer takes the pre-apply fast path."""
    cat = cat_svc.create_category(name="My Cafes", description="Coffee")
    # Seed history: one categorized BEAN MACHINE row.
    svc.create_transaction(
        date="2026-04-10", merchant="BEAN MACHINE", amount=4.50, category_id=cat["id"],
    )

    # Now insert a fresh BEAN MACHINE row (uncategorized) and ask the
    # categorizer to handle it.
    rows = [ImportedRow(date="2026-04-15", merchant="BEAN MACHINE", amount=5.25)]
    with db_module.connect(seeded_db) as conn:
        result = insert_rows(conn, rows)
    new_ids = result.inserted_ids
    assert len(new_ids) == 1

    def boom():
        raise AssertionError(
            "Claude must not be called when every input merchant is already known"
        )
    monkeypatch.setattr(categorizer, "get_client", boom)

    out = categorizer.categorize_rows(new_ids)
    assert out["categorized"] == 1
    assert out["pre_applied"] == 1
    assert out["skipped_no_match"] == 0
    assert out["ai_usage"] is None  # never called

    # Verify the new row got the historical category.
    fresh = next(t for t in svc.list_transactions(merchant_query="bean machine", limit=10)
                 if t["id"] == new_ids[0])
    assert fresh["category_id"] == cat["id"]


def test_categorizer_history_uses_most_recent_assignment(
    seeded_db: Path, monkeypatch
) -> None:
    """When a merchant has multiple historical assignments, the most-recent
    one wins (mirrors the user's latest decision)."""
    cat_a = cat_svc.create_category(name="Cat A", description="x")
    cat_b = cat_svc.create_category(name="Cat B", description="y")
    # First, three rows in cat_a (lower ids) ...
    for i in range(3):
        svc.create_transaction(
            date=f"2026-04-{10+i:02d}", merchant="SPLIT MERCHANT",
            amount=10.00, category_id=cat_a["id"],
        )
    # ... then ONE more recent row in cat_b (highest id, wins).
    svc.create_transaction(
        date="2026-04-20", merchant="SPLIT MERCHANT", amount=11.00, category_id=cat_b["id"],
    )

    # Import a new SPLIT MERCHANT row.
    rows = [ImportedRow(date="2026-04-25", merchant="SPLIT MERCHANT", amount=12.00)]
    with db_module.connect(seeded_db) as conn:
        new_ids = insert_rows(conn, rows).inserted_ids

    monkeypatch.setattr(categorizer, "get_client",
                        lambda: (_ for _ in ()).throw(AssertionError("no AI please")))

    out = categorizer.categorize_rows(new_ids)
    assert out["pre_applied"] == 1

    fresh = next(t for t in svc.list_transactions(merchant_query="split merchant", limit=10)
                 if t["id"] == new_ids[0])
    # Most-recent assignment was cat_b — that wins.
    assert fresh["category_id"] == cat_b["id"]


def test_categorizer_mixes_pre_applied_and_ai_assignments(
    seeded_db: Path, monkeypatch
) -> None:
    """Half-known, half-unknown merchants in one batch: pre-apply for the
    known half, Claude for the rest. Counts are accurate."""
    cat = cat_svc.create_category(name="From History", description="x")
    # Seed history for one merchant.
    svc.create_transaction(
        date="2026-03-15", merchant="KNOWN MERCH", amount=20.00, category_id=cat["id"],
    )

    # Import 4 rows: 2 KNOWN (will pre-apply), 2 NEW (will go to Claude).
    new_rows = [
        ImportedRow(date="2026-04-01", merchant="KNOWN MERCH", amount=10.00),
        ImportedRow(date="2026-04-02", merchant="KNOWN MERCH", amount=11.00),
        ImportedRow(date="2026-04-03", merchant="NEW MERCH A", amount=12.00),
        ImportedRow(date="2026-04-04", merchant="NEW MERCH B", amount=13.00),
    ]
    with db_module.connect(seeded_db) as conn:
        new_ids = insert_rows(conn, new_rows).inserted_ids
    assert len(new_ids) == 4

    # Stub the AI to assign both new merchants.
    new_a_id = next(i for i in new_ids
                    if next(t for t in svc.list_transactions(limit=500) if t["id"] == i)["merchant"] == "NEW MERCH A")
    new_b_id = next(i for i in new_ids
                    if next(t for t in svc.list_transactions(limit=500) if t["id"] == i)["merchant"] == "NEW MERCH B")
    fake = _fake_client_returning([
        {"transaction_id": new_a_id, "category_path": "Living / Grocery"},
        {"transaction_id": new_b_id, "category_path": "Living / Gas"},
    ])
    monkeypatch.setattr(categorizer, "get_client", lambda: fake)

    out = categorizer.categorize_rows(new_ids)
    assert out["categorized"] == 4
    assert out["pre_applied"] == 2  # the 2 KNOWN rows
    assert out["skipped_no_match"] == 0
    assert out["ai_usage"] is not None  # Claude WAS called for the 2 unknowns
