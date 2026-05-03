# CLAUDE.md

Guidance for Claude Code working in this repository.

## Read this first

The architecture is documented in [`docs/`](docs/README.md). Before changing anything substantive, read the doc that matches your task:

- Just trying to run it → [`docs/running-end-to-end.md`](docs/running-end-to-end.md)
- The full REST surface (Categories, Transactions, Features) → [`docs/rest-api.md`](docs/rest-api.md)
- CSV upload, AI parser, dedupe → [`docs/upload.md`](docs/upload.md)
- Touching the AI chat loop, MCP tools (read + write), prompt, or `ChartSpec` shape → [`docs/insights-ai.md`](docs/insights-ai.md)
- Anything in `backend/` → [`docs/backend.md`](docs/backend.md)
- Anything in `frontend/` → [`docs/frontend.md`](docs/frontend.md)
- Schema or seed → [`docs/data-model.md`](docs/data-model.md)
- Things easy to get wrong (date formats, path strings, JSON casing, feature flags) → [`docs/conventions.md`](docs/conventions.md)

## Project shape

Two halves:

- **`frontend/`** — Flutter app, three tabs (Categories, Expenses, Insights). All three talk to the Python backend; there is no in-memory mock data.
- **`backend/`** — Python FastAPI app. Owns the SQLite store (seeded with 12 months of mock transactions), exposes a REST API for Categories + Transactions, runs the chat orchestrator that calls Anthropic, and hosts an MCP server (read + write tools) that the chat AI uses for data access and (when `ai_mutations` is on) mutations.

CSV upload is supported on the free tier; PDF / screenshot / etc. are handled by the AI parser when `ai_import` is enabled. See [`docs/architecture.md`](docs/architecture.md) for the diagram and [`docs/upload.md`](docs/upload.md) for the upload contract.

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
budget-trace-seed                                          # writes data/budget_trace.db
uvicorn budget_trace_backend.main:app --reload --port 8000
pytest                                                     # data-tool tests
```

`ANTHROPIC_API_KEY` must be set before starting the backend's HTTP server (the seed script doesn't need it).

## Frontend architecture (quick reference)

- **Responsive layout.** Every screen uses `LayoutBuilder` at a **600 dp breakpoint**; private `_MobileXxx` / `_DesktopXxx` widget classes per file.
- **Shell.** `AppShell` ([frontend/lib/widgets/app_shell.dart](frontend/lib/widgets/app_shell.dart)) owns the mutable category root and transaction list, threads them down to Categories and Expenses. The Insights tab is self-contained — it talks directly to the backend.
- **Theming.** `BudgetTheme` is a `ThemeExtension`; reach it via `context.bt`. Semantic colours: `ink`/`ink2`-`ink5`, `bg`/`surface`/`surface2`, `pos`/`neg`/`warn`/`warnBg`, `rule`/`ruleStrong`. Never use raw `Colors.*` for visible UI.
- **Icons.** `BudgetIcons` ([frontend/lib/widgets/cat_icon.dart](frontend/lib/widgets/cat_icon.dart)) — Lucide-style SVG paths via a custom `CustomPainter`. Use `BudgetIcons.build(key, size, strokeWidth, color)`. Categories no longer carry icons in the UI.
- **Generic chart.** [`TimeseriesChart`](frontend/lib/widgets/timeseries_chart.dart) — multi-series, dashed forecasts, theme-derived palette, optional `xTickLabels`. Driven by `ChartSpec` JSON returned from the backend.

## Conventions worth re-stating

- ISO `YYYY-MM-DD` dates everywhere across the wire.
- Category paths use `" / "` (space + slash + space). Root "Budget" is **not** a valid path. The string `"Unknown"` is overloaded — see [`docs/conventions.md`](docs/conventions.md).
- Backend JSON is snake_case; Dart-side mirror is camelCase. Translation is manual in `*.fromJson` constructors.
- `flutter analyze` clean is a hard requirement before considering any change done.

## Original design reference

Hi-fi prototypes for the *original* 4-tab budget tracker live in [`original-design-docs/`](original-design-docs/). They're useful for visual style and component reference but no longer reflect the current scope. Don't treat them as a spec.
