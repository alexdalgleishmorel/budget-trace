"""GET /me + PATCH /me round-trips. No Anthropic calls."""

from __future__ import annotations

import os
from pathlib import Path

import pytest
from fastapi.testclient import TestClient

from budget_trace_backend import features, seed
from budget_trace_backend.main import app


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


def test_get_me_defaults(client: TestClient) -> None:
    resp = client.get("/me")
    assert resp.status_code == 200
    body = resp.json()
    assert body["features"] == {"ai": False}
    assert body["theme"] == "system"
    assert body["anthropic_api_key_set"] is False
    assert body["anthropic_admin_api_key_set"] is False
    assert body["anthropic_model"] == "claude-sonnet-4-6"
    assert body["ai_spent_usd"] == 0.0
    assert body["ai_spent_source"] == "estimated"
    assert {m["id"] for m in body["available_models"]} == {
        "claude-opus-4-7", "claude-sonnet-4-6", "claude-haiku-4-5-20251001",
    }


def test_patch_me_set_and_clear_admin_key(client: TestClient) -> None:
    resp = client.patch("/me", json={"anthropic_admin_api_key": "sk-ant-admin-test"})
    assert resp.status_code == 200
    assert resp.json()["anthropic_admin_api_key_set"] is True

    resp = client.patch("/me", json={"anthropic_admin_api_key": None})
    assert resp.status_code == 200
    assert resp.json()["anthropic_admin_api_key_set"] is False


def test_patch_me_set_and_reset_model(client: TestClient) -> None:
    resp = client.patch("/me", json={"anthropic_model": "claude-haiku-4-5-20251001"})
    assert resp.status_code == 200
    assert resp.json()["anthropic_model"] == "claude-haiku-4-5-20251001"

    resp = client.patch("/me", json={"anthropic_model": None})
    assert resp.status_code == 200
    assert resp.json()["anthropic_model"] == "claude-sonnet-4-6"


def test_patch_me_unknown_model_returns_422(client: TestClient) -> None:
    resp = client.patch("/me", json={"anthropic_model": "claude-bogus-9-9"})
    assert resp.status_code == 422


def test_patch_me_features_round_trip(client: TestClient) -> None:
    resp = client.patch("/me", json={"features": {"ai": True}})
    assert resp.status_code == 200
    assert resp.json()["features"] == {"ai": True}
    assert client.get("/me").json()["features"] == {"ai": True}


def test_patch_me_theme(client: TestClient) -> None:
    resp = client.patch("/me", json={"theme": "dark"})
    assert resp.status_code == 200
    assert resp.json()["theme"] == "dark"


def test_patch_me_invalid_theme_returns_422(client: TestClient) -> None:
    resp = client.patch("/me", json={"theme": "midnight"})
    assert resp.status_code == 422


def test_patch_me_set_and_clear_api_key(client: TestClient, seeded_db: Path) -> None:
    # Set
    resp = client.patch("/me", json={"anthropic_api_key": "sk-test-123"})
    assert resp.status_code == 200
    assert resp.json()["anthropic_api_key_set"] is True
    # The key value itself is stored — verify via the internal accessor, not
    # the response (which intentionally never echoes it).
    assert features.get_me()["anthropic_api_key"] == "sk-test-123"

    # Clear with explicit null
    resp = client.patch("/me", json={"anthropic_api_key": None})
    assert resp.status_code == 200
    assert resp.json()["anthropic_api_key_set"] is False
    assert features.get_me()["anthropic_api_key"] is None


def test_patch_me_empty_string_key_returns_422(client: TestClient) -> None:
    resp = client.patch("/me", json={"anthropic_api_key": ""})
    assert resp.status_code == 422


def test_patch_me_omitted_field_unchanged(client: TestClient) -> None:
    client.patch("/me", json={"theme": "light", "anthropic_api_key": "sk-keep"})
    # Now only PATCH theme — key must remain set.
    resp = client.patch("/me", json={"theme": "dark"})
    assert resp.status_code == 200
    body = resp.json()
    assert body["theme"] == "dark"
    assert body["anthropic_api_key_set"] is True


def test_patch_me_unknown_feature_returns_422(client: TestClient) -> None:
    resp = client.patch("/me", json={"features": {"not_a_flag": True}})
    assert resp.status_code == 422


def test_old_features_route_is_gone(client: TestClient) -> None:
    resp = client.get("/me/features")
    assert resp.status_code == 404
