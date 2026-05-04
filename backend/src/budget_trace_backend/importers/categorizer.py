"""Auto-categorize freshly-imported transactions.

Runs after `insert_rows()` for both CSV and AI-parsed imports when the `ai`
flag is on. One Anthropic call per import: the model sees the rows + the
current category tree (leaves only, Unknown filtered out) and emits an
`assign_categories` tool call mapping `transaction_id → category_path`.

Best-effort: every failure mode (missing key, network error, no leaves
defined, model emits garbage) returns a structured `{error: ...}` dict so
the import response is always 200. The import itself never breaks.

Defensive on the SQL side:
- Only updates rows where `category_id IS NULL` — never overwrites an
  existing category. (Belt-and-braces; freshly inserted rows are always NULL.)
- Drops assignments whose path doesn't resolve, isn't a leaf, or points at
  the symbolic Unknown row. The chat AI is the place to retry/fix those.
"""

from __future__ import annotations

import json
import logging

from ..db import category_id_for_path, connect, fetch_category_tree
from ..services.anthropic_client import AiKeyMissing, get_client, get_model

log = logging.getLogger(__name__)


ASSIGN_TOOL = {
    "name": "assign_categories",
    "description": (
        "Return a category assignment for every transaction you can confidently "
        "place. Omit transactions you're unsure about — they'll stay "
        "uncategorized for the user to review."
    ),
    "input_schema": {
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
        return {"attempted": 0, "categorized": 0, "skipped_no_match": 0, "ai_usage": None}

    with connect() as conn:
        leaves = [
            n for n in fetch_category_tree(conn)
            if n["is_leaf"] and not n["is_unknown"]
        ]
        if not leaves:
            return {
                "attempted": len(transaction_ids),
                "categorized": 0,
                "skipped_no_match": len(transaction_ids),
                "ai_usage": None,
                "error": "no_leaf_categories",
            }

        placeholders = ",".join("?" for _ in transaction_ids)
        rows = conn.execute(
            f"SELECT id, date, merchant, amount FROM transactions WHERE id IN ({placeholders})",
            transaction_ids,
        ).fetchall()
        txn_payload = [
            {"id": r["id"], "date": r["date"], "merchant": r["merchant"], "amount": r["amount"]}
            for r in rows
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
            client = get_client()
            resp = client.messages.create(
                model=get_model(),
                max_tokens=4096,
                system=SYSTEM_PROMPT,
                tools=[ASSIGN_TOOL],
                messages=[{"role": "user", "content": user_text}],
            )
        except AiKeyMissing as e:
            return {
                "attempted": len(transaction_ids),
                "categorized": 0,
                "skipped_no_match": len(transaction_ids),
                "ai_usage": None,
                "error": e.code,
            }
        except Exception as e:  # noqa: BLE001
            log.exception("categorizer call failed")
            return {
                "attempted": len(transaction_ids),
                "categorized": 0,
                "skipped_no_match": len(transaction_ids),
                "ai_usage": None,
                "error": "ai_failed",
                "message": str(e),
            }

        valid_paths = {n["path"] for n in leaves}
        requested_ids = set(transaction_ids)
        id_to_merchant = {r["id"]: r["merchant"] for r in rows}

        # Dedupe Claude's output by merchant. If the model assigns the same
        # merchant to two different categories within one batch, the first
        # wins — this enforces the same-merchant-same-category invariant
        # consistently with the manual-categorize cascade in
        # services/transactions.py.
        merchant_to_cat_id: dict[str, int] = {}
        for block in resp.content:
            if getattr(block, "type", None) != "tool_use" or block.name != "assign_categories":
                continue
            for raw in (block.input or {}).get("assignments", []):
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

        # Apply each (merchant, category) as a bulk update — covers both the
        # rows in this import batch AND any previously-imported rows with
        # the same merchant that were still uncategorized (or differently
        # categorized). The response's `categorized` field stays scoped to
        # the input batch so `categorized + skipped_no_match == attempted`
        # holds for the SnackBar math.
        for merchant, cat_id in merchant_to_cat_id.items():
            conn.execute(
                "UPDATE transactions SET category_id = ? "
                "WHERE merchant = ? "
                "AND (category_id IS NULL OR category_id != ?)",
                (cat_id, merchant, cat_id),
            )

        categorized = sum(
            1 for txn_id in transaction_ids
            if id_to_merchant.get(txn_id) in merchant_to_cat_id
        )

    usage = {
        "input_tokens": getattr(resp.usage, "input_tokens", 0),
        "output_tokens": getattr(resp.usage, "output_tokens", 0),
    }
    return {
        "attempted": len(transaction_ids),
        "categorized": categorized,
        "skipped_no_match": len(transaction_ids) - categorized,
        "ai_usage": usage,
    }
