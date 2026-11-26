"""Land Sachsen-Anhalt. Checked 2026-11-25 (add-city pilot).

Found:
- Beteiligungsportal (beteiligung.sachsen-anhalt.de, mandant "hauptportal"):
  same software as Sachsen's, no robots.txt; 139 items (events, surveys,
  Bauleitpläne, consultations). The Land's own authorities appear as
  Ministerium ..., Landesamt ..., Landesverwaltungsamt, Amt für
  Landwirtschaft ..., and state companies named "... Sachsen-Anhalt".
- openPetition /region/petition/Sachsen-Anhalt: 12 running.
- abgeordnetenwatch: parliament 8, term 2026-2031 present (MdL, not wired).

Blocked:
- Landtag PADOKA (padoka.landtag.sachsen-anhalt.de): robots Disallow: /.
  Agenda PDFs on www.landtag.sachsen-anhalt.de are allowed; no adapter yet.
"""

from meinimpact.infrastructure.listings.sources.sachsen_beteiligung import PortalSite
from meinimpact.places.model import Level, Place

PLACE = Place(
    key="sachsen-anhalt",
    name="Sachsen-Anhalt",
    level=Level.LAND,
    ags="15",
    parent="bund",
    openpetition_path="/region/petition/Sachsen-Anhalt",
    portal=PortalSite(
        source_id="beteiligung-sachsen-anhalt",
        base_url="https://beteiligung.sachsen-anhalt.de",
        mandant="hauptportal",
        name="Beteiligungsportal Sachsen-Anhalt",
    ),
    portal_land_markers=(
        "Ministerium",
        "Landesamt",
        "Landesverwaltungsamt",
        "Amt für Landwirtschaft",
        "Sachsen-Anhalt",
    ),
)
