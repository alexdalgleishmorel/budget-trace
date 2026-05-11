# Budget Trace docs

Pick-up notes for whoever (human or AI) needs to work on this app next. Each
file answers one specific question — start with whichever matches your task.

| File | When to read |
|------|--------------|
| [running-end-to-end.md](running-end-to-end.md) | Just trying to run the thing. Step-by-step with a comment above every command. |
| [architecture.md](architecture.md) | First-time onboarding. Walks through the whole stack and one round-trip of a `/chat` request. |
| [rest-api.md](rest-api.md) | The full Categories + Transactions + `/me` REST surface. |
| [upload.md](upload.md) | CSV format, dedupe semantics, AI parser + auto-categorize. |
| [insights-ai.md](insights-ai.md) | Touching the AI chat loop, MCP tool surface, prompt, response shape. |
| [widgets.md](widgets.md) | Dashboards, widgets, the metric registry, saved insights, drag/resize. |
| [account.md](account.md) | The `/me` settings surface — feature flags, API key, theme, auth-TODO. |
| [backend.md](backend.md) | Working in `backend/` — running it, env vars, schema, seed, ports. |
| [frontend.md](frontend.md) | Working in `frontend/` — service clients, chart slot, `--dart-define` knobs. |
| [data-model.md](data-model.md) | SQLite schema + ERD, category-path conventions, what the seed actually generates. |
| [conventions.md](conventions.md) | Cross-cutting things that are easy to get wrong: date format, path separator, JSON casing. |

## What this app is

Budget Trace is a category + AI-insights app for personal expenses. Four tabs:

1. **Categories** — editable tree of spending categories, each with a description that doubles as the AI's classification hint. Backed by `GET/POST/PATCH/DELETE /categories`.
2. **Expenses** — list of transactions with category assignment, per-row edit, bulk-rename, hard delete, and a CSV upload dropzone with hash-based dedupe. Backed by `GET/POST/PATCH/DELETE /transactions` + `POST /transactions/import`.
3. **Widgets** — Datadog-style dashboards. Each dashboard owns a time range and N widgets (timeseries, bar, pie, big-number, table, treemap). Widgets pull from a curated server-side metric registry or from frozen snapshots saved off the Insights chat. Drag + resize on desktop; full-width vertical list on mobile. Gated behind a `widgets` flag (defaults on). See [widgets.md](widgets.md).
4. **Insights** — chat with an AI assistant about your spending. The AI returns text plus an optional **widget** of any type, picked to best fit the question. The AI can also edit categories and transactions on request. The whole tab (and PDF/AI parsing in upload, plus auto-categorization on import) is gated behind a single `ai` flag, toggled in the Account screen — see [account.md](account.md).

Categories, Expenses, and Widgets all talk to the same SQLite store the AI sees — there's no in-memory mock-data divergence.

## Where things live

```
frontend/         Flutter app — see frontend.md
backend/          Python FastAPI + MCP server — see backend.md
docs/             You are here
original-design-docs/   Read-only hi-fi prototypes from the original design pass
CLAUDE.md         Top-level project instructions for Claude Code
```
