"""In-memory, thread-safe per-service status + open incidents. Mutated
live via POST /admin/status — not automated, so the presenter controls
timing precisely (spec section 2.3 / 5)."""

import threading

from support_portal.incidents.known_issues import SERVICES


class PortalState:
    def __init__(self):
        self._lock = threading.Lock()
        self.service_status: dict[str, str] = {s: "operational" for s in SERVICES}
        self.incidents: list[dict] = []

    def get_status(self) -> dict:
        with self._lock:
            return {"services": dict(self.service_status), "incidents": list(self.incidents)}

    def get_service_status(self) -> dict[str, str]:
        with self._lock:
            return dict(self.service_status)

    def set_incident(self, service: str, status: str, description: str = "") -> dict:
        with self._lock:
            self.service_status[service] = status
            self.incidents = [i for i in self.incidents if i["service"] != service]
            if status != "operational":
                self.incidents.append({"service": service, "status": status, "description": description})
            return {"services": dict(self.service_status), "incidents": list(self.incidents)}
