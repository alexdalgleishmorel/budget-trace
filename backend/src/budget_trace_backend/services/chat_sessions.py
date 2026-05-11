"""Persistence for Insights chat history.

Sessions group turns; messages carry role/text and optionally a serialised
ChartSpec for assistant replies that included a chart.
"""

from __future__ import annotations

import json
from datetime import datetime
from typing import Any

from ..db import connect, init_schema

_TITLE_MAX = 60


def _now_iso() -> str:
    return datetime.utcnow().isoformat(timespec="seconds") + "Z"


def _ensure_schema() -> None:
    with connect() as conn:
        init_schema(conn)


def list_sessions() -> list[dict]:
    _ensure_schema()
    with connect() as conn:
        rows = conn.execute(
            """
            SELECT s.id, s.title, s.created_at, s.updated_at,
                   (SELECT COUNT(*) FROM chat_messages m WHERE m.session_id = s.id) AS message_count,
                   (SELECT COALESCE(SUM(u.cost_usd), 0.0) FROM ai_usage u WHERE u.chat_session_id = s.id) AS spent_usd
              FROM chat_sessions s
             ORDER BY s.updated_at DESC, s.id DESC
            """,
        ).fetchall()
        return [
            {
                "id": r["id"],
                "title": r["title"] or "New chat",
                "created_at": r["created_at"],
                "updated_at": r["updated_at"],
                "message_count": r["message_count"],
                "spent_usd": float(r["spent_usd"] or 0.0),
            }
            for r in rows
        ]


def create_session() -> dict:
    _ensure_schema()
    now = _now_iso()
    with connect() as conn:
        cur = conn.execute(
            "INSERT INTO chat_sessions (title, created_at, updated_at) VALUES ('', ?, ?)",
            (now, now),
        )
        sid = cur.lastrowid
        return {
            "id": sid,
            "title": "New chat",
            "created_at": now,
            "updated_at": now,
            "message_count": 0,
        }


def get_session(session_id: int) -> dict | None:
    _ensure_schema()
    with connect() as conn:
        row = conn.execute(
            """
            SELECT s.id, s.title, s.created_at, s.updated_at,
                   (SELECT COALESCE(SUM(u.cost_usd), 0.0) FROM ai_usage u WHERE u.chat_session_id = s.id) AS spent_usd
              FROM chat_sessions s WHERE s.id = ?
            """,
            (session_id,),
        ).fetchone()
        if row is None:
            return None
        return {
            "id": row["id"],
            "title": row["title"] or "New chat",
            "created_at": row["created_at"],
            "updated_at": row["updated_at"],
            "spent_usd": float(row["spent_usd"] or 0.0),
        }


def get_messages(session_id: int) -> list[dict]:
    _ensure_schema()
    with connect() as conn:
        rows = conn.execute(
            """
            SELECT id, sequence, role, text, chart_json, widget_json, errored, created_at
              FROM chat_messages
             WHERE session_id = ?
             ORDER BY sequence ASC
            """,
            (session_id,),
        ).fetchall()
        return [_row_to_message(r) for r in rows]


def get_message(message_id: int) -> dict | None:
    """Fetch one message by id (across sessions). Used by the
    save-chat-widget-to-dashboard route."""
    _ensure_schema()
    with connect() as conn:
        row = conn.execute(
            """
            SELECT id, sequence, role, text, chart_json, widget_json, errored, created_at
              FROM chat_messages
             WHERE id = ?
            """,
            (message_id,),
        ).fetchone()
        if row is None:
            return None
        return _row_to_message(row)


def _row_to_message(r: Any) -> dict:
    # Prefer `widget_json` (new). For pre-widget rows, synthesise a
    # timeseries widget from the legacy `chart_json` so the frontend
    # renders consistently.
    widget = json.loads(r["widget_json"]) if r["widget_json"] else None
    if widget is None and r["chart_json"]:
        chart = json.loads(r["chart_json"])
        widget = {
            "type": "timeseries",
            "title": chart.get("title", ""),
            "data": {"chart": chart},
        }
    return {
        "id": r["id"],
        "sequence": r["sequence"],
        "role": r["role"],
        "text": r["text"],
        "widget": widget,
        "errored": bool(r["errored"]),
        "created_at": r["created_at"],
    }


def append_message(
    session_id: int,
    role: str,
    text: str,
    *,
    widget: dict | None = None,
    errored: bool = False,
) -> dict:
    """Append a turn. Updates the session's `updated_at`. If the session has
    no title yet and this is a user turn, derive a short title from the text."""
    _ensure_schema()
    now = _now_iso()
    with connect() as conn:
        seq_row = conn.execute(
            "SELECT COALESCE(MAX(sequence), -1) + 1 AS next_seq FROM chat_messages WHERE session_id = ?",
            (session_id,),
        ).fetchone()
        seq = seq_row["next_seq"]
        cur = conn.execute(
            """
            INSERT INTO chat_messages
                (session_id, sequence, role, text, widget_json, errored, created_at)
                VALUES (?, ?, ?, ?, ?, ?, ?)
            """,
            (
                session_id,
                seq,
                role,
                text,
                json.dumps(widget) if widget else None,
                1 if errored else 0,
                now,
            ),
        )
        msg_id = cur.lastrowid

        # Update session updated_at; set title from first user message if missing.
        if role == "user":
            current = conn.execute(
                "SELECT title FROM chat_sessions WHERE id = ?", (session_id,),
            ).fetchone()
            if current is not None and not (current["title"] or "").strip():
                title = text.strip().splitlines()[0][:_TITLE_MAX] if text.strip() else ""
                conn.execute(
                    "UPDATE chat_sessions SET title = ?, updated_at = ? WHERE id = ?",
                    (title, now, session_id),
                )
            else:
                conn.execute(
                    "UPDATE chat_sessions SET updated_at = ? WHERE id = ?",
                    (now, session_id),
                )
        else:
            conn.execute(
                "UPDATE chat_sessions SET updated_at = ? WHERE id = ?",
                (now, session_id),
            )

        return {
            "id": msg_id,
            "sequence": seq,
            "role": role,
            "text": text,
            "widget": widget,
            "errored": errored,
            "created_at": now,
        }


def delete_session(session_id: int) -> bool:
    _ensure_schema()
    with connect() as conn:
        cur = conn.execute("DELETE FROM chat_sessions WHERE id = ?", (session_id,))
        # ON DELETE CASCADE wipes messages.
        return cur.rowcount > 0
