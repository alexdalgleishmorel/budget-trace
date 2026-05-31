"""Auto-categorizer tests. Stubs `ai.client.chat()` so no network is hit."""

from __future__ import annotations

import json
import os
from pathlib import Path

import pytest
from fastapi.testclient import TestClient

from budget_trace_backend import db as db_module
from budget_trace_backend import seed
from budget_trace_backend.importers import categorizer
from budget_trace_backend.importers.common import ImportedRow, insert_rows
from budget_trace_backend.main import app
from budget_trace_backend.services.ai import client as ai_client
from budget_trace_backend.services import categories as cat_svc
from budget_trace_backend.services import transactions as svc


@pytest.fixture()
def seeded_db(tmp_path: Path, monkeypatch) -> Path:
    target = tmp_path / "test.db"
    os.environ["BUDGET_TRACE_DB"] = str(target)
    # Block env-var fallback so AiKeyMissing reliably fires when expected.
    for var in ("ANTHROPIC_API_KEY", "OPENAI_API_KEY", "GEMINI_API_KEY", "GOOGLE_API_KEY"):
        monkeypatch.delenv(var, raising=False)
    seed.main(target)
    # A model is only selectable once fetched — these tests fake the chat call,
    # which still needs a real model id to record usage against.
    from budget_trace_backend import features
    from budget_trace_backend.services.ai import discovery
    discovery._replace_provider_models("anthropic", [
        discovery.DiscoveredModel(
            id="claude-test", provider="anthropic", display_name="claude-test",
            input_per_mtok=3.0, output_per_mtok=15.0,
            cache_write_per_mtok=None, cache_read_per_mtok=None, pricing_available=True),
    ])
    features.update_me(selected_model="claude-test")
    yield target
    os.environ.pop("BUDGET_TRACE_DB", None)


@pytest.fixture()
def client(seeded_db: Path) -> TestClient:
    return TestClient(app)


def _fake_chat_returning(assignments: list[dict]):
    """Build a stand-in for `ai.client.chat` that emits an `assign_categories`
    tool call with the supplied assignments."""

    def fake(*, model, system, messages, tools=None, max_tokens=2048):
        return {
            "content": None,
            "tool_calls": [{
                "id": "call_test",
                "name": "assign_categories",
                "arguments_json": json.dumps({"assignments": assignments}),
            }],
            "usage": {
                "input_tokens": 10, "output_tokens": 5,
                "cache_creation_input_tokens": 0, "cache_read_input_tokens": 0,
            },
            "finish_reason": "tool_calls",
        }
    return fake


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

    monkeypatch.setattr(
        categorizer,
        "ai_chat",
        _fake_chat_returning([
            {"transaction_id": ids[0], "category_path": "Living / Grocery"},
            {"transaction_id": ids[1], "category_path": "Living / Gas"},
        ]),
    )

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

    monkeypatch.setattr(
        categorizer,
        "ai_chat",
        _fake_chat_returning([
            # Hallucinated path — not in the category list at all.
            {"transaction_id": ids[0], "category_path": "Made Up / Imaginary"},
            # Another invalid path — different shape, still not real.
            {"transaction_id": ids[1], "category_path": "Also Fake"},
        ]),
    )

    result = categorizer.categorize_rows(ids)

    assert result["categorized"] == 0
    assert result["skipped_no_match"] == 2
    assert "error" not in result


def test_categorizer_accepts_parent_category_paths(seeded_db: Path, monkeypatch) -> None:
    """Non-leaf (parent) paths are valid assignment targets. The AI may pick
    a parent when no child is a clearer fit."""
    ids = _insert_uncategorised(seeded_db)

    monkeypatch.setattr(
        categorizer,
        "ai_chat",
        _fake_chat_returning([
            # "Living" is a parent in the seeded tree — accepted, not dropped.
            {"transaction_id": ids[0], "category_path": "Living"},
            {"transaction_id": ids[1], "category_path": "Living / Gas"},
        ]),
    )

    result = categorizer.categorize_rows(ids)

    assert result["categorized"] == 2
    assert result["skipped_no_match"] == 0
    assert "error" not in result

    with db_module.connect(seeded_db) as conn:
        rows = {r["id"]: r["category_id"] for r in conn.execute(
            "SELECT id, category_id FROM transactions WHERE id IN (?, ?)", ids,
        )}
    # Both rows landed on a real category (parent or child).
    assert all(cid is not None for cid in rows.values())


def test_categorizer_empty_ids_skips_ai_call(seeded_db: Path, monkeypatch) -> None:
    def boom(**kw):
        raise AssertionError("AI must not be called for empty input")
    monkeypatch.setattr(categorizer, "ai_chat", boom)

    result = categorizer.categorize_rows([])

    assert result == {
        "attempted": 0, "categorized": 0, "pre_applied": 0,
        "skipped_no_match": 0, "ai_usage": None,
    }


def test_categorizer_missing_key_degrades_gracefully(seeded_db: Path, monkeypatch) -> None:
    ids = _insert_uncategorised(seeded_db)

    def raise_missing(**kw):
        raise ai_client.AiKeyMissing("anthropic")
    monkeypatch.setattr(categorizer, "ai_chat", raise_missing)

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

    monkeypatch.setattr(
        categorizer,
        "ai_chat",
        _fake_chat_returning([
            {"transaction_id": grocery_ids[0], "category_path": "Living / Grocery"},
        ]),
    )

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

    monkeypatch.setattr(
        categorizer,
        "ai_chat",
        _fake_chat_returning([
            {"transaction_id": a["id"], "category_path": "Living / Grocery"},
            {"transaction_id": b["id"], "category_path": "Living / Gas"},  # conflicting
        ]),
    )

    result = categorizer.categorize_rows([a["id"], b["id"]])
    assert result["categorized"] == 2  # both rows categorized via cascade

    rows = {t["id"]: t for t in svc.list_transactions(merchant_query="dupe merch", limit=10)}
    # First wins: both end up Grocery, not Gas.
    assert rows[a["id"]]["category_path"] == "Living / Grocery"
    assert rows[b["id"]]["category_path"] == "Living / Grocery"


def test_categorizer_pre_applies_known_merchants_skipping_ai(
    seeded_db: Path, monkeypatch
) -> None:
    """When every input merchant is already in history, the AI must NOT be
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

    def boom(**kw):
        raise AssertionError(
            "AI must not be called when every input merchant is already known"
        )
    monkeypatch.setattr(categorizer, "ai_chat", boom)

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

    def boom(**kw):
        raise AssertionError("no AI please")
    monkeypatch.setattr(categorizer, "ai_chat", boom)

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
    known half, AI for the rest. Counts are accurate."""
    cat = cat_svc.create_category(name="From History", description="x")
    # Seed history for one merchant.
    svc.create_transaction(
        date="2026-03-15", merchant="KNOWN MERCH", amount=20.00, category_id=cat["id"],
    )

    # Import 4 rows: 2 KNOWN (will pre-apply), 2 NEW (will go to AI).
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
    monkeypatch.setattr(
        categorizer,
        "ai_chat",
        _fake_chat_returning([
            {"transaction_id": new_a_id, "category_path": "Living / Grocery"},
            {"transaction_id": new_b_id, "category_path": "Living / Gas"},
        ]),
    )

    out = categorizer.categorize_rows(new_ids)
    assert out["categorized"] == 4
    assert out["pre_applied"] == 2  # the 2 KNOWN rows
    assert out["skipped_no_match"] == 0
    assert out["ai_usage"] is not None  # AI WAS called for the 2 unknowns
