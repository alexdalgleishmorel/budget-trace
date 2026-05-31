# Account

Settings for the single local user. This is a local single-user app: there's one `users` row (id=1 hardcoded) and a `/me` REST surface, and **no auth** — every request acts as user 1. All data, including API keys, lives only in the local SQLite file (a Docker volume when run via the image).

## What lives on the user

- `features` — JSON blob of feature flags: `{ "ai": bool, "widgets": bool }`. The `ai` flag is **off** by default (requires a provider key to be useful); the `widgets` flag is **on** by default (see [`features.py::DEFAULT_ON_FLAGS`](../backend/src/budget_trace_backend/features.py)). Each gate:
  - `ai` — PDF / image / general AI parsing on `POST /transactions/import?parser=ai` (403 when off); auto-categorize-on-import via [`importers/categorizer.py`](../backend/src/budget_trace_backend/importers/categorizer.py); the Insights chat (`POST /chat/sessions/{id}/messages` returns 403 when off; historical reads stay open).
  - `widgets` — the Widgets tab and every `/dashboards/*`, `/widget-metrics`, `/chat/messages/{id}/save-to-dashboard`, `/ai-widget-audit` route (403 + `feature_disabled` when off). See [widgets.md](widgets.md).
- `selected_provider` — the generic provider the user picked: `anthropic` | `openai` | `google`. Defaults to `anthropic`. Its key is used for every AI call, and its fetched models are the only selectable ones. Switching it clears `selected_model`.
- `selected_model` — a model id **fetched live** from the selected provider (see `discovered_models` and [`services/ai/discovery.py`](../backend/src/budget_trace_backend/services/ai/discovery.py)). Drives every AI call (chat, parser, auto-categorizer). **There is no hardcoded model catalog and no default model** — `null`/empty until the user fetches a provider's models and picks one (`SELECTED_MODEL` env can pin one for power users). `PATCH` rejects ids that aren't in the fetched catalog with 422. When nothing is selected, AI calls return `400 no_model_selected`.
- `theme` — legacy `system` | `light` | `dark` column. **Frontend ignores this** since the Arctic rework — the app is dark-only and `MaterialApp` hard-codes `themeMode: ThemeMode.dark`. The field stays in the DB and on the wire to preserve the API shape; nothing on the Account screen lets the user change it any more.
- `last_dashboard_id` — nullable FK-ish pointer to the dashboard the user was last viewing. `GET /dashboards/{id}` stamps it as a side effect so the Widgets tab can reopen on the same dashboard. Surfaced on `/me` for the frontend to seed initial navigation.

Per-provider API keys are stored in a separate table — [`ai_provider_keys(user_id, provider, api_key)`](../backend/src/budget_trace_backend/db.py) — one row per provider (`anthropic`, `openai`, `google`, …). Each provider also accepts an env-var fallback: `ANTHROPIC_API_KEY`, `OPENAI_API_KEY`, `GEMINI_API_KEY` (the names match each SDK's convention; LiteLLM uses them too).

## REST: `/me`

```
GET   /me                       → MeOut
PATCH /me  { partial fields }   → MeOut
POST  /me/models/refresh        → { provider, available_models[] }   # the selected provider
```

`MeOut` shape (fresh user — provider chosen, nothing fetched yet):
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
  "selected_provider": "anthropic",
  "selected_provider_key_available": false,
  "selected_model": "",
  "available_models": [],
  "ai_spent_usd": 0.0,
  "last_dashboard_id": null
}
```

After fetching, `available_models` holds the **selected provider's** fetched models, e.g. `{ "id": "claude-…", "provider": "anthropic", "display_name": "…", "input_per_mtok": 3, "output_per_mtok": 15, "discovered": true, "pricing_available": true }`. `pricing_available` is `false` when the rate isn't in LiteLLM's cost table.

Key values themselves are **never** returned — only `api_key_set` per provider, plus `env_fallback` to indicate the matching env var is present in the process.

To set or clear a key, `PATCH /me` with `{"provider_keys": {"anthropic": "sk-ant-…"}}`. `null` clears that provider's row; an empty string is a 422 — pass `null` instead. The dict is partial.

To switch provider, `PATCH /me` with `{"selected_provider": "openai"}` — this clears `selected_model` (it belonged to the old provider) and `available_models` reflects the new provider's previously-fetched set. To pick a model, `PATCH /me` with `{"selected_model": "<id>"}` (must be in the fetched catalog, else 422); `null` clears it. The route doesn't require a stored key to select — `selected_provider_key_available: false` lets the UI warn while you paste the key next.

### `POST /me/models/refresh` — fetch the selected provider's models

There is no hardcoded model catalog. `POST /me/models/refresh` fetches the **currently-selected provider's** live model list using its key, prices each model from LiteLLM's bundled cost table where it can, and **replaces** that provider's rows in `discovered_models`. Logic lives in [`services/ai/discovery.py`](../backend/src/budget_trace_backend/services/ai/discovery.py).

- **Per-provider, isolated** — a provider that's down, has a bad key, or no key set is reported in the `provider` result (`ok`, `skipped`, `error`, `discovered_count`) and never 500s the call.
- **Replace, not merge** — each fetch swaps that provider's whole set, so models the provider dropped disappear.
- **Unknown pricing** — chat models absent from the cost table are stored with `pricing_available: false`; they're still selectable, and spend records those calls at zero cost.

Fetched models flow through `discovery.is_known_model` / `provider_of` / `model_pricing`, which `PATCH /me` validation, the AI client, and spend computation all consult.

`ai_spent_usd` is the cumulative locally-estimated cost of every AI call this app has made. Computed at insert time as `tokens × selected model's per-MTok price` and snapshotted into [`ai_usage`](../backend/src/budget_trace_backend/db.py). **This is an estimate, not your provider bill** — for the authoritative figure, check each provider's dashboard.

`PATCH` is partial: omit a field to leave it unchanged. `features` is a partial dict — sending `{"features": {"ai": true}}` flips just `ai` and leaves `widgets` (and any future flags) alone.

The `widgets` flag is `true` by default and can be flipped off via `PATCH /me {"features": {"widgets": false}}`. With it off, the tab disappears from the nav and every dashboard / save-chat / metric-registry / audit route 403s. There's no UI surface on the Account screen for it today — flip via API.

## UI: the Account screen

[frontend/lib/screens/account_screen.dart](../frontend/lib/screens/account_screen.dart). A local-data disclaimer banner at the top (everything stays on this machine), then one flat card — no collapsible — with these sections in order:

- **AI features** (top) — the master toggle gating parser / auto-categorize / Insights chat. When it's **off**, the rows below are hidden (they'd be inert). Turning it on reveals the provider-first flow:
- **Provider** — a dropdown of the generic providers (Anthropic / OpenAI / Google) from `me.providers`. Switching it `PATCH`es `selected_provider` (which clears the model) and swaps the key field + model list.
- **API key** — for the **selected provider only**. Status pill (Stored / Env / Not set), masked field with show/hide, Save + Clear.
- **Model** — a **Fetch models** button calls `POST /me/models/refresh` and re-reads `/me`; a one-line note summarizes the outcome. The dropdown is then populated from the provider's fetched `available_models` (each item: `Provider — Model Name` + per-MTok rates, or "pricing n/a" when unknown). Until a key is set / models are fetched it shows a hint instead of a dropdown.
- **AI spend** — read-only chip showing cumulative USD spent, with the canonical "estimate, not your bill" disclaimer.

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

## No auth — by design

This is a local single-user app. `DEFAULT_USER_ID = 1` is hardcoded in [`features.py`](../backend/src/budget_trace_backend/features.py) and the `/me` routes pick it up by default. There is no session/JWT layer and none is planned for V1 — the app runs on the user's own machine and the data (including `ai_provider_keys.api_key`, stored in plaintext) lives only in their local SQLite file / Docker volume. The Account screen states this plainly in its local-data banner.
