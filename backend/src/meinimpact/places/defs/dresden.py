"""Landeshauptstadt Dresden (kreisfrei). Sources: OParl (council papers),
openPetition Dresden, Beteiligungsportal Sachsen (authority "Dresden").

Blocked: ratsinfo.dresden.de (robots.txt Disallow: /); OParl is the
official route instead. Letters: Fraktion offices in council/offices.py
(hand-kept, verified 2026-11-08; to be replaced by a sync).
"""

from meinimpact.infrastructure.listings.sources.oparl import OParlBody
from meinimpact.places.model import Level, Place, Status

ORTSTEIL = "Q253019"

COUNCIL = OParlBody(
    source_id="dresden-ratsinfo",
    body_url="https://oparl.dresden.de/bodies/0001",
    region="dresden",
    locality="Dresden",
    paper_web_url="https://ratsinfo.dresden.de/vo0050.asp?__kvonr={number}",
    bodies=(
        r"^Stadtrat$",
        r"^Ausschuss ",
        r"ausschuss$",
        r"^Stadtbezirksbeirat ",
        r"^Ortschaftsrat ",
    ),
    council="Stadtrat",
    committees=(r"^Ausschuss ", r"ausschuss$"),
    neighbourhoods=(
        r"^Stadtbezirksbeirat (?P<area>.+)$",
        r"^Ortschaftsrat (?P<area>.+)$",
    ),
)

PLACE = Place(
    key="dresden",
    name="Dresden",
    level=Level.KOMMUNE,
    ags="14612",
    parent="sachsen",
    status=Status.LIVE,
    wikidata_id="Q1731",
    district_types=(ORTSTEIL,),
    openpetition_path="/region/petition/Dresden",
    oparl=COUNCIL,
)
