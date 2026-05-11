"""Audit log for AI assistant messages that emitted a snapshot-only widget.

Snapshots are the fallback path — used when no curated metric in the
registry could express the answer. Recording each occurrence with the
AI's stated `fallback_reason` and the user's question lets us spot
recurring gaps and grow the registry.
"""

from __future__ import annotations

from datetime import datetime, timezone

from ..db import connect


def record_snapshot_fallback(
    *,
    message_id: int,
    widget_type: str,
    fallback_reason: str | None,
    user_question: str | None,
) -> None:
    now = datetime.now(timezone.utc).isoformat(timespec="microseconds")
    with connect() as conn:
        conn.execute(
            "INSERT INTO ai_widget_audit "
            "(message_id, widget_type, fallback_reason, user_question, created_at) "
            "VALUES (?, ?, ?, ?, ?)",
            (message_id, widget_type, fallback_reason, user_question, now),
        )


def list_audit_rows(limit: int = 200) -> list[dict]:
    with connect() as conn:
        rows = conn.execute(
            "SELECT id, message_id, widget_type, fallback_reason, user_question, created_at "
            "FROM ai_widget_audit ORDER BY created_at DESC LIMIT ?",
            (max(1, min(limit, 1000)),),
        ).fetchall()
    return [
        {
            "id": r["id"],
            "message_id": r["message_id"],
            "widget_type": r["widget_type"],
            "fallback_reason": r["fallback_reason"],
            "user_question": r["user_question"],
            "created_at": r["created_at"],
        }
        for r in rows
    ]
