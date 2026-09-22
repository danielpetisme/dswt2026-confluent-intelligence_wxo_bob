"""Ticket lifecycle business logic: the shared ticket store, the per-ticket
WebSocket broadcast, the Kafka agent-action dispatch, and the fallback
escalation that keeps the demo moving if the real Flink pipeline stalls.

Module-level state (`store`, `_connections`, `_fallback_tasks`) mirrors
dashboard/service.py's style: process-global, not persisted, not stashed
on app.state, since nothing outside this module needs it directly.
"""

import asyncio

from fastapi import WebSocket

from support_portal.tickets.models import TicketEvent
from support_portal.tickets.store import TicketStore

FALLBACK_TIMEOUT_SECONDS = 30
FALLBACK_MESSAGE = "Your request needs additional review and has been escalated to support."

store = TicketStore()
_connections: dict[str, set[WebSocket]] = {}
_fallback_tasks: dict[str, asyncio.Task] = {}


def register_connection(ticket_id: str, ws: WebSocket) -> None:
    _connections.setdefault(ticket_id, set()).add(ws)


def unregister_connection(ticket_id: str, ws: WebSocket) -> None:
    conns = _connections.get(ticket_id)
    if conns is not None:
        conns.discard(ws)


# --- Kafka dispatch (registered with the shared DashboardConsumer) ---


def handle_agent_action(topic: str, value: dict) -> None:
    """Correlates a real tickets.agent-actions message back to a ticket.
    Defensive by design: the exact AI_RUN_AGENT output shape is unconfirmed
    (see PROJECT_SPEC.md), so anything unexpected is skipped, never raised."""
    ticket_id = value.get("ticket_id")
    action = value.get("action")
    if not ticket_id or not action:
        return
    message = value.get("message") or "We've reviewed your request."
    event = store.apply_agent_action(ticket_id, action, message)
    if event is None:
        return
    cancel_fallback(ticket_id)
    record = store.get(ticket_id)
    if record is not None:
        asyncio.create_task(_broadcast(ticket_id, event, record.status))


# --- Fallback: keep the demo moving if the real pipeline stalls ---


def cancel_fallback(ticket_id: str) -> None:
    task = _fallback_tasks.pop(ticket_id, None)
    if task and not task.done():
        task.cancel()


def schedule_fallback(ticket_id: str, after_event_id: str) -> None:
    cancel_fallback(ticket_id)

    async def _fallback() -> None:
        try:
            await asyncio.sleep(FALLBACK_TIMEOUT_SECONDS)
        except asyncio.CancelledError:
            return
        record = store.get(ticket_id)
        if record is None or record.status == "closed" or not record.events:
            return
        if record.events[-1].event_id != after_event_id:
            return  # a real agent action (or something else) already landed
        event = store.apply_agent_action(ticket_id, "escalate", FALLBACK_MESSAGE)
        if event is not None:
            await _broadcast(ticket_id, event, record.status)

    _fallback_tasks[ticket_id] = asyncio.create_task(_fallback())


# --- WebSocket broadcast ---


async def _broadcast(ticket_id: str, event: TicketEvent, status: str) -> None:
    conns = _connections.get(ticket_id)
    if not conns:
        return
    payload = {
        "type": "ticket_event",
        "ticket_id": ticket_id,
        "event": event.model_dump(mode="json"),
        "status": status,
    }
    dead = []
    for ws in conns:
        try:
            await ws.send_json(payload)
        except Exception:
            dead.append(ws)
    for ws in dead:
        conns.discard(ws)
