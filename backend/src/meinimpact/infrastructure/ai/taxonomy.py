"""The fixed topic taxonomy shared by enrichment and the app.

Tags are grounded in Politbarometer "wichtigste Probleme", cross-checked
against Sachsen-Monitor and the Kommunale Bürgerumfrage Dresden.
Demokratieverteidigung was added from Sachsen-Monitor 2023's "Bekämpfung des
Rechtsextremismus" category.

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
    "Demokratieverteidigung": ["liberty_authority"],
    "Gesundheit/Pflege": [],
    "Familie/Kinder": [],
    "Umwelt/Natur": [],
    "Selbstständigkeit/Unternehmertum": [],
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
    "Selbstständigkeit/Unternehmertum": ["erwerbsstatus:selbststaendig"],
}
