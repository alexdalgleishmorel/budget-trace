"""FastAPI app — the only HTTP surface.

Insights chat lives under /chat/sessions (history-backed). CORS is wide-open
since this is a local-dev-only build.

On startup we run `bootstrap_db()` so a brand-new `data/budget_trace.db`
(or no DB file at all) gets the schema, the symbolic Budget root, and the
single-user row before the first request lands. This is the entire
first-run setup — no separate seed step.
"""

from __future__ import annotations

import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from .db import bootstrap_db
from .routes import categories as categories_routes
from .routes import chat_sessions as chat_sessions_routes
from .routes import dashboards as dashboards_routes
from .routes import imports as imports_routes
from .routes import me as me_routes
from .routes import transactions as transactions_routes

logging.basicConfig(level=logging.INFO)


@asynccontextmanager
async def lifespan(app: FastAPI):
    bootstrap_db()
    yield


app = FastAPI(title="Budget Trace backend", version="0.1.0", lifespan=lifespan)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)


app.include_router(categories_routes.router)
app.include_router(transactions_routes.router)
app.include_router(imports_routes.router)
app.include_router(me_routes.router)
app.include_router(chat_sessions_routes.router)
app.include_router(dashboards_routes.router)


@app.get("/healthz")
def healthz() -> dict:
    return {"ok": True}
