"""Where a named municipality or Kreis lies.

Locates the place names enrichment reads from a text ("Weinböhla",
"Erzgebirgskreis"), from the committed GeoNames table
(`scripts/sync_plz.py`). A name is only located when it is unambiguous
within the area it is looked up in: a wrong place is worse than none.

Names are matched exactly first, then more loosely, since a text writes
"Neustadt (Sachsen)" or "Weißwasser/Oberlausitz" where GeoNames has
"Neustadt in Sachsen" and "Weißwasser".
"""

import json
import re
from collections import defaultdict
from collections.abc import Callable
from pathlib import Path

from meinimpact.infrastructure.geo.plz import Area, PlzIndex, Point

DATA_FILE = Path(__file__).parent / "data" / "places.json"

# A one-PLZ village has a single point; its houses still reach this far.
MIN_PLACE_KM = 2.0

# "Landkreis Görlitz", "Kreisfreie Stadt Dresden", "Chemnitz, Stadt" and
# "Görlitz" name the same kind of thing
_KREIS_AFFIXES = re.compile(r"^(landkreis|kreisfreie stadt|kreis) |, stadt$")
_FILLERS = frozenset({"in", "im", "am", "an", "der", "bei", "ob", "auf"})
# Where the qualifier of "Neustadt/Vogtland", "Neustadt (Sachsen)" or
# "Neustadt in Sachsen" begins
_QUALIFIER = re.compile(r"[/(,]| (?:{}) ".format("|".join(sorted(_FILLERS))))


def _bare(kreis_name: str) -> str:
    return _KREIS_AFFIXES.sub("", kreis_name.casefold()).strip()


def _words(name: str) -> str:
    """ "Neustadt (Sachsen)" and "Neustadt in Sachsen" alike."""
    words = re.findall(r"\w+", name.casefold())
    return " ".join(sorted(w for w in words if w not in _FILLERS))


def _base(name: str) -> str:
    """ "Weißwasser/Oberlausitz" -> "weißwasser"; every Neustadt alike."""
    return _QUALIFIER.split(name.casefold())[0].strip()


class PlaceIndex:
    def __init__(
        self,
        places: dict[str, list[tuple[str, Area]]],
        kreise: dict[str, str],
        plz: PlzIndex,
    ) -> None:
        """`places` maps a name to its (Kreis AGS, area) entries, `kreise`
        a Kreis name to its AGS; Kreis areas come from `plz`."""
        self._places = places
        # Looser keys, tried in this order when the exact name is no place
        self._loose: list[
            tuple[Callable[[str], str], dict[str, list[tuple[str, Area]]]]
        ] = []
        for key in (_words, _base):
            index: dict[str, list[tuple[str, Area]]] = defaultdict(list)
            for name, entries in places.items():
                index[key(name)].extend(entries)
            self._loose.append((key, index))
        self._kreise = kreise
        self._bare_kreise: dict[str, set[str]] = defaultdict(set)
        for name, kreis in kreise.items():
            self._bare_kreise[_bare(name)].add(kreis)
        self._plz = plz

    @classmethod
    def load(cls, plz: PlzIndex, path: Path = DATA_FILE) -> PlaceIndex:
        raw = json.loads(path.read_text(encoding="utf-8"))
        return cls(
            {
                name: [
                    (kreis, Area(Point(lat, lon), km))
                    for kreis, lat, lon, km in entries
                ]
                for name, entries in raw["places"].items()
            },
            raw["kreise"],
            plz,
        )

    def _municipalities(self, name: str, gebiet: str) -> list[tuple[str, Area]]:
        """(Kreis AGS, area) of the municipalities called `name` within
        `gebiet`, from the strictest name match that finds any."""
        candidates = [self._places.get(name, [])] + [
            index.get(key(name), []) for key, index in self._loose
        ]
        for entries in candidates:
            found = [
                (kreis, area) for kreis, area in entries if kreis.startswith(gebiet)
            ]
            if found:
                return found
        return []

    def kreis_of(self, name: str, gebiet: str = "") -> str | None:
        """The Kreis AGS of the one municipality called `name` within
        `gebiet`; None when there is none or more than one.

        A merged municipality the table only knows by its parts
        ("Oranienbaum-Wörlitz" as "Oranienbaum" and "Wörlitz") counts when
        every part lies in the same, single Kreis."""
        found = self._municipalities(name, gebiet)
        if found:
            return found[0][0] if len(found) == 1 else None
        parts = [part.strip() for part in name.split("-") if part.strip()]
        if len(parts) < 2:
            return None
        kreise = {
            kreis for part in parts for kreis, _ in self._municipalities(part, gebiet)
        }
        found_all = all(self._municipalities(part, gebiet) for part in parts)
        return kreise.pop() if found_all and len(kreise) == 1 else None

    def locate(self, name: str, gebiet: str = "") -> Area | None:
        """The area of the municipality, else the Kreis, called `name`
        within `gebiet` (an AGS prefix, "" = all of Germany); None when
        no or more than one place there has that name."""
        municipalities = self._municipalities(name, gebiet)
        if len(municipalities) > 1:
            return None
        if municipalities:
            area = municipalities[0][1]
            return Area(area.centre, max(area.km, MIN_PLACE_KM))
        kreis = self._kreise.get(name)
        if kreis is None:
            kreise = {
                k
                for k in self._bare_kreise.get(_bare(name), ())
                if k.startswith(gebiet)
            }
            kreis = kreise.pop() if len(kreise) == 1 else None
        if kreis is None or not kreis.startswith(gebiet):
            return None
        return self._plz.kreis_area(kreis)
