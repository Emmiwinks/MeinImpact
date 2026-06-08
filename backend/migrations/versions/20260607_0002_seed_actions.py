"""Seed demo civic actions for the prototype."""

from collections.abc import Sequence
from datetime import date

import sqlalchemy as sa
from alembic import op

revision: str = "202606070002"
down_revision: str | None = "202605300001"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None

_actions_table = sa.table(
    "civic_actions",
    sa.column("id", sa.String),
    sa.column("title", sa.String),
    sa.column("action_type", sa.String),
    sa.column("summary", sa.Text),
    sa.column("topics", sa.JSON),
    sa.column("region", sa.String),
    sa.column("deadline", sa.Date),
    sa.column("effort_minutes", sa.Integer),
    sa.column("impact_hint", sa.Text),
    sa.column("source_url", sa.String),
)

_SEED_IDS = [
    "bundesbau-wohnungsbau-brief",
    "bundestag-solar-petition",
    "kohleausstieg-anfrage",
    "bafoeg-reform-brief",
    "krankenhausreform-brief",
    "deutsche-bahn-petition",
    "kita-ausbau-brief",
    "fahrradinfrastruktur-anfrage",
    "gebaeudeenergiegesetz-brief",
    "wahlrecht-16-petition",
]

_SEED_ROWS = [
    {
        "id": "bundesbau-wohnungsbau-brief",
        "title": "Brief an MdB: Sozialen Wohnungsbau stärken",
        "action_type": "representative_letter",
        "summary": (
            "Das Bundesbauministerium plant Kürzungen beim sozialen Wohnungsbau. "
            "Ein Ausschuss berät diese Woche über den Entwurf. "
            "Dein Brief kann die Positionierung deines MdB beeinflussen."
        ),
        "topics": ["housing", "democracy", "public spending"],
        "region": "Germany",
        "deadline": date(2026, 6, 21),
        "effort_minutes": 3,
        "impact_hint": "Die Abstimmungsposition deines MdB ist nach der Ausschusswoche einsehbar.",  # noqa: E501
        "source_url": "https://www.abgeordnetenwatch.de/",
    },
    {
        "id": "bundestag-solar-petition",
        "title": "Petition: Solaranlagen auf allen Bundesgebäuden",
        "action_type": "petition_signature",
        "summary": (
            "Eine Bundestag-Petition fordert die Pflicht zur Solaranlage auf allen "
            "Bundesgebäuden ab 2027. Die Petition braucht 50.000 Unterschriften."
        ),
        "topics": ["climate", "energy", "public spending"],
        "region": "Germany",
        "deadline": date(2026, 6, 28),
        "effort_minutes": 2,
        "impact_hint": "Bei 50.000 Unterschriften muss der Bundestag die Petition behandeln.",  # noqa: E501
        "source_url": "https://epetitionen.bundestag.de/",
    },
    {
        "id": "kohleausstieg-anfrage",
        "title": "Anfrage an MdB: Zeitplan Kohleausstieg 2030",
        "action_type": "public_question",
        "summary": (
            "Die Bundesregierung hat den Kohleausstieg auf 2030 vorgezogen, "
            "aber konkrete Umsetzungspläne fehlen. Eine öffentliche Anfrage "
            "an deinen MdB setzt den Zeitplan auf die Tagesordnung."
        ),
        "topics": ["climate", "energy"],
        "region": "Germany",
        "deadline": date(2026, 7, 15),
        "effort_minutes": 3,
        "impact_hint": "MdBs müssen öffentliche Anfragen über Abgeordnetenwatch beantworten.",  # noqa: E501
        "source_url": "https://www.abgeordnetenwatch.de/",
    },
    {
        "id": "bafoeg-reform-brief",
        "title": "Brief an MdB: BAföG-Reform für Studierende",
        "action_type": "representative_letter",
        "summary": (
            "Eine Koalitionseinigung zur BAföG-Reform steht noch aus. "
            "Die zweite Lesung im Bundestag ist für Juli geplant. "
            "Dein Brief beeinflusst die Positionierung deines MdB."
        ),
        "topics": ["education", "democracy"],
        "region": "Germany",
        "deadline": date(2026, 7, 5),
        "effort_minutes": 3,
        "impact_hint": "Das Abstimmungsergebnis ist nach der zweiten Lesung öffentlich einsehbar.",  # noqa: E501
        "source_url": "https://www.abgeordnetenwatch.de/",
    },
    {
        "id": "krankenhausreform-brief",
        "title": "Brief an MdB: Krankenhausreform nachbessern",
        "action_type": "representative_letter",
        "summary": (
            "Die Krankenhausreform tritt 2026 in Kraft, aber Verbände kritisieren "
            "die Finanzierung der Grundversorger. Der Bundesrat berät diesen Monat "
            "Nachbesserungen."
        ),
        "topics": ["health", "public spending"],
        "region": "Germany",
        "deadline": date(2026, 6, 25),
        "effort_minutes": 4,
        "impact_hint": "Der Bundesrat veröffentlicht sein Votum nach der Sitzung.",
        "source_url": "https://www.abgeordnetenwatch.de/",
    },
    {
        "id": "deutsche-bahn-petition",
        "title": "Petition: Zuverlässigkeitsoffensive Deutsche Bahn",
        "action_type": "petition_signature",
        "summary": (
            "Eine WeAct-Petition fordert gesetzlich verankerte Pünktlichkeitsziele "
            "für die Deutsche Bahn und Entschädigung bei Verspätungen ab 15 Minuten."
        ),
        "topics": ["mobility", "climate"],
        "region": "Germany",
        "deadline": date(2026, 8, 1),
        "effort_minutes": 2,
        "impact_hint": "Campact leitet die Petition bei Erreichen des Quorums an das Bundesverkehrsministerium weiter.",  # noqa: E501
        "source_url": "https://weact.campact.de/",
    },
    {
        "id": "kita-ausbau-brief",
        "title": "Brief an MdB: Rechtsanspruch Kitaplatz umsetzen",
        "action_type": "representative_letter",
        "summary": (
            "Trotz gesetzlichem Rechtsanspruch fehlen in deutschen Städten über "
            "300.000 Kitaplätze. Der Bundestag berät diesen Monat über Förderprogramme."
        ),
        "topics": ["education", "housing"],
        "region": "Germany",
        "deadline": date(2026, 6, 20),
        "effort_minutes": 3,
        "impact_hint": "Das Förderprogramm wird nach der Bundestagsabstimmung veröffentlicht.",  # noqa: E501
        "source_url": "https://www.abgeordnetenwatch.de/",
    },
    {
        "id": "fahrradinfrastruktur-anfrage",
        "title": "Anfrage an MdB: Ausbau Radschnellwege",
        "action_type": "public_question",
        "summary": (
            "Deutschland hat bisher weniger als 200 km Radschnellwege. "
            "Eine öffentliche Anfrage nach dem Stand des Bundesrahmenplans 2030 "
            "setzt das Thema auf die Agenda."
        ),
        "topics": ["mobility", "climate"],
        "region": "Germany",
        "deadline": date(2026, 7, 20),
        "effort_minutes": 3,
        "impact_hint": "Öffentliche Antworten auf Abgeordnetenwatch sind für alle einsehbar.",  # noqa: E501
        "source_url": "https://www.abgeordnetenwatch.de/",
    },
    {
        "id": "gebaeudeenergiegesetz-brief",
        "title": "Brief an MdB: Wärmegesetz sozial gestalten",
        "action_type": "representative_letter",
        "summary": (
            "Die Übergangsfristen des GEG 2024 laufen 2026 aus. Viele Mieter:innen "
            "fürchten Kostenumlage durch Vermieter. Im Bundesrat wird über Anpassungen "
            "beraten."
        ),
        "topics": ["climate", "housing", "energy"],
        "region": "Germany",
        "deadline": date(2026, 7, 10),
        "effort_minutes": 4,
        "impact_hint": "Das Votum des Bundesrats ist öffentlich zugänglich.",
        "source_url": "https://www.abgeordnetenwatch.de/",
    },
    {
        "id": "wahlrecht-16-petition",
        "title": "Petition: Wahlrecht ab 16 bei Bundestagswahlen",
        "action_type": "petition_signature",
        "summary": (
            "Eine Bundestag-Petition fordert das aktive Wahlrecht bei Bundestagswahlen "
            "ab 16 Jahren. Bei Kommunal- und Europawahlen gilt es bereits in mehreren "
            "Bundesländern."
        ),
        "topics": ["democracy", "education"],
        "region": "Germany",
        "deadline": date(2026, 8, 15),
        "effort_minutes": 2,
        "impact_hint": "Bei 50.000 Unterschriften muss der Bundestag die Petition behandeln.",  # noqa: E501
        "source_url": "https://epetitionen.bundestag.de/",
    },
]


def upgrade() -> None:
    """Inserts seed civic actions."""
    op.bulk_insert(_actions_table, _SEED_ROWS)


def downgrade() -> None:
    """Removes seed civic actions."""
    op.execute(_actions_table.delete().where(_actions_table.c.id.in_(_SEED_IDS)))
