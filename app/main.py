"""FastAPI entrypoint.

Routes are deliberately thin: read input, call ``app.logic``, render a
template. No integration code, no data shaping, no hand-written HTML.
"""

from __future__ import annotations

import logging
import os
from contextlib import asynccontextmanager
from pathlib import Path

from appkit import auth, doctor
from fastapi import FastAPI, Form, Request
from fastapi.responses import HTMLResponse, JSONResponse
from fastapi.staticfiles import StaticFiles
from fastapi.templating import Jinja2Templates

from . import logic

BASE_DIR = Path(__file__).parent

log = logging.getLogger(__name__)


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Say out loud what this process is configured to do, then serve.

    The failures this stack has are quiet ones: on the fake backend mail is
    discarded and database writes vanish on restart, while every call still
    returns success. `doctor.log_startup()` contacts nothing and reports what
    is configured and — the useful half — what is not, so the first lines of
    the log answer "what is this process actually going to do?".

    For the questions that need a round trip ("does this identity *really*
    have Mail.Send?"), run the full check: `python -m appkit.doctor`.
    """
    # uvicorn configures its own loggers and leaves the root one alone, so
    # without this the report below goes nowhere. basicConfig only installs a
    # handler when the root has none, so a deployment that configures logging
    # keeps its own setup.
    logging.basicConfig(
        level=os.getenv("APP_LOG_LEVEL", "INFO").upper(),
        format="%(asctime)s %(levelname)-8s %(name)s | %(message)s",
    )
    doctor.log_startup(log)
    yield


app = FastAPI(title="UZH Requests", lifespan=lifespan)
app.mount("/static", StaticFiles(directory=BASE_DIR / "static"), name="static")
templates = Jinja2Templates(directory=BASE_DIR / "templates")

APP_NAME = "Requests"
NAV_ITEMS = [{"href": "/", "label": "Requests"}]


def context(request: Request, **extra) -> dict:
    """Common template context: signed-in user and page chrome."""
    return {
        "user": auth.user(request),
        "app_name": APP_NAME,
        "nav_items": NAV_ITEMS,
        "current_path": request.url.path,
        **extra,
    }


@app.get("/", response_class=HTMLResponse)
def index(request: Request) -> HTMLResponse:
    rows = logic.list_requests()
    return templates.TemplateResponse(
        request,
        "index.html",
        context(
            request,
            title="Requests",
            columns=logic.COLUMNS,
            rows=rows,
            summary=logic.summarize(rows),
            list_name=logic.REQUESTS_LIST,
        ),
    )


@app.post("/mail-summary", response_class=HTMLResponse)
def mail_summary(request: Request, recipient: str = Form(...)) -> HTMLResponse:
    try:
        summary = logic.send_summary(recipient)
    except ValueError as exc:
        return templates.TemplateResponse(
            request,
            "_summary.html",
            context(request, error=str(exc), recipient=recipient),
            status_code=400,
        )
    return templates.TemplateResponse(
        request,
        "_summary.html",
        context(request, summary=summary, recipient=recipient),
    )


@app.get("/health")
def health() -> JSONResponse:
    return JSONResponse({"status": "ok"})
