"""Bund. Sources: openPetition Deutschland, WeAct (all of it).

Checked and not used: Bundestag ePetitionen (list needs a JS session
token), Bundestag agendas (PDF only; DIP API is the other route).
"""

from meinimpact.places.model import Level, Place, Status

PLACE = Place(
    key="bund",
    name="Deutschland",
    level=Level.BUND,
    ags="",
    parent="eu",
    status=Status.LIVE,
    openpetition_path="/region/petition/Deutschland",
)
