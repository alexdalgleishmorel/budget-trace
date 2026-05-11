"""Dashboards / widgets / save-from-chat surface — REST + service layer.

Mirrors the fixture pattern from test_transactions.py. The seed contains
12 months of transactions ending 2026-04-30, giving every metric a
reasonable window to operate over.
"""

from __future__ import annotations

import os
from pathlib import Path

import pytest
from fastapi.testclient import TestClient

from budget_trace_backend import features, seed
from budget_trace_backend.main import app
from budget_trace_backend.services import dashboards as svc
from budget_trace_backend.services import widget_metrics


@pytest.fixture()
def seeded_db(tmp_path: Path) -> Path:
    target = tmp_path / "test.db"
    os.environ["BUDGET_TRACE_DB"] = str(target)
    seed.main(target)
    yield target
    os.environ.pop("BUDGET_TRACE_DB", None)


@pytest.fixture()
def client(seeded_db: Path) -> TestClient:
    return TestClient(app)


# A window inside the seed (12 months ending 2026-04-30).
SEED_START = "2025-05-01"
SEED_END = "2026-04-30"


def _new_dashboard(name: str = "X") -> dict:
    """Helper: create a dashboard with its time range pinned to the seed
    window, so tests don't drift relative to today's date."""
    d = svc.create_dashboard(1, name)
    return svc.update_dashboard(
        1, d["id"],
        time_range={"preset": "custom",
                    "custom_start": SEED_START, "custom_end": SEED_END},
    )


# ── Service layer: dashboards CRUD ───────────────────────────────────────────


def test_create_then_get_dashboard(seeded_db: Path) -> None:
    d = svc.create_dashboard(1, "Monthly review")
    assert d["name"] == "Monthly review"
    # Defaults to last_3_months out of the box.
    assert d["time_range"]["preset"] == "last_3_months"
    fetched = svc.get_dashboard(1, d["id"])
    assert fetched["id"] == d["id"]
    assert fetched["widgets"] == []


def test_create_dashboard_rejects_empty_name(seeded_db: Path) -> None:
    with pytest.raises(svc.ServiceError):
        svc.create_dashboard(1, "  ")


def test_rename_dashboard(seeded_db: Path) -> None:
    d = svc.create_dashboard(1, "First")
    renamed = svc.rename_dashboard(1, d["id"], "Renamed")
    assert renamed["name"] == "Renamed"


def test_update_dashboard_time_range(seeded_db: Path) -> None:
    d = svc.create_dashboard(1, "X")
    out = svc.update_dashboard(1, d["id"], time_range={
        "preset": "custom",
        "custom_start": SEED_START, "custom_end": SEED_END,
    })
    assert out["time_range"] == {
        "preset": "custom",
        "custom_start": SEED_START, "custom_end": SEED_END,
    }


def test_update_dashboard_rejects_unknown_preset(seeded_db: Path) -> None:
    d = svc.create_dashboard(1, "X")
    with pytest.raises(svc.ServiceError):
        svc.update_dashboard(1, d["id"],
                             time_range={"preset": "not_a_preset"})


def test_update_dashboard_custom_requires_dates(seeded_db: Path) -> None:
    d = svc.create_dashboard(1, "X")
    with pytest.raises(svc.ServiceError):
        svc.update_dashboard(1, d["id"], time_range={"preset": "custom"})


def test_delete_dashboard_cascades_widgets(seeded_db: Path) -> None:
    d = _new_dashboard("Doomed")
    w = svc.create_widget(1, d["id"], {
        "type": "query_value",
        "layout": {"x": 0, "y": 0, "w": 2, "h": 2},
        "data_source": {"kind": "metric", "metric_id": "total_spend"},
        "config": {},
    })
    svc.delete_dashboard(1, d["id"])
    with pytest.raises(svc.NotFound):
        svc.update_widget(1, d["id"], w["id"], {"title": "X"})


def test_get_dashboard_marks_last_viewed(seeded_db: Path) -> None:
    a = svc.create_dashboard(1, "A")
    b = svc.create_dashboard(1, "B")
    svc.get_dashboard(1, b["id"])
    assert features.get_me()["last_dashboard_id"] == b["id"]
    svc.get_dashboard(1, a["id"])
    assert features.get_me()["last_dashboard_id"] == a["id"]


def test_delete_last_viewed_dashboard_clears_pointer(seeded_db: Path) -> None:
    d = svc.create_dashboard(1, "Soon to go")
    svc.get_dashboard(1, d["id"])
    assert features.get_me()["last_dashboard_id"] == d["id"]
    svc.delete_dashboard(1, d["id"])
    assert features.get_me()["last_dashboard_id"] is None


# ── Service layer: widget CRUD + validation ──────────────────────────────────


def _seed_metric_widget(dashboard_id: int, type_: str = "query_value") -> dict:
    return svc.create_widget(1, dashboard_id, {
        "type": type_,
        "title": "Demo",
        "layout": {"x": 0, "y": 0, "w": 2, "h": 2},
        "data_source": {"kind": "metric", "metric_id": "total_spend"},
        "config": {},
    })


def test_create_widget_rejects_unknown_metric(seeded_db: Path) -> None:
    d = _new_dashboard()
    with pytest.raises(svc.ServiceError):
        svc.create_widget(1, d["id"], {
            "type": "query_value",
            "layout": {"x": 0, "y": 0, "w": 1, "h": 1},
            "data_source": {"kind": "metric", "metric_id": "no_such_metric"},
            "config": {},
        })


def test_create_widget_rejects_incompatible_type(seeded_db: Path) -> None:
    d = _new_dashboard()
    # `spend_forecast` is timeseries-only; trying to use it as a pie chart
    # should be rejected.
    with pytest.raises(svc.ServiceError):
        svc.create_widget(1, d["id"], {
            "type": "pie",
            "layout": {"x": 0, "y": 0, "w": 2, "h": 2},
            "data_source": {"kind": "metric", "metric_id": "spend_forecast"},
            "config": {},
        })


def test_create_widget_rejects_below_min_size(seeded_db: Path) -> None:
    d = _new_dashboard()
    with pytest.raises(svc.ServiceError):
        svc.create_widget(1, d["id"], {
            "type": "timeseries",
            "layout": {"x": 0, "y": 0, "w": 1, "h": 1},  # timeseries min is 3×2
            "data_source": {"kind": "metric", "metric_id": "spend_over_time"},
            "config": {},
        })


def test_update_widget_layout(seeded_db: Path) -> None:
    d = _new_dashboard()
    w = _seed_metric_widget(d["id"])
    updated = svc.update_widget(1, d["id"], w["id"], {
        "layout": {"x": 3, "y": 1, "w": 3, "h": 2},
    })
    assert updated["layout"] == {"x": 3, "y": 1, "w": 3, "h": 2}


def test_create_widget_derives_title_from_metric(seeded_db: Path) -> None:
    d = _new_dashboard()
    w = _seed_metric_widget(d["id"])
    # No title is sent by clients any more; the service derives one as
    # "{Widget type} : {Metric}" so the chrome can render it.
    assert w["title"] == "Big number : Total spend"


def test_bulk_update_layout_atomic(seeded_db: Path) -> None:
    d = _new_dashboard()
    w1 = _seed_metric_widget(d["id"])
    w2 = _seed_metric_widget(d["id"])
    svc.bulk_update_layout(1, d["id"], [
        {"id": w1["id"], "x": 0, "y": 0, "w": 2, "h": 2},
        {"id": w2["id"], "x": 2, "y": 0, "w": 2, "h": 2},
    ])
    fresh = svc.get_dashboard(1, d["id"])
    by_id = {w["id"]: w for w in fresh["widgets"]}
    assert by_id[w1["id"]]["layout"] == {"x": 0, "y": 0, "w": 2, "h": 2}
    assert by_id[w2["id"]]["layout"] == {"x": 2, "y": 0, "w": 2, "h": 2}


def test_bulk_update_layout_rejects_foreign_widget(seeded_db: Path) -> None:
    d1 = _new_dashboard("A")
    d2 = _new_dashboard("B")
    foreign = _seed_metric_widget(d2["id"])
    with pytest.raises(svc.NotFound):
        svc.bulk_update_layout(1, d1["id"], [
            {"id": foreign["id"], "x": 0, "y": 0, "w": 2, "h": 2},
        ])


def test_time_range_change_bumps_widget_updated_at(seeded_db: Path) -> None:
    d = _new_dashboard()
    w = _seed_metric_widget(d["id"])
    old = w["updated_at"]
    svc.update_dashboard(1, d["id"], time_range={
        "preset": "custom",
        "custom_start": "2025-09-01", "custom_end": "2026-04-30",
    })
    fresh = svc.get_dashboard(1, d["id"])
    assert fresh["widgets"][0]["updated_at"] != old


# ── Widget data resolution (one per type) ────────────────────────────────────


def _make_widget(dashboard_id: int, type_: str, metric_id: str,
                 params: dict | None = None,
                 *, w: int = 3, h: int = 2) -> dict:
    return svc.create_widget(1, dashboard_id, {
        "type": type_, "title": metric_id,
        "layout": {"x": 0, "y": 0, "w": w, "h": h},
        "data_source": {"kind": "metric", "metric_id": metric_id,
                        "params": params or {}},
        "config": {},
    })


def test_widget_data_timeseries(seeded_db: Path) -> None:
    d = _new_dashboard()
    w = _make_widget(d["id"], "timeseries", "spend_over_time",
                     {"rollup_period": "month"})
    data = svc.get_widget_data(1, d["id"], w["id"])
    assert data["type"] == "timeseries"
    chart = data["data"]["chart"]
    assert "series" in chart and len(chart["series"]) >= 1
    assert len(chart["series"][0]["points"]) > 0


def test_widget_data_pie(seeded_db: Path) -> None:
    d = _new_dashboard()
    w = _make_widget(d["id"], "pie", "spend_by_category", w=2, h=2)
    data = svc.get_widget_data(1, d["id"], w["id"])
    assert data["type"] == "pie"
    assert "slices" in data["data"]
    assert data["data"]["total"] > 0
    assert any(s["label"] == "Living" for s in data["data"]["slices"])


def test_widget_data_bar(seeded_db: Path) -> None:
    d = _new_dashboard()
    w = _make_widget(d["id"], "bar", "spend_by_category", w=2, h=2)
    data = svc.get_widget_data(1, d["id"], w["id"])
    assert data["type"] == "bar"
    assert all("label" in c and "value" in c for c in data["data"]["categories"])


def test_widget_data_query_value(seeded_db: Path) -> None:
    d = _new_dashboard()
    w = _make_widget(d["id"], "query_value", "total_spend",
                     {"compare_to_previous": True}, w=2, h=2)
    data = svc.get_widget_data(1, d["id"], w["id"])
    assert data["type"] == "query_value"
    assert data["data"]["value"] > 0
    assert "comparison" in data["data"]


def test_widget_data_table(seeded_db: Path) -> None:
    d = _new_dashboard()
    w = _make_widget(d["id"], "table", "recent_transactions",
                     {"limit": 5}, w=3, h=2)
    data = svc.get_widget_data(1, d["id"], w["id"])
    assert data["type"] == "table"
    cols = [c["key"] for c in data["data"]["columns"]]
    assert "merchant" in cols and "amount" in cols
    assert len(data["data"]["rows"]) <= 5


def test_widget_data_treemap(seeded_db: Path) -> None:
    d = _new_dashboard()
    w = _make_widget(d["id"], "treemap", "spend_by_category", w=2, h=2)
    data = svc.get_widget_data(1, d["id"], w["id"])
    assert data["type"] == "treemap"
    assert len(data["data"]["nodes"]) >= 1


def test_widget_data_forecast_has_two_series(seeded_db: Path) -> None:
    d = _new_dashboard()
    w = _make_widget(d["id"], "timeseries", "spend_forecast",
                     {"horizon_months": 3, "method": "trailing_avg"})
    data = svc.get_widget_data(1, d["id"], w["id"])
    series = data["data"]["chart"]["series"]
    styles = {s["style"] for s in series}
    assert {"solid", "dashed"} <= styles


def test_widget_data_uses_dashboard_time_range(seeded_db: Path) -> None:
    """Same widget on two dashboards with different ranges returns
    different totals — confirms the range comes from the dashboard, not
    the widget."""
    wide = _new_dashboard("Wide")
    narrow = svc.create_dashboard(1, "Narrow")
    svc.update_dashboard(1, narrow["id"], time_range={
        "preset": "custom",
        "custom_start": "2026-04-01", "custom_end": "2026-04-30",
    })
    w1 = _make_widget(wide["id"], "query_value", "total_spend", w=2, h=2)
    w2 = _make_widget(narrow["id"], "query_value", "total_spend", w=2, h=2)
    v_wide = svc.get_widget_data(1, wide["id"], w1["id"])["data"]["value"]
    v_narrow = svc.get_widget_data(1, narrow["id"], w2["id"])["data"]["value"]
    assert v_wide > v_narrow > 0


# ── Saved insights ───────────────────────────────────────────────────────────


SAMPLE_CHART = {
    "title": "Monthly spend",
    "y_axis_label": "USD",
    "x_axis_label": None,
    "x_tick_labels": ["Feb '26", "Mar '26", "Apr '26"],
    "series": [
        {
            "label": "Total",
            "style": "solid",
            "points": [{"x": 0.0, "y": 1200.0}, {"x": 1.0, "y": 1350.0}, {"x": 2.0, "y": 1180.0}],
        },
    ],
}

# Polymorphic widget snapshots that can be persisted as saved insights.
SAMPLE_TIMESERIES_WIDGET = {
    "type": "timeseries",
    "title": "Monthly spend",
    "data": {"chart": SAMPLE_CHART},
}

SAMPLE_PIE_WIDGET = {
    "type": "pie",
    "title": "April breakdown",
    "data": {
        "slices": [
            {"label": "Living", "value": 800.0},
            {"label": "House",  "value": 1200.0},
        ],
        "total": 2000.0,
    },
}


def test_save_chat_widget_to_dashboard_metric_path(seeded_db: Path) -> None:
    """A chat widget carrying metric_id + metric_params becomes a
    kind:"metric" widget on the dashboard. The dashboard's time range
    governs its data."""
    d = _new_dashboard()
    chat_widget = {
        "type": "query_value",
        "title": "Total spend",
        # When metric_id is present `data` is ignored — backend re-runs the
        # metric using the dashboard's time range.
        "data": {},
        "metric_id": "total_spend",
        "metric_params": {},
    }
    out = svc.save_chat_widget_to_dashboard(
        1, dashboard_id=d["id"], chat_widget=chat_widget,
    )
    assert out["type"] == "query_value"
    assert out["data_source"] == {
        "kind": "metric", "metric_id": "total_spend", "params": {},
    }
    # The data endpoint must report it as non-snapshot and produce live data.
    data = svc.get_widget_data(1, d["id"], out["id"])
    assert data["is_snapshot"] is False
    assert data["data"]["value"] > 0


def test_save_chat_widget_to_dashboard_snapshot_path(seeded_db: Path) -> None:
    """When no metric_id is present, the widget is saved as a frozen
    snapshot stored inline on the widget row."""
    d = _new_dashboard()
    chat_widget = {
        "type": "pie",
        "title": "April breakdown",
        "data": SAMPLE_PIE_WIDGET["data"],
        "fallback_reason": "no curated metric matches a hand-picked range",
    }
    out = svc.save_chat_widget_to_dashboard(
        1, dashboard_id=d["id"], chat_widget=chat_widget,
    )
    assert out["data_source"] == {"kind": "snapshot"}
    data = svc.get_widget_data(1, d["id"], out["id"])
    assert data["is_snapshot"] is True
    assert data["type"] == "pie"
    assert data["data"] == SAMPLE_PIE_WIDGET["data"]


def test_save_chat_widget_snapshot_ignores_dashboard_time_range(
    seeded_db: Path,
) -> None:
    """Snapshot widgets are byte-frozen — switching the dashboard's
    time range must not change their data."""
    d = _new_dashboard()
    out = svc.save_chat_widget_to_dashboard(
        1, dashboard_id=d["id"], chat_widget={
            "type": "pie", "title": "Snap",
            "data": SAMPLE_PIE_WIDGET["data"],
        },
    )
    before = svc.get_widget_data(1, d["id"], out["id"])
    svc.update_dashboard(1, d["id"], time_range={
        "preset": "custom",
        "custom_start": "2026-04-01", "custom_end": "2026-04-30",
    })
    after = svc.get_widget_data(1, d["id"], out["id"])
    assert before["data"] == after["data"]


def test_drawer_cannot_create_snapshot_widget(seeded_db: Path) -> None:
    """Snapshots are only created by the chat-save endpoint — the
    create_widget service layer must reject kind:"snapshot" directly."""
    d = svc.create_dashboard(1, "X")
    with pytest.raises(svc.ServiceError):
        svc.create_widget(1, d["id"], {
            "type": "pie",
            "layout": {"x": 0, "y": 0, "w": 2, "h": 2},
            "data_source": {"kind": "snapshot"},
            "config": {},
        })


def test_drawer_rejects_legacy_insight_kind(seeded_db: Path) -> None:
    """The legacy kind:"insight" data source is gone — anything still
    sending it should get a clean validation error."""
    d = svc.create_dashboard(1, "X")
    with pytest.raises(svc.ServiceError):
        svc.create_widget(1, d["id"], {
            "type": "pie",
            "layout": {"x": 0, "y": 0, "w": 2, "h": 2},
            "data_source": {"kind": "insight", "insight_id": 1},
            "config": {},
        })


# ── Registry surface ─────────────────────────────────────────────────────────


def test_metric_registry_lists_all_metrics(seeded_db: Path) -> None:
    metrics = widget_metrics.list_metric_defs()
    ids = {m["id"] for m in metrics}
    assert {
        "spend_over_time", "spend_by_category", "top_merchants",
        "total_spend", "average_per_period", "transaction_count",
        "period_comparison", "spend_forecast", "recent_transactions",
    } <= ids
    # Every widget type appears in at least one metric's compatibility list.
    covered: set[str] = set()
    for m in metrics:
        covered.update(m["widget_types"])
    assert covered >= set(widget_metrics.ALL_WIDGET_TYPES)


# ── REST routes ──────────────────────────────────────────────────────────────


def test_full_round_trip_via_rest(client: TestClient) -> None:
    # Create a dashboard, pin its time range to the seed window.
    resp = client.post("/dashboards", json={"name": "via REST"})
    assert resp.status_code == 201, resp.text
    did = resp.json()["id"]

    resp = client.patch(f"/dashboards/{did}", json={
        "time_range": {
            "preset": "custom",
            "custom_start": SEED_START, "custom_end": SEED_END,
        },
    })
    assert resp.status_code == 200, resp.text
    assert resp.json()["time_range"]["preset"] == "custom"

    # Add a widget
    resp = client.post(
        f"/dashboards/{did}/widgets",
        json={
            "type": "query_value",
            "layout": {"x": 0, "y": 0, "w": 2, "h": 2},
            "data_source": {"kind": "metric", "metric_id": "total_spend"},
            "config": {},
        },
    )
    assert resp.status_code == 201, resp.text
    wid = resp.json()["id"]

    # Fetch the widget data
    resp = client.get(f"/dashboards/{did}/widgets/{wid}/data")
    assert resp.status_code == 200
    body = resp.json()
    assert body["type"] == "query_value"
    assert body["data"]["value"] > 0

    # Bulk-update layout
    resp = client.put(
        f"/dashboards/{did}/layout",
        json={"layouts": [{"id": wid, "x": 1, "y": 1, "w": 3, "h": 2}]},
    )
    assert resp.status_code == 200
    assert resp.json() == {"updated": 1}

    # Delete the widget
    resp = client.delete(f"/dashboards/{did}/widgets/{wid}")
    assert resp.status_code == 200
    assert resp.json() == {"deleted_id": wid}

    # Delete the dashboard
    resp = client.delete(f"/dashboards/{did}")
    assert resp.status_code == 200


def test_widget_metrics_endpoint(client: TestClient) -> None:
    resp = client.get("/widget-metrics")
    assert resp.status_code == 200
    body = resp.json()
    assert any(m["id"] == "spend_over_time" for m in body["metrics"])
    assert "timeseries" in body["widget_min_sizes"]
    assert "last_3_months" in body["time_range_presets"]
    # Forecast doesn't honour the dashboard's time range — surfaced so the
    # frontend can label that widget as such.
    forecast = next(m for m in body["metrics"] if m["id"] == "spend_forecast")
    assert forecast["uses_time_range"] is False
    # No metric exposes start/end fields in its params schema.
    for m in body["metrics"]:
        names = {p["name"] for p in m["params_schema"]}
        assert "start" not in names and "end" not in names


def test_period_comparison_uses_dashboard_range(client: TestClient) -> None:
    did = client.post("/dashboards", json={"name": "compare"}).json()["id"]
    client.patch(f"/dashboards/{did}", json={
        "time_range": {
            "preset": "custom",
            "custom_start": "2026-03-01", "custom_end": "2026-04-30",
        },
    })
    resp = client.post(f"/dashboards/{did}/widgets", json={
        "type": "query_value",
        "layout": {"x": 0, "y": 0, "w": 2, "h": 2},
        "data_source": {"kind": "metric", "metric_id": "period_comparison",
                        "params": {"baseline_kind": "previous_period"}},
        "config": {},
    })
    wid = resp.json()["id"]
    body = client.get(f"/dashboards/{did}/widgets/{wid}/data").json()
    assert body["type"] == "query_value"
    assert body["data"]["value"] > 0
    assert "comparison" in body["data"]


def test_save_chat_widget_via_rest(client: TestClient) -> None:
    """End-to-end through the REST surface: a chat message with a
    metric-backed widget gets saved as a kind:"metric" dashboard widget
    and its data follows the dashboard time range."""
    from budget_trace_backend.services import chat_sessions

    # Make a chat session + assistant message carrying a metric-backed widget.
    sess = chat_sessions.create_session()
    assistant = chat_sessions.append_message(
        sess["id"], "assistant", "Total spend over the last 3 months.",
        widget={
            "type": "query_value",
            "title": "Total spend",
            "data": {"value": 0.0, "format": "currency"},
            "metric_id": "total_spend",
            "metric_params": {},
        },
    )

    # Save it to a dashboard via the new endpoint.
    did = client.post("/dashboards", json={"name": "saved"}).json()["id"]
    client.patch(f"/dashboards/{did}", json={
        "time_range": {
            "preset": "custom",
            "custom_start": SEED_START, "custom_end": SEED_END,
        },
    })
    resp = client.post(
        f"/chat/messages/{assistant['id']}/save-to-dashboard",
        json={"dashboard_id": did},
    )
    assert resp.status_code == 201, resp.text
    wid = resp.json()["id"]
    assert resp.json()["data_source"] == {
        "kind": "metric", "metric_id": "total_spend", "params": {},
    }

    # Data endpoint returns live aggregation, not a snapshot.
    data = client.get(f"/dashboards/{did}/widgets/{wid}/data").json()
    assert data["is_snapshot"] is False
    assert data["data"]["value"] > 0


def test_save_chat_widget_snapshot_fallback_audits(client: TestClient) -> None:
    """Saving a widget that has no metric_id stores a snapshot widget and
    surfaces an audit row on `/ai-widget-audit`."""
    from budget_trace_backend.routes import chat_sessions as chat_route
    from budget_trace_backend.services import (
        ai_widget_audit, chat_sessions,
    )

    sess = chat_sessions.create_session()
    user_msg = chat_sessions.append_message(
        sess["id"], "user", "What's my custom multi-bucket comparison?",
    )
    assistant = chat_sessions.append_message(
        sess["id"], "assistant", "Here is the breakdown.",
        widget=SAMPLE_PIE_WIDGET | {
            "fallback_reason": "no metric covers this exact bucketing",
        },
    )
    # The chat route writes audits; for this test we exercise the
    # service directly with the user_msg as the question.
    ai_widget_audit.record_snapshot_fallback(
        message_id=assistant["id"],
        widget_type=SAMPLE_PIE_WIDGET["type"],
        fallback_reason="no metric covers this exact bucketing",
        user_question=user_msg["text"],
    )
    # Silence the unused-import warning — chat_route is imported so the
    # FastAPI app has the route mounted before we hit it.
    _ = chat_route

    did = client.post("/dashboards", json={"name": "snap"}).json()["id"]
    resp = client.post(
        f"/chat/messages/{assistant['id']}/save-to-dashboard",
        json={"dashboard_id": did},
    )
    assert resp.status_code == 201, resp.text
    wid = resp.json()["id"]
    assert resp.json()["data_source"] == {"kind": "snapshot"}
    data = client.get(f"/dashboards/{did}/widgets/{wid}/data").json()
    assert data["is_snapshot"] is True
    assert data["data"] == SAMPLE_PIE_WIDGET["data"]

    audit = client.get("/ai-widget-audit").json()["rows"]
    assert any(r["message_id"] == assistant["id"] for r in audit)


def test_widgets_flag_off_returns_403(client: TestClient) -> None:
    # Turn the flag off via PATCH /me.
    resp = client.patch("/me", json={"features": {"widgets": False}})
    assert resp.status_code == 200
    assert resp.json()["features"]["widgets"] is False

    resp = client.get("/dashboards")
    assert resp.status_code == 403
    assert resp.json()["detail"]["code"] == "feature_disabled"


def test_dashboard_not_found_returns_404(client: TestClient) -> None:
    resp = client.get("/dashboards/9999")
    assert resp.status_code == 404


def test_widget_validation_errors_surface(client: TestClient) -> None:
    did = client.post("/dashboards", json={"name": "X"}).json()["id"]
    resp = client.post(f"/dashboards/{did}/widgets", json={
        "type": "timeseries",
        "layout": {"x": 0, "y": 0, "w": 1, "h": 1},
        "data_source": {"kind": "metric", "metric_id": "spend_over_time"},
        "config": {},
    })
    assert resp.status_code == 400
    assert resp.json()["detail"]["code"] == "validation_error"
