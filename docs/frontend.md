# Frontend

Flutter app. Four tabs (Categories, Expenses, Widgets, Insights). All four talk to the backend — there is no in-memory mock data.

The user-facing brand is **Expense Visualizer** ([lib/main.dart](../frontend/lib/main.dart) sets `MaterialApp.title`). The Dart package, the `BudgetTrace*` class names, and the `BudgetTheme`/`BudgetCard`/`BudgetIcons` symbols are internal identifiers and stay as-is.

## Run it

From `frontend/`:

```sh
flutter pub get
flutter run -d chrome --dart-define=API_BASE_URL=http://localhost:8000
```

Without the `--dart-define`, the Insights tab still loads, but every chat request errors with a connection refused — `ChatClient` defaults to `http://localhost:8000` and there's nothing listening unless the backend is up.

`flutter run -d macos` also works; iOS/Android need the host to be reachable from the device.

## Visual layer (Arctic)

Dark-only glass-morphism theme. The visual primitives live in two files:

| File | Purpose |
|------|---------|
| [lib/theme/app_theme.dart](../frontend/lib/theme/app_theme.dart) | `BudgetTheme` (a `ThemeExtension`) plus `BudgetColors` constants and `BudgetRadius` scale. Reach the tokens via `context.bt`. Tokens include the existing semantic set (`ink`/`ink2-5`, `bg`/`bg2`, `surface`/`surface2`, `pos`/`neg`/`warn`, `rule`/`ruleStrong`/`ruleSoft`, `tile1-5`) plus the rework additions (`bgGrad`/`bgVeilA`/`bgVeilB`, `glass1-3`/`glassBorder`/`glassBorderStrong`/`glassHighlight`/`glassShadow`, `fieldBg`/`fieldBorder`, `accent`/`accent2`/`accentGrad`, `categoryColors`). Light variant has been retired; `BudgetTheme.dark` is the single canonical theme. |
| [lib/widgets/glass.dart](../frontend/lib/widgets/glass.dart) | Shared primitives: `GlassSurface` (tier-1/2/3/strong frosted card with optional sheen + drop shadow + dashed border), `AppBackground` (page gradient + accent veil orbs, wraps the AppShell body), `GlassButton` (variants primary/secondary/ghost/destructive), `GlassChip`, `GlassField`, `GlassToggle`, `GradientText`, `GradientIconTile`, `GlassModalShell`, `showGlassModal()`. |

`ThemeData` sets `dialogTheme` / `popupMenuTheme` / `bottomSheetTheme` to an opaque deep-navy fill (`BudgetColors.bgGrad[1]`). Without those, Material's defaults inherit the translucent `ColorScheme.surface` (= `glass1`) and render see-through over the page gradient.

Modal dialogs (category edit, transaction edit, save-to-dashboard, new-dashboard, etc.) share a single visual pattern: `Dialog(backgroundColor: Colors.transparent)` → `GlassSurface(tier: strong, radius: 24)` → header (border-bottom, title + close pill) → scrollable body → optional footer (glass-1 bg, border-top, action buttons). When you need to add a new modal, follow that pattern — the form modals and the insights modals all wrap it.

## Service clients

All clients sit in `lib/services/` and follow the same pattern: take an optional `http.Client`, expose typed methods, throw `ApiException` on non-2xx responses.

| File | Purpose |
|------|---------|
| [api_base.dart](../frontend/lib/services/api_base.dart) | `apiBaseUrl` constant + `decodeOrThrow` shared error handling. |
| [categories_client.dart](../frontend/lib/services/categories_client.dart) | `GET/POST/PATCH/DELETE /categories`. Returns `CategoryDto`. |
| [transactions_client.dart](../frontend/lib/services/transactions_client.dart) | CRUD + `bulkRename` + `import` (multipart upload). Returns `TransactionDto`/`ImportResult`. |
| [me_client.dart](../frontend/lib/services/me_client.dart) | `GET/PATCH /me`. Returns `Me` (features + theme + providers + selected model + `lastDashboardId`). |
| [chat_client.dart](../frontend/lib/services/chat_client.dart) | `POST /chat/sessions/{id}/messages` plus session history. Assistant turns carry an optional `WidgetPayload`. |
| [dashboards_client.dart](../frontend/lib/services/dashboards_client.dart) | Dashboards / widgets / saved insights / metric registry. See [widgets.md](widgets.md). |
| [category_tree_builder.dart](../frontend/lib/services/category_tree_builder.dart) | Turn the flat list of `CategoryDto` into the in-app `BudgetCategory` tree (synthesises a "Budget" root). |

## Insights wiring

| File | Purpose |
|------|---------|
| [lib/models/chat_message.dart](../frontend/lib/models/chat_message.dart) | `ChatMessage { id?, role, text, widget?, pending, errored }` and `ChatRole`. `id` is the server-assigned message id (used by the save-to-dashboard flow). |
| [lib/models/chart_spec.dart](../frontend/lib/models/chart_spec.dart) | Wire-format `ChartSpec`/`ChartSeriesSpec` with `fromJson` + `buildChart()` to render via `TimeseriesChart`. Used inside the `timeseries` widget renderer. |
| [lib/models/dashboard.dart](../frontend/lib/models/dashboard.dart) | `WidgetPayload { type, title, data, metricId?, metricParams?, fallbackReason? }`, plus the dashboard model. `isSnapshot` is true when no `metricId` was emitted. |

Modified:

- [lib/screens/insights_screen.dart](../frontend/lib/screens/insights_screen.dart) — renders the assistant's `widget` inline below the text via the same [`WidgetCard`](../frontend/lib/widgets/dash_widgets/widget_card.dart) used on dashboards. A "Save to dashboard…" affordance per message opens a dashboard picker and creates a widget directly via `POST /chat/messages/{id}/save-to-dashboard` — re-runnable when the AI emitted a metric_id, snapshot fallback otherwise.
- [lib/widgets/timeseries_chart.dart](../frontend/lib/widgets/timeseries_chart.dart) — `xTickLabels` thinned to whatever fits the chart's width to avoid label overlap; `height: null` flexes the chart to fill its parent (used by the `timeseries` widget renderer inside the dashboard grid).

## Widgets / dashboards

See [widgets.md](widgets.md) for the full feature reference (data model, REST surface, AI integration, drag/resize internals). Quick map of the frontend pieces:

| File | Purpose |
|------|---------|
| [lib/screens/widgets_screen.dart](../frontend/lib/screens/widgets_screen.dart) | Tab root — list / empty-state / auto-open on `me.lastDashboardId`. |
| [lib/screens/dashboard_screen.dart](../frontend/lib/screens/dashboard_screen.dart) | One dashboard. Time-range picker in the header. Desktop = `DashboardGrid`; mobile = `_MobileDashboardList` (vertical, fixed height, no drag). |
| [lib/widgets/dash_widgets/dashboard_grid.dart](../frontend/lib/widgets/dash_widgets/dashboard_grid.dart) | Absolute-positioned 6-column grid with drag + corner-resize. Always-on (no edit mode). |
| [lib/widgets/dash_widgets/widget_card.dart](../frontend/lib/widgets/dash_widgets/widget_card.dart) | Titlebar + body + loading/error states. Used on dashboards *and* inline in the Insights transcript via `previewData`. |
| [lib/widgets/dash_widgets/add_widget_drawer.dart](../frontend/lib/widgets/dash_widgets/add_widget_drawer.dart) | Add / edit a widget. Type chips with descriptions, generic params form, live preview. |
| [lib/widgets/dash_widgets/{bar,pie,query_value,recent_table,timeseries,treemap}_widget.dart](../frontend/lib/widgets/dash_widgets/) | One file per widget type renderer. |

## `--dart-define` knobs

- `API_BASE_URL` — backend URL. Default `http://localhost:8000`.

Add new ones via `String.fromEnvironment(...)` and document them here.

## Tests

```sh
flutter analyze            # must pass before merging
flutter test               # smoke test only — InsightsScreen is not exercised
```

The smoke test mounts `BudgetTraceApp`. It does *not* hit the backend, so it passes even if the backend is down.

## What the rest of the app does

- **Categories tab** ([lib/screens/categories_screen.dart](../frontend/lib/screens/categories_screen.dart)) — fill-screen grid, drill-down navigation, inline add/edit modal. CRUD goes through `CategoriesClient`; the screen drill state tracks ids so it survives a tree refetch.
- **Expenses tab** ([lib/screens/expenses_screen.dart](../frontend/lib/screens/expenses_screen.dart)) — transaction list with category chips, edit pencil per row, cycle-month selector, CSV upload dropzone. All operations go through `TransactionsClient`. The cycle dropdown filters by date range via `?start_date&end_date`.
- **Widgets tab** ([lib/screens/widgets_screen.dart](../frontend/lib/screens/widgets_screen.dart)) — dashboards. See "Widgets / dashboards" above and [widgets.md](widgets.md).

`AppShell` ([lib/widgets/app_shell.dart](../frontend/lib/widgets/app_shell.dart)) is the data orchestrator: loads categories + transactions + `Me` on startup, refetches on demand, and shows a `_BackendError` panel with a Retry button if the backend is unreachable. Tab indices are stable: `0=Categories, 1=Expenses, 2=Widgets, 3=Insights`. Widgets disappears from the nav lists when `me.features.widgets` is off; Insights still renders an `AiPromo` empty state when `me.features.ai` is off.

## Feature flags

`BudgetTraceApp` ([lib/main.dart](../frontend/lib/main.dart)) calls `GET /me` on startup and holds the resulting `Me` (features + providers + `lastDashboardId`). `Me.theme` is still on the wire but ignored — the app forces `themeMode: ThemeMode.dark`. Today's flag-driven UI:

- `ai: true` — Insights chat is enabled; Dropzone shows a **Use AI parsing** toggle (off by default per upload, opt-in); auto-categorize runs after every successful import.
- `widgets: true` (default on) — the Widgets tab is reachable. When false, it's filtered out of the nav and the dashboards REST surface 403s.
