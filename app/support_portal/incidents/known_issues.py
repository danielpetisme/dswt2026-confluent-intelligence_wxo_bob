"""Known-issues list, loaded from knowledge_base.csv, matched against
ticket free text via rapidfuzz. Local fuzzy matching only, per spec
section 3 (no external cloud dependency here)."""

import csv
from dataclasses import dataclass
from pathlib import Path

from rapidfuzz import fuzz, process

SERVICES = ["login", "checkout", "payments", "search", "notifications", "order-tracking"]

CSV_PATH = Path(__file__).resolve().parent / "knowledge_base.csv"

# knowledge_base.csv's apply_to column uses slightly different service names
# than SERVICES (singular "notification", spaced "order tracking") -- map
# those onto the canonical SERVICES spelling used everywhere else in the app.
_SERVICE_ALIASES = {"notification": "notifications", "order tracking": "order-tracking"}


@dataclass(frozen=True)
class KnownIssue:
    issue_id: str
    service: str
    symptoms: str
    suggested_fix: str


def _normalize_service(raw: str) -> str | None:
    service = _SERVICE_ALIASES.get(raw, raw)
    return service if service in SERVICES else None


def _load() -> list[KnownIssue]:
    issues = []
    with CSV_PATH.open(newline="", encoding="utf-8") as f:
        for row in csv.DictReader(f):
            # apply_to can list several services (e.g. "checkout, payments");
            # an article is tagged with only the first for matching purposes,
            # since search_known_issues has no service context to disambiguate
            # ties between them anyway.
            first_service = row["apply_to"].split(",")[0].strip().lower()
            service = _normalize_service(first_service)
            if service is None:
                continue
            issues.append(KnownIssue(
                issue_id=row["article_id"],
                service=service,
                symptoms=row["symptoms"],
                suggested_fix=row["resolution"],
            ))
    return issues


KNOWN_ISSUES: list[KnownIssue] = _load()

_CHOICES = {issue.issue_id: issue.symptoms for issue in KNOWN_ISSUES}
_BY_ID = {issue.issue_id: issue for issue in KNOWN_ISSUES}


def search_known_issues(ticket_text: str, threshold: int) -> dict:
    match = process.extractOne(ticket_text, _CHOICES, scorer=fuzz.token_set_ratio)
    if match is None:
        return {"matched": False, "issue_id": None, "service": None, "suggested_fix": None, "confidence": 0.0}

    _symptoms, score, issue_id = match
    if score < threshold:
        return {"matched": False, "issue_id": None, "service": None, "suggested_fix": None, "confidence": round(score, 1)}

    issue = _BY_ID[issue_id]
    return {
        "matched": True,
        "issue_id": issue.issue_id,
        "service": issue.service,
        "suggested_fix": issue.suggested_fix,
        "confidence": round(score, 1),
    }
