"""District reference data and the matcher that finds districts in text.

A city is one `CityConfig`; its districts are loaded from the committed
data file. `DistrictMatcher` is deterministic and case-sensitive (district
names are proper nouns): it finds "Dresden-Mockritz" and a bare "Mockritz",
prefers the longest name ("Südvorstadt-Ost" over "Südvorstadt") and never
guesses from inflected or embedded forms ("Plauener Straße").
"""

import json
import re
from collections.abc import Sequence
from dataclasses import dataclass
from pathlib import Path

DATA_DIR = Path(__file__).parent / "data"

_LETTER = r"[\wÄÖÜäöüß]"


@dataclass(frozen=True, slots=True)
class CityConfig:
    key: str  # data file name, e.g. "dresden"
    name: str  # as used in compounds like "Dresden-Mockritz"
    wikidata_id: str
    # Wikidata classes whose instances located in the city count as districts
    district_types: tuple[str, ...]


@dataclass(frozen=True, slots=True)
class District:
    name: str
    wikidata_id: str


ORTSTEIL = "Q253019"

CITIES: dict[str, CityConfig] = {
    "dresden": CityConfig(
        key="dresden",
        name="Dresden",
        wikidata_id="Q1731",
        district_types=(ORTSTEIL,),
    ),
}


def data_file(city: CityConfig) -> Path:
    return DATA_DIR / f"{city.key}.json"


def load_districts(city: CityConfig) -> list[District]:
    raw = json.loads(data_file(city).read_text(encoding="utf-8"))
    return [District(d["name"], d["wikidata_id"]) for d in raw["districts"]]


class DistrictMatcher:
    def __init__(self, city_name: str, districts: Sequence[District]) -> None:
        names = sorted({d.name for d in districts}, key=len, reverse=True)
        alternation = "|".join(re.escape(name) for name in names)
        self._pattern = re.compile(
            rf"(?<!{_LETTER}|-)(?:{re.escape(city_name)}-)?({alternation})(?!{_LETTER})"
        )

    @classmethod
    def for_city(cls, city: CityConfig) -> DistrictMatcher:
        return cls(city.name, load_districts(city))

    def find(self, text: str) -> tuple[str, ...]:
        """Districts named in `text`, unique, in order of first mention."""
        return tuple(dict.fromkeys(m.group(1) for m in self._pattern.finditer(text)))
