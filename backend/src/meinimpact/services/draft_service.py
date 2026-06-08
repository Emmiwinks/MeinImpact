"""AI-assisted letter and question draft orchestration."""

from collections.abc import AsyncIterator

from meinimpact.api.schemas import LetterRequest
from meinimpact.domain.entities import CivicAction
from meinimpact.infrastructure.ai.base import AiTextGenerator

_TONE_LABELS: dict[str, str] = {
    "community-oriented": "gemeinschaftsorientiert",
    "pragmatic": "eigenverantwortlich denkend",
    "nationally-focused": "national orientiert",
    "internationally-minded": "international orientiert",
    "rights-conscious": "bürgerrechtsbewusst",
    "security-oriented": "sicherheitsorientiert",
    "stability-oriented": "stabilitätsorientiert",
    "reform-minded": "reformorientiert",
    "balanced": "ausgewogen",
}

_LEBENSSITUATION_LABELS: dict[str, str] = {
    "elternteil": "Elternteil",
    "eigentuemer": "Wohneigentümer/in",
    "pflegend": "pflegend tätig",
    "rentner": "Rentner/in",
    "ausbildung": "in Ausbildung",
    "berufstaetig": "berufstätig",
}

_PLZ_REGIONS: dict[str, str] = {
    "0": "Sachsen / Thüringen",
    "1": "Berlin / Brandenburg",
    "2": "Hamburg / Schleswig-Holstein",
    "3": "Niedersachsen",
    "4": "Nordrhein-Westfalen Nord",
    "5": "Nordrhein-Westfalen Süd / Rheinland",
    "6": "Hessen / Rheinland-Pfalz",
    "7": "Baden-Württemberg",
    "8": "Bayern",
    "9": "Bayern / Franken",
}

_BRIEF_PROMPT = """\
Du schreibst einen persönlichen Brief eines deutschen Staatsbürgers an \
seinen/ihren Bundestagsabgeordneten.

Empfänger: {recipient_name} ({recipient_party}), Wahlkreis {recipient_wahlkreis}

Politisches Thema: {action_title}
Hintergrund: {action_summary}

Bürger-Profil:
- Orientierung: {tone_descriptors}
- Lebenssituation: {lebenssituation}
- Beruflicher Bereich: {sektor}
- Region: {plz_region}

Schreibe einen Brief der:
- 150–200 Wörter hat
- Persönlich klingt, nicht wie eine Vorlage
- Eine konkrete Bitte oder Frage enthält
- Keine Parteinamen nennt außer dem Empfänger
- Mit einer Grußformel endet, aber OHNE Namen — Platzhalter {{USER_FULL_NAME}} am Ende

Variiere Satzbau und Wortschatz.\
"""

_ANFRAGE_PROMPT = """\
Du formulierst eine öffentliche Anfrage eines deutschen Staatsbürgers \
an seinen/ihren Bundestagsabgeordneten via Abgeordnetenwatch.

Empfänger: {recipient_name} ({recipient_party})

Thema: {action_title}
Kontext: {action_summary}

Bürger-Profil:
- Orientierung: {tone_descriptors}
- Lebenssituation: {lebenssituation}
- Region: {plz_region}

Schreibe eine öffentliche Frage die:
- 2–3 Sätze lang ist
- Konkret und beantwortbar ist (keine Ja/Nein-Frage)
- Sachlich und respektvoll formuliert ist
- Mit der direkten Frage beginnt

Keine Anrede, keine Grußformel. Nur die Frage selbst.\
"""


class DraftService:
    """Builds German prompts and streams letter/question drafts via AI."""

    def __init__(self, ai_generator: AiTextGenerator) -> None:
        """Initializes the service with an AI generator."""
        self._ai_generator = ai_generator

    async def stream_letter(
        self,
        request: LetterRequest,
        action: CivicAction,
    ) -> AsyncIterator[str]:
        """Streams a letter or public question draft as raw tokens."""
        prompt = self._build_prompt(request, action)
        async for delta in self._ai_generator.stream_text(prompt):
            yield delta

    def _build_prompt(self, request: LetterRequest, action: CivicAction) -> str:
        tone = (
            ", ".join(_TONE_LABELS.get(d, d) for d in request.tone_descriptors)
            or "ausgewogen"
        )
        lebenssituation = (
            ", ".join(
                _LEBENSSITUATION_LABELS.get(k, k) for k in request.lebenssituation
            )
            or "keine Angabe"
        )
        plz_region = (
            _PLZ_REGIONS.get(request.plz_prefix[0], "Deutschland")
            if request.plz_prefix
            else "Deutschland"
        )
        wahlkreis = request.recipient_wahlkreis or "unbekannt"

        if request.type == "brief":
            return _BRIEF_PROMPT.format(
                recipient_name=request.recipient_name,
                recipient_party=request.recipient_party,
                recipient_wahlkreis=wahlkreis,
                action_title=action.title,
                action_summary=action.summary,
                tone_descriptors=tone,
                lebenssituation=lebenssituation,
                sektor=request.sektor or "keine Angabe",
                plz_region=plz_region,
            )
        return _ANFRAGE_PROMPT.format(
            recipient_name=request.recipient_name,
            recipient_party=request.recipient_party,
            action_title=action.title,
            action_summary=action.summary,
            tone_descriptors=tone,
            lebenssituation=lebenssituation,
            plz_region=plz_region,
        )
