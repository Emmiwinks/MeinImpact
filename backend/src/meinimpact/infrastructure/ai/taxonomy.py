"""The fixed topic taxonomy shared by enrichment and the app.

Tags are grounded in Politbarometer "wichtigste Probleme", cross-checked
against Sachsen-Monitor and the Kommunale Bürgerumfrage Dresden.
Demokratie/Mitbestimmung started as Demokratieverteidigung from
Sachsen-Monitor 2023's "Bekämpfung des Rechtsextremismus" category and was
widened after the free-topic review showed transparency and direct-democracy
items filed under it. Stadtentwicklung/Bauen and Gleichstellung/Inklusion
came from the same review (2026-11-02).

`TAG_BETROFFENHEIT_KEYS` must stay in lockstep with the app's
`Betroffenheitsprofil.matchingKeys()`: renamed keys silently stop matching.
"""

# tag -> werte axes it is value-differentiated on ([] = not differentiated)
TAG_AXES: dict[str, list[str]] = {
    "Wohnen/Miete": ["equality_markets"],
    "Mobilität/Verkehr": ["tradition_progress"],
    "Arbeit/Einkommen": ["equality_markets"],
    "Energie/Heizkosten": ["tradition_progress", "equality_markets"],
    "Bildung/Ausbildung": ["tradition_progress"],
    "Rente/Alter": ["equality_markets"],
    "Digitales/Datenschutz": ["liberty_authority"],
    "Sicherheit": ["liberty_authority"],
    "Migration/Integration": ["nation_globe"],
    "Außenpolitik/Verteidigung": ["liberty_authority"],
    "Demokratie/Mitbestimmung": ["liberty_authority"],
    "Stadtentwicklung/Bauen": ["tradition_progress"],
    "Gesundheit/Pflege": [],
    "Familie/Kinder": [],
    "Umwelt/Natur": [],
    "Selbstständigkeit/Unternehmertum": [],
    "Gleichstellung/Inklusion": [],
}

# One-line scope for tags the model over-applies without it (the first
# review run filed energy grid and mining items under Stadtentwicklung/Bauen).
TAG_HINTS: dict[str, str] = {
    "Stadtentwicklung/Bauen": (
        "nur Bauleitplanung und Stadtgestaltung: Bebauungspläne, Quartiere, "
        "Gewerbegebiete, Wohnungsbau, öffentliche Räume. NICHT Energie-, "
        "Bergbau- oder Waldthemen und nicht Kitas/Schulen als Einrichtung"
    ),
    "Gleichstellung/Inklusion": (
        "Diskriminierung, Gleichberechtigung, Barrierefreiheit, Teilhabe"
    ),
    "Demokratie/Mitbestimmung": (
        "Transparenz, Bürgerbeteiligung, direkte Demokratie, Schutz der "
        "Demokratie vor Extremismus"
    ),
}

# Topics seen in the free labels but too thin for a tag yet, with their scope.
# The model names one when it fits; `scripts/topic_report.py` counts them, and
# a candidate that keeps growing becomes a tag.
CANDIDATE_TOPICS: dict[str, str] = {
    "Verbraucher/Preise": (
        "Verbraucherschutz und Preise für Waren/Energie/Sprit; NICHT Löhne, "
        "Mieten oder Sozialleistungen"
    ),
    "Kultur/Freizeit/Ehrenamt": "Sport, Kultur, Freizeitangebote, Ehrenamt",
}

# Each axis in its own bipolar language, never a generic left/right label.
AXIS_LANGUAGE: dict[str, str] = {
    "tradition_progress": "-1 = Bewahrung/Tradition ... +1 = Reform/Wandel",
    "equality_markets": (
        "-1 = Umverteilung/Sozialstaat ... +1 = freier Markt/Privatisierung"
    ),
    "liberty_authority": (
        "-1 = staatliche Regulierung/Eingriff ... +1 = individuelle Freiheit"
    ),
    "nation_globe": "-1 = nationaler Fokus ... +1 = international/multilateral",
}

# tag -> Betroffenheitsprofil "field:value" keys that get a personal snippet
TAG_BETROFFENHEIT_KEYS: dict[str, list[str]] = {
    "Wohnen/Miete": ["wohnsituation:mieter", "wohnsituation:eigentuemer"],
    "Mobilität/Verkehr": ["oepnv_nutzung:true", "auto_nutzung:true"],
    "Arbeit/Einkommen": [
        "erwerbsstatus:angestellt",
        "erwerbsstatus:arbeitslos",
        "erwerbsstatus:selbststaendig",
    ],
    "Energie/Heizkosten": ["wohnsituation:mieter", "wohnsituation:eigentuemer"],
    "Bildung/Ausbildung": ["hat_kinder:true", "erwerbsstatus:schueler_student"],
    "Rente/Alter": ["erwerbsstatus:rentner"],
    "Migration/Integration": ["migrationshintergrund:true"],
    "Gesundheit/Pflege": ["pflege_betroffen:true"],
    "Familie/Kinder": ["hat_kinder:true"],
    "Stadtentwicklung/Bauen": ["wohnsituation:mieter", "wohnsituation:eigentuemer"],
    "Selbstständigkeit/Unternehmertum": ["erwerbsstatus:selbststaendig"],
}
