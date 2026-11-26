"""Lutherstadt Wittenberg (Kreisstadt). Checked 2026-11-25 (add-city pilot).

Found:
- Beteiligungsportal Sachsen-Anhalt, authority "Lutherstadt Wittenberg"
  (0 items on 2026-11-25; its own portal /portal/wittenberg/ shows 0 too).
- Wikidata: 29 Ortsteile (P131 = Q6837). The place table knows the town
  as "Wittenberg".

Rejected:
- openPetition: its region "Wittenberg" is the Landkreis (see
  lk_wittenberg.py); no page for the town itself.

Blocked:
- Ratsinformationssystem (ratsinfo.wittenberg.de, SessionNet): robots.txt
  Disallow: /, no OParl. Permission letter drafted 2026-11-25, not sent.

Known, no adapter: the town's Öffentlichkeitsbeteiligung and Bauleitplanung
pages on wittenberg.de, the Amtsblatt "Die Neue Brücke". Council office
for letters: ratsangelegenheiten@stadtrat.wittenberg.de (no Fraktion
addresses in the council system).
"""

from meinimpact.places.model import Level, Place

ORTSTEIL = "Q253019"

PLACE = Place(
    key="wittenberg",
    name="Wittenberg",
    level=Level.KOMMUNE,
    ags="15091375",
    parent="lk-wittenberg",
    wikidata_id="Q6837",
    district_types=(ORTSTEIL,),
    portal_names=("Lutherstadt Wittenberg",),
)
