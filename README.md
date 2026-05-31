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

## Quick start (if you already use Docker)

```sh
docker compose up --build      # run from the project folder
# then open http://localhost:8000
```

Everything below is the same thing, explained step by step for a first-timer.

## Set it up — step by step (no coding experience needed)

You don't need to know how to code. You'll install **one** free program (Docker),
download this project, and run a single command. Plan for about 15 minutes —
most of it is just waiting for things to download the first time.

When it's done, the app runs **entirely on your own computer**. Your transactions
and settings never leave your machine.

### 1. Install Docker Desktop

Docker is a free program that runs apps like this one in a self-contained box, so
you don't have to install Python, databases, or anything else yourself.

1. Go to **[docker.com/products/docker-desktop](https://www.docker.com/products/docker-desktop/)**
   and download Docker Desktop for your system (Mac or Windows).
2. Open the downloaded file and follow the installer (just click through the
   defaults).
3. **Start Docker Desktop** (from your Applications/Start menu) and wait until it
   says it's **running** — on Mac you'll see a small whale icon 🐳 in the top
   menu bar; on Windows, in the bottom-right system tray. Keep it running while
   you use the app.

> On Windows it may ask to install/enable "WSL 2" — say yes and follow its
> prompt. This is normal and one-time.

### 2. Download Expense Visualizer

1. On the project's GitHub page, click the green **`< > Code`** button near the
   top.
2. Click **Download ZIP**.
3. Find the downloaded `budget-trace-main.zip` (usually in your **Downloads**
   folder) and **unzip** it — double-click it on Mac, or right-click → "Extract
   All" on Windows. You'll get a folder named **`budget-trace-main`**.

### 3. Open a terminal inside that folder

A "terminal" is just a window where you type one command. You need it pointed at
the project folder.

- **Mac:** Open the **Terminal** app (press `Cmd`+`Space`, type `Terminal`,
  press Enter). Then type `cd ` (the letters c, d, and a space), drag the
  `budget-trace-main` folder from Finder onto the Terminal window (it pastes the
  location), and press **Enter**.
- **Windows:** Open the `budget-trace-main` folder in File Explorer. Click the
  address bar at the top, type `cmd`, and press **Enter** — a black terminal
  window opens already pointed at that folder.

### 4. Start the app

Type this exactly and press **Enter**:

```sh
docker compose up --build
```

The **first time**, this downloads and builds everything, which can take **5–15
minutes** depending on your internet — that's normal, and only happens once.
You'll see lots of text scrolling. When it's ready you'll see a line like:

```
api-1  | Uvicorn running on http://0.0.0.0:8000
```

Leave this window open — it's running the app.

### 5. Open it in your browser

Go to **[http://localhost:8000](http://localhost:8000)**. That's the app! 🎉

It starts empty. Add transactions by uploading a statement on the **Expenses**
tab — a CSV export from your bank works with no extra setup. (PDF and image
statements need an AI key — next step.)

### 6. (Optional) Turn on the AI features

The Insights chat, PDF/image import, and auto-categorize need a key from one AI
provider. You only need **one**:

- **Anthropic (Claude)** — [console.anthropic.com](https://console.anthropic.com/)
- **OpenAI (ChatGPT)** — [platform.openai.com/api-keys](https://platform.openai.com/api-keys)
- **Google (Gemini)** — [aistudio.google.com/app/apikey](https://aistudio.google.com/app/apikey)

Create an account there, generate an **API key** (a long secret string), then in
Expense Visualizer open the **Account** tab, turn on **AI features**, pick that
provider, paste the key, and click **Fetch models** to choose a model. The key is
stored only on your computer.

> Provider keys are usage-based and may cost a small amount per request — check
> the provider's pricing. CSV upload and everything else works with no key.

### Stopping and starting again

- **Stop:** click the terminal window and press `Ctrl`+`C` (Mac too — it's
  Control, not Command). Or, in a new terminal in the same folder, run
  `docker compose down`.
- **Start again later:** open a terminal in the folder and run
  `docker compose up` (no `--build` needed after the first time — it's much
  faster), then reopen [http://localhost:8000](http://localhost:8000).

Your data is saved between runs (see [Resetting your data](#resetting-your-data-wipe-the-volume)
to start fresh).

### If something goes wrong

- **`docker: command not found` or "Cannot connect to the Docker daemon":**
  Docker Desktop isn't running. Open it and wait for the whale icon to say
  "running", then try again.
- **"port is already allocated" / can't open the page:** something else is using
  port 8000. Edit [`docker-compose.yml`](docker-compose.yml), change `8000:8000`
  to `3000:8000`, rerun `docker compose up --build`, and open
  [http://localhost:3000](http://localhost:3000) instead.
- **The build seems stuck:** the first build is genuinely slow (it downloads a
  few GB). As long as text is still appearing now and then, let it finish.
- **Make sure you're in the right folder:** the command only works from inside
  `budget-trace-main` (the folder that contains the file `docker-compose.yml`).

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
