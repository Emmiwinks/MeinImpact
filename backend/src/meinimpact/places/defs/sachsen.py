"""Freistaat Sachsen. Sources: openPetition Sachsen, Beteiligungsportal
Sachsen (buergerbeteiligung.sachsen.de, page size fixed at 10).

Blocked: Landtag Sitzungskalender (robots.txt disallows
/de/aktuelles/sitzungskalender); no permission asked yet.
"""

from meinimpact.places.model import Level, Place

PLACE = Place(
    key="sachsen",
    name="Sachsen",
    level=Level.LAND,
    ags="14",
    parent="bund",
    openpetition_path="/region/petition/Sachsen",
    portal_land_markers=(
        "Staatsministerium",
        "Staatskanzlei",
        "Landesdirektion",
        "Landesamt",
        "Sächsische Staats",
        "Sächsisches",
        "Freistaat Sachsen",
    ),
)
