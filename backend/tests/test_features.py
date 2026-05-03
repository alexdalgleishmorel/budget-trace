"""Feature-flag tests. Don't touch the Anthropic API."""

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


def test_get_features_defaults_all_false(seeded_db: Path) -> None:
    flags = features.get_flags()
    assert flags == {"ai_import": False, "ai_mutations": False}


def test_set_flag_persists(seeded_db: Path) -> None:
    features.set_flag("ai_import", True)
    flags = features.get_flags()
    assert flags["ai_import"] is True
    assert flags["ai_mutations"] is False


def test_env_override_enables_flag(seeded_db: Path, monkeypatch) -> None:
    monkeypatch.setenv("BUDGET_TRACE_FEATURES", "ai_mutations,ai_import")
    flags = features.get_flags()
    assert flags == {"ai_import": True, "ai_mutations": True}


def test_set_flag_unknown_raises(seeded_db: Path) -> None:
    with pytest.raises(ValueError):
        features.set_flag("not_a_flag", True)


def test_me_features_route(client: TestClient) -> None:
    resp = client.get("/me/features")
    assert resp.status_code == 200
    assert resp.json() == {"ai_import": False, "ai_mutations": False}


def test_import_ai_unblocked_when_flag_on(client: TestClient, monkeypatch) -> None:
    monkeypatch.setenv("BUDGET_TRACE_FEATURES", "ai_import")

    # Stub the AI parser — the actual Anthropic call needs an API key and
    # network. We just verify the route reaches the parser and the response
    # carries `ai_usage`.
    from budget_trace_backend.importers import ai_parser
    from budget_trace_backend.importers.common import ImportedRow

    def fake_parse(content, *, mime):
        return (
            [ImportedRow(date="2026-04-15", merchant="FAKE AI MERCHANT", amount=12.34)],
            [],
            {"input_tokens": 100, "output_tokens": 20},
        )

    monkeypatch.setattr(ai_parser, "parse_with_ai", fake_parse)

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
