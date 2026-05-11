"""GET /me + PATCH /me round-trips. No AI calls."""

from __future__ import annotations

import os
from pathlib import Path

import pytest
from fastapi.testclient import TestClient

from budget_trace_backend import features, seed
from budget_trace_backend.main import app


@pytest.fixture()
def seeded_db(tmp_path: Path, monkeypatch) -> Path:
    target = tmp_path / "test.db"
    os.environ["BUDGET_TRACE_DB"] = str(target)
    # Ensure env-fallbacks for provider keys don't leak from the host shell.
    for var in ("ANTHROPIC_API_KEY", "OPENAI_API_KEY", "GEMINI_API_KEY", "GOOGLE_API_KEY"):
        monkeypatch.delenv(var, raising=False)
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
    assert body["features"] == {"ai": False, "widgets": True}
    assert body["theme"] == "system"
    assert body["selected_model"] == "claude-sonnet-4-6"
    assert body["selected_model_provider"] == "anthropic"
    assert body["selected_model_key_available"] is False
    assert body["ai_spent_usd"] == 0.0
    # Providers list is data-driven from the registry — at least the big 3.
    provider_ids = {p["id"] for p in body["providers"]}
    assert {"anthropic", "openai", "google"} <= provider_ids
    for p in body["providers"]:
        assert p["api_key_set"] is False
        assert p["env_fallback"] is False
        assert "display_name" in p
        assert "env_var" in p
    # Available models include Anthropic + others.
    model_ids = {m["id"] for m in body["available_models"]}
    assert {"claude-opus-4-7", "claude-sonnet-4-6", "claude-haiku-4-5-20251001"} <= model_ids
    # Each model carries its provider so the dropdown can group / label.
    for m in body["available_models"]:
        assert "provider" in m


def test_patch_me_set_and_clear_provider_key(client: TestClient, seeded_db: Path) -> None:
    resp = client.patch("/me", json={"provider_keys": {"anthropic": "sk-ant-test"}})
    assert resp.status_code == 200
    body = resp.json()
    anth = next(p for p in body["providers"] if p["id"] == "anthropic")
    assert anth["api_key_set"] is True
    # Other providers still empty.
    other = next(p for p in body["providers"] if p["id"] == "openai")
    assert other["api_key_set"] is False
    # Internal accessor sees the actual key (not echoed via the route).
    assert features.get_me()["provider_keys"]["anthropic"] == "sk-ant-test"

    # Clear with null.
    resp = client.patch("/me", json={"provider_keys": {"anthropic": None}})
    assert resp.status_code == 200
    anth = next(p for p in resp.json()["providers"] if p["id"] == "anthropic")
    assert anth["api_key_set"] is False
    assert "anthropic" not in features.get_me()["provider_keys"]


def test_patch_me_multiple_provider_keys_in_one_request(client: TestClient) -> None:
    resp = client.patch("/me", json={
        "provider_keys": {"anthropic": "sk-ant", "openai": "sk-openai"},
    })
    assert resp.status_code == 200
    by_id = {p["id"]: p for p in resp.json()["providers"]}
    assert by_id["anthropic"]["api_key_set"] is True
    assert by_id["openai"]["api_key_set"] is True
    assert by_id["google"]["api_key_set"] is False


def test_patch_me_empty_string_key_returns_422(client: TestClient) -> None:
    resp = client.patch("/me", json={"provider_keys": {"anthropic": ""}})
    assert resp.status_code == 422


def test_patch_me_unknown_provider_returns_422(client: TestClient) -> None:
    resp = client.patch("/me", json={"provider_keys": {"acme-ai": "sk-x"}})
    assert resp.status_code == 422


def test_patch_me_set_and_reset_model(client: TestClient) -> None:
    resp = client.patch("/me", json={"selected_model": "claude-haiku-4-5-20251001"})
    assert resp.status_code == 200
    body = resp.json()
    assert body["selected_model"] == "claude-haiku-4-5-20251001"
    assert body["selected_model_provider"] == "anthropic"

    resp = client.patch("/me", json={"selected_model": None})
    assert resp.status_code == 200
    assert resp.json()["selected_model"] == "claude-sonnet-4-6"


def test_patch_me_select_openai_model_flips_provider(client: TestClient) -> None:
    resp = client.patch("/me", json={"selected_model": "gpt-4o"})
    assert resp.status_code == 200
    body = resp.json()
    assert body["selected_model"] == "gpt-4o"
    assert body["selected_model_provider"] == "openai"
    # No OpenAI key set yet → flag should report unavailable.
    assert body["selected_model_key_available"] is False


def test_selected_model_key_available_flips_on_key_set(client: TestClient) -> None:
    # Pick an OpenAI model, then add the matching key — flag should flip.
    client.patch("/me", json={"selected_model": "gpt-4o"})
    assert client.get("/me").json()["selected_model_key_available"] is False
    client.patch("/me", json={"provider_keys": {"openai": "sk-openai-test"}})
    assert client.get("/me").json()["selected_model_key_available"] is True


def test_patch_me_unknown_model_returns_422(client: TestClient) -> None:
    resp = client.patch("/me", json={"selected_model": "claude-bogus-9-9"})
    assert resp.status_code == 422


def test_patch_me_features_round_trip(client: TestClient) -> None:
    resp = client.patch("/me", json={"features": {"ai": True}})
    assert resp.status_code == 200
    assert resp.json()["features"] == {"ai": True, "widgets": True}
    assert client.get("/me").json()["features"] == {"ai": True, "widgets": True}


def test_patch_me_theme(client: TestClient) -> None:
    resp = client.patch("/me", json={"theme": "dark"})
    assert resp.status_code == 200
    assert resp.json()["theme"] == "dark"


def test_patch_me_invalid_theme_returns_422(client: TestClient) -> None:
    resp = client.patch("/me", json={"theme": "midnight"})
    assert resp.status_code == 422


def test_patch_me_omitted_field_unchanged(client: TestClient) -> None:
    client.patch("/me", json={
        "theme": "light",
        "provider_keys": {"anthropic": "sk-keep"},
    })
    # Now only PATCH theme — key must remain set.
    resp = client.patch("/me", json={"theme": "dark"})
    assert resp.status_code == 200
    body = resp.json()
    assert body["theme"] == "dark"
    anth = next(p for p in body["providers"] if p["id"] == "anthropic")
    assert anth["api_key_set"] is True


def test_patch_me_unknown_feature_returns_422(client: TestClient) -> None:
    resp = client.patch("/me", json={"features": {"not_a_flag": True}})
    assert resp.status_code == 422


def test_patch_me_legacy_fields_rejected(client: TestClient) -> None:
    # The old Anthropic-specific fields are gone — extra="forbid" rejects them.
    resp = client.patch("/me", json={"anthropic_api_key": "sk-foo"})
    assert resp.status_code == 422


def test_env_fallback_surfaces_in_providers(client: TestClient, monkeypatch) -> None:
    monkeypatch.setenv("OPENAI_API_KEY", "sk-from-env")
    body = client.get("/me").json()
    openai = next(p for p in body["providers"] if p["id"] == "openai")
    assert openai["env_fallback"] is True
    assert openai["api_key_set"] is False
