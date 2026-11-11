"""News and statements about one action, for Mein Impact.

Searches up a ladder and stops at the first rung that finds something:
1. `exact`: the concrete matter in the words the press would use (the
   measure, facility or place), never "Petition", platform names or paper
   numbers: those found next to nothing in the first dry run.
2. `issue`: the same matter, phrased differently or one place wider.
3. `background`: the overarching topic, at most one item, shown as
   background only.

Every hit is judged by Mistral against the action's facts. On the first
two rungs a hit counts if it is about the action or the concrete matter
it targets (e.g. the planned cut itself); the same topic elsewhere does
not count. "Nothing found" is a valid result: the app says so instead of
padding with general news.

Social media is excluded for now, as are action platforms and search
engine entity pages: they crowded out the press in the first dry run.
"""

import logging
from collections.abc import Sequence
from dataclasses import dataclass
from datetime import date
from typing import Any, Protocol
from urllib.parse import urlparse

import httpx

from meinimpact.infrastructure.ai.mistral_json import JsonCompleter

logger = logging.getLogger(__name__)

EXACT = "exact"
ISSUE = "issue"
BACKGROUND = "background"
LEVELS = (EXACT, ISSUE, BACKGROUND)

EXCLUDED_DOMAINS = (
    # Social media (later, as its own source)
    "facebook.com",
    "instagram.com",
    "tiktok.com",
    "linkedin.com",
    "x.com",
    "twitter.com",
    "reddit.com",
    "youtube.com",
    "mastodon.social",
    "threads.com",
    "bsky.app",
    # Action platforms and registries: the action itself, not news on it
    "openpetition.de",
    "openpetition.eu",
    "weact.campact.de",
    "change.org",
    "ratsmonitor.de",
    "ratsinfo.dresden.de",
    "buergerbeteiligung.sachsen.de",
    # Search engine entity pages
    "tavily.com",
)

HIT_KINDS = frozenset({"news", "statement", "social", "action_page", "other"})

_SNIPPET_CHARS = 600


@dataclass(frozen=True, slots=True)
class ImpactSubject:
    """The facts of one action the ladder searches for."""

    kind: str
    title: str
    summary: str
    organizer: str | None
    locality: str | None
    source_url: str
    # Hits published before this day cannot be about the action
    since: date


@dataclass(frozen=True, slots=True)
class SearchHit:
    title: str
    url: str
    content: str
    published_date: str | None = None


@dataclass(frozen=True, slots=True)
class JudgedHit:
    hit: SearchHit
    relevant: bool
    kind: str
    reason: str


@dataclass(frozen=True, slots=True)
class Rung:
    level: str
    query: str
    hits: tuple[JudgedHit, ...]

    @property
    def relevant(self) -> tuple[JudgedHit, ...]:
        return tuple(h for h in self.hits if h.relevant)


@dataclass(frozen=True, slots=True)
class LadderResult:
    queries: dict[str, str]
    rungs: tuple[Rung, ...]

    @property
    def items(self) -> tuple[JudgedHit, ...]:
        """What Mein Impact shows: the first specific rung with relevant
        hits, else at most one background item."""
        for rung in self.rungs:
            if rung.level != BACKGROUND and rung.relevant:
                return rung.relevant
        for rung in self.rungs:
            if rung.level == BACKGROUND and rung.relevant:
                return rung.relevant[:1]
        return ()


class WebSearch(Protocol):
    async def search(
        self, query: str, *, since: date, exclude_domains: Sequence[str]
    ) -> list[SearchHit]:
        """Hits for `query` published on or after `since`; [] on errors."""
        ...


class TavilySearch:
    """Tavily web search, restricted to German results after a date."""

    _URL = "https://api.tavily.com/search"

    def __init__(
        self,
        api_key: str,
        *,
        max_results: int = 8,
        client: httpx.AsyncClient | None = None,
    ) -> None:
        self._api_key = api_key
        self._max_results = max_results
        self._client = client or httpx.AsyncClient(timeout=30.0)

    async def aclose(self) -> None:
        await self._client.aclose()

    async def search(
        self, query: str, *, since: date, exclude_domains: Sequence[str]
    ) -> list[SearchHit]:
        payload: dict[str, object] = {
            "query": query,
            "topic": "general",
            "search_depth": "basic",
            "country": "germany",
            "max_results": self._max_results,
            "start_date": since.isoformat(),
            "include_published_date": True,
        }
        if exclude_domains:
            payload["exclude_domains"] = list(exclude_domains)
        try:
            response = await self._client.post(
                self._URL,
                headers={"Authorization": f"Bearer {self._api_key}"},
                json=payload,
            )
            response.raise_for_status()
            results = response.json().get("results") or []
        except Exception as error:
            logger.warning("Tavily search failed for %r: %s", query[:60], error)
            return []
        return [
            SearchHit(
                title=str(r.get("title") or ""),
                url=str(r.get("url") or ""),
                content=str(r.get("content") or ""),
                published_date=r.get("published_date") or None,
            )
            for r in results
            if r.get("url")
        ]


class NewsLadder:
    def __init__(self, completer: JsonCompleter, search: WebSearch) -> None:
        self._completer = completer
        self._search = search

    async def run(
        self, subject: ImpactSubject, *, exhaustive: bool = False
    ) -> LadderResult:
        """Climbs the ladder. `exhaustive` searches every rung even after a
        find, to measure each rung (dry runs)."""
        queries = await self.plan_queries(subject)
        exclude = _excluded_domains(subject)
        rungs: list[Rung] = []
        for level in LEVELS:
            query = queries.get(level, "")
            if not query:
                continue
            hits = await self._search.search(
                query, since=subject.since, exclude_domains=exclude
            )
            judged = await self.judge(subject, level, hits) if hits else ()
            rungs.append(Rung(level=level, query=query, hits=judged))
            if not exhaustive and level != BACKGROUND and rungs[-1].relevant:
                break
        return LadderResult(queries=queries, rungs=tuple(rungs))

    async def plan_queries(self, subject: ImpactSubject) -> dict[str, str]:
        answer = await self._completer.complete_json(_query_prompt(subject))
        return {
            level: " ".join(str(answer.get(level) or "").split()) for level in LEVELS
        }

    async def judge(
        self, subject: ImpactSubject, level: str, hits: Sequence[SearchHit]
    ) -> tuple[JudgedHit, ...]:
        answer = await self._completer.complete_json(
            _judge_prompt(subject, level, hits)
        )
        return parse_judgments(answer, hits)


def parse_judgments(
    answer: dict[str, Any], hits: Sequence[SearchHit]
) -> tuple[JudgedHit, ...]:
    """One verdict per hit; a hit the model skipped or garbled counts as
    not relevant."""
    verdicts: dict[int, dict[str, Any]] = {}
    for item in answer.get("results") or []:
        if isinstance(item, dict) and isinstance(item.get("i"), int):
            verdicts.setdefault(item["i"], item)
    judged = []
    for index, hit in enumerate(hits):
        verdict = verdicts.get(index, {})
        kind = verdict.get("kind")
        kind = kind if kind in HIT_KINDS else "other"
        judged.append(
            JudgedHit(
                hit=hit,
                # The action's own page is never news about it
                relevant=verdict.get("relevant") is True and kind != "action_page",
                kind=kind,
                reason=str(verdict.get("reason") or ""),
            )
        )
    return tuple(judged)


def _excluded_domains(subject: ImpactSubject) -> list[str]:
    # The action's own site is not news about it
    host = (urlparse(subject.source_url).hostname or "").removeprefix("www.")
    return [*EXCLUDED_DOMAINS, *([host] if host not in EXCLUDED_DOMAINS else [])]


def _facts(subject: ImpactSubject) -> str:
    return "\n".join(
        f"{label}: {value}"
        for label, value in (
            ("Art", subject.kind),
            ("Titel", subject.title),
            ("Beschreibung", subject.summary),
            ("Gremium/Organisator", subject.organizer),
            ("Ort", subject.locality),
            ("Link", subject.source_url),
        )
        if value
    )


def _query_prompt(subject: ImpactSubject) -> str:
    return f"""Du suchst Presseberichte und Stellungnahmen zu einer
Beteiligungsmöglichkeit (Petition, Ratsvorlage, Bürgerbeteiligung).

{_facts(subject)}

Schreibe drei kurze deutsche Suchanfragen (je 3 bis 7 Wörter, keine
Anführungszeichen, keine Operatoren), so formuliert, wie eine Zeitung
darüber schreiben würde. Nie Wörter wie Petition, Konsultation, Vorlage,
Beteiligung, keine Plattformnamen, keine Nummern.
- "exact": die konkrete Sache: Gegenstand plus Ort, Einrichtung oder
  Gesetz (z. B. "Imbisspavillons Prager Straße Dresden", "Kita
  Tännichtweg Hellerau Schließung", "Wohngeld Kürzung Bundesregierung").
- "issue": dieselbe konkrete Sache, anders formuliert: andere Begriffe
  oder der nächstgrößere Ort (Stadtteil statt Straße, Stadt statt
  Stadtteil).
- "background": das übergeordnete Thema auf der passenden Ebene (Stadt,
  Land, Bund oder EU), ohne Details dieser Sache (z. B. "Innenstadt
  Gastronomie Dresden").

Antworte nur mit JSON: {{"exact": "...", "issue": "...", "background": "..."}}"""


_ABOUT_THIS = (
    "relevant = true, wenn der Treffer genau diese Sache behandelt: die "
    "Petition, Vorlage oder Beteiligung selbst ODER das konkrete Vorhaben, "
    "die Maßnahme, das Gesetz, die Einrichtung oder den Ort, um die es "
    "geht (z. B. die geplante Kürzung selbst, die Kita, die Straße). Er "
    "muss die Petition nicht nennen. Dasselbe Thema bei einer anderen "
    "Maßnahme oder an einem anderen Ort ist NICHT relevant."
)
_LEVEL_RULES = {
    EXACT: _ABOUT_THIS,
    ISSUE: _ABOUT_THIS,
    BACKGROUND: (
        "relevant = true nur für aktuelle Berichterstattung oder "
        "Stellungnahmen (Presse, Politik, Verwaltung, Verbände) zum "
        "übergeordneten Thema auf derselben Ebene (Stadt, Land, Bund oder "
        "EU). Ratgeber, Lexikon-, Statistik- oder Infoseiten ohne aktuellen "
        "Anlass sind NICHT relevant."
    ),
}


def _judge_prompt(subject: ImpactSubject, level: str, hits: Sequence[SearchHit]) -> str:
    listing = "\n\n".join(
        f"[{i}] {hit.title}\nURL: {hit.url}\n"
        f"Datum: {hit.published_date or 'unbekannt'}\n"
        f"Auszug: {hit.content[:_SNIPPET_CHARS]}"
        for i, hit in enumerate(hits)
    )
    return f"""Du prüfst Suchtreffer für eine neutrale Civic-Tech-App.
Nutzerinnen haben bei dieser Sache mitgemacht und wollen wissen, was
daraus geworden ist und was darüber berichtet oder gesagt wurde.

Die Sache:
{_facts(subject)}

Regel: {_LEVEL_RULES[level]}
Seiten von Petitionsplattformen,
Ratsinformationssystemen oder Beteiligungsportalen sind kind
"action_page" und nicht relevant. Im Zweifel nicht relevant.

kind: "news" (Presse, Medien), "statement" (Politik, Verwaltung,
Parteien, Verbände äußern sich), "social" (Social-Media-Beitrag),
"action_page", "other".

Treffer:
{listing}

Antworte nur mit JSON:
{{"results": [{{"i": 0, "relevant": true, "kind": "news", "reason": "..."}}]}}
Ein Eintrag pro Treffer, reason ist ein kurzer Satz."""
