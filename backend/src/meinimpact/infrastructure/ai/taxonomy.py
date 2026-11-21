"""The fixed topic taxonomy shared by enrichment and the app.

Tags are grounded in Politbarometer "wichtigste Probleme", cross-checked
against Sachsen-Monitor and the Kommunale Bürgerumfrage Dresden.
Demokratie/Mitbestimmung started as Demokratieverteidigung from
Sachsen-Monitor 2023's "Bekämpfung des Rechtsextremismus" category and was
widened after the free-topic review showed transparency and direct-democracy
items filed under it. Stadtentwicklung/Bauen and Gleichstellung/Inklusion
came from the same review (2026-11-02).

Three tables must stay in lockstep with the app, or matches silently stop:
`TAG_BETROFFENHEIT_KEYS` with `Betroffenheitsprofil.matchingKeys()`,
`WERTE_AUSSAGEN` with the questionnaire (`werteQuestionKeys` and the
statements in `value_profile_screen.dart`), and `GELD_BEREICHE` with the
budget areas of the Stadthaushalt step.
"""

# The fixed topic tags, in the order the app and the landing page use
TAGS: tuple[str, ...] = (
    "Wohnen/Miete",
    "Mobilität/Verkehr",
    "Arbeit/Einkommen",
    "Energie/Heizkosten",
    "Bildung/Ausbildung",
    "Rente/Alter",
    "Digitales/Datenschutz",
    "Sicherheit",
    "Migration/Integration",
    "Außenpolitik/Verteidigung",
    "Demokratie/Mitbestimmung",
    "Stadtentwicklung/Bauen",
    "Gesundheit/Pflege",
    "Familie/Kinder",
    "Umwelt/Natur",
    "Selbstständigkeit/Unternehmertum",
    "Gleichstellung/Inklusion",
)

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

# The questionnaire's statement pairs, keyed and ordered like the app's
# `werteQuestionKeys`, word for word: (left, right). In the app the left
# statement is -2 and the right one +2, so an opportunity's werte_relevanz
# value is -1 where people agreeing with the left statement support it and
# +1 where those agreeing with the right one do.
WERTE_AUSSAGEN: dict[str, tuple[str, str]] = {
    "wirtschaft_gleichheit": (
        "Der Staat sollte große Vermögen und Einkommen stärker ausgleichen.",
        "Wer Leistung bringt, sollte davon profitieren, mit möglichst wenig "
        "staatlichem Eingriff.",
    ),
    "wirtschaft_staat": (
        "Der Staat muss Märkte regulieren und wichtige Bereiche selbst kontrollieren.",
        "Privatwirtschaft und Wettbewerb lösen Probleme besser als der Staat.",
    ),
    "diplomatie_nation": (
        "Deutschland sollte seine eigenen Interessen klar vertreten, auch wenn "
        "das Partner vor den Kopf stößt.",
        "Globale Probleme lassen sich nur gemeinsam lösen. Nationale "
        "Alleingänge bringen nichts.",
    ),
    "diplomatie_welt": (
        "Deutschland sollte außenpolitisch unabhängiger werden und weniger "
        "Verpflichtungen eingehen.",
        "Deutschland muss mehr globale Verantwortung übernehmen, auch wenn das kostet.",
    ),
    "freiheit_staat": (
        "Der Staat soll so wenig wie möglich in das Leben der Menschen eingreifen.",
        "Mehr staatliche Regeln und Kontrolle sind nötig, um Sicherheit und "
        "Zusammenhalt zu gewährleisten.",
    ),
    "freiheit_sicherheit": (
        "Im Zweifel sind Bürgerrechte wichtiger als staatliche Sicherheitsinteressen.",
        "Im Zweifel ist Sicherheit wichtiger als individuelle Freiheiten.",
    ),
    "wandel_tradition": (
        "Gesellschaftliche Strukturen, die sich bewährt haben, sollten erhalten "
        "bleiben.",
        "Die Gesellschaft muss sich mutig weiterentwickeln, auch wenn das "
        "unbequem ist.",
    ),
    "wandel_zukunft": (
        "Wir fordern zu viel von der heutigen Generation für Probleme, die erst "
        "in der Zukunft spürbar werden.",
        "Ich bin bereit, heute auf Komfort zu verzichten, damit zukünftige "
        "Generationen es besser haben.",
    ),
}

# Budget areas of the Stadthaushalt step: id -> label. They map onto the
# Produktbereiche every German municipal budget uses, so they fit any city.
GELD_BEREICHE: dict[str, str] = {
    "kinder_bildung": "Kitas & Schulen",
    "soziales": "Soziales, Pflege & Gesundheit",
    "oepnv_rad": "Bus, Bahn & Rad",
    "strassen": "Straßen & Brücken",
    "kultur": "Kultur",
    "sport_freizeit": "Sport, Bäder & Freizeit",
    "sicherheit": "Sicherheit & Ordnung",
    "gruen_klima": "Grün, Umwelt & Klima",
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
