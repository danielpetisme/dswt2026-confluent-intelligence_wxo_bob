"""Presenter console backend. Both the incident flip and the burst
trigger are driven from one browser tab (support_portal/static/console.html)
so nothing requires a second terminal on stage."""

import asyncio
import logging
from typing import Literal

from fastapi import APIRouter, Header, HTTPException, Request
from pydantic import BaseModel

from support_portal.config import settings
from support_portal.incidents.known_issues import SERVICES
from support_portal.generator.synthetic import fire_burst
from support_portal.dashboard.service import push_status

logger = logging.getLogger(__name__)
router = APIRouter()

_burst_in_progress = False
_last_burst_error: str | None = None


def _check_token(x_admin_token: str | None) -> None:
    if x_admin_token != settings.admin_token:
        raise HTTPException(status_code=401, detail="Invalid admin token")


class IncidentUpdate(BaseModel):
    service: str
    status: str  # "operational" | "degraded" | "outage"
    description: str = ""


@router.post("/admin/status")
async def update_status(
    update: IncidentUpdate,
    request: Request,
    x_admin_token: str | None = Header(default=None),
):
    _check_token(x_admin_token)
    new_status = request.app.state.portal_state.set_incident(
        update.service, update.status, update.description
    )
    push_status(new_status)
    return new_status


class BurstRequest(BaseModel):
    service: str  # one of SERVICES, or "all"
    count: int = 15
    interval_ms: int = 400


@router.post("/admin/burst")
async def trigger_burst(
    burst: BurstRequest,
    request: Request,
    x_admin_token: str | None = Header(default=None),
):
    _check_token(x_admin_token)
    if _burst_in_progress:
        raise HTTPException(status_code=409, detail="A burst is already in progress")

    producer = request.app.state.producer

    async def _run() -> None:
        global _burst_in_progress, _last_burst_error
        _burst_in_progress = True
        _last_burst_error = None
        try:
            if burst.service == "all":
                # Split the requested count across every service instead of
                # firing `count` tickets per service -- keeps total volume
                # proportional to the requested duration regardless of scope.
                per_service = max(burst.count // len(SERVICES), 1)
                await asyncio.gather(*(
                    fire_burst(producer, service, per_service, burst.interval_ms)
                    for service in SERVICES
                ))
            else:
                await fire_burst(producer, burst.service, burst.count, burst.interval_ms)
        except Exception as exc:
            logger.exception("Burst failed")
            _last_burst_error = str(exc)
        finally:
            _burst_in_progress = False

    asyncio.create_task(_run())
    return {"started": True, "service": burst.service, "count": burst.count}


@router.get("/admin/burst-status")
async def burst_status(x_admin_token: str | None = Header(default=None)):
    _check_token(x_admin_token)
    return {"in_progress": _burst_in_progress, "last_error": _last_burst_error}


class GeneratorUpdate(BaseModel):
    action: Literal["pause", "resume", "rate"]
    rate: float | None = None  # tickets/second, required when action == "rate"


def _generator_state(generator) -> dict:
    if generator is None:
        return {"enabled": False, "running": False, "rate": 0.0}
    return {"enabled": True, "running": generator.running, "rate": generator.rate}


@router.get("/admin/generator")
async def get_generator(request: Request, x_admin_token: str | None = Header(default=None)):
    _check_token(x_admin_token)
    return _generator_state(request.app.state.generator)


@router.post("/admin/generator")
async def update_generator(
    update: GeneratorUpdate,
    request: Request,
    x_admin_token: str | None = Header(default=None),
):
    _check_token(x_admin_token)
    generator = request.app.state.generator
    if generator is None:
        raise HTTPException(status_code=409, detail="Baseline generator is disabled")

    if update.action == "pause":
        generator.pause()
    elif update.action == "resume":
        generator.resume()
    elif update.action == "rate":
        if update.rate is None:
            raise HTTPException(status_code=422, detail="rate is required for action=rate")
        generator.set_rate(update.rate)

    return _generator_state(generator)
