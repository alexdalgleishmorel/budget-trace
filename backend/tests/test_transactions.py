"""Tests for the Phase 2 transaction surface — REST routes + MCP write tools.

Same fixture pattern as test_categories.py."""

from __future__ import annotations

import os
from pathlib import Path

import pytest
from fastapi.testclient import TestClient

from budget_trace_backend import db as db_module
from budget_trace_backend import mcp_server, seed
from budget_trace_backend.main import app
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


# ── Service layer ────────────────────────────────────────────────────────────


def test_create_minimal(seeded_db: Path) -> None:
    row = svc.create_transaction(
        date="2026-04-15", merchant="TEST MERCHANT", amount=12.34,
    )
    assert row["merchant"] == "TEST MERCHANT"
    assert row["category_id"] is None
    assert row["category_path"] is None


def test_create_with_invalid_category_rejected(seeded_db: Path) -> None:
    with pytest.raises(svc.NotFound):
        svc.create_transaction(
            date="2026-04-15", merchant="X", amount=1.0, category_id=999999,
        )


def test_set_category_by_id_round_trip(seeded_db: Path) -> None:
    txns = svc.list_transactions(uncategorised=True, limit=1)
    assert txns
    tid = txns[0]["id"]

    with db_module.connect(seeded_db) as conn:
        grocery_id = next(c["id"] for c in
                          cat_svc.list_categories_with_ids(conn) if c["path"] == "Living / Grocery")

    updated = svc.set_category_by_id(tid, grocery_id)
    assert updated["category_id"] == grocery_id
    assert updated["category_path"] == "Living / Grocery"

    # Unassign by passing None
    cleared = svc.set_category_by_id(tid, None)
    assert cleared["category_id"] is None


def test_bulk_rename_merchant(seeded_db: Path) -> None:
    before = len(svc.list_transactions(merchant_query="STARBUCKS", limit=500))
    assert before > 0

    out = svc.bulk_rename_merchant("STARBUCKS #4419", "STARBUCKS RIVERSIDE")
    assert out["updated"] == before

    after_old = svc.list_transactions(merchant_query="STARBUCKS #4419", limit=500)
    after_new = svc.list_transactions(merchant_query="STARBUCKS RIVERSIDE", limit=500)
    assert after_old == []
    assert len(after_new) == before


def test_delete_transaction(seeded_db: Path) -> None:
    txns = svc.list_transactions(limit=1)
    tid = txns[0]["id"]
    svc.delete_transaction(tid)
    with pytest.raises(svc.NotFound):
        svc.delete_transaction(tid)


# ── MCP write tools (path-based) ─────────────────────────────────────────────


def test_set_transaction_category_via_mcp(seeded_db: Path) -> None:
    txns = svc.list_transactions(uncategorised=True, limit=1)
    tid = txns[0]["id"]
    updated = mcp_server.set_transaction_category(tid, "Living / Fun")
    assert updated["category_path"] == "Living / Fun"


def test_bulk_categorise_merchant_via_mcp(seeded_db: Path) -> None:
    out = mcp_server.bulk_categorise_merchant("STARBUCKS #4419", "Living / Fun")
    assert out["updated"] > 0
    matches = svc.list_transactions(merchant_query="STARBUCKS", limit=500)
    assert all(m["category_path"] == "Living / Fun" for m in matches)


def test_update_transaction_via_mcp(seeded_db: Path) -> None:
    tid = svc.list_transactions(limit=1)[0]["id"]
    updated = mcp_server.update_transaction(
        tid, merchant="RENAMED", category_path="Living / Grocery",
    )
    assert updated["merchant"] == "RENAMED"
    assert updated["category_path"] == "Living / Grocery"


def test_update_transaction_unassigns_with_empty_path(seeded_db: Path) -> None:
    txns = svc.list_transactions(category_path="Living / Grocery", limit=1)
    tid = txns[0]["id"]
    updated = mcp_server.update_transaction(tid, category_path="")
    assert updated["category_id"] is None


# ── REST routes ──────────────────────────────────────────────────────────────


def test_get_transactions_with_filter(client: TestClient) -> None:
    resp = client.get("/transactions", params={"limit": 5, "category_path": "Living / Grocery"})
    assert resp.status_code == 200
    body = resp.json()
    assert len(body) == 5
    assert all(r["category_path"] == "Living / Grocery" for r in body)


def test_patch_assigns_category(client: TestClient) -> None:
    listed = client.get("/transactions", params={"uncategorised": True, "limit": 1}).json()
    tid = listed[0]["id"]
    cats = client.get("/categories").json()
    fun_id = next(c["id"] for c in cats if c["path"] == "Living / Fun")

    resp = client.patch(f"/transactions/{tid}", json={"category_id": fun_id})
    assert resp.status_code == 200
    assert resp.json()["category_id"] == fun_id


def test_patch_unassigns_with_explicit_null(client: TestClient) -> None:
    listed = client.get("/transactions",
                        params={"category_path": "Living / Grocery", "limit": 1}).json()
    tid = listed[0]["id"]
    resp = client.patch(f"/transactions/{tid}", json={"category_id": None})
    assert resp.status_code == 200
    assert resp.json()["category_id"] is None


def test_bulk_rename_route(client: TestClient) -> None:
    resp = client.post("/transactions/bulk_rename", json={
        "from_merchant": "SHELL OIL", "to_merchant": "SHELL FUEL",
    })
    assert resp.status_code == 200
    assert resp.json()["updated"] > 0


def test_delete_returns_summary(client: TestClient) -> None:
    listed = client.get("/transactions", params={"limit": 1}).json()
    tid = listed[0]["id"]
    resp = client.delete(f"/transactions/{tid}")
    assert resp.status_code == 200
    assert resp.json() == {"deleted_id": tid}
