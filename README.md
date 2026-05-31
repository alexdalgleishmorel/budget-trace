# Expense Visualizer

Personal expense categorisation + AI-powered insights. A local-first app you run
on your own machine — your data never leaves it.

- **Frontend** — Flutter app: Categories, Expenses, Widgets, Insights tabs.
- **Backend** — Python FastAPI + MCP server: the AI chat orchestrator and an SQLite-backed query surface.

> Internal package names keep the legacy `budget_trace` identifier; only the
> user-facing name is "Expense Visualizer".

See [`docs/`](docs/README.md) for architecture and conventions, and
[`docs/running-end-to-end.md`](docs/running-end-to-end.md) for a step-by-step
walkthrough with a comment above every command.

## Live demo

**→ [alexdalgleishmorel.github.io/budget-trace](https://alexdalgleishmorel.github.io/budget-trace/)**

A browser-only demo with **no backend**. The Flutter web app runs against an
in-memory mock (a sample 12-month dataset) so you can click through Categories,
Expenses, and Widgets — creating and editing as you go. Two caveats, surfaced in
the app itself via a banner:

- **Nothing persists** — reload the page and your changes reset.
- **The Insights AI is mocked** — replies are pre-written examples, clearly
  labelled, not a live model.

For the real thing — persistence, statement import, and live AI — run it locally
with Docker (below).

### How it's built and shipped

- A `--dart-define=DEMO_MODE=true` build swaps the app's HTTP layer for an
  in-memory backend ([`frontend/lib/services/demo/`](frontend/lib/services/demo/)).
  Normal builds are unaffected.
- The demo lives on the long-lived **`demo`** branch, kept in sync with `main` by
  [`.github/workflows/sync-demo.yml`](.github/workflows/sync-demo.yml).
- [`.github/workflows/deploy-demo.yml`](.github/workflows/deploy-demo.yml) builds
  and publishes to Pages — **manual trigger** (Actions → "Deploy demo to GitHub
  Pages" → Run workflow). One-time setup: Settings → Pages → Source = GitHub
  Actions.
- Regenerate the sample dataset
  ([`frontend/assets/demo/seed.json`](frontend/assets/demo/seed.json)) from the
  deterministic backend seed if the schema or seed changes.

Run the demo locally with `flutter run -d chrome --dart-define=DEMO_MODE=true`
(from `frontend/`, no backend needed).

## Run it with Docker (recommended)

One container builds the Flutter web app and serves it together with the API on
a single port. Your data — transactions, categories, settings, and API keys —
lives in a named Docker volume (`ev_data`) and survives restarts.

**Prerequisites:** [Docker Desktop](https://www.docker.com/products/docker-desktop/)
(or any Docker engine with Compose v2).

```sh
# From the repo root:
docker compose up --build

# Then open:
#   http://localhost:8000
```

That's the whole setup. There's no separate database step — the backend creates
`/data/budget_trace.db` (schema + the single user row) on first boot and starts
empty. Add your transactions by uploading statements on the **Expenses** tab
(CSV always works; PDF/image need an AI key — see below).

### AI features (optional)

AI parsing, auto-categorize, and the Insights chat need an API key for one
provider (Anthropic, OpenAI, or Google Gemini). Two ways to provide it:

- **In the app** — open **Account**, pick a model, paste the key for that
  provider. It persists in the volume. *(Recommended.)*
- **As an environment variable** — uncomment the relevant line in
  [`docker-compose.yml`](docker-compose.yml) and set it in your shell:

  ```sh
  ANTHROPIC_API_KEY=sk-ant-... docker compose up --build
  ```

Get a key at
[console.anthropic.com](https://console.anthropic.com/) ·
[platform.openai.com](https://platform.openai.com/api-keys) ·
[aistudio.google.com](https://aistudio.google.com/app/apikey).
CSV upload works without any key.

### Everyday commands

```sh
docker compose up --build          # start (rebuild after code changes)
docker compose up -d               # start in the background
docker compose down                # stop (keeps your data)
docker compose down -v             # stop and WIPE all data (removes the volume)
docker compose logs -f             # follow logs
```

Without Compose:

```sh
docker build -t expense-visualizer .
docker run -p 8000:8000 -v ev_data:/data expense-visualizer
```

Map a different host port by changing `8000:8000` (e.g. `3000:8000` →
`http://localhost:3000`); the app uses same-origin requests, so it works on any
host port.

## Developer mode — Docker with live reload

A separate compose file runs both halves in containers that **auto-reload on
file change**, with the source bind-mounted from the host:

```sh
docker compose -f docker-compose.dev.yml up --build

#   API → http://localhost:8000   (uvicorn --reload: restarts on save)
#   App → http://localhost:8080   (Flutter dev server: hot-restarts on save)
```

Edit any file in `backend/` or `frontend/` in your editor as usual:

- **Backend** — `uvicorn --reload` watches `backend/src` and restarts on save.
- **Frontend** — a watcher in the container sends Flutter a hot-restart whenever
  you save a `.dart` file (or anything under `frontend/lib`, `frontend/web`,
  `pubspec.yaml`), and the browser updates itself. The first web compile takes
  ~30–60s; saves after that hot-restart in a couple seconds.

Dev data lives in its own `ev_dev_data` volume, separate from the production
`ev_data` one. Stop with `Ctrl-C` (or `docker compose -f docker-compose.dev.yml down`).

## Resetting your data (wipe the volume)

Your data lives in a Docker volume. Removing it gives you a brand-new install —
an empty database with no transactions, categories, settings, or saved API keys
(it's recreated on the next boot). The `-v` flag is what deletes the volume.

```sh
# Production stack (volume: ev_data)
docker compose down -v

# Developer mode (volume: ev_dev_data — also clears the pub cache, harmless)
docker compose -f docker-compose.dev.yml down -v

# Wipe and restart fresh in one go
docker compose down -v && docker compose up --build
```

These are **separate volumes**, so wiping one doesn't touch the other.

If you started the container with plain `docker run` (not Compose), remove the
named volume directly — stop the container first if it's still running:

```sh
docker rm -f <container>      # if it's still up
docker volume rm ev_data      # or: docker volume rm -f ev_data
```

`docker volume ls` lists what exists. Compose prefixes volume names with the
project folder (e.g. `budget-trace_ev_data`), but `down -v` resolves that for
you — you only need the raw name for the manual `docker volume rm` form.

## Dev setup — no Docker (fastest hot reload)

Runs the backend and Flutter app as separate host processes. `flutter run -d
chrome` gives the snappiest reload of all (true hot reload via your terminal/IDE).

```sh
# Backend
cd backend
python3 -m venv .venv && . .venv/bin/activate
pip install -e '.[dev]'
export ANTHROPIC_API_KEY=sk-ant-...   # optional — can also be set in the Account UI
uvicorn budget_trace_backend.main:app --reload --port 8000
# First boot auto-creates data/budget_trace.db. No separate seed step.

# Frontend (in another terminal)
cd frontend
flutter pub get
flutter run -d chrome --dart-define=API_BASE_URL=http://localhost:8000
```

## Tests

```sh
cd backend  && . .venv/bin/activate && pytest
cd frontend && flutter analyze && flutter test
```
