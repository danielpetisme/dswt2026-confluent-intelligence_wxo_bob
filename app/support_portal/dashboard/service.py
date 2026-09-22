"""Live dashboard pub/sub + metrics aggregation. handle_message is invoked
from the Kafka consumer's background thread via loop.call_soon_threadsafe,
so it always runs on the event loop and can safely schedule the async
broadcast."""

import asyncio

from fastapi import WebSocket

_connections: set[WebSocket] = set()
_recent_actions: list[dict] = []
_recent_metrics: list[dict] = []
_urgency_counts: dict[str, int] = {"low": 0, "medium": 0, "high": 0}
_last_status: dict | None = None
# Running totals for the dashboard KPI cards -- the Kafka topics themselves
# carry no cumulative counts, so this is the only place that survives a
# dashboard page reload without replaying the full topic history.
_counters: dict[str, int] = {"total_tickets": 0, "auto_resolved": 0, "escalated": 0}


def snapshot() -> dict:
    return {
        "urgency_counts": dict(_urgency_counts),
        "recent_metrics": _recent_metrics[-30:],
        "recent_actions": _recent_actions[-20:],
        "status": _last_status,
        "counters": dict(_counters),
    }


def register_connection(ws: WebSocket) -> None:
    _connections.add(ws)


def unregister_connection(ws: WebSocket) -> None:
    _connections.discard(ws)


async def _broadcast(event: dict) -> None:
    dead = []
    for ws in _connections:
        try:
            await ws.send_json(event)
        except Exception:
            dead.append(ws)
    for ws in dead:
        _connections.discard(ws)


def handle_message(topic: str, value: dict) -> None:
    if topic == "tickets.enriched":
        urgency = value.get("urgency_self_rated", "low")
        _urgency_counts[urgency] = _urgency_counts.get(urgency, 0) + 1
        _counters["total_tickets"] += 1
        event = {"type": "enriched", "data": value}
    elif topic == "tickets.metrics":
        _recent_metrics.append(value)
        event = {"type": "metrics", "data": value}
    elif topic == "tickets.agent-actions":
        _recent_actions.append(value)
        if value.get("action") == "auto_resolve":
            _counters["auto_resolved"] += 1
        elif value.get("action") == "escalate":
            _counters["escalated"] += 1
        event = {"type": "agent_action", "data": value}
    else:
        return
    asyncio.create_task(_broadcast(event))


def push_status(status: dict) -> None:
    global _last_status
    _last_status = status
    asyncio.create_task(_broadcast({"type": "status", "data": status}))
