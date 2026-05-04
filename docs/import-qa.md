# Import QA — first-time real-data walkthrough

A click-through pass that exercises [`POST /transactions/import`](../backend/src/budget_trace_backend/routes/imports.py) and the [`ImportProgressModal`](../frontend/lib/widgets/import_progress_modal.dart) against four real bank-statement fixtures plus the dedupe round-trip. Run this any time the import surface changes.

The modal has three terminal panels:
- **success** — green check, headline, stats grid (Added · Duplicates · Failed · Categorized).
- **error** — red alert, headline keyed off `ApiException.code`, explicit "No transactions were saved" line.
- **in-progress** — indeterminate bar with "Processing your statement…" plus a wait-time hint when AI parsing is selected.

All five cases below should land on a clean dialog. If anything raises a SnackBar instead, that's a bug — report it.

## Pre-flight setup

```sh
# Wipe to first-time-user state. Lifespan auto-creates schema + Budget root + default user.
pkill -f "uvicorn.*budget_trace_backend"
rm -f backend/data/budget_trace.db
cd backend && . .venv/bin/activate
uvicorn budget_trace_backend.main:app --reload --port 8000
```

In another shell, start the frontend (or hot-restart with `R` if it's already running):

```sh
cd frontend
flutter run -d chrome --dart-define=API_BASE_URL=http://localhost:8000
```

In the app:

1. Open **Account** (gear icon, mobile bottom row or desktop sidebar). Set:
   - **AI features** → on
   - **Anthropic API key** → paste your `sk-ant-…` key, Save
   - (optional) **Appearance** → whatever you want
2. Open **Categories** and tap **Create category** for at least three top-level categories with descriptions — gives the auto-categorizer somewhere to file things. Suggested:
   - **Living** — *"Day-to-day food, transport, dining out"*
   - **Fun** — *"Entertainment, subscriptions, hobbies"*
   - **House** — *"Rent, utilities, household"*
3. Switch to **Expenses**. The empty-state panel should be visible below the dropzone.

Fixtures live at [`backend/tests/fixtures/real/`](../backend/tests/fixtures/real/):
- `scotia_visa_april_2026.csv`
- `scotia_visa_april_2026-corrupted.csv`
- `scotia_visa_april_2026.pdf`
- `scotia_visa_april_2026-corrupted.pdf`

## Case 1 — Clean CSV

**File:** `scotia_visa_april_2026.csv`. **AI toggle:** off (CSV path).

**Steps:** Expenses → tap the dropzone → pick the file.

**Expected modal sequence:**
1. *In-progress*: bar appears with "Processing your statement…" and the filename in monospace.
2. *Success*: headline reads **"Imported 61 transactions"**. Stats grid shows `Added: 61`. No Duplicates, Failed, or Categorized (AI was off).

The file has 73 data rows, but 12 of them are negative-amount Credit lines (payments to the card / refunds) — the parser skips those silently as out-of-scope for spend tracking. Only the 61 Debit rows are imported.

**Verify in Expenses:**
- The cycle picker auto-snaps to **April 2026** (via `GET /transactions/latest_date`).
- 61 rows visible. Mix of merchants — `EQ3 LTD`, `STARBUCKS 8007827282`, `IKEA CALGARY`, `SOBEYS TUSCANY #5085`, etc. **No** `payment from - *****00*98` rows (those are the Credits — confirm they're absent).
- All rows are uncategorised — they show in "Needs review" because AI was off and no manual cascade has run.

**Verify via API:**
```sh
curl -s localhost:8000/transactions/latest_date     # {"date":"2026-04-30"}
curl -s "localhost:8000/transactions?limit=500" | jq length   # 61
```

## Case 2 — Dedupe (re-upload the same file)

**File:** same as Case 1. **AI toggle:** off.

**Steps:** Drop the same file again, immediately.

**Expected modal:**
- *Success* with headline **"All rows already imported"**. Stats: `Added: 0`, `Duplicates: 61`. No Failed.

**Verify via API:** `curl -s "localhost:8000/transactions?limit=500" | jq length` is still **61** — the count hasn't moved. SHA256 `source_hash` dedupe (partial unique index) is doing its job.

## Case 3 — Corrupted (mid-row truncated) CSV

**File:** `scotia_visa_april_2026-corrupted.csv` — a copy of the clean file truncated at byte 4610, mid-quote, with no terminating newline. Simulates a network drop during download.

**Steps:** Drop on a fresh DB. (Running it after Cases 1-2 just collapses to a dedupe success — see note below.)

**Expected modal (from a fresh DB):**
- *Success* with headline **"Imported 41 transactions"**. Stats: `Added: 41`, `Failed: 1` (the truncated last row). Tap the "1 row couldn't be parsed and was skipped" expander to see the row reason.

**Expected modal (run after Cases 1-2):**
- *Success* with headline **"All rows already imported"**. Stats: `Added: 0`, `Duplicates: 41`, `Failed: 1`. The truncated row still surfaces as a parse error even though no spend rows landed.

The point: real corruption surfaces as a `Failed` count — the user can see exactly how many rows didn't make it. No raw exception text, no silent loss.

## Case 4 — Clean PDF via AI parser

**File:** `scotia_visa_april_2026.pdf`. **AI toggle:** ON (flip the dropzone's PREMIUM toggle).

**Pre-step:** wipe the DB if you want clean numbers (`pkill uvicorn; rm backend/data/budget_trace.db; uvicorn …` and re-create your categories). Otherwise, expect everything to dedupe.

**Steps:** Expenses → flip the **Use AI parsing** toggle → drop the PDF.

**Expected modal sequence:**
1. *In-progress*: bar with "Processing your statement…\nAI parsing can take 5–30 seconds." (5–30s wait — Claude is parsing).
2. *Success*: headline **"Imported N transactions"** where N is somewhere in the 60–73 range (Claude's extraction is non-deterministic). Stats grid shows `Added`, plus `Categorized` (most should be classified into Living/Fun/House if the AI matches descriptions).

**Verify in Expenses:**
- Rows visible in April 2026.
- Most have a category badge (auto-categorize on import).
- Spot-check that obvious merchants (Starbucks, IKEA, restaurants) landed in plausible categories.

## Case 5 — Corrupted PDF via AI parser

**File:** `scotia_visa_april_2026-corrupted.pdf`. **AI toggle:** ON.

**Steps:** drop the PDF.

**Expected modal — one of:**
- *Success* with headline **"No transactions detected"** and `Added: 0` if the AI gracefully extracts nothing.
- *Error* panel with headline **"Import failed"** and the underlying message in a code block, plus the "No transactions were saved" line, if the Anthropic call raises (e.g. invalid PDF stream).

Either way: zero new rows in the DB, no half-written state.

## What to verify after every case

- The modal closes cleanly when you tap **Done** / **Close** — no stuck overlay, no leaked focus.
- Expenses tab refetches automatically (`onImported` callback fires) — new rows appear without a manual reload.
- The Insights chat (with a key set) can answer *"what did I spend the most on?"* — sanity-check the data is queryable end-to-end.

## Parser semantics worth knowing

- **Negative amounts in a single-Amount column are skipped.** Treated as credit-card payments / refunds rather than spend. See [`csv_parser.py:99-105`](../backend/src/budget_trace_backend/importers/csv_parser.py#L99-L105). This is why the clean Scotia CSV imports 61 rows instead of 73 — the 12 negatives are payments to the card.
- **Two-column debit/credit splits** (`debit_credit.csv` test fixture) take the Debit-as-positive path; explicit Credit rows are dropped silently. See the `credit_col` branch in the parser.
- **Mid-row truncation surfaces as a parse error.** The truncated row's `IndexError` is caught and recorded in the response's `errors` array; `rows_failed` increments. The user sees "N rows couldn't be parsed and were skipped" in the success modal.
- **Dedupe** uses `sha256(date|normalised_merchant|amount)`. Re-importing the same file → 0 inserts, all skipped as duplicates. Importing a corrupted file after a clean import → 0 inserts (everything that's there is a dupe of the clean import) plus the same `Failed: 1` for the truncated row.
