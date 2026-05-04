# Account

Single-user settings for the local-dev build. There's a real `users` table (id=1 hardcoded) and a `/me` REST surface, but no auth — every request acts as user 1. The schema and the surface are designed to extend cleanly when auth lands.

## What lives on the user

- `features` — JSON blob of feature flags. Today it's just `{ "ai": bool }`. The single master flag controls:
  - PDF / image / general AI parsing on `POST /transactions/import?parser=ai` (403 when off).
  - Auto-categorize-on-import — every successful CSV or AI import runs the inserted rows through Claude via [`importers/categorizer.py`](../backend/src/budget_trace_backend/importers/categorizer.py).
  - The Insights chat (`POST /chat/sessions/{id}/messages` returns 403 when off; historical reads stay open).
- `anthropic_api_key` — plaintext, optional. Read by [`services/anthropic_client.py::get_client()`](../backend/src/budget_trace_backend/services/anthropic_client.py); falls back to the `ANTHROPIC_API_KEY` env var.
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
  "anthropic_api_key_set": false
}
```

The key value itself is **never** returned — only `anthropic_api_key_set`. To set it, `PATCH /me` with `{"anthropic_api_key": "sk-ant-…"}`. To clear it, send `{"anthropic_api_key": null}`. Empty string is a 422 — pass `null` instead.

`PATCH` is partial: omit a field to leave it unchanged. `features` is a partial dict — sending `{"features": {"ai": true}}` flips just `ai` and leaves any future flags alone.

## UI: the Account screen

[frontend/lib/screens/account_screen.dart](../frontend/lib/screens/account_screen.dart). Three sections:

1. **Features** — a single switch for "AI features."
2. **Anthropic API Key** — masked text field, show/hide toggle, Save + Clear. Status line below: *"Set"* or *"Not set — falls back to ANTHROPIC_API_KEY env var."*
3. **Appearance** — three-segment control: System / Light / Dark.

Every control bubbles its update through `MeClient.update()` immediately and bubbles the resulting `Me` back up to `BudgetTraceApp` via `onMeChanged`. That triggers `MaterialApp.themeMode` to re-resolve, the Insights tab to show/hide, and the Dropzone's AI toggle to appear/disappear — all in one pass.

Open the screen via the **Settings** entry in the bottom-bar (mobile) or the sidebar (desktop).

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
