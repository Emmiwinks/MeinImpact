"""The Lebenslagen catalog: life situations, identities and occupations a
person can say "das ist mir wichtig" about, and an opportunity can concern.

One relation only (important to me): for ranking it makes no difference
whether someone is affected themselves, knows someone affected or just cares.
The model tags each opportunity with catalog ids; the app matches them
against the ids the user picked on their device. Nothing about a user's own
picks ever reaches the server.

`private` marks entries that fall under GDPR Art. 9 special categories
(sexual identity, religion, ethnic origin, health, disability). It is a
data-handling rule, not a judgment about the topic: the app shows every
group in the same picker, but never puts a private one on a profile summary
or any other view a bystander could see. What to enter is always the user's
choice.

The `label`s and `synonyms` (search terms, lower case) are exported to the
app by `scripts/export_lebenslagen.py`; this module is the single source.
Occupations follow the Berufsbereiche/-gruppen of the Bundesagentur's KldB
2010 in plain words.
"""

from dataclasses import dataclass

AREAS: tuple[str, ...] = (
    "Wohnen",
    "Arbeit & Einkommen",
    "Familie & Alter",
    "Gesundheit",
    "Identität & Herkunft",
    "Mobilität",
    "Alltag & Engagement",
    "Beruf",
)


@dataclass(frozen=True, slots=True)
class Lebenslage:
    id: str
    label: str
    area: str
    private: bool = False
    synonyms: tuple[str, ...] = ()


def _l(
    id: str, label: str, area: str, synonyms: str = "", *, private: bool = False
) -> Lebenslage:
    terms = tuple(t.strip() for t in synonyms.split(",") if t.strip())
    return Lebenslage(id, label, area, private, terms)


LEBENSLAGEN: tuple[Lebenslage, ...] = (
    # --- Wohnen
    _l("mieter", "Mieter:in", "Wohnen", "miete, wohnung, mietwohnung"),
    _l("eigentuemer", "Wohneigentümer:in", "Wohnen", "eigenheim, haus, eigentum"),
    _l("vermieter", "Vermieter:in", "Wohnen", "vermietung, immobilien"),
    _l("wohnungssuchend", "Auf Wohnungssuche", "Wohnen", "wohnungsnot, umzug"),
    _l(
        "wohnungslos",
        "Wohnungslos oder von Wohnungslosigkeit bedroht",
        "Wohnen",
        "obdachlos, räumung, zwangsräumung",
    ),
    _l("wohngeld", "Bezieht Wohngeld", "Wohnen", "wohngeld plus, mietzuschuss"),
    # --- Arbeit & Einkommen
    _l("angestellt", "Angestellt", "Arbeit & Einkommen", "arbeitnehmer, job"),
    _l(
        "selbststaendig",
        "Selbstständig oder Gründer:in",
        "Arbeit & Einkommen",
        "freiberufler, gründung, startup, unternehmer",
    ),
    _l(
        "arbeitssuchend",
        "Arbeitssuchend",
        "Arbeit & Einkommen",
        "arbeitslos, jobcenter, arbeitsagentur",
    ),
    _l(
        "buergergeld",
        "Bezieht Bürgergeld",
        "Arbeit & Einkommen",
        "hartz, grundsicherung",
    ),
    _l("minijob", "Minijob oder Teilzeit", "Arbeit & Einkommen", "midijob, 538 euro"),
    _l(
        "geringverdienend",
        "Geringverdienend",
        "Arbeit & Einkommen",
        "mindestlohn, niedriglohn, aufstocker",
    ),
    _l("azubi", "In Ausbildung", "Arbeit & Einkommen", "lehre, auszubildende"),
    _l(
        "studierend",
        "Schüler:in oder Student:in",
        "Arbeit & Einkommen",
        "uni, hochschule, bafög, schule",
    ),
    _l("beamtet", "Beamt:in", "Arbeit & Einkommen", "öffentlicher dienst, verbeamtet"),
    _l(
        "rentner",
        "Rentner:in oder Pensionär:in",
        "Arbeit & Einkommen",
        "rente, ruhestand, pension, altersrente",
    ),
    _l(
        "berufswiedereinstieg",
        "Berufliche Neuorientierung oder Wiedereinstieg",
        "Arbeit & Einkommen",
        "umschulung, weiterbildung, quereinstieg",
    ),
    # --- Familie & Alter
    _l("eltern", "Eltern", "Familie & Alter", "kinder, mutter, vater, familie"),
    _l(
        "schwanger", "Schwanger oder Kinderwunsch", "Familie & Alter", "geburt, hebamme"
    ),
    _l(
        "alleinerziehend",
        "Alleinerziehend",
        "Familie & Alter",
        "alleinerziehende, unterhalt",
    ),
    _l(
        "kita_kinder",
        "Kind in der Kita",
        "Familie & Alter",
        "kindergarten, krippe, hort",
    ),
    _l("schulkinder", "Kind in der Schule", "Familie & Alter", "grundschule, schulweg"),
    _l(
        "jugendlich",
        "Jugendliche:r oder junge:r Erwachsene:r",
        "Familie & Alter",
        "jugend, teenager",
    ),
    _l(
        "pflegende_angehoerige",
        "Pflegt Angehörige",
        "Familie & Alter",
        "pflege zuhause, pflegegeld",
    ),
    _l("senioren", "Ältere Menschen", "Familie & Alter", "senior, alter, altenpflege"),
    # --- Gesundheit
    _l(
        "chronisch_krank",
        "Chronisch krank",
        "Gesundheit",
        "krankheit, diabetes, krebs, dauerhaft",
        private=True,
    ),
    _l(
        "psychisch_belastet",
        "Psychische Erkrankung oder Belastung",
        "Gesundheit",
        "depression, therapie, burnout, psychotherapie",
        private=True,
    ),
    _l(
        "behinderung",
        "Mensch mit Behinderung",
        "Gesundheit",
        "schwerbehindert, barrierefrei, rollstuhl, inklusion",
        private=True,
    ),
    _l(
        "pflegebeduerftig",
        "Pflegebedürftig",
        "Gesundheit",
        "pflegegrad, pflegeheim, pflege",
        private=True,
    ),
    _l(
        "suchterfahrung",
        "Suchterkrankung oder -erfahrung",
        "Gesundheit",
        "sucht, alkohol, drogen, cannabis",
        private=True,
    ),
    _l(
        "neurodivers",
        "Neurodivergent (z. B. ADHS, Autismus)",
        "Gesundheit",
        "adhs, autismus, legasthenie",
        private=True,
    ),
    # --- Identität & Herkunft
    _l(
        "lgbtq",
        "LGBTQ+",
        "Identität & Herkunft",
        "queer, schwul, lesbisch, bi, trans, intersexuell, nichtbinär, csd",
        private=True,
    ),
    _l(
        "frauen",
        "Frauen und Gleichstellung",
        "Identität & Herkunft",
        "gleichberechtigung, frauenrechte, gewalt gegen frauen",
    ),
    _l(
        "migrationshintergrund",
        "Migrationshintergrund oder eingewandert",
        "Identität & Herkunft",
        "zuwanderung, ausländer, einwanderung, integration",
        private=True,
    ),
    _l(
        "gefluechtet",
        "Geflüchtet oder im Asylverfahren",
        "Identität & Herkunft",
        "flucht, asyl, geduldet, ukraine, aufenthalt",
        private=True,
    ),
    _l(
        "rassismuserfahrung",
        "Von Rassismus oder Diskriminierung betroffen",
        "Identität & Herkunft",
        "diskriminierung, rassismus, antisemitismus",
        private=True,
    ),
    _l(
        "religioes",
        "Religiös oder Mitglied einer Glaubensgemeinschaft",
        "Identität & Herkunft",
        "kirche, moschee, synagoge, glaube, religion",
        private=True,
    ),
    _l(
        "sorbisch",
        "Sorbisch / Minderheit in Sachsen",
        "Identität & Herkunft",
        "sorben, minderheit, sinti, roma",
        private=True,
    ),
    _l(
        "ostdeutsch",
        "Ostdeutsche Biografie",
        "Identität & Herkunft",
        "ddr, wende, ostdeutschland, osten",
    ),
    # --- Mobilität
    _l(
        "oepnv",
        "Nutzt Bus und Bahn",
        "Mobilität",
        "öpnv, straßenbahn, deutschlandticket",
    ),
    _l("autofahrer", "Fährt Auto", "Mobilität", "pkw, parken, tempolimit, sprit"),
    _l("radfahrer", "Fährt Rad", "Mobilität", "fahrrad, radweg, e-bike, lastenrad"),
    _l(
        "zu_fuss",
        "Viel zu Fuß unterwegs",
        "Mobilität",
        "fußgänger, gehweg, zebrastreifen",
    ),
    _l("pendler", "Pendelt zur Arbeit", "Mobilität", "pendeln, entfernungspauschale"),
    _l("motorrad", "Fährt Motorrad", "Mobilität", "motorradfahrer, roller"),
    # --- Alltag & Engagement
    _l(
        "ehrenamt",
        "Engagiert sich ehrenamtlich",
        "Alltag & Engagement",
        "freiwillig, verein",
    ),
    _l(
        "sport_verein",
        "Sport und Vereinsleben",
        "Alltag & Engagement",
        "sportverein, fitness, schwimmbad, sportplatz",
    ),
    _l("haustiere", "Hat Haustiere", "Alltag & Engagement", "hund, katze, tierschutz"),
    _l(
        "garten",
        "Garten oder Kleingarten",
        "Alltag & Engagement",
        "kleingarten, schrebergarten, balkon",
    ),
    _l(
        "kultur",
        "Kultur und Freizeit",
        "Alltag & Engagement",
        "theater, musik, kino, museum",
    ),
    _l(
        "digital_aktiv",
        "Viel online und digital aktiv",
        "Alltag & Engagement",
        "internet, social media, datenschutz, gaming",
    ),
    _l(
        "nachbarschaft",
        "Engagiert im Viertel",
        "Alltag & Engagement",
        "stadtteil, nachbarschaft, quartier, bürgerinitiative",
    ),
    # --- Beruf (Berufsbereiche in Alltagssprache)
    _l(
        "beruf_pflege",
        "Pflege und Betreuung",
        "Beruf",
        "krankenpflege, altenpflege, pflegekraft",
    ),
    _l(
        "beruf_medizin",
        "Ärzt:in und Medizin",
        "Beruf",
        "arzt, ärztin, klinik, krankenhaus, praxis",
    ),
    _l(
        "beruf_heilberufe",
        "Therapie und Heilberufe",
        "Beruf",
        "physiotherapie, ergotherapie, logopädie, hebamme",
    ),
    _l("beruf_apotheke", "Apotheke und Pharma", "Beruf", "apotheker, pharmazie"),
    _l(
        "beruf_kita",
        "Erziehung und Kita",
        "Beruf",
        "erzieherin, erzieher, kindergarten, kita, tagespflege",
    ),
    _l(
        "beruf_schule",
        "Lehrkraft an Schulen",
        "Beruf",
        "lehrer, lehrerin, schule, referendar",
    ),
    _l(
        "beruf_hochschule",
        "Hochschule und Forschung",
        "Beruf",
        "professor, wissenschaft, uni, doktorand",
    ),
    _l(
        "beruf_soziales",
        "Soziale Arbeit",
        "Beruf",
        "sozialarbeiter, jugendhilfe, beratung",
    ),
    _l(
        "beruf_verwaltung",
        "Verwaltung und öffentlicher Dienst",
        "Beruf",
        "amt, behörde, sachbearbeiter, rathaus",
    ),
    _l(
        "beruf_buero",
        "Büro und kaufmännische Berufe",
        "Beruf",
        "büro, sekretariat, buchhaltung, bürokauffrau",
    ),
    _l(
        "beruf_finanzen",
        "Bank, Versicherung und Steuern",
        "Beruf",
        "bank, versicherung, steuerberater, finanzen",
    ),
    _l("beruf_recht", "Recht und Justiz", "Beruf", "jurist, anwalt, richter, notar"),
    _l(
        "beruf_it",
        "IT und Softwareentwicklung",
        "Beruf",
        "programmierer, entwickler, informatik, admin",
    ),
    _l(
        "beruf_technik",
        "Ingenieur:in und Technik",
        "Beruf",
        "ingenieur, techniker, konstruktion, maschinenbau",
    ),
    _l(
        "beruf_handwerk",
        "Handwerk (Bau, Elektro, Metall, Holz)",
        "Beruf",
        "tischler, elektriker, maurer, dachdecker, klempner, installateur",
    ),
    _l(
        "beruf_kfz",
        "Kfz und Fahrzeugtechnik",
        "Beruf",
        "mechatroniker, werkstatt, automobil, autowerkstatt",
    ),
    _l(
        "beruf_bau",
        "Bau und Architektur",
        "Beruf",
        "architekt, bauleiter, tiefbau, hochbau, stadtplaner",
    ),
    _l(
        "beruf_produktion",
        "Industrie und Produktion",
        "Beruf",
        "fabrik, fertigung, schichtarbeit, werk, chipfabrik",
    ),
    _l(
        "beruf_chemie",
        "Chemie, Labor und Naturwissenschaft",
        "Beruf",
        "chemiker, labor, biologe, physiker",
    ),
    _l(
        "beruf_logistik",
        "Logistik, Lager und Paketdienst",
        "Beruf",
        "lager, spedition, paketbote, zusteller, post",
    ),
    _l(
        "beruf_fahrer",
        "Berufskraftfahrer:in und Bus/Bahn",
        "Beruf",
        "lkw, busfahrer, bahnfahrer, taxi, lokführer",
    ),
    _l(
        "beruf_handel",
        "Verkauf und Einzelhandel",
        "Beruf",
        "verkäufer, supermarkt, kasse, einzelhandel",
    ),
    _l(
        "beruf_gastro",
        "Gastronomie und Hotel",
        "Beruf",
        "koch, kellner, restaurant, hotel, küche",
    ),
    _l(
        "beruf_tourismus",
        "Tourismus und Reisen",
        "Beruf",
        "reisebüro, stadtführer, urlaub",
    ),
    _l(
        "beruf_lebensmittel",
        "Lebensmittelherstellung",
        "Beruf",
        "bäcker, fleischer, metzger, konditor, brauerei",
    ),
    _l(
        "beruf_landwirtschaft",
        "Landwirtschaft und Gartenbau",
        "Beruf",
        "landwirt, bauer, gärtner, ackerbau, weinbau",
    ),
    _l(
        "beruf_forst",
        "Forst und Naturschutz",
        "Beruf",
        "förster, wald, ranger, landschaftspflege",
    ),
    _l(
        "beruf_energie",
        "Energie, Wasser und Umwelttechnik",
        "Beruf",
        "stadtwerke, solar, windkraft, klärwerk",
    ),
    _l(
        "beruf_entsorgung",
        "Reinigung und Entsorgung",
        "Beruf",
        "gebäudereinigung, müllabfuhr, stadtreinigung, hausmeister",
    ),
    _l(
        "beruf_hauswirtschaft",
        "Hauswirtschaft und Haushaltshilfe",
        "Beruf",
        "haushaltshilfe, putzkraft, alltagsbegleiter",
    ),
    _l(
        "beruf_koerperpflege",
        "Friseur und Kosmetik",
        "Beruf",
        "friseurin, barber, kosmetikerin, nagelstudio",
    ),
    _l(
        "beruf_sicherheit",
        "Polizei, Bundeswehr und Sicherheitsdienst",
        "Beruf",
        "polizist, soldat, wachdienst, zoll",
    ),
    _l(
        "beruf_rettung",
        "Feuerwehr und Rettungsdienst",
        "Beruf",
        "feuerwehrmann, sanitäter, notfall, rettungssanitäter",
    ),
    _l(
        "beruf_medien",
        "Medien, Journalismus und PR",
        "Beruf",
        "journalist, redakteur, pr, kommunikation, social media manager",
    ),
    _l(
        "beruf_kunst",
        "Kunst, Kultur und Design",
        "Beruf",
        "künstler, musiker, schauspieler, designer, fotograf, kreativ",
    ),
    _l(
        "beruf_marketing",
        "Marketing, Vertrieb und Beratung",
        "Beruf",
        "werbung, consulting, unternehmensberatung, sales",
    ),
    _l(
        "beruf_personal",
        "Personal und Weiterbildung",
        "Beruf",
        "hr, recruiting, trainer",
    ),
    _l(
        "beruf_tier",
        "Tiermedizin und Tierpflege",
        "Beruf",
        "tierarzt, tierpfleger, zoo, tierheim",
    ),
    _l(
        "beruf_sport",
        "Sport und Fitness als Beruf",
        "Beruf",
        "trainer, fitnesstrainer, sportlehrer, profisport",
    ),
)

LEBENSLAGEN_BY_ID: dict[str, Lebenslage] = {item.id: item for item in LEBENSLAGEN}
