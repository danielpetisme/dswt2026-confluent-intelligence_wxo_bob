"""Background consumer feeding feature-owned handlers (dashboard, tickets).
Runs its own thread (confluent-kafka's Consumer.poll is blocking) and hands
decoded messages back to the asyncio event loop via loop.call_soon_threadsafe,
dispatching each message to the handlers registered for its topic instead of
calling every handler unconditionally."""

import asyncio
import threading
from collections import defaultdict
from typing import Callable

from confluent_kafka import Consumer
from confluent_kafka.schema_registry.json_schema import JSONDeserializer
from confluent_kafka.serialization import MessageField, SerializationContext

from support_portal.config import settings
from support_portal.messaging.client import client_config, schema_registry_client

OnMessage = Callable[[str, dict], None]


class DashboardConsumer:
    """No-ops when CC_BOOTSTRAP_SERVERS isn't set, so the app can boot and
    serve the REST/MCP surface locally without a real Confluent Cloud
    cluster -- the dashboard just won't receive live updates until real
    credentials are configured."""

    def __init__(self, loop: asyncio.AbstractEventLoop, handlers: dict[str, list[OnMessage]]):
        self._loop = loop
        self._handlers: dict[str, list[OnMessage]] = defaultdict(list, handlers)
        self._running = False
        self._thread: threading.Thread | None = None
        self._enabled = bool(settings.cc_bootstrap_servers)
        if not self._enabled:
            self._consumer = None
            self._deserializer = None
            return

        self._consumer = Consumer(client_config({
            "group.id": "support-portal-dashboard",
            "auto.offset.reset": "latest",
        }))
        sr_client = schema_registry_client()
        # schema_str=None with a schema_registry_client fetches the writer
        # schema by id embedded in the message; verify this matches the
        # installed confluent-kafka version's JSONDeserializer signature.
        self._deserializer = JSONDeserializer(
            schema_str=None,
            from_dict=lambda obj, ctx: obj,
            schema_registry_client=sr_client,
        )

    def start(self, topics: list[str]) -> None:
        if not self._enabled:
            return
        self._consumer.subscribe(topics)
        self._running = True
        self._thread = threading.Thread(target=self._run, daemon=True)
        self._thread.start()

    def stop(self) -> None:
        if not self._enabled:
            return
        self._running = False
        if self._thread:
            self._thread.join(timeout=2)
        self._consumer.close()

    def _run(self) -> None:
        while self._running:
            msg = self._consumer.poll(1.0)
            if msg is None or msg.error():
                continue
            try:
                ctx = SerializationContext(msg.topic(), MessageField.VALUE)
                value = self._deserializer(msg.value(), ctx)
            except Exception:
                # Never let a bad message crash the dashboard feed on stage.
                continue
            self._loop.call_soon_threadsafe(self._dispatch, msg.topic(), value)

    def _dispatch(self, topic: str, value: dict) -> None:
        for handler in self._handlers.get(topic, []):
            handler(topic, value)
