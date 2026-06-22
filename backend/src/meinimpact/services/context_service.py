"""AI-powered personalised action context generation."""

from meinimpact.api.schemas import ActionContextRequest
from meinimpact.domain.entities import CivicAction
from meinimpact.infrastructure.ai.base import AiTextGenerator

_LEBENS_DE: dict[str, str] = {
    "elternteil": "Elternteil",
    "schueler": "Schüler/in",
    "student": "Studierend",
    "berufstaetig": "berufstätig",
    "rentner": "Rentner/in",
    "selbststaendig": "selbstständig",
    "arbeitssuchend": "arbeitssuchend",
    "pflegend": "pflegende Angehörige/r",
}

_PLZ_REGION: dict[str, str] = {
    "0": "Sachsen/Sachsen-Anhalt/Thüringen",
    "1": "Brandenburg/Berlin/Mecklenburg-Vorpommern",
    "2": "Hamburg/Schleswig-Holstein/Bremen",
    "3": "Niedersachsen/Sachsen-Anhalt",
    "4": "Nordrhein-Westfalen",
    "5": "Nordrhein-Westfalen/Rheinland-Pfalz",
    "6": "Hessen/Rheinland-Pfalz/Baden-Württemberg",
    "7": "Baden-Württemberg",
    "8": "Bayern",
    "9": "Bayern/Thüringen/Sachsen",
}


class ContextService:
    """Generates a personalised 'what this means for you' paragraph."""

    def __init__(self, ai_generator: AiTextGenerator) -> None:
        self._ai = ai_generator

    async def generate(
        self,
        action: CivicAction,
        request: ActionContextRequest,
    ) -> str:
        prompt = self._build_prompt(action, request)
        chunks: list[str] = []
        async for token in self._ai.stream_text(prompt):
            chunks.append(token)
        return "".join(chunks).strip()

    def _build_prompt(
        self,
        action: CivicAction,
        request: ActionContextRequest,
    ) -> str:
        leben_labels = [_LEBENS_DE.get(s, s) for s in request.lebenssituation]
        region = (
            _PLZ_REGION.get(request.plz_prefix[0], "Deutschland")
            if request.plz_prefix
            else "Deutschland"
        )

        profile_parts: list[str] = []
        if leben_labels:
            profile_parts.append(f"Lebenssituation: {', '.join(leben_labels)}")
        if request.sektor:
            profile_parts.append(f"Berufssektor: {request.sektor}")
        if request.wohnsituation:
            profile_parts.append(f"Wohnsituation: {request.wohnsituation}")
        if request.plz_prefix:
            profile_parts.append(f"Region: {region}")

        profile_desc = (
            "; ".join(profile_parts) if profile_parts else "allgemeine Bevölkerung"
        )

        return (
            f"Du bist ein Redakteur für eine deutsche Civic-Tech-App.\n\n"
            f"Erkläre in 2-3 Sätzen auf Deutsch, warum folgende politische Aktion "
            f"für diese Person konkret relevant ist.\n\n"
            f"Profil: {profile_desc}\n\n"
            f"Aktion: {action.title}\n"
            f"Zusammenfassung: {action.summary}\n\n"
            f"Antworte direkt mit dem Erklärungstext. Keine Einleitung, "
            f"kein 'Als ...'-Beginn erzwingen — schreib natürlich und konkret."
        )
