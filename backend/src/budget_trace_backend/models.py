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


class ChatTurn(BaseModel):
    role: Literal["user", "assistant"]
    content: str


class ChatRequest(BaseModel):
    messages: list[ChatTurn]


class ChatResponse(BaseModel):
    text: str
    chart: ChartSpec | None = None


class ChatSessionOut(BaseModel):
    id: int
    title: str
    created_at: str
    updated_at: str
    message_count: int = 0


class ChatMessageOut(BaseModel):
    id: int
    sequence: int
    role: Literal["user", "assistant"]
    text: str
    chart: ChartSpec | None = None
    errored: bool = False
    created_at: str


class AppendMessageRequest(BaseModel):
    text: str


class AppendMessageResponse(BaseModel):
    user_message: ChatMessageOut
    assistant_message: ChatMessageOut
