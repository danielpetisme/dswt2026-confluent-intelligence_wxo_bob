import asyncio
from contextlib import asynccontextmanager
from pathlib import Path

from fastapi import FastAPI
from fastapi.staticfiles import StaticFiles
from mcp.server.transport_security import TransportSecuritySettings

from support_portal import pages
from support_portal.accounts.pool import AccountPool
from support_portal.admin import routes as admin
from support_portal.config import settings
from support_portal.dashboard import routes as dashboard
from support_portal.dashboard import service as dashboard_service
from support_portal.generator.synthetic import BaselineGenerator
from support_portal.incidents.state import PortalState
from support_portal.mcp.server import build_mcp_server
from support_portal.messaging.consumer import DashboardConsumer
from support_portal.messaging.producer import TicketProducer
from support_portal.tickets import routes as tickets
from support_portal.tickets import service as tickets_service

account_pool = AccountPool(settings.account_pool_size)
portal_state = PortalState()
producer = TicketProducer()

# Keep the SDK's default internal route ("/mcp") and mount the sub-app at
# "/" (below, registered last) rather than mounting at "/mcp" with an
# internal "/" route -- the latter makes Starlette 307-redirect bare
# "/mcp" requests to "/mcp/", which not every MCP HTTP client follows on
# POST. mcp 2.x also rejects any request whose Host header isn't
# allowlisted (DNS-rebinding protection, on by default) -- add the
# public deployment hostname to MCP_ALLOWED_HOSTS before going live.
mcp_server = build_mcp_server(account_pool, portal_state)
mcp_asgi_app = mcp_server.streamable_http_app(
    transport_security=TransportSecuritySettings(
        allowed_hosts=[h.strip() for h in settings.mcp_allowed_hosts.split(",") if h.strip()],
        allowed_origins=[h.strip() for h in settings.mcp_allowed_hosts.split(",") if h.strip()],
    ),
)


KAFKA_HANDLERS = {
    "tickets.enriched": [dashboard_service.handle_message],
    "tickets.metrics": [dashboard_service.handle_message],
    "tickets.agent-actions": [dashboard_service.handle_message, tickets_service.handle_agent_action],
}


@asynccontextmanager
async def lifespan(app: FastAPI):
    loop = asyncio.get_event_loop()
    consumer = DashboardConsumer(loop, handlers=KAFKA_HANDLERS)
    consumer.start(list(KAFKA_HANDLERS))

    generator = None
    if settings.enable_generator:
        generator = BaselineGenerator(producer, rate=settings.generator_rate, portal_state=portal_state)
        generator.start()

    app.state.consumer = consumer
    app.state.generator = generator

    # The mounted MCP sub-app's streamable-HTTP session manager needs its
    # own async context manager entered for the mount to actually work --
    # Starlette does not propagate a sub-app's lifespan automatically.
    async with mcp_server.session_manager.run():
        yield

    if generator:
        generator.stop()
    consumer.stop()
    producer.flush()


app = FastAPI(title="Fake Shop Support Portal", lifespan=lifespan)
app.state.account_pool = account_pool
app.state.portal_state = portal_state
app.state.producer = producer

app.include_router(pages.router)
app.include_router(tickets.router)
app.include_router(dashboard.router)
app.include_router(admin.router)
app.mount("/static", StaticFiles(directory=Path(__file__).resolve().parent / "static"), name="static")

# Registered last: Starlette matches routes in registration order, so the
# explicit routes/mounts above always win and only unmatched paths (i.e.
# "/mcp") fall through to this catch-all mount.
app.mount("/", mcp_asgi_app)
