"""Test-fixture mock-data generator. Not exposed as a CLI to end users.

Generates 12 months of deterministic mock transactions ending 2026-04-30
plus a sample category tree. Used by `tests/` to populate a tmp DB; the
shipped backend bootstraps to a clean empty state via `db.bootstrap_db()`
on FastAPI startup, so users start with no data instead of the mock set.

Deterministic: `random.seed(SEED_VALUE)` makes runs reproducible. Idempotent:
calling `main()` wipes both tables before reseeding.
"""

from __future__ import annotations

import random
from datetime import date, timedelta
from pathlib import Path

from .db import connect, db_path, init_schema
from .features import ensure_default_user
from .importers.common import ImportedRow, source_hash as compute_source_hash

SEED_VALUE = 42
END_DATE = date(2026, 4, 30)
MONTHS = 12  # → 2025-05 through 2026-04

CATEGORY_TREE: list[dict] = [
    {
        "name": "House",
        "description": "Costs of keeping a roof over your head — housing payments and home services.",
        "color": "stone",
        "children": [
            {
                "name": "Rent",
                "description": "Recurring monthly payment for the home itself.",
                "color": "graphite",
                "children": [
                    {"name": "Mortgage",   "description": "Bank or lender mortgage payment for the primary residence.", "color": "graphite"},
                    {"name": "Strata Fee", "description": "Condo, HOA, or strata fees for shared building maintenance.", "color": "graphite"},
                ],
            },
            {"name": "Utilities", "description": "Electricity, gas, water, and other recurring home utilities.", "color": "ochre"},
            {"name": "Internet",  "description": "Home internet service and mobile phone bills.", "color": "sky"},
        ],
    },
    {
        "name": "Living",
        "description": "Day-to-day spending — transport, food, and everyday personal expenses.",
        "color": "sage",
        "children": [
            {"name": "Car Insurance", "description": "Auto insurance premiums.", "color": "plum"},
            {"name": "Gas",           "description": "Fuel for personal vehicles (gas stations, EV charging).", "color": "clay"},
            {"name": "Grocery",       "description": "Supermarket and grocery-store food shopping for the household.", "color": "moss"},
            {"name": "Fun",           "description": "Entertainment, streaming subscriptions, dining out, hobbies, going out.", "color": "teal"},
            {"name": "Shopping",      "description": "Discretionary retail purchases — clothes, electronics, household goods.", "color": "sand"},
        ],
    },
    {
        "name": "Savings",
        "description": "Money set aside for the future — investments and earmarked savings.",
        "color": "olive",
        "children": [
            {"name": "Emergency Fund", "description": "Transfers into a rainy-day savings account.", "color": "olive"},
            {"name": "Retirement",     "description": "Retirement contributions — 401k, IRA, RRSP, brokerage auto-invest.", "color": "graphite"},
            {"name": "Travel",         "description": "Money set aside for upcoming trips and vacations.", "color": "cream"},
        ],
    },
    {
        "name": "Unknown",
        "description": "Catch-all for transactions that have not been categorised yet.",
        "is_unknown": True,
        "color": "stone",
    },
]


def _insert_category(conn, name, description, parent_id, is_unknown=False, color="stone") -> int:
    cur = conn.execute(
        "INSERT INTO categories (name, description, parent_id, is_unknown, color) VALUES (?, ?, ?, ?, ?)",
        (name, description, parent_id, int(is_unknown), color),
    )
    return cur.lastrowid


def _seed_categories(conn) -> dict[str, int]:
    """Returns a {category_name: id} map for leaf-and-group lookups during txn seeding."""
    ids: dict[str, int] = {}

    def walk(nodes, parent_id):
        for n in nodes:
            cid = _insert_category(
                conn,
                n["name"],
                n.get("description"),
                parent_id,
                n.get("is_unknown", False),
                n.get("color", "stone"),
            )
            ids[n["name"]] = cid
            walk(n.get("children", []), cid)

    # Root: "Budget"
    root_id = _insert_category(conn, "Budget", "Top-level container for all spending and savings.", None)
    ids["Budget"] = root_id
    walk(CATEGORY_TREE, root_id)
    return ids


# ── Transaction generators ────────────────────────────────────────────────────

UNCATEGORISED_MERCHANTS = [
    "AMZN MKTP US*Z82",
    "STARBUCKS #4419",
    "BLOCK INC *VENMO",
    "UBER *TRIP",
    "CHIPOTLE 2241",
    "IKEA RICHMOND",
    "LYFT *RIDE",
    "APPLE.COM/BILL",
    "DOORDASH*MAIN ST",
    "CVS PHARMACY #774",
    "TIM HORTONS #221",
    "PAYPAL *DIGITAL",
    "ETSY ORDER",
    "REI #129",
    "MCDONALD'S F11",
]

GROCERY_MERCHANTS = ["TRADER JOES #142", "WHOLE FOODS MKT", "COSTCO WHSE", "SAFEWAY #3192", "LOCAL FARM CO-OP"]
GAS_MERCHANTS = ["SHELL OIL", "CHEVRON #1182", "PETRO-CANADA"]
FUN_MERCHANTS = ["NETFLIX.COM", "SPOTIFY USA", "AMC THEATERS", "HBO MAX", "STEAM GAMES", "RESY * DINNER"]
SHOPPING_MERCHANTS = ["TARGET 00012445", "BEST BUY #404", "ZARA US", "UNIQLO", "MUJI"]


def _last_day_of_month(y: int, m: int) -> int:
    if m == 12:
        return 31
    return (date(y, m + 1, 1) - timedelta(days=1)).day


def _generate_transactions(rng: random.Random, ids: dict[str, int]) -> list[tuple]:
    """Yield (date, merchant, amount, category_id) tuples for 12 months ending END_DATE."""
    out: list[tuple] = []

    # End at END_DATE; first month is 11 months earlier.
    start_year = END_DATE.year if END_DATE.month > MONTHS else END_DATE.year - 1
    start_month = ((END_DATE.month - MONTHS) % 12) + 1

    y, m = start_year, start_month
    for _ in range(MONTHS):
        last_day = _last_day_of_month(y, m)

        # Recurring, fixed-day-of-month bills
        out.append((date(y, m, 1).isoformat(), "VANGUARD AUTO INVEST", 700.00, ids["Retirement"]))
        out.append((date(y, m, 1).isoformat(), "EMERGENCY FUND XFER",  600.00, ids["Emergency Fund"]))
        out.append((date(y, m, 4).isoformat(), "GEICO AUTO",           320.00, ids["Car Insurance"]))
        out.append((date(y, m, 15).isoformat(), "CHASE MORTGAGE",     1500.00, ids["Rent"]))
        out.append((date(y, m, 29 if last_day >= 29 else last_day).isoformat(),
                    "XFINITY MOBILE", 100.00 + rng.uniform(0, 12), ids["Internet"]))

        # Utilities — heavier in winter (Nov-Feb), lighter in summer
        winter_boost = 1.4 if m in (11, 12, 1, 2) else (0.8 if m in (6, 7, 8) else 1.0)
        out.append((date(y, m, 3).isoformat(),
                    "CON EDISON BILL", round(140 * winter_boost + rng.uniform(-15, 25), 2),
                    ids["Utilities"]))

        # Travel contribution — bigger contributions May-Aug and Dec
        travel_boost = 2.0 if m in (5, 6, 7, 8, 12) else 1.0
        out.append((date(y, m, 1).isoformat(),
                    "TRAVEL FUND CONTRIB", round(200 * travel_boost, 2),
                    ids["Travel"]))

        # Grocery — 4-6/month, spread across the month
        for _ in range(rng.randint(4, 6)):
            d = rng.randint(2, last_day)
            out.append((date(y, m, d).isoformat(),
                        rng.choice(GROCERY_MERCHANTS),
                        round(rng.uniform(45, 220), 2),
                        ids["Grocery"]))

        # Gas — 2-4/month
        for _ in range(rng.randint(2, 4)):
            d = rng.randint(2, last_day)
            out.append((date(y, m, d).isoformat(),
                        rng.choice(GAS_MERCHANTS),
                        round(rng.uniform(32, 78), 2),
                        ids["Gas"]))

        # Fun — variable count, larger in Dec
        fun_count = rng.randint(8, 14) if m == 12 else rng.randint(4, 9)
        for _ in range(fun_count):
            d = rng.randint(2, last_day)
            out.append((date(y, m, d).isoformat(),
                        rng.choice(FUN_MERCHANTS),
                        round(rng.uniform(8, 65), 2),
                        ids["Fun"]))

        # Shopping — variable, bigger in Nov-Dec
        shop_count = rng.randint(5, 9) if m in (11, 12) else rng.randint(2, 5)
        for _ in range(shop_count):
            d = rng.randint(2, last_day)
            out.append((date(y, m, d).isoformat(),
                        rng.choice(SHOPPING_MERCHANTS),
                        round(rng.uniform(20, 220), 2),
                        ids["Shopping"]))

        # Strata fee — fixed monthly
        out.append((date(y, m, 5).isoformat(), "STRATA CORP #4421", 300.00, ids["Strata Fee"]))

        # Uncategorised — 6-12/month
        for _ in range(rng.randint(6, 12)):
            d = rng.randint(2, last_day)
            out.append((date(y, m, d).isoformat(),
                        rng.choice(UNCATEGORISED_MERCHANTS),
                        round(rng.uniform(7, 150), 2),
                        None))

        # Lumpy travel actuals — every 3-4 months a real trip outlay
        if m in (7, 12, 3):
            d = rng.randint(5, 18)
            out.append((date(y, m, d).isoformat(), "AIR CANADA",
                        round(rng.uniform(420, 1100), 2), ids["Travel"]))

        # Advance the month
        if m == 12:
            y, m = y + 1, 1
        else:
            m += 1

    out.sort(key=lambda t: t[0])
    return out


def main(db_path_override: Path | None = None) -> Path:
    rng = random.Random(SEED_VALUE)
    target = db_path_override or db_path()

    with connect(target) as conn:
        init_schema(conn)
        # Idempotent: clear before reseeding so reruns produce identical data.
        conn.execute("DELETE FROM transactions")
        conn.execute("DELETE FROM categories")

        ids = _seed_categories(conn)
        ensure_default_user(conn)
        rows = _generate_transactions(rng, ids)

        # Compute source_hash for every seeded row so future imports get the
        # same dedupe behaviour against the seed (re-importing a CSV that
        # contains a seeded transaction will silently skip it).
        with_hash: list[tuple] = []
        for date_iso, merchant, amount, category_id in rows:
            try:
                imported = ImportedRow(date=date_iso, merchant=merchant, amount=amount)
                h = compute_source_hash(imported)
            except Exception:
                h = None
            with_hash.append((date_iso, merchant, amount, category_id, h))

        conn.executemany(
            "INSERT OR IGNORE INTO transactions "
            "(date, merchant, amount, category_id, source_hash) "
            "VALUES (?, ?, ?, ?, ?)",
            with_hash,
        )
        n = conn.execute("SELECT COUNT(*) AS c FROM transactions").fetchone()["c"]

    print(f"Seeded {n} transactions across {MONTHS} months → {target}")
    return target


if __name__ == "__main__":
    main()
