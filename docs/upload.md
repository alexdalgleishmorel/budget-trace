# Statement upload

The Expenses tab has a dropzone that uploads to `POST /transactions/import`. Two parsers, one endpoint.

## CSV (free, default)

Always available. Stdlib `csv.Sniffer` for delimiter detection plus heuristic header matching:

| Looking for | Accepted column names |
|-------------|----------------------|
| Date | `date`, `transaction date`, `post date`, `posted`, `posted date` |
| Merchant | `description`, `merchant`, `payee`, `name`, `details` |
| Amount | `amount`, `value` |
| Debit (alt) | `debit`, `withdrawal`, `spend` |
| Credit (skip) | `credit`, `deposit`, `refund` |

Date strings are parsed across `YYYY-MM-DD`, `MM/DD/YYYY`, `DD/MM/YYYY`, `Mar 14, 2026`, `Mar 14 2026`, `YYYY/MM/DD`. Merchant gets uppercased + whitespace-collapsed for stable hashing. Amounts can include `$` and `,` — the parser strips them.

If the file has separate `debit` and `credit` columns, debit rows go in (as positive spend) and credit rows are silently dropped — refunds and transfers aren't spend.

If header detection fails, the response is `400 csv_parse_failed`. The error message names which column is missing.

## AI parser (gated by the master `ai` flag)

When the user has the `ai` flag enabled (Account → Features), the dropzone shows a **Use AI parsing** toggle and accepts both `.csv` and `.pdf`. The toggle is **off by default even when the flag is on** — opt-in per upload because it costs API tokens.

Server-side: `POST /transactions/import?parser=ai` checks `users.features.ai` and returns `403 feature_disabled` when off. When on, it routes to `importers/ai_parser.py`, which:

1. For `text/*` payloads (CSV mistakenly sent as AI): pass the text directly.
2. For PDFs: try `pdfplumber` text extraction first. If that fails, fall back to base64 document input.
3. For images: base64 vision input.

The orchestrator then sends the content to the selected AI model with one tool, `parse_transactions`, whose schema *is* the `ImportedRow` shape (date, merchant, amount). The model calls it once with the full row list; the orchestrator hands those rows off to the same `insert_rows` path the CSV parser uses.

The response includes an `ai_usage` object (`{input_tokens, output_tokens}`) for cost observability. CSV imports leave `ai_usage` as `null`.

**Provider note:** PDF document support depends on the selected model's provider. Anthropic and Google models accept PDFs; OpenAI models don't. Uploading a PDF while an OpenAI model is selected returns `400 unsupported_content` with a message suggesting the user switch model — no tokens are charged, the bytes never reach the model.

If `ai` is on but no API key is configured for the selected model's provider (neither stored via `PATCH /me` nor in the matching env var), the route returns `400 ai_key_missing`. CSV uploads are unaffected — they never need a key.

## Auto-categorize on import (gated by `ai`)

When `ai` is on, every successful import (CSV or AI) runs the freshly-inserted rows through `importers/categorizer.py` before returning. One AI call per import: the model receives the rows + the full category list (every non-Unknown category, leaf and parent, with descriptions) and returns an `assign_categories` tool call mapping `transaction_id → category_path`. Parent categories are valid assignment targets — the AI may pick one when no child is a clearer fit. Anything the model isn't confident about it omits, leaving the row at `category_id = NULL` for the user to handle.

It's best-effort. Every failure mode (missing key, network error, no categories defined, unparseable model output) shows up as a structured `error` in the response — the import itself is always 200.

## Response shape

## Dedupe

Every imported row is hashed:

```
source_hash = sha256("{date_iso}|{normalised_merchant}|{amount:.2f}")
```

Stored on the `transactions` table with a partial UNIQUE index (`WHERE source_hash IS NOT NULL`). Inserts use `INSERT OR IGNORE` so duplicates silently skip. Re-importing the same file produces `rows_inserted: 0` and `rows_skipped_duplicate: N`.

The seed populates `source_hash` for every seeded transaction too, so imports against a fresh DB still dedupe correctly against the mock data.

**Edge case worth knowing:** two genuine same-day same-merchant same-amount purchases (two $4.50 coffees on the same day) collapse into one. Acceptable tradeoff vs. the alternative of asking the user to disambiguate uploads. If users complain, extend the hash with a per-day counter.

Manual `POST /transactions` (single-row create from the UI) does **not** set `source_hash`, so two manually-added rows with identical `(date, merchant, amount)` coexist. The hash is an importer concern only.

Same shape regardless of which parser ran. The `categorization` key is omitted when `ai` is off.

```json
{
  "job_id": "imp_01H...",
  "format_detected": "csv",
  "rows_parsed": 84,
  "rows_skipped_duplicate": 12,
  "rows_failed": 1,
  "rows_inserted": 71,
  "preview": [ /* first 20 inserted rows */ ],
  "errors": [ {"row": 41, "reason": "amount unparseable: 'N/A'"} ],
  "ai_usage": null,
  "categorization": {
    "attempted": 71,
    "categorized": 64,
    "skipped_no_match": 7,
    "ai_usage": {"input_tokens": 1240, "output_tokens": 380}
  }
}
```

When the categorizer trips on a missing key or a transient failure, `categorization` carries an `error` field instead:

```json
{ "categorization": {"attempted": 71, "categorized": 0, "skipped_no_match": 71, "error": "ai_key_missing"} }
```

`job_id` is currently informational — there's no async job storage yet. CSV finishes in the POST, and the AI path is fast enough to do the same. If we ever need backgrounded uploads, a polling endpoint slots in here.

## Flipping the flag locally

The simplest path is the **Account screen** in the app. For tests / CI / a fresh dev shell, the env override still works:

```sh
export BUDGET_TRACE_FEATURES=ai
uvicorn budget_trace_backend.main:app --reload --port 8000
```

That env var wins over the DB for the running process. To persist instead, use `python -c "from budget_trace_backend.features import set_flag; set_flag('ai', True)"` or `curl -X PATCH localhost:8000/me -d '{"features":{"ai":true}}'`.

## What's not here

- **OFX, QFX, screenshots, plain-text paste.** All flow through the AI parser when the flag is on. No dedicated parsers.
- **Bank-specific PDF layouts.** We don't try to maintain regex zoos per bank. The AI parser handles anything the CSV parser can't.
- **Edits to imported rows from the response.** Use the Expenses screen to fix a bad import row; the response just confirms what landed.
