"""FastAPI app — the only HTTP surface.

Insights chat lives under /chat/sessions (history-backed). CORS is wide-open
since this is a local-dev-only build.
"""

from __future__ import annotations

import logging

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from .routes import categories as categories_routes
from .routes import chat_sessions as chat_sessions_routes
from .routes import imports as imports_routes
from .routes import me as me_routes
from .routes import transactions as transactions_routes

logging.basicConfig(level=logging.INFO)

app = FastAPI(title="Budget Trace backend", version="0.1.0")

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


@app.get("/healthz")
def healthz() -> dict:
    return {"ok": True}
