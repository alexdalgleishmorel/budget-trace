"""Wire-format models. These are the shapes that cross HTTP boundaries.

`ChartSpec` is mirrored on the Flutter side in `lib/models/chart_spec.dart`.
Field names are snake_case (pydantic default) — the Dart side maps to camelCase.
"""

from __future__ import annotations

from typing import Literal

from pydantic import BaseModel, Field


class ChartPoint(BaseModel):
    x: float
    y: float


class ChartSeriesSpec(BaseModel):
    label: str
    style: Literal["solid", "dashed"] = "solid"
    points: list[ChartPoint]


class ChartSpec(BaseModel):
    title: str
    y_axis_label: str | None = None
    x_axis_label: str | None = None
    x_tick_labels: list[str] | None = Field(
        default=None,
        description=(
            "Optional human-readable tick labels along the x-axis, evenly spaced "
            "between min and max x. Use when x represents time periods that "
            "deserve labels (e.g. ['Feb 26', 'Mar 26', 'Apr 26'])."
        ),
    )
    series: list[ChartSeriesSpec]


class WidgetSpec(BaseModel):
    """Generic, polymorphic widget payload — used by the Insights AI to
    return any widget type and emitted alongside each assistant message.

    `data` is the rendered snapshot the chat shows. When the AI was able
    to express the answer as a curated metric, `metric_id` /
    `metric_params` capture the re-runnable query: saving the widget to
    a dashboard later uses these to create a `kind:"metric"` widget that
    follows the dashboard's time range. When the answer is a novel
    pattern that no registry metric covers, both stay null and the saved
    widget becomes a `kind:"snapshot"` (frozen bytes) instead.
    """

    type: Literal["timeseries", "bar", "pie", "query_value", "table", "treemap"]
    # Titles are no longer surfaced in the UI; kept optional for older
    # stored payloads and for snapshot-fallback metadata.
    title: str = ""
    data: dict
    metric_id: str | None = None
    metric_params: dict | None = None
    # Only populated when the AI fell back to a snapshot — surfaced via
    # the ai_widget_audit table so the registry can grow.
    fallback_reason: str | None = None


def widget_from_chart(chart: dict | ChartSpec | None) -> WidgetSpec | None:
    """Wrap a legacy ChartSpec as a timeseries WidgetSpec.

    Used both at read-time (legacy stored chart_json gets surfaced as a
    widget) and when the AI returns the old `chart` argument for
    backward compatibility.
    """
    if chart is None:
        return None
    spec = chart if isinstance(chart, ChartSpec) else ChartSpec(**chart)
    return WidgetSpec(
        type="timeseries", title=spec.title,
        data={"chart": spec.model_dump()},
    )


class ChatTurn(BaseModel):
    role: Literal["user", "assistant"]
    content: str


class ChatRequest(BaseModel):
    messages: list[ChatTurn]
    chat_session_id: int | None = None


class ChatResponse(BaseModel):
    text: str
    widget: WidgetSpec | None = None
    cost_usd: float = 0.0
    session_spent_usd: float = 0.0


class ChatSessionOut(BaseModel):
    id: int
    title: str
    created_at: str
    updated_at: str
    message_count: int = 0
    spent_usd: float = 0.0


class ChatMessageOut(BaseModel):
    id: int
    sequence: int
    role: Literal["user", "assistant"]
    text: str
    widget: WidgetSpec | None = None
    errored: bool = False
    created_at: str


class AppendMessageRequest(BaseModel):
    text: str


class AppendMessageResponse(BaseModel):
    user_message: ChatMessageOut
    assistant_message: ChatMessageOut
    cost_usd: float = 0.0
    session_spent_usd: float = 0.0
