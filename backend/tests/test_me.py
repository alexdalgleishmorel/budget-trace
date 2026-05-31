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
    # Provider-first: defaults to Anthropic, no model picked, no models fetched.
    assert body["selected_provider"] == "anthropic"
    assert body["selected_provider_key_available"] is False
    assert body["selected_model"] == ""
    assert body["available_models"] == []
    assert body["ai_spent_usd"] == 0.0
    # Providers list is data-driven from the registry — at least the big 3.
    provider_ids = {p["id"] for p in body["providers"]}
    assert {"anthropic", "openai", "google"} <= provider_ids
    for p in body["providers"]:
        assert p["api_key_set"] is False
        assert p["env_fallback"] is False
        assert "display_name" in p
        assert "env_var" in p


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


def _fetch_anthropic_model(model_id: str = "claude-x") -> None:
    """Stand in for a live fetch so a model id is selectable."""
    from budget_trace_backend.services.ai import discovery
    discovery._replace_provider_models("anthropic", [
        discovery.DiscoveredModel(
            id=model_id, provider="anthropic", display_name=model_id,
            input_per_mtok=3.0, output_per_mtok=15.0,
            cache_write_per_mtok=None, cache_read_per_mtok=None, pricing_available=True),
    ])


def test_patch_me_set_and_clear_model(client: TestClient) -> None:
    _fetch_anthropic_model("claude-x")
    resp = client.patch("/me", json={"selected_model": "claude-x"})
    assert resp.status_code == 200
    body = resp.json()
    assert body["selected_model"] == "claude-x"
    assert body["selected_provider"] == "anthropic"

    # null clears back to "no model picked".
    resp = client.patch("/me", json={"selected_model": None})
    assert resp.status_code == 200
    assert resp.json()["selected_model"] == ""


def test_patch_me_switch_provider_clears_model(client: TestClient) -> None:
    _fetch_anthropic_model("claude-x")
    client.patch("/me", json={"selected_model": "claude-x"})
    # Switching to a different provider invalidates the model.
    resp = client.patch("/me", json={"selected_provider": "openai"})
    assert resp.status_code == 200
    body = resp.json()
    assert body["selected_provider"] == "openai"
    assert body["selected_model"] == ""
    # available_models is scoped to the selected provider (openai has none fetched).
    assert body["available_models"] == []


def test_patch_me_unknown_provider_selection_returns_422(client: TestClient) -> None:
    resp = client.patch("/me", json={"selected_provider": "acme-ai"})
    assert resp.status_code == 422


def test_selected_provider_key_available_flips_on_key_set(client: TestClient) -> None:
    client.patch("/me", json={"selected_provider": "openai"})
    assert client.get("/me").json()["selected_provider_key_available"] is False
    client.patch("/me", json={"provider_keys": {"openai": "sk-openai-test"}})
    assert client.get("/me").json()["selected_provider_key_available"] is True


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
