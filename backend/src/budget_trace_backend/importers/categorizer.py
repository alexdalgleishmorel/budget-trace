"""Auto-categorize freshly-imported transactions.

Runs after `insert_rows()` for both CSV and AI-parsed imports when the `ai`
flag is on. Two-stage pipeline:

  1. **Pre-apply from history** — query existing
     `(merchant → category_id)` pairs from the `transactions` table
     (most-recent assignment wins on collision). Any incoming row whose
     merchant is already known is categorized immediately, no AI call
     needed. This is how manual user fixes silently train future imports.

  2. **AI fallback** — send only the truly-unknown merchants to the model
     with the leaf category list. The model emits an `assign_categories`
     tool call mapping `transaction_id → category_path`. Output is deduped
     by merchant (first assignment wins on per-batch conflicts) and applied
     via the same per-merchant bulk UPDATE as stage 1.

If every input row is matched in stage 1, stage 2 is skipped entirely —
zero tokens billed.

Best-effort: every failure mode (missing key, network error, no leaves
defined, model emits garbage) returns a structured `{error: ...}` dict so
the import response is always 200. The import itself never breaks.

Defensive on the SQL side:
- Pre-applied + AI-assigned categories both use a per-merchant bulk
  UPDATE that skips rows already on the target category — keeps row
  counts honest.
- Drops AI assignments whose path doesn't resolve, isn't a leaf, or points
  at the symbolic Unknown row. The chat AI is the place to retry/fix those.
"""

from __future__ import annotations

import json
import logging

from ..db import category_id_for_path, connect, fetch_category_tree
from ..services import ai_usage as ai_usage_svc
from ..services.ai.client import AiKeyMissing, chat as ai_chat, get_selected_model

log = logging.getLogger(__name__)


ASSIGN_TOOL = {
    "type": "function",
    "function": {
        "name": "assign_categories",
        "description": (
            "Return a category assignment for every transaction you can confidently "
            "place. Omit transactions you're unsure about — they'll stay "
            "uncategorized for the user to review."
        ),
        "parameters": {
            "type": "object",
            "properties": {
                "assignments": {
                    "type": "array",
                    "items": {
                        "type": "object",
                        "properties": {
                            "transaction_id": {"type": "integer"},
                            "category_path": {
                                "type": "string",
                                "description": "Must be one of the leaf paths supplied in the prompt.",
                            },
                        },
                        "required": ["transaction_id", "category_path"],
                    },
                },
            },
            "required": ["assignments"],
        },
    },
}


SYSTEM_PROMPT = (
    "You categorize personal banking transactions into a fixed list of leaf "
    "category paths. Call `assign_categories` exactly once with everything "
    "you can confidently place. Match merchants and amounts against the "
    "category descriptions provided. Use only the exact leaf paths from the "
    "supplied list — never invent new ones. Omit any transaction where no "
    "leaf is a clear fit; the user will categorize it manually."
)


def categorize_rows(transaction_ids: list[int]) -> dict:
    """Open our own connection. Callers (the import route) must commit the
    insert transaction before invoking us, otherwise our read of the users
    table for the API key would deadlock against the outer write."""
    if not transaction_ids:
        return {
            "attempted": 0,
            "categorized": 0,
            "pre_applied": 0,
            "skipped_no_match": 0,
            "ai_usage": None,
        }

    with connect() as conn:
        leaves = [
            n for n in fetch_category_tree(conn)
            if n["is_leaf"] and not n["is_unknown"]
        ]
        if not leaves:
            return {
                "attempted": len(transaction_ids),
                "categorized": 0,
                "pre_applied": 0,
                "skipped_no_match": len(transaction_ids),
                "ai_usage": None,
                "error": "no_leaf_categories",
            }

        # Look up the input rows so we have their merchants + amounts.
        placeholders = ",".join("?" for _ in transaction_ids)
        rows = conn.execute(
            f"SELECT id, date, merchant, amount FROM transactions WHERE id IN ({placeholders})",
            transaction_ids,
        ).fetchall()
        id_to_merchant = {r["id"]: r["merchant"] for r in rows}

        # ── Stage 1: pre-apply from history ───────────────────────────────
        # Build a (merchant → category_id) dict from existing categorized
        # rows. Most-recent wins on collision (id DESC + setdefault).
        history = conn.execute(
            "SELECT merchant, category_id FROM transactions "
            "WHERE category_id IS NOT NULL AND merchant IS NOT NULL "
            "ORDER BY id DESC"
        ).fetchall()
        merchant_to_cat_id: dict[str, int] = {}
        for h in history:
            merchant_to_cat_id.setdefault(h["merchant"], h["category_id"])

        # Track which merchants in this batch are already known. We don't
        # apply the UPDATE per-row here — we collect the set and let stage 3
        # do one bulk UPDATE per merchant.
        pre_applied_merchants: set[str] = {
            m for m in id_to_merchant.values() if m in merchant_to_cat_id
        }

        # ── Stage 2: AI for the unknowns ──────────────────────────────────
        # Only the rows whose merchants are NOT in the history get sent to
        # the model. If the set is empty, skip the API call entirely.
        unknown_rows = [
            r for r in rows if r["merchant"] not in merchant_to_cat_id
        ]
        ai_usage = None
        if unknown_rows:
            txn_payload = [
                {"id": r["id"], "date": r["date"], "merchant": r["merchant"], "amount": r["amount"]}
                for r in unknown_rows
            ]
            user_text = (
                "Available leaf categories (use these exact paths):\n\n"
                + "\n".join(
                    f"- `{n['path']}` — {n['description'] or '(no description)'}"
                    for n in leaves
                )
                + "\n\nTransactions to categorize:\n\n"
                + json.dumps(txn_payload, indent=2)
            )

            try:
                model = get_selected_model()
                resp = ai_chat(
                    model=model,
                    system=SYSTEM_PROMPT,
                    messages=[{"role": "user", "content": user_text}],
                    tools=[ASSIGN_TOOL],
                    max_tokens=4096,
                )
                ai_usage_svc.record_usage(
                    source="auto_categorize", model=model, usage=resp.get("usage") or {},
                )
            except AiKeyMissing as e:
                # History pre-apply still happens; only the unknowns are lost.
                _apply_merchant_updates(conn, merchant_to_cat_id, pre_applied_merchants)
                pre_applied = sum(
                    1 for tid in transaction_ids
                    if id_to_merchant.get(tid) in pre_applied_merchants
                )
                return {
                    "attempted": len(transaction_ids),
                    "categorized": pre_applied,
                    "pre_applied": pre_applied,
                    "skipped_no_match": len(transaction_ids) - pre_applied,
                    "ai_usage": None,
                    "error": e.code,
                }
            except Exception as e:  # noqa: BLE001
                log.exception("categorizer call failed")
                _apply_merchant_updates(conn, merchant_to_cat_id, pre_applied_merchants)
                pre_applied = sum(
                    1 for tid in transaction_ids
                    if id_to_merchant.get(tid) in pre_applied_merchants
                )
                return {
                    "attempted": len(transaction_ids),
                    "categorized": pre_applied,
                    "pre_applied": pre_applied,
                    "skipped_no_match": len(transaction_ids) - pre_applied,
                    "ai_usage": None,
                    "error": "ai_failed",
                    "message": str(e),
                }

            # Merge the model's assignments into merchant_to_cat_id.
            # Dedupe by merchant — first assignment per merchant wins (same
            # invariant as the manual cascade).
            valid_paths = {n["path"] for n in leaves}
            requested_ids = {r["id"] for r in unknown_rows}
            for tc in resp.get("tool_calls") or []:
                if tc.get("name") != "assign_categories":
                    continue
                try:
                    args = json.loads(tc.get("arguments_json", "") or "{}")
                except json.JSONDecodeError:
                    args = {}
                if not isinstance(args, dict):
                    args = {}
                for raw in (args.get("assignments") or []):
                    try:
                        txn_id = int(raw["transaction_id"])
                        path = str(raw["category_path"])
                    except (KeyError, TypeError, ValueError):
                        continue
                    if txn_id not in requested_ids or path not in valid_paths:
                        continue
                    merchant = id_to_merchant.get(txn_id)
                    if merchant is None or merchant in merchant_to_cat_id:
                        continue
                    cat_id = category_id_for_path(conn, path)
                    if cat_id is None:
                        continue
                    merchant_to_cat_id[merchant] = cat_id
                break  # only honour the first call

            usage_dict = resp.get("usage") or {}
            ai_usage = {
                "input_tokens": int(usage_dict.get("input_tokens") or 0),
                "output_tokens": int(usage_dict.get("output_tokens") or 0),
            }

        # ── Stage 3: bulk UPDATE per merchant ─────────────────────────────
        # Covers both pre-applied and AI-assigned merchants. The
        # `(category_id IS NULL OR category_id != ?)` clause keeps the row
        # counts honest — already-correct rows aren't touched.
        ai_assigned_merchants = set(merchant_to_cat_id.keys()) - pre_applied_merchants
        all_merchants = pre_applied_merchants | ai_assigned_merchants
        _apply_merchant_updates(conn, merchant_to_cat_id, all_merchants)

        # Count input-batch hits per source so the response can distinguish
        # pre-applied from AI-assigned rows. (categorized = sum of the two.)
        pre_applied = sum(
            1 for tid in transaction_ids
            if id_to_merchant.get(tid) in pre_applied_merchants
        )
        ai_categorized = sum(
            1 for tid in transaction_ids
            if id_to_merchant.get(tid) in ai_assigned_merchants
        )
        categorized = pre_applied + ai_categorized

    return {
        "attempted": len(transaction_ids),
        "categorized": categorized,
        "pre_applied": pre_applied,
        "skipped_no_match": len(transaction_ids) - categorized,
        "ai_usage": ai_usage,
    }


def _apply_merchant_updates(conn, merchant_to_cat_id: dict[str, int], merchants: set[str]) -> None:
    """One bulk UPDATE per merchant. Idempotent: rows already on the target
    category are not touched (kept that way to make the per-row cascade
    inside services/transactions.py see consistent state)."""
    for merchant in merchants:
        cat_id = merchant_to_cat_id[merchant]
        conn.execute(
            "UPDATE transactions SET category_id = ? "
            "WHERE merchant = ? "
            "AND (category_id IS NULL OR category_id != ?)",
            (cat_id, merchant, cat_id),
        )
