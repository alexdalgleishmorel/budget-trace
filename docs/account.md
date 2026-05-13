# Account

Single-user settings for the local-dev build. There's a real `users` table (id=1 hardcoded) and a `/me` REST surface, but no auth — every request acts as user 1. The schema and the surface are designed to extend cleanly when auth lands.

## What lives on the user

- `features` — JSON blob of feature flags: `{ "ai": bool, "widgets": bool }`. The `ai` flag is **off** by default (requires a provider key to be useful); the `widgets` flag is **on** by default (see [`features.py::DEFAULT_ON_FLAGS`](../backend/src/budget_trace_backend/features.py)). Each gate:
  - `ai` — PDF / image / general AI parsing on `POST /transactions/import?parser=ai` (403 when off); auto-categorize-on-import via [`importers/categorizer.py`](../backend/src/budget_trace_backend/importers/categorizer.py); the Insights chat (`POST /chat/sessions/{id}/messages` returns 403 when off; historical reads stay open).
  - `widgets` — the Widgets tab and every `/dashboards/*`, `/widget-metrics`, `/chat/messages/{id}/save-to-dashboard`, `/ai-widget-audit` route (403 + `feature_disabled` when off). See [widgets.md](widgets.md).
- `selected_model` — a model id from [`services/ai/registry.py`](../backend/src/budget_trace_backend/services/ai/registry.py). Drives every AI call (chat, parser, auto-categorizer). `null` falls back to the `SELECTED_MODEL` env var, then the registry's `DEFAULT_MODEL`. Validated server-side; `PATCH` rejects unknown ids with 422.
- `theme` — legacy `system` | `light` | `dark` column. **Frontend ignores this** since the Arctic rework — the app is dark-only and `MaterialApp` hard-codes `themeMode: ThemeMode.dark`. The field stays in the DB and on the wire to preserve the API shape; nothing on the Account screen lets the user change it any more.
- `last_dashboard_id` — nullable FK-ish pointer to the dashboard the user was last viewing. `GET /dashboards/{id}` stamps it as a side effect so the Widgets tab can reopen on the same dashboard. Surfaced on `/me` for the frontend to seed initial navigation.

Per-provider API keys are stored in a separate table — [`ai_provider_keys(user_id, provider, api_key)`](../backend/src/budget_trace_backend/db.py) — one row per provider (`anthropic`, `openai`, `google`, …). The model registry tells the runtime which provider's key to use for any given model. Each provider also accepts an env-var fallback: `ANTHROPIC_API_KEY`, `OPENAI_API_KEY`, `GEMINI_API_KEY` (the names match each SDK's convention; LiteLLM uses them too).

## REST: `/me`

```
GET   /me                       → MeOut
PATCH /me  { partial fields }   → MeOut
```

`MeOut` shape:
```json
{
  "features": { "ai": false, "widgets": true },
  "theme": "system",
  "providers": [
    { "id": "anthropic", "display_name": "Anthropic", "env_var": "ANTHROPIC_API_KEY",
      "api_key_set": false, "env_fallback": false },
    { "id": "openai",    "display_name": "OpenAI",    "env_var": "OPENAI_API_KEY",
      "api_key_set": false, "env_fallback": false },
    { "id": "google",    "display_name": "Google",    "env_var": "GEMINI_API_KEY",
      "api_key_set": false, "env_fallback": false }
  ],
  "selected_model": "claude-sonnet-4-6",
  "selected_model_provider": "anthropic",
  "selected_model_key_available": false,
  "available_models": [
    { "id": "claude-opus-4-7",   "provider": "anthropic", "display_name": "Opus 4.7",
      "input_per_mtok": 15, "output_per_mtok": 75 },
    { "id": "claude-sonnet-4-6", "provider": "anthropic", "display_name": "Sonnet 4.6",
      "input_per_mtok": 3,  "output_per_mtok": 15 },
    { "id": "gpt-4o",            "provider": "openai",    "display_name": "GPT-4o",
      "input_per_mtok": 2.5, "output_per_mtok": 10 },
    { "id": "gemini-2.5-flash",  "provider": "google",    "display_name": "Gemini 2.5 Flash",
      "input_per_mtok": 0.3, "output_per_mtok": 2.5 }
    /* …registry continues */
  ],
  "ai_spent_usd": 0.0,
  "last_dashboard_id": null
}
```

Key values themselves are **never** returned — only `api_key_set` per provider, plus `env_fallback` to indicate the matching env var is present in the process.

To set or clear a key, `PATCH /me` with `{"provider_keys": {"anthropic": "sk-ant-…"}}`. `null` clears that provider's row; an empty string is a 422 — pass `null` instead. The dict is partial: only the providers you include get changed.

To switch model, `PATCH /me` with `{"selected_model": "gpt-4o"}`. `null` resets to env/default. Any value not in `available_models` is a 422. The route does **not** require a stored key for the picked model's provider — that's surfaced via `selected_model_key_available: false` so the UI can warn but the user can still save (handy when they're about to paste the key next).

`ai_spent_usd` is the cumulative locally-estimated cost of every AI call this app has made. Computed at insert time as `tokens × selected model's per-MTok price` and snapshotted into [`ai_usage`](../backend/src/budget_trace_backend/db.py). **This is an estimate, not your provider bill** — for the authoritative figure, check each provider's dashboard.

`PATCH` is partial: omit a field to leave it unchanged. `features` is a partial dict — sending `{"features": {"ai": true}}` flips just `ai` and leaves `widgets` (and any future flags) alone.

The `widgets` flag is `true` by default and can be flipped off via `PATCH /me {"features": {"widgets": false}}`. With it off, the tab disappears from the nav and every dashboard / save-chat / metric-registry / audit route 403s. There's no UI surface on the Account screen for it today — flip via API.

## UI: the Account screen

[frontend/lib/screens/account_screen.dart](../frontend/lib/screens/account_screen.dart). One card:

**AI features** — collapsible card. Tap the header to expand. The first row inside is the master "AI features" switch; when it's on, the card also reveals:
- **API keys** — one row per provider in `me.providers`, fully data-driven. Each row has a label, a status pill (Stored / Env / Not set), a masked text field with show/hide, and Save + Clear actions. Adding a provider on the backend automatically yields a new row here.
- **AI Spend** — read-only chip showing cumulative USD spent on AI, with the canonical disclaimer that the figure is estimated from token usage and the selected model's published per-MTok price (not the same as your provider bill).
- **Model** — dropdown built from `available_models`; each item shows `Provider — Model Name` plus per-MTok input/output rates. When the selected model's provider has no key, an inline warning appears beneath the dropdown. "Reset to default" sends `selected_model: null`.

There is no Appearance control. The app is dark-only after the Arctic rework — the `theme` field on `Me` is preserved on the wire but is never surfaced to the user (see the bullet above for the column's status).

Every control bubbles its update through `MeClient.update()` immediately and bubbles the resulting `Me` back up to `BudgetTraceApp` via `onMeChanged`. That triggers the Insights tab to show/hide, the Dropzone's AI toggle to appear/disappear, and the global AI-spend chip to refresh — all in one pass.

The same `AiSpendChip` widget renders the chip in the **Account screen** (cumulative total), the **Dropzone** in Expenses (cumulative total — co-located with the only non-chat AI surface), the **Insights chat header** (per-active-chat amount), and each row of the **chat history view**. Desktop's side nav has no chip; the metric only appears next to actual AI surfaces.

Open the screen via:
- **Mobile** — the gear icon in the top-left of any tab's header (replaces the legacy "Categories" / "Expenses" / "Insights" page titles, which were redundant with the bottom tab bar).
- **Desktop** — the **Account** entry at the bottom of the side nav.

## Env override

`BUDGET_TRACE_FEATURES=ai` still works as a force-on for the running process; it wins over the DB on the read path. Useful for tests / CI / reproducible dev shells.

Each provider has a documented env-var fallback for its API key (`ANTHROPIC_API_KEY`, `OPENAI_API_KEY`, `GEMINI_API_KEY`). When the corresponding env var is set, the `/me` response surfaces it via `env_fallback: true` and the Account screen renders the "Env" status pill. A stored key overrides the env var.

`SELECTED_MODEL` overrides the default model when no row-level `selected_model` is stored.

## Auth — TODO

The single-user assumption (`DEFAULT_USER_ID = 1`) lives in two places:

- [`backend/src/budget_trace_backend/features.py`](../backend/src/budget_trace_backend/features.py) — `get_me`/`update_me`/`get_flags`/`set_flag` all default to id=1.
- [`backend/src/budget_trace_backend/routes/me.py`](../backend/src/budget_trace_backend/routes/me.py) — the routes pass nothing, picking up the default.

When auth lands:

1. Add a session/JWT layer.
2. Replace the `user_id=1` defaults with a `user_id` derived from the request session.
3. Audit every other call site that reaches into `users` — there are no others today, but [`services/ai/client.py::_resolve_key()`](../backend/src/budget_trace_backend/services/ai/client.py) reads `get_me()` without a user_id, which will need threading.
4. Encrypt the `ai_provider_keys.api_key` column at rest. Until then, the Account screen carries a **plaintext-storage warning banner** so it's not silently surprising.

The route shapes (`/me`) and the frontend `Me` model are auth-agnostic and won't change.
