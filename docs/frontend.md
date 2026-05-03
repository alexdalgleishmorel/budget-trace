# Frontend

Flutter app. Three tabs (Categories, Expenses, Insights). Categories and Expenses are pure in-memory mock data; the Insights tab is the only one that talks to the backend.

## Run it

From `frontend/`:

```sh
flutter pub get
flutter run -d chrome --dart-define=API_BASE_URL=http://localhost:8000
```

Without the `--dart-define`, the Insights tab still loads, but every chat request errors with a connection refused — `ChatClient` defaults to `http://localhost:8000` and there's nothing listening unless the backend is up.

`flutter run -d macos` also works; iOS/Android need the host to be reachable from the device.

## Service clients

All clients sit in `lib/services/` and follow the same pattern: take an optional `http.Client`, expose typed methods, throw `ApiException` on non-2xx responses.

| File | Purpose |
|------|---------|
| [api_base.dart](../frontend/lib/services/api_base.dart) | `apiBaseUrl` constant + `decodeOrThrow` shared error handling. |
| [categories_client.dart](../frontend/lib/services/categories_client.dart) | `GET/POST/PATCH/DELETE /categories`. Returns `CategoryDto`. |
| [transactions_client.dart](../frontend/lib/services/transactions_client.dart) | CRUD + `bulkRename` + `import` (multipart upload). Returns `TransactionDto`/`ImportResult`. |
| [features_client.dart](../frontend/lib/services/features_client.dart) | `GET /me/features` → `FeatureFlags`. |
| [chat_client.dart](../frontend/lib/services/chat_client.dart) | `POST /chat`. Stateless; caller passes the full `List<ChatMessage>` history. |
| [category_tree_builder.dart](../frontend/lib/services/category_tree_builder.dart) | Turn the flat list of `CategoryDto` into the in-app `BudgetCategory` tree (synthesises a "Budget" root). |

## Insights wiring

| File | Purpose |
|------|---------|
| [lib/models/chat_message.dart](../frontend/lib/models/chat_message.dart) | `ChatMessage { role, text, chart?, pending, errored }` and `ChatRole`. |
| [lib/models/chart_spec.dart](../frontend/lib/models/chart_spec.dart) | Wire-format `ChartSpec`/`ChartSeriesSpec` with `fromJson` + `buildChart()` to render via `TimeseriesChart`. |

Modified:

- [lib/screens/insights_screen.dart](../frontend/lib/screens/insights_screen.dart) — full rewrite. Submits async, renders the latest chart in a sticky panel above the chat, replaces the pending placeholder with the resolved response.
- [lib/widgets/timeseries_chart.dart](../frontend/lib/widgets/timeseries_chart.dart) — gained an optional `xTickLabels: List<String>?` parameter. When provided, those labels are evenly spaced along the x-axis (first at xMin, last at xMax). When omitted, falls back to numeric endpoints.

## The chart slot

`InsightsScreen._latestChart` walks `_messages` backwards and returns the first non-null `chart`. Pinned in a panel between the header and `_ChatPanel`. When a new chart-bearing assistant response arrives, the panel re-renders.

If you want each chart to render *inline* with its message instead of just at the top, change the chart slot to iterate `_messages` in `_TranscriptItem` rather than reading `_latestChart`. The plan deliberately picked sticky-only to keep scroll content small.

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

`AppShell` ([lib/widgets/app_shell.dart](../frontend/lib/widgets/app_shell.dart)) is the data orchestrator: loads categories + transactions + feature flags on startup, refetches on demand, and shows a `_BackendError` panel with a Retry button if the backend is unreachable.

## Feature flags

`AppShell` calls `GET /me/features` on startup and threads the resulting `FeatureFlags` through to the Expenses screen. Today's flag-driven UI:

- `aiImport: true` — Dropzone shows a **Use AI parsing** toggle. Off by default per upload (opt-in). Accepts CSV + PDF. Off-flag: only CSV.
- `aiMutations: true` — affects the chat AI server-side; the frontend doesn't render anything different (Insights tab works the same shape regardless).
