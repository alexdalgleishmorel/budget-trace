"""Tests for the Phase 1 category surface — REST routes + MCP write tools.

Both surfaces share `services/categories.py`, so most tests target the
service layer directly. Route-level tests just verify the HTTP plumbing
(status codes, JSON shape).
"""

from __future__ import annotations

import os
from pathlib import Path

import pytest
from fastapi.testclient import TestClient

from budget_trace_backend import db as db_module
from budget_trace_backend import mcp_server, seed
from budget_trace_backend.main import app
from budget_trace_backend.services import categories as svc


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


def test_create_under_existing_parent(seeded_db: Path) -> None:
    with db_module.connect(seeded_db) as conn:
        living = svc.list_categories_with_ids(conn)
        living_id = next(c["id"] for c in living if c["path"] == "Living")

    created = svc.create_category("Subscriptions", "Recurring services", living_id)
    assert created["path"] == "Living / Subscriptions"
    assert created["parent_id"] == living_id
    assert created["is_leaf"] is True


def test_create_top_level_when_no_parent(seeded_db: Path) -> None:
    created = svc.create_category("Misc", None, None)
    assert created["path"] == "Misc"
    assert created["parent_id"] is not None  # equals root id


def test_rename_changes_only_leaf_name(seeded_db: Path) -> None:
    renamed = mcp_server.rename_category("Living / Fun", "Entertainment")
    assert renamed["name"] == "Entertainment"
    assert renamed["path"] == "Living / Entertainment"


def test_move_category_into_descendant_rejected(seeded_db: Path) -> None:
    with pytest.raises(svc.Conflict):
        mcp_server.move_category("Living", new_parent_path="Living / Grocery")


def test_move_category_to_top_level(seeded_db: Path) -> None:
    moved = mcp_server.move_category("Living / Grocery", new_parent_path=None)
    assert moved["path"] == "Grocery"
    assert moved["parent_id"] is not None  # root


def test_delete_category_unassigns_transactions(seeded_db: Path) -> None:
    # Living / Grocery has a healthy stack of transactions in the seed.
    with db_module.connect(seeded_db) as conn:
        before = conn.execute(
            "SELECT COUNT(*) AS c FROM transactions WHERE category_id = "
            "(SELECT id FROM categories WHERE name = 'Grocery')"
        ).fetchone()["c"]
    assert before > 0

    result = mcp_server.delete_category("Living / Grocery")
    assert result["transactions_unassigned"] == before
    assert result["descendants_deleted"] == 0

    # Category is gone, transactions are now NULL.
    with db_module.connect(seeded_db) as conn:
        gone = conn.execute(
            "SELECT 1 FROM categories WHERE name = 'Grocery'"
        ).fetchone()
        unassigned = conn.execute(
            "SELECT COUNT(*) AS c FROM transactions WHERE merchant LIKE '%TRADER%' AND category_id IS NULL"
        ).fetchone()["c"]
    assert gone is None
    assert unassigned > 0


def test_delete_unknown_rejected(seeded_db: Path) -> None:
    with pytest.raises(svc.Conflict):
        mcp_server.delete_category("Unknown")


def test_delete_root_rejected_via_id(seeded_db: Path) -> None:
    with db_module.connect(seeded_db) as conn:
        root_id = svc.get_root_id(conn)
    with pytest.raises(svc.Conflict):
        svc.delete_category(root_id)


def test_update_description_clears_when_empty(seeded_db: Path) -> None:
    updated = mcp_server.update_category_description("Living / Fun", "")
    assert updated["description"] is None


# ── REST routes ──────────────────────────────────────────────────────────────


def test_get_categories_returns_paths_with_ids(client: TestClient) -> None:
    resp = client.get("/categories")
    assert resp.status_code == 200
    body = resp.json()
    paths = {c["path"] for c in body}
    assert "Living / Grocery" in paths
    assert "Budget" not in paths
    sample = next(c for c in body if c["path"] == "Living / Grocery")
    assert "id" in sample and "parent_id" in sample


def test_post_creates(client: TestClient) -> None:
    resp = client.post("/categories", json={"name": "TestCat", "description": "x"})
    assert resp.status_code == 201
    body = resp.json()
    assert body["name"] == "TestCat"
    assert body["path"] == "TestCat"


def test_patch_rename(client: TestClient) -> None:
    listed = client.get("/categories").json()
    fun_id = next(c["id"] for c in listed if c["path"] == "Living / Fun")
    resp = client.patch(f"/categories/{fun_id}", json={"name": "Entertainment"})
    assert resp.status_code == 200
    assert resp.json()["path"] == "Living / Entertainment"


def test_patch_with_explicit_null_description(client: TestClient) -> None:
    listed = client.get("/categories").json()
    grocery_id = next(c["id"] for c in listed if c["path"] == "Living / Grocery")
    resp = client.patch(f"/categories/{grocery_id}", json={"description": None})
    assert resp.status_code == 200
    assert resp.json()["description"] is None


def test_delete_returns_summary(client: TestClient) -> None:
    listed = client.get("/categories").json()
    travel_id = next(c["id"] for c in listed if c["path"] == "Savings / Travel")
    resp = client.delete(f"/categories/{travel_id}")
    assert resp.status_code == 200
    body = resp.json()
    assert body["deleted_id"] == travel_id
    assert body["transactions_unassigned"] >= 0


def test_delete_root_returns_409(client: TestClient) -> None:
    # Root id isn't in the listed paths, but we know it from the service.
    with db_module.connect() as conn:
        root_id = svc.get_root_id(conn)
    resp = client.delete(f"/categories/{root_id}")
    assert resp.status_code == 409


# ── POST /categories/seed_defaults ──────────────────────────────────────────


def test_seed_defaults_on_empty_tree(tmp_path: Path, monkeypatch) -> None:
    """Fresh DB with only the Budget root + default user — seed creates the
    expenses-only default tree."""
    target = tmp_path / "fresh.db"
    monkeypatch.setenv("BUDGET_TRACE_DB", str(target))
    from budget_trace_backend.main import app as fresh_app
    with TestClient(fresh_app) as c:
        # The lifespan has just initialized: schema + Budget root + default user.
        before = c.get("/categories").json()
        assert before == []  # Budget root is filtered out of the AI-facing path list

        resp = c.post("/categories/seed_defaults")
        assert resp.status_code == 200
        created = resp.json()

        paths = {row["path"] for row in created}
        # Spot-check structural expectations: flat top-level for daily-life
        # buckets, plus a nested Car group for vehicle-related expenses.
        assert "Grocery" in paths
        assert "Dining Out" in paths
        assert "Medical" in paths
        assert "Day-to-Day" in paths
        assert "Car" in paths
        assert "Car / Parking" in paths
        assert "Car / Gas" in paths
        assert "Car / Insurance" in paths
        # Old House / Living groups and Savings are gone.
        assert not any(p.startswith("House") for p in paths)
        assert not any(p.startswith("Living") for p in paths)
        assert not any(p.startswith("Savings") for p in paths)


def test_seed_defaults_refuses_when_tree_not_empty(client: TestClient) -> None:
    # The shared `client` fixture uses the seeded DB which already has the
    # full mock category tree.
    resp = client.post("/categories/seed_defaults")
    assert resp.status_code == 409
    assert resp.json()["detail"]["code"] == "categories_exist"
