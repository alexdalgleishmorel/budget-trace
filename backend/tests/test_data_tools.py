"""Backend tests — exercise db.py + the MCP tool functions against a fresh,
deterministic seed in a tmp DB. We don't touch the Anthropic API here.

If a test fails because the seed numbers shifted, check `seed.py`'s
SEED_VALUE — that's the only knob that should change the data."""

from __future__ import annotations

import os
from pathlib import Path

import pytest

from budget_trace_backend import db as db_module
from budget_trace_backend import mcp_server, seed


@pytest.fixture(scope="module")
def seeded_db(tmp_path_factory) -> Path:
    target = tmp_path_factory.mktemp("data") / "test.db"
    os.environ["BUDGET_TRACE_DB"] = str(target)
    seed.main(target)
    yield target
    del os.environ["BUDGET_TRACE_DB"]


def test_seed_creates_categories_and_transactions(seeded_db: Path) -> None:
    with db_module.connect(seeded_db) as conn:
        cats = conn.execute("SELECT COUNT(*) AS c FROM categories").fetchone()["c"]
        txns = conn.execute("SELECT COUNT(*) AS c FROM transactions").fetchone()["c"]
    assert cats >= 14  # root + 3 groups + leaves + Unknown
    assert txns > 200  # 12 months * ~20+/month


def test_category_paths_are_built(seeded_db: Path) -> None:
    tree = mcp_server.list_categories()
    paths = {c["path"] for c in tree}
    # Root "Budget" is intentionally excluded — top-level groups are the entry
    # points the AI sees.
    assert "Budget" not in paths
    assert "House" in paths
    assert "Living / Grocery" in paths
    assert "House / Rent / Mortgage" in paths


def test_aggregate_spending_monthly_grocery(seeded_db: Path) -> None:
    rows = mcp_server.aggregate_spending(
        start_date="2025-05-01",
        end_date="2026-04-30",
        bucket="month",
        category_path="Living / Grocery",
    )
    assert len(rows) == 12
    for r in rows:
        assert r["value"] > 0
        assert "period_label" in r


def test_aggregate_spending_uncategorised_filter(seeded_db: Path) -> None:
    rows = mcp_server.aggregate_spending(
        start_date="2025-05-01",
        end_date="2026-04-30",
        bucket="month",
        category_path="Unknown",
    )
    assert len(rows) == 12  # every month has uncategorised txns


def test_top_merchants_grocery(seeded_db: Path) -> None:
    rows = mcp_server.top_merchants(
        start_date="2025-05-01",
        end_date="2026-04-30",
        category_path="Living / Grocery",
        limit=3,
    )
    assert 1 <= len(rows) <= 3
    assert all(r["total"] > 0 for r in rows)
    # Result should be sorted descending by total
    totals = [r["total"] for r in rows]
    assert totals == sorted(totals, reverse=True)


def test_compare_periods_returns_delta(seeded_db: Path) -> None:
    out = mcp_server.compare_periods(
        period_a_start="2025-05-01",
        period_a_end="2025-07-31",
        period_b_start="2026-02-01",
        period_b_end="2026-04-30",
        category_path="Living / Fun",
    )
    assert out["a_total"] > 0
    assert out["b_total"] > 0
    assert out["abs_delta"] == round(out["b_total"] - out["a_total"], 2)


def test_list_transactions_merchant_query(seeded_db: Path) -> None:
    rows = mcp_server.list_transactions(merchant_query="STARBUCKS", limit=5)
    assert all("STARBUCKS" in r["merchant"].upper() for r in rows)


def test_aggregate_by_top_level_returns_multiple_series(seeded_db: Path) -> None:
    rows = mcp_server.aggregate_spending(
        start_date="2025-05-01",
        end_date="2026-04-30",
        bucket="month",
        by_category=True,
    )
    series_paths = {r["category_path"] for r in rows}
    assert {"House", "Living", "Savings", "Unassigned"}.issubset(series_paths)


def test_forecast_extends_horizon(seeded_db: Path) -> None:
    out = mcp_server.forecast(horizon_months=3, category_path="Living / Grocery")
    assert len(out["historical"]) == 12
    assert len(out["forecast"]) == 3
    assert all(r["value"] > 0 for r in out["forecast"])
