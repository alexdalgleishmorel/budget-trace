"""Provider-first model discovery: per-provider refresh + fetched-model store.

No real provider calls — refresh runs with no key (the selected provider is
skipped), and fetched models are injected directly to exercise selection,
provider scoping, and pricing flags.
"""

from __future__ import annotations

import os
from pathlib import Path

import pytest
from fastapi.testclient import TestClient

from budget_trace_backend import seed
from budget_trace_backend.main import app
from budget_trace_backend.services.ai import discovery


@pytest.fixture()
def seeded_db(tmp_path: Path, monkeypatch) -> Path:
    target = tmp_path / "test.db"
    os.environ["BUDGET_TRACE_DB"] = str(target)
    for var in ("ANTHROPIC_API_KEY", "OPENAI_API_KEY", "GEMINI_API_KEY", "GOOGLE_API_KEY"):
        monkeypatch.delenv(var, raising=False)
    seed.main(target)
    yield target
    os.environ.pop("BUDGET_TRACE_DB", None)


@pytest.fixture()
def client(seeded_db: Path) -> TestClient:
    return TestClient(app)


def _fetch(provider: str, *models: discovery.DiscoveredModel) -> None:
    discovery._replace_provider_models(provider, list(models))


def _model(id_: str, provider: str, priced: bool = True) -> discovery.DiscoveredModel:
    return discovery.DiscoveredModel(
        id=id_, provider=provider, display_name=id_,
        input_per_mtok=3.0 if priced else None,
        output_per_mtok=15.0 if priced else None,
        cache_write_per_mtok=None, cache_read_per_mtok=None,
        pricing_available=priced,
    )


def test_refresh_selected_provider_with_no_key_is_skipped(client: TestClient) -> None:
    # Default selected provider is anthropic; no key set anywhere.
    resp = client.post("/me/models/refresh")
    assert resp.status_code == 200
    body = resp.json()
    assert body["provider"]["provider"] == "anthropic"
    assert body["provider"]["skipped"] is True
    assert body["provider"]["ok"] is False
    assert body["provider"]["error"] is None
    assert body["available_models"] == []


def test_fetched_model_is_selectable(client: TestClient, seeded_db: Path) -> None:
    _fetch("anthropic", _model("claude-future-9", "anthropic"))

    body = client.get("/me").json()
    opt = next(m for m in body["available_models"] if m["id"] == "claude-future-9")
    assert opt["discovered"] is True
    assert opt["provider"] == "anthropic"

    resp = client.patch("/me", json={"selected_model": "claude-future-9"})
    assert resp.status_code == 200
    assert resp.json()["selected_model"] == "claude-future-9"
    assert resp.json()["selected_provider"] == "anthropic"


def test_available_models_scoped_to_selected_provider(
    client: TestClient, seeded_db: Path
) -> None:
    _fetch("anthropic", _model("claude-a", "anthropic"))
    _fetch("openai", _model("gpt-a", "openai"))

    # Selected provider defaults to anthropic → only its models show.
    ids = {m["id"] for m in client.get("/me").json()["available_models"]}
    assert ids == {"claude-a"}

    # Switch provider → see the other provider's models.
    client.patch("/me", json={"selected_provider": "openai"})
    ids = {m["id"] for m in client.get("/me").json()["available_models"]}
    assert ids == {"gpt-a"}


def test_unpriced_fetched_model_still_known(client: TestClient, seeded_db: Path) -> None:
    _fetch("anthropic", _model("claude-nopricing", "anthropic", priced=False))
    assert discovery.is_known_model("claude-nopricing") is True
    # No price → model_pricing returns None so spend records zero cost.
    assert discovery.model_pricing("claude-nopricing") is None
    opt = next(m for m in client.get("/me").json()["available_models"]
               if m["id"] == "claude-nopricing")
    assert opt["pricing_available"] is False


def test_refresh_replaces_provider_models(client: TestClient, seeded_db: Path) -> None:
    _fetch("anthropic", _model("old-model", "anthropic"))
    assert discovery.is_known_model("old-model") is True
    # A subsequent fetch for the same provider replaces the old set.
    _fetch("anthropic", _model("new-model", "anthropic"))
    assert discovery.is_known_model("old-model") is False
    assert discovery.is_known_model("new-model") is True
