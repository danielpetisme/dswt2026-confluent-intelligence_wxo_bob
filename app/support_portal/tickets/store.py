"""In-memory, thread-safe ticket lifecycle store (spec: specs/ticket-lifecycle/spec.md).

Not Kafka-backed and not persisted -- tickets live only for the process
lifetime, same trade-off as AccountPool/PortalState. The *decision*
(auto-reply vs. escalate) still comes from the real Confluent Cloud Flink
pipeline via tickets.agent-actions; this store just tracks per-ticket
status/timeline for the attendee UI and correlates incoming agent actions
back to a ticket_id.
"""

import threading
import uuid
from dataclasses import dataclass, field
from datetime import datetime
from typing import Optional

from support_portal.tickets.models import TicketDetail, TicketEvent, TicketStatus, TicketSummary, _utcnow


def _new_event_id() -> str:
    return f"evt-{uuid.uuid4().hex[:12]}"


@dataclass
class TicketRecord:
    ticket_id: str
    user_id: int
    service: str
    subject: str
    description: Optional[str]
    urgency: str
    status: TicketStatus
    created_at: datetime
    updated_at: datetime
    events: list[TicketEvent] = field(default_factory=list)

    def to_summary(self) -> TicketSummary:
        return TicketSummary(
            ticket_id=self.ticket_id,
            service=self.service,
            subject=self.subject,
            status=self.status,
            urgency=self.urgency,
            created_at=self.created_at,
            updated_at=self.updated_at,
        )

    def to_detail(self) -> TicketDetail:
        return TicketDetail(**self.to_summary().model_dump(), description=self.description, events=list(self.events))

    def conversation_context(self) -> str:
        """Full thread as plain text, for re-triage (spec section 24) -- the
        agent should see prior turns, not just the latest reply in isolation."""
        lines = [f"Subject: {self.subject}"]
        if self.description:
            lines.append(f"Original request: {self.description}")
        for evt in self.events:
            if evt.type == "user_reply" and evt.message:
                lines.append(f"User reply: {evt.message}")
            elif evt.type == "automatic_reply" and evt.message:
                lines.append(f"Automatic reply: {evt.message}")
            elif evt.type == "escalated" and evt.message:
                lines.append(f"Escalation note: {evt.message}")
            elif evt.type == "support_reply" and evt.message:
                lines.append(f"Support reply: {evt.message}")
        return "\n".join(lines)


class TicketStore:
    def __init__(self):
        self._lock = threading.Lock()
        self._tickets: dict[str, TicketRecord] = {}
        self._by_user: dict[int, list[str]] = {}

    def create(self, user_id: int, service: str, subject: str, description: Optional[str], urgency: str) -> TicketRecord:
        now = _utcnow()
        ticket_id = str(uuid.uuid4())
        record = TicketRecord(
            ticket_id=ticket_id,
            user_id=user_id,
            service=service,
            subject=subject,
            description=description,
            urgency=urgency,
            status="open",
            created_at=now,
            updated_at=now,
        )
        record.events.append(TicketEvent(event_id=_new_event_id(), ticket_id=ticket_id, type="ticket_created", created_at=now))
        with self._lock:
            self._tickets[ticket_id] = record
            self._by_user.setdefault(user_id, []).insert(0, ticket_id)
        return record

    def get(self, ticket_id: str) -> Optional[TicketRecord]:
        with self._lock:
            return self._tickets.get(ticket_id)

    def list_for_user(self, user_id: int) -> list[TicketRecord]:
        with self._lock:
            ids = list(self._by_user.get(user_id, []))
            records = [self._tickets[i] for i in ids if i in self._tickets]
        return sorted(records, key=lambda t: t.updated_at, reverse=True)

    def _append(self, ticket_id: str, event_type: str, message: Optional[str]) -> Optional[TicketEvent]:
        with self._lock:
            record = self._tickets.get(ticket_id)
            if record is None:
                return None
            if record.status == "closed":
                raise ValueError("Ticket is closed")
            now = _utcnow()
            event = TicketEvent(event_id=_new_event_id(), ticket_id=ticket_id, type=event_type, message=message, created_at=now)
            record.events.append(event)
            record.status = "closed" if event_type == "ticket_closed" else "open"
            record.updated_at = now
            return event

    def add_reply(self, ticket_id: str, message: str) -> tuple[TicketEvent, str]:
        """Appends the user_reply event and returns (event, conversation_context)
        -- the context is what gets re-published to tickets.raw to re-trigger
        triage with full history, not just the latest message."""
        event = self._append(ticket_id, "user_reply", message)
        if event is None:
            raise KeyError(ticket_id)
        record = self.get(ticket_id)
        return event, record.conversation_context()

    def apply_agent_action(self, ticket_id: str, action: str, message: Optional[str]) -> Optional[TicketEvent]:
        """Maps a real tickets.agent-actions message to a local lifecycle
        event. Silently no-ops for unknown ticket_ids (e.g. synthetic
        generator tickets never created through the attendee UI) or an
        already-closed ticket (a stray/duplicate late delivery)."""
        event_type = {"auto_resolve": "automatic_reply", "escalate": "escalated"}.get(action)
        if event_type is None:
            return None
        try:
            return self._append(ticket_id, event_type, message)
        except ValueError:
            return None

    def close(self, ticket_id: str) -> TicketEvent:
        event = self._append(ticket_id, "ticket_closed", None)
        if event is None:
            raise KeyError(ticket_id)
        return event
