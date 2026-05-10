"""services/ai/client.py — provider dispatch + key resolution."""

from __future__ import annotations

import os
from pathlib import Path

import pytest

from budget_trace_backend import seed
from budget_trace_backend import features
from budget_trace_backend.services.ai import client as ai_client
from budget_trace_backend.services.ai import registry


@pytest.fixture()
def seeded_db(tmp_path: Path, monkeypatch) -> Path:
    target = tmp_path / "test.db"
    os.environ["BUDGET_TRACE_DB"] = str(target)
    for var in ("ANTHROPIC_API_KEY", "OPENAI_API_KEY", "GEMINI_API_KEY", "GOOGLE_API_KEY"):
        monkeypatch.delenv(var, raising=False)
    seed.main(target)
    yield target
    os.environ.pop("BUDGET_TRACE_DB", None)


def test_get_selected_model_defaults_to_registry_default(seeded_db: Path) -> None:
    assert ai_client.get_selected_model() == registry.DEFAULT_MODEL


def test_get_selected_model_respects_db(seeded_db: Path) -> None:
    features.update_me(selected_model="gpt-4o")
    assert ai_client.get_selected_model() == "gpt-4o"


def test_get_selected_model_env_fallback(seeded_db: Path, monkeypatch) -> None:
    monkeypatch.setenv("SELECTED_MODEL", "gpt-4o-mini")
    assert ai_client.get_selected_model() == "gpt-4o-mini"


def test_chat_raises_for_unknown_model(seeded_db: Path) -> None:
    with pytest.raises(ValueError):
        ai_client.chat(model="nope-1", system="", messages=[])


def test_chat_raises_aikeymissing_with_provider(seeded_db: Path) -> None:
    # No keys set anywhere. Selected model defaults to Anthropic.
    with pytest.raises(ai_client.AiKeyMissing) as excinfo:
        ai_client.chat(model="claude-sonnet-4-6", system="", messages=[])
    assert excinfo.value.provider == "anthropic"
    assert excinfo.value.code == "ai_key_missing"


def test_chat_raises_aikeymissing_for_openai_when_selected(seeded_db: Path) -> None:
    with pytest.raises(ai_client.AiKeyMissing) as excinfo:
        ai_client.chat(model="gpt-4o", system="", messages=[])
    assert excinfo.value.provider == "openai"


def test_provider_env_present_reads_env(seeded_db: Path, monkeypatch) -> None:
    monkeypatch.setenv("OPENAI_API_KEY", "sk-test")
    assert ai_client.provider_env_present("openai") is True
    assert ai_client.provider_env_present("anthropic") is False


def test_chat_dispatches_to_litellm_with_provider_prefix(
    seeded_db: Path, monkeypatch
) -> None:
    """Verifies the model id gets the provider prefix and the stored key is
    passed through. No actual API call."""
    features.update_me(provider_keys={"anthropic": "sk-ant-test"})

    captured: dict = {}

    class _Choice:
        def __init__(self):
            self.message = type("M", (), {"content": "hi", "tool_calls": None})()
            self.finish_reason = "stop"

    class _Resp:
        def __init__(self):
            self.choices = [_Choice()]
            self.usage = type("U", (), {
                "prompt_tokens": 1, "completion_tokens": 2,
                "cache_creation_input_tokens": 0, "cache_read_input_tokens": 0,
            })()

    def fake_completion(**kwargs):
        captured.update(kwargs)
        return _Resp()

    import litellm  # type: ignore
    monkeypatch.setattr(litellm, "completion", fake_completion)

    out = ai_client.chat(
        model="claude-sonnet-4-6",
        system="hello",
        messages=[{"role": "user", "content": "x"}],
    )
    assert captured["model"] == "anthropic/claude-sonnet-4-6"
    assert captured["api_key"] == "sk-ant-test"
    # System prompt threaded as the first message.
    assert captured["messages"][0]["role"] == "system"
    assert out["content"] == "hi"
    assert out["usage"]["input_tokens"] == 1
    assert out["usage"]["output_tokens"] == 2
