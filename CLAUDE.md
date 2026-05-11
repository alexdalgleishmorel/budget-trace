# CLAUDE.md

Guidance for Claude Code working in this repository.

## Read this first

The architecture is documented in [`docs/`](docs/README.md). Before changing anything substantive, read the doc that matches your task:

- Just trying to run it → [`docs/running-end-to-end.md`](docs/running-end-to-end.md)
- The full REST surface (Categories, Transactions, `/me`, Dashboards) → [`docs/rest-api.md`](docs/rest-api.md)
- CSV upload, AI parser, auto-categorize, dedupe → [`docs/upload.md`](docs/upload.md)
- Touching the AI chat loop, MCP tools (read + write), prompt, or `WidgetSpec` shape → [`docs/insights-ai.md`](docs/insights-ai.md)
- Dashboards, widgets, metric registry, saved insights, drag/resize → [`docs/widgets.md`](docs/widgets.md)
- The `/me` settings surface — feature flags, API key, theme, auth-TODO → [`docs/account.md`](docs/account.md)
- Anything in `backend/` → [`docs/backend.md`](docs/backend.md)
- Anything in `frontend/` → [`docs/frontend.md`](docs/frontend.md)
- Schema or seed → [`docs/data-model.md`](docs/data-model.md)
- Things easy to get wrong (date formats, path strings, JSON casing, feature flags) → [`docs/conventions.md`](docs/conventions.md)

## Project shape

Two halves:

- **`frontend/`** — Flutter app, four tabs (Categories, Expenses, Widgets, Insights). All four talk to the Python backend; there is no in-memory mock data.
- **`backend/`** — Python FastAPI app. Owns the SQLite store (seeded with 12 months of mock transactions), exposes a REST API for Categories + Transactions + `/me` settings + Dashboards/Widgets, runs the chat orchestrator that talks to the selected AI model via LiteLLM (Anthropic, OpenAI, and Google Gemini supported today), and hosts an MCP server (read + write tools) that the chat AI uses for data access and mutations. The AI surface (chat, AI parser, auto-categorize-on-import) is gated behind the `ai` flag; the Widgets tab is gated behind the `widgets` flag (defaults on). Both toggled via the `/me` endpoint.

CSV upload is always available. PDF / screenshot / etc. are handled by the AI parser when `ai` is enabled, and every successful import also runs the rows through an auto-categorizer when `ai` is on. See [`docs/architecture.md`](docs/architecture.md) for the diagram and [`docs/upload.md`](docs/upload.md) for the upload contract.

## Commands

Frontend (from `frontend/`):

```bash
flutter analyze                                                          # must pass before merging
flutter test
flutter run -d chrome --dart-define=API_BASE_URL=http://localhost:8000   # web
flutter run -d macos --dart-define=API_BASE_URL=http://localhost:8000    # desktop
dart format lib/
```

Backend (from `backend/`, after `python3 -m venv .venv && . .venv/bin/activate && pip install -e '.[dev]'`):

```bash
uvicorn budget_trace_backend.main:app --reload --port 8000
# The startup lifespan auto-creates the schema, the symbolic Budget root,
# and the default user row on first boot — no separate seed step.

pytest                                                     # data-tool tests
```

An AI provider API key is needed for any AI surface (chat, PDF/AI parser, auto-categorize). Keys are configured per-provider via the Account screen (`PATCH /me { provider_keys }`, persisted in `ai_provider_keys` in SQLite) or the matching env var fallback (`ANTHROPIC_API_KEY` / `OPENAI_API_KEY` / `GEMINI_API_KEY`). The seed and CSV-only flows don't need a key.

## Frontend architecture (quick reference)

- **Responsive layout.** Every screen uses `LayoutBuilder` at a **600 dp breakpoint**; private `_MobileXxx` / `_DesktopXxx` widget classes per file.
- **Shell.** `AppShell` ([frontend/lib/widgets/app_shell.dart](frontend/lib/widgets/app_shell.dart)) owns the mutable category root and transaction list, threads them down to Categories and Expenses. The Widgets and Insights tabs are self-contained — they talk directly to the backend. The top-level `BudgetTraceApp` ([frontend/lib/main.dart](frontend/lib/main.dart)) owns the `Me` state (features + theme + key-set bool + `last_dashboard_id` from `GET /me`) and rebuilds `MaterialApp` on theme change. Tab indices are stable across the app: `0=Categories, 1=Expenses, 2=Widgets, 3=Insights`. Widgets is filtered out of the nav lists when `me.features.widgets` is off.
- **Theming.** `BudgetTheme` is a `ThemeExtension`; reach it via `context.bt`. Semantic colours: `ink`/`ink2`-`ink5`, `bg`/`surface`/`surface2`, `pos`/`neg`/`warn`/`warnBg`, `rule`/`ruleStrong`. Never use raw `Colors.*` for visible UI.
- **Icons.** `BudgetIcons` ([frontend/lib/widgets/cat_icon.dart](frontend/lib/widgets/cat_icon.dart)) — Lucide-style SVG paths via a custom `CustomPainter`. Use `BudgetIcons.build(key, size, strokeWidth, color)`. Categories no longer carry icons in the UI.
- **Generic chart.** [`TimeseriesChart`](frontend/lib/widgets/timeseries_chart.dart) — multi-series, dashed forecasts, theme-derived palette, optional `xTickLabels`. Driven by `ChartSpec` JSON. Used by the `timeseries` widget renderer.
- **Dashboard widget chrome.** [`WidgetCard`](frontend/lib/widgets/dash_widgets/widget_card.dart) wraps every widget on a dashboard *and* every AI-produced widget in the Insights transcript. One renderer file per widget type under [`frontend/lib/widgets/dash_widgets/`](frontend/lib/widgets/dash_widgets/). The Insights screen short-circuits the data fetch by passing `previewData`. See [`docs/widgets.md`](docs/widgets.md).

## Conventions worth re-stating

- ISO `YYYY-MM-DD` dates everywhere across the wire.
- Category paths use `" / "` (space + slash + space). Root "Budget" is **not** a valid path. The string `"Unknown"` is overloaded — see [`docs/conventions.md`](docs/conventions.md).
- Backend JSON is snake_case; Dart-side mirror is camelCase. Translation is manual in `*.fromJson` constructors.
- `flutter analyze` clean is a hard requirement before considering any change done.

## Original design reference

Hi-fi prototypes for the *original* 4-tab budget tracker live in [`original-design-docs/`](original-design-docs/). They're useful for visual style and component reference but no longer reflect the current scope. Don't treat them as a spec.
