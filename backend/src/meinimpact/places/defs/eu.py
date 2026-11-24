"""EU. Sources: EU Commission "Have your say" (all of it, no place config)."""

from meinimpact.places.model import Level, Place, Status

PLACE = Place(
    key="eu", name="EU", level=Level.EU, ags="", parent=None, status=Status.LIVE
)
