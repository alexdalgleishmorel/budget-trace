"""Provider-agnostic AI client + model/provider registry.

`client.chat()` is the single entry every AI call site uses (chat orchestrator,
AI parser, auto-categorizer). It dispatches through LiteLLM based on the
selected model's provider; the registry is the source of truth for what
models and providers the app supports.
"""
