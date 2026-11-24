"""Every place the app covers: one module per place under `defs/`.

Adding a place means adding its module there (a `PLACE = Place(...)`);
sources, coverage, districts and council sync all read from here. The
registry checks the declarations when it loads, so a broken place file
fails at import, not in production.
"""

import importlib
import pkgutil
from collections.abc import Iterable

from meinimpact.places import defs
from meinimpact.places.model import Level, Place, Status

__all__ = [
    "ALL",
    "LIVE",
    "LIVE_KEYS",
    "Level",
    "Place",
    "PlaceConfigError",
    "Status",
    "ags_of",
    "by_key",
    "chain",
    "depth_of",
    "validate",
]


class PlaceConfigError(ValueError):
    """A place declaration contradicts another one."""


def _discover() -> tuple[Place, ...]:
    found = []
    for module in pkgutil.iter_modules(defs.__path__):
        place = importlib.import_module(f"{defs.__name__}.{module.name}").PLACE
        if not isinstance(place, Place):
            raise PlaceConfigError(f"{module.name}: PLACE is no Place")
        found.append(place)
    return tuple(sorted(found, key=lambda p: (p.depth, p.key)))


def validate(places: Iterable[Place]) -> None:
    """Keys unique, parents declared and wider, AGS inside the parent's."""
    keyed: dict[str, Place] = {}
    for place in places:
        if place.key in keyed:
            raise PlaceConfigError(f"duplicate place key {place.key!r}")
        keyed[place.key] = place
    for place in keyed.values():
        if place.parent is None:
            if place.level is not Level.EU:
                raise PlaceConfigError(f"{place.key}: only the EU has no parent")
            continue
        parent = keyed.get(place.parent)
        if parent is None:
            raise PlaceConfigError(f"{place.key}: parent {place.parent!r} missing")
        if parent.depth >= place.depth:
            raise PlaceConfigError(f"{place.key}: parent {parent.key} is not wider")
        if not place.ags.startswith(parent.ags):
            raise PlaceConfigError(f"{place.key}: AGS outside {parent.key}'s")
        if place.oparl and place.oparl.region != place.key:
            raise PlaceConfigError(f"{place.key}: OParl body is for another place")
        if place.is_live and not parent.is_live:
            raise PlaceConfigError(f"{place.key}: live, but {parent.key} is a draft")


ALL: tuple[Place, ...] = _discover()
validate(ALL)
_BY_KEY = {place.key: place for place in ALL}
# What the app serves and counts as coverage
LIVE: tuple[Place, ...] = tuple(place for place in ALL if place.is_live)
LIVE_KEYS: tuple[str, ...] = tuple(place.key for place in LIVE)


def by_key(key: str) -> Place | None:
    return _BY_KEY.get(key)


def chain(key: str | None) -> tuple[Place, ...]:
    """The place and every wider one it belongs to, most specific first;
    empty for none or an unknown key."""
    found: list[Place] = []
    place = _BY_KEY.get(key) if key else None
    while place is not None:
        found.append(place)
        place = _BY_KEY.get(place.parent) if place.parent else None
    return tuple(found)


def ags_of(key: str) -> str | None:
    """The place's AGS ("" for Bund and EU); None for an unknown key."""
    place = _BY_KEY.get(key)
    return place.ags if place else None


def depth_of(key: str | None) -> int:
    """How specific a region is; -1 for none or an unknown one."""
    place = _BY_KEY.get(key) if key else None
    return place.depth if place else -1
