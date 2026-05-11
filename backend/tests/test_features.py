"""Feature-flag tests for the single `ai` flag. Don't touch the Anthropic API."""

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


def test_get_flags_default_false(seeded_db: Path) -> None:
    # `ai` is off-by-default (requires a key to be useful); `widgets` is
    # on-by-default so the tab is visible on a fresh install.
    assert features.get_flags() == {"ai": False, "widgets": True}


def test_set_flag_persists(seeded_db: Path) -> None:
    features.set_flag("ai", True)
    assert features.get_flags() == {"ai": True, "widgets": True}


def test_env_override_enables_flag(seeded_db: Path, monkeypatch) -> None:
    monkeypatch.setenv("BUDGET_TRACE_FEATURES", "ai")
    assert features.get_flags() == {"ai": True, "widgets": True}


def test_widgets_flag_can_be_disabled(seeded_db: Path) -> None:
    features.set_flag("widgets", False)
    assert features.get_flags() == {"ai": False, "widgets": False}


def test_set_flag_unknown_raises(seeded_db: Path) -> None:
    with pytest.raises(ValueError):
        features.set_flag("not_a_flag", True)


def test_old_flag_names_are_gone() -> None:
    # Hard-coded sanity check so a future refactor that re-introduces the
    # old flags trips here, not silently in route handlers.
    assert "ai_import" not in features.KNOWN_FLAGS
    assert "ai_mutations" not in features.KNOWN_FLAGS
