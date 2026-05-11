"""REST routes for dashboards and widgets.

Gated behind the `widgets` feature flag (defaults on). Single-user dev today
— `DEFAULT_USER_ID` is hardcoded; when auth lands the routes will read
`user_id` from the request session and the service-layer signatures stay
the same.

The save-chat-to-dashboard route lives here too because the saved payload
is always a widget on a dashboard — there is no separate "saved insight"
inbox any more.
"""

from __future__ import annotations

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel, ConfigDict, Field

from .. import features
from ..features import DEFAULT_USER_ID
from ..services import ai_widget_audit, dashboards as svc
from ..services import chat_sessions as chat_svc
from ..services import widget_metrics
from ..services.categories import ServiceError

router = APIRouter(tags=["widgets"])


# ── Wire-format models ───────────────────────────────────────────────────────


class WidgetLayout(BaseModel):
    x: int
    y: int
    w: int
    h: int


class WidgetOut(BaseModel):
    id: int
    dashboard_id: int
    type: str
    title: str
    layout: WidgetLayout
    data_source: dict
    config: dict
    created_at: str
    updated_at: str


class DashboardTimeRange(BaseModel):
    model_config = ConfigDict(extra="forbid")
    preset: str
    custom_start: str | None = None
    custom_end: str | None = None


class DashboardSummary(BaseModel):
    id: int
    name: str
    time_range: DashboardTimeRange
    created_at: str
    updated_at: str


class DashboardOut(DashboardSummary):
    widgets: list[WidgetOut]


class DashboardCreate(BaseModel):
    model_config = ConfigDict(extra="forbid")
    name: str


class DashboardPatch(BaseModel):
    model_config = ConfigDict(extra="forbid")
    name: str | None = None
    time_range: DashboardTimeRange | None = None


class WidgetCreate(BaseModel):
    model_config = ConfigDict(extra="forbid")
    type: str
    # Optional — when omitted, the server places the widget at the next
    # free row below the existing grid contents using the type's min size.
    layout: WidgetLayout | None = None
    data_source: dict
    config: dict = Field(default_factory=dict)


class WidgetUpdate(BaseModel):
    model_config = ConfigDict(extra="forbid")
    title: str | None = None
    layout: WidgetLayout | None = None
    data_source: dict | None = None
    config: dict | None = None


class LayoutEntry(BaseModel):
    id: int
    x: int
    y: int
    w: int
    h: int


class LayoutUpdate(BaseModel):
    model_config = ConfigDict(extra="forbid")
    layouts: list[LayoutEntry]


class LayoutUpdateResult(BaseModel):
    updated: int


class WidgetDataOut(BaseModel):
    type: str
    data: dict
    is_snapshot: bool = False
    via_chat: bool = False


class SaveChatWidgetRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")
    dashboard_id: int


class AiWidgetAuditRow(BaseModel):
    id: int
    message_id: int | None = None
    widget_type: str
    fallback_reason: str | None = None
    user_question: str | None = None
    created_at: str


class AiWidgetAuditList(BaseModel):
    rows: list[AiWidgetAuditRow]


class WidgetMetricDefOut(BaseModel):
    id: str
    label: str
    description: str
    widget_types: list[str]
    params_schema: list[dict]
    uses_time_range: bool = True


class WidgetMetricList(BaseModel):
    metrics: list[WidgetMetricDefOut]
    widget_min_sizes: dict[str, list[int]]
    time_range_presets: list[str]


class Deleted(BaseModel):
    deleted_id: int


# ── Helpers ──────────────────────────────────────────────────────────────────


def _err(e: ServiceError) -> HTTPException:
    return HTTPException(
        status_code=e.http_status,
        detail={"code": e.code, "message": str(e)},
    )


def _require_widgets_flag() -> None:
    if not features.get_flags().get("widgets", False):
        raise HTTPException(
            status_code=403,
            detail={"code": "feature_disabled",
                    "message": "Widgets are not enabled for this user."},
        )


def _widget_to_out(w: dict) -> WidgetOut:
    return WidgetOut(
        id=w["id"],
        dashboard_id=w["dashboard_id"],
        type=w["type"],
        title=w["title"],
        layout=WidgetLayout(**w["layout"]),
        data_source=w["data_source"],
        config=w["config"],
        created_at=w["created_at"],
        updated_at=w["updated_at"],
    )


def _time_range_to_out(tr: dict) -> DashboardTimeRange:
    return DashboardTimeRange(
        preset=tr.get("preset", "last_3_months"),
        custom_start=tr.get("custom_start"),
        custom_end=tr.get("custom_end"),
    )


def _dashboard_to_summary(d: dict) -> DashboardSummary:
    return DashboardSummary(
        id=d["id"],
        name=d["name"],
        time_range=_time_range_to_out(d.get("time_range") or {}),
        created_at=d["created_at"],
        updated_at=d["updated_at"],
    )


def _dashboard_to_out(d: dict) -> DashboardOut:
    return DashboardOut(
        id=d["id"],
        name=d["name"],
        time_range=_time_range_to_out(d.get("time_range") or {}),
        created_at=d["created_at"],
        updated_at=d["updated_at"],
        widgets=[_widget_to_out(w) for w in d.get("widgets", [])],
    )


# ── Dashboards ───────────────────────────────────────────────────────────────


@router.get("/dashboards", response_model=list[DashboardSummary])
def list_all() -> list[DashboardSummary]:
    _require_widgets_flag()
    return [_dashboard_to_summary(d) for d in svc.list_dashboards(DEFAULT_USER_ID)]


@router.post("/dashboards", response_model=DashboardSummary, status_code=201)
def create(payload: DashboardCreate) -> DashboardSummary:
    _require_widgets_flag()
    try:
        return _dashboard_to_summary(
            svc.create_dashboard(DEFAULT_USER_ID, payload.name),
        )
    except ServiceError as e:
        raise _err(e)


@router.get("/dashboards/{dashboard_id}", response_model=DashboardOut)
def get_one(dashboard_id: int) -> DashboardOut:
    _require_widgets_flag()
    try:
        return _dashboard_to_out(svc.get_dashboard(DEFAULT_USER_ID, dashboard_id))
    except ServiceError as e:
        raise _err(e)


@router.patch("/dashboards/{dashboard_id}", response_model=DashboardSummary)
def patch(dashboard_id: int, payload: DashboardPatch) -> DashboardSummary:
    _require_widgets_flag()
    if payload.name is None and payload.time_range is None:
        raise HTTPException(
            status_code=422,
            detail={"code": "validation_error",
                    "message": "provide name and/or time_range"},
        )
    try:
        return _dashboard_to_summary(svc.update_dashboard(
            DEFAULT_USER_ID, dashboard_id,
            name=payload.name,
            time_range=payload.time_range.model_dump()
                if payload.time_range else None,
        ))
    except ServiceError as e:
        raise _err(e)


@router.delete("/dashboards/{dashboard_id}", response_model=Deleted)
def delete(dashboard_id: int) -> Deleted:
    _require_widgets_flag()
    try:
        return Deleted(**svc.delete_dashboard(DEFAULT_USER_ID, dashboard_id))
    except ServiceError as e:
        raise _err(e)


# ── Widgets ──────────────────────────────────────────────────────────────────


@router.post(
    "/dashboards/{dashboard_id}/widgets",
    response_model=WidgetOut, status_code=201,
)
def create_widget(dashboard_id: int, payload: WidgetCreate) -> WidgetOut:
    _require_widgets_flag()
    try:
        return _widget_to_out(svc.create_widget(
            DEFAULT_USER_ID, dashboard_id, payload.model_dump(),
        ))
    except ServiceError as e:
        raise _err(e)


@router.patch(
    "/dashboards/{dashboard_id}/widgets/{widget_id}",
    response_model=WidgetOut,
)
def patch_widget(
    dashboard_id: int, widget_id: int, payload: WidgetUpdate,
) -> WidgetOut:
    _require_widgets_flag()
    try:
        return _widget_to_out(svc.update_widget(
            DEFAULT_USER_ID, dashboard_id, widget_id,
            payload.model_dump(exclude_unset=True),
        ))
    except ServiceError as e:
        raise _err(e)


@router.delete(
    "/dashboards/{dashboard_id}/widgets/{widget_id}",
    response_model=Deleted,
)
def delete_widget(dashboard_id: int, widget_id: int) -> Deleted:
    _require_widgets_flag()
    try:
        return Deleted(**svc.delete_widget(DEFAULT_USER_ID, dashboard_id, widget_id))
    except ServiceError as e:
        raise _err(e)


@router.put(
    "/dashboards/{dashboard_id}/layout",
    response_model=LayoutUpdateResult,
)
def put_layout(dashboard_id: int, payload: LayoutUpdate) -> LayoutUpdateResult:
    _require_widgets_flag()
    try:
        result = svc.bulk_update_layout(
            DEFAULT_USER_ID, dashboard_id,
            [e.model_dump() for e in payload.layouts],
        )
        return LayoutUpdateResult(**result)
    except ServiceError as e:
        raise _err(e)


@router.get(
    "/dashboards/{dashboard_id}/widgets/{widget_id}/data",
    response_model=WidgetDataOut,
)
def get_widget_data(dashboard_id: int, widget_id: int) -> WidgetDataOut:
    _require_widgets_flag()
    try:
        return WidgetDataOut(**svc.get_widget_data(
            DEFAULT_USER_ID, dashboard_id, widget_id,
        ))
    except ServiceError as e:
        raise _err(e)


# ── Save chat widget to a dashboard ──────────────────────────────────────────


@router.post(
    "/chat/messages/{message_id}/save-to-dashboard",
    response_model=WidgetOut, status_code=201,
)
def save_chat_widget(
    message_id: int, payload: SaveChatWidgetRequest,
) -> WidgetOut:
    """Create a dashboard widget from an AI assistant message.

    When the message's widget carries `metric_id` + `metric_params`, the
    new dashboard widget is `kind:"metric"` and follows the dashboard's
    time range on every render. Otherwise it's `kind:"snapshot"` —
    frozen bytes that ignore the dashboard's time range.
    """
    _require_widgets_flag()
    msg = chat_svc.get_message(message_id)
    if msg is None:
        raise HTTPException(status_code=404, detail="chat message not found")
    if msg.get("role") != "assistant":
        raise HTTPException(
            status_code=400,
            detail={"code": "validation_error",
                    "message": "only assistant messages can be saved"},
        )
    chat_widget = msg.get("widget")
    if not chat_widget:
        raise HTTPException(
            status_code=400,
            detail={"code": "validation_error",
                    "message": "message has no widget to save"},
        )
    try:
        out = svc.save_chat_widget_to_dashboard(
            DEFAULT_USER_ID,
            dashboard_id=payload.dashboard_id,
            chat_widget=chat_widget,
        )
    except ServiceError as e:
        raise _err(e)
    return _widget_to_out(out)


# ── AI widget audit ──────────────────────────────────────────────────────────


@router.get("/ai-widget-audit", response_model=AiWidgetAuditList)
def list_ai_widget_audit() -> AiWidgetAuditList:
    """Snapshot-fallback log — the AI's record of answers it couldn't
    express via a curated metric. Used to grow the metric registry."""
    _require_widgets_flag()
    return AiWidgetAuditList(
        rows=[AiWidgetAuditRow(**r) for r in ai_widget_audit.list_audit_rows()],
    )


# ── Widget-metric registry ───────────────────────────────────────────────────


@router.get("/widget-metrics", response_model=WidgetMetricList)
def list_metrics() -> WidgetMetricList:
    _require_widgets_flag()
    return WidgetMetricList(
        metrics=[
            WidgetMetricDefOut(**m)
            for m in widget_metrics.list_metric_defs()
        ],
        widget_min_sizes={
            k: [v[0], v[1]] for k, v in widget_metrics.WIDGET_MIN_SIZE.items()
        },
        time_range_presets=list(widget_metrics.TIME_RANGE_PRESETS),
    )
