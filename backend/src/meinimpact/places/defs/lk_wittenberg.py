"""Landkreis Wittenberg. Checked 2026-11-25 (add-city pilot).

Found:
- Beteiligungsportal Sachsen-Anhalt, authority "Landkreis Wittenberg"
  (1 item on 2026-11-25).
- openPetition /region/petition/Wittenberg: openPetition's regions are
  Kreise and kreisfreie Städte, so this is the Kreis (0 running on
  2026-11-25; kept, it costs one request per run).

Rejected:
- openPetition /region/petition/Landkreis-Wittenberg: 404.

Blocked:
- Kreistag (sitzungsdienst.landkreis-wittenberg.de, SessionNet): no OParl
  (/bi/oparl/1.0/system.asp 404); robots.txt answered 503 twice, so treated
  as disallowed. Permission letter drafted 2026-11-25, not sent yet.
"""

from meinimpact.places.model import Level, Place

PLACE = Place(
    key="lk-wittenberg",
    name="Landkreis Wittenberg",
    level=Level.KREIS,
    ags="15091",
    parent="sachsen-anhalt",
    openpetition_path="/region/petition/Wittenberg",
    portal_names=("Landkreis Wittenberg",),
)
