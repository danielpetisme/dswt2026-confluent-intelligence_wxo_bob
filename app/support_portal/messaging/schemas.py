"""Kafka wire-format models — source of truth for the JSON Schemas registered
in Confluent Cloud Schema Registry for tickets.raw / tickets.enriched /
tickets.metrics / tickets.agent-actions. TicketRaw is produced by this app
(tickets/, generator/) via messaging/producer.py; the other three are
produced by the external Flink pipeline and consumed back here only as
raw dicts (messaging/consumer.py), so they're never instantiated in-app --
they exist purely to document that pipeline's wire contract."""

from datetime import datetime, timezone
from typing import Literal, Optional

from pydantic import BaseModel, Field


def _utcnow() -> datetime:
    return datetime.now(timezone.utc)


class TicketRaw(BaseModel):
    ticket_id: str
    user_id: int
    text: str
    urgency_self_rated: Literal["low", "medium", "high"]
    submitted_at: datetime = Field(default_factory=_utcnow)
    source: Literal["live", "synthetic"] = "live"
    # Self-declared, same as urgency_self_rated -- the enrichment pipeline
    # doesn't classify service from ticket text (see 02_statements_ticket_enrichment.tf),
    # so synthetic producers stamp the service they already know here.
    service: Optional[str] = None
    # Display-only subject line for the ticket-lifecycle UI; not used by the
    # enrichment/triage pipeline, which only reads `text`. Optional so this
    # is a backward-compatible addition to the registered JSON Schema.
    subject: Optional[str] = None


class EnrichedTicket(BaseModel):
    ticket_id: str
    user_id: int
    service: Optional[str] = None
    text: str
    urgency_self_rated: str
    sentiment: Optional[str] = None
    urgency_score: Optional[float] = None
    enriched_at: datetime = Field(default_factory=_utcnow)


class MetricsPoint(BaseModel):
    window_start: datetime
    window_end: datetime
    count: int
    forecast_next: Optional[float] = None


class AgentAction(BaseModel):
    ticket_id: str
    action: Literal["auto_resolve", "escalate"]
    issue_id: Optional[str] = None
    confidence: Optional[float] = None
    message: str
    created_at: datetime = Field(default_factory=_utcnow)
