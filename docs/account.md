# Account

Single-user settings for the local-dev build. There's a real `users` table (id=1 hardcoded) and a `/me` REST surface, but no auth — every request acts as user 1. The schema and the surface are designed to extend cleanly when auth lands.

## What lives on the user

- `features` — JSON blob of feature flags. Today it's just `{ "ai": bool }`. The single master flag controls:
  - PDF / image / general AI parsing on `POST /transactions/import?parser=ai` (403 when off).
  - Auto-categorize-on-import — every successful CSV or AI import runs the inserted rows through Claude via [`importers/categorizer.py`](../backend/src/budget_trace_backend/importers/categorizer.py).
  - The Insights chat (`POST /chat/sessions/{id}/messages` returns 403 when off; historical reads stay open).
- `anthropic_api_key` — plaintext, optional. Read by [`services/anthropic_client.py::get_client()`](../backend/src/budget_trace_backend/services/anthropic_client.py); falls back to the `ANTHROPIC_API_KEY` env var.
- `anthropic_admin_api_key` — plaintext, optional. The `sk-ant-admin-…` admin key, distinct from the regular workspace key. When set, the `/me` handler queries [Anthropic's `cost_report`](../backend/src/budget_trace_backend/services/anthropic_admin.py) and uses the returned figure as the authoritative `ai_spent_usd` instead of the locally-estimated token cost (60 s in-process cache to stay under Anthropic's polling limits).
- `anthropic_model` — the Claude model id used for every AI call. `null` falls back to `ANTHROPIC_MODEL`, then the default `claude-sonnet-4-6`. Validated against `MODEL_PRICES` in [`services/ai_usage.py`](../backend/src/budget_trace_backend/services/ai_usage.py) so the spend chip always has a price to multiply against — `PATCH` rejects unknown ids with 422.
- `theme` — `system` | `light` | `dark`. Drives `MaterialApp.themeMode` in `main.dart`.

## REST: `/me`

```
GET   /me                       → MeOut
PATCH /me  { partial fields }   → MeOut
```

`MeOut` shape:
```json
{
  "features": { "ai": false },
  "theme": "system",
  "anthropic_api_key_set": false,
  "anthropic_admin_api_key_set": false,
  "anthropic_model": "claude-sonnet-4-6",
  "available_models": [
    { "id": "claude-opus-4-7",          "display_name": "Opus 4.7",   "input_per_mtok": 15, "output_per_mtok": 75 },
    { "id": "claude-sonnet-4-6",        "display_name": "Sonnet 4.6", "input_per_mtok":  3, "output_per_mtok": 15 },
    { "id": "claude-haiku-4-5-20251001","display_name": "Haiku 4.5",  "input_per_mtok":  1, "output_per_mtok":  5 }
  ],
  "ai_spent_usd": 0.0,
  "ai_spent_source": "estimated"
}
```

Key values themselves are **never** returned — only the `*_set` booleans. To set a key, `PATCH /me` with `{"anthropic_api_key": "sk-ant-…"}` (or `anthropic_admin_api_key`). To clear, send `null`. Empty string is a 422 — pass `null` instead.

To switch model, `PATCH /me` with `{"anthropic_model": "claude-haiku-4-5-20251001"}`. To reset to env/default, send `null`. Any value not in `available_models` is a 422.

`ai_spent_usd` is the cumulative dollar cost of every Anthropic call this app has made. Source is reported via `ai_spent_source`:
- `"estimated"` — locally summed from token usage × the price table in [`services/ai_usage.py`](../backend/src/budget_trace_backend/services/ai_usage.py).
- `"authoritative"` — pulled from Anthropic's `cost_report` (admin key set, fetch succeeded, window = `[earliest local-recorded call, now]`).

Anthropic does **not** expose a "remaining balance" endpoint. The chip is therefore always a **spend** readout, never a balance.

`PATCH` is partial: omit a field to leave it unchanged. `features` is a partial dict — sending `{"features": {"ai": true}}` flips just `ai` and leaves any future flags alone.

## UI: the Account screen

[frontend/lib/screens/account_screen.dart](../frontend/lib/screens/account_screen.dart). Six sections:

1. **Features** — a single switch for "AI features."
2. **Anthropic API Key** — masked text field, show/hide toggle, Save + Clear.
3. **AI Spend** — read-only chip showing cumulative USD spent on Anthropic, with a one-line note disclosing whether the figure is estimated or admin-API-authoritative.
4. **Model** — dropdown built from `available_models`; each item shows the model's per-MTok input/output rates. "Reset to default" sends `anthropic_model: null`.
5. **Anthropic Admin API key** — same masked-input pattern as the regular key. When set, the spend total flips to authoritative.
6. **Appearance** — three-segment control: System / Light / Dark.

Every control bubbles its update through `MeClient.update()` immediately and bubbles the resulting `Me` back up to `BudgetTraceApp` via `onMeChanged`. That triggers `MaterialApp.themeMode` to re-resolve, the Insights tab to show/hide, the Dropzone's AI toggle to appear/disappear, and the global AI-spend chip in the upload Dropzone to refresh — all in one pass.

The same `AiSpendChip` widget renders the chip in the **Account screen** (cumulative total), the **Dropzone** in Expenses (cumulative total — co-located with the only non-chat AI surface), the **Insights chat header** (per-active-chat amount), and each row of the **chat history view**. Desktop's side nav has no chip; the metric only appears next to actual AI surfaces.

Open the screen via:
- **Mobile** — the gear icon in the top-left of any tab's header (replaces the legacy "Categories" / "Expenses" / "Insights" page titles, which were redundant with the bottom tab bar).
- **Desktop** — the **Account** entry at the bottom of the side nav.

## Env override

`BUDGET_TRACE_FEATURES=ai` still works as a force-on for the running process; it wins over the DB on the read path. Useful for tests / CI / reproducible dev shells. No env override exists for the API key beyond the existing `ANTHROPIC_API_KEY` — that's already the documented fallback.

## Auth — TODO

The single-user assumption (`DEFAULT_USER_ID = 1`) lives in two places:

- [`backend/src/budget_trace_backend/features.py`](../backend/src/budget_trace_backend/features.py) — `get_me`/`update_me`/`get_flags`/`set_flag` all default to id=1.
- [`backend/src/budget_trace_backend/routes/me.py`](../backend/src/budget_trace_backend/routes/me.py) — the routes pass nothing, picking up the default.

When auth lands:

1. Add a session/JWT layer.
2. Replace the `user_id=1` defaults with a `user_id` derived from the request session.
3. Audit every other call site that reaches into `users` — there are no others today, but `services/anthropic_client.py::get_client()` reads `get_me()` without a user_id, which will need threading.
4. Encrypt `anthropic_api_key` at rest. Until then, the Account screen carries a **plaintext-storage warning banner** so it's not silently surprising.

The route shapes (`/me`) and the frontend `Me` model are auth-agnostic and won't change.
