"""FastAPI app — the only HTTP surface.

Insights chat lives under /chat/sessions (history-backed). CORS is wide-open;
this is a local single-user app with no auth.

On startup we run `bootstrap_db()` so a brand-new `data/budget_trace.db`
(or no DB file at all) gets the schema, the symbolic Budget root, and the
single user row before the first request lands. This is the entire first-run
setup — no separate seed step.

In the Docker image the built Flutter web bundle is served from this same app
(see the static mount at the bottom): API routers are registered first, then a
catch-all static mount serves the SPA so the whole product runs on one port.
Set `BUDGET_TRACE_WEB_DIR` to the directory holding `index.html`; when it's
unset or missing (plain backend dev), the mount is skipped.
"""

from __future__ import annotations

import logging
import os
from contextlib import asynccontextmanager
from pathlib import Path

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles

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


def _mount_web() -> None:
    """Serve the built Flutter web bundle from the same origin as the API.

    Registered last so every API route above wins; `html=True` makes the mount
    serve `index.html` for `/` (and 404 → index for the SPA). Skipped silently
    when the directory isn't present so backend-only dev keeps working.
    """
    web_dir = os.environ.get("BUDGET_TRACE_WEB_DIR")
    if not web_dir:
        return
    path = Path(web_dir)
    if not (path / "index.html").is_file():
        logging.warning("BUDGET_TRACE_WEB_DIR=%s has no index.html; not serving web", web_dir)
        return
    app.mount("/", StaticFiles(directory=str(path), html=True), name="web")


_mount_web()
