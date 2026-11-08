"""Fraktion office addresses, maintained by hand.

Letters about council decisions go to the offices of the Fraktionen whose
members sit on the deciding or preparing body, never to personal addresses
(decided 2026-11-08: OParl rarely carries them, and one address per Fraktion
treats every party the same). Keys are OParl organization URLs, so a renamed
Fraktion keeps working while OParl keeps its id. A Fraktion missing here
shows in the app without an address; the member sync logs it.

Verified 2026-11-08.
"""

_DRESDEN = "https://oparl.dresden.de/bodies/0001/organizations/gr/"

FRAKTION_OFFICES: dict[str, str] = {
    # dresden.de Fraktion pages (rathaus/politik/stadtrat/fraktionen/*.php)
    _DRESDEN + "5": "cdu-fraktion@dresden.de",
    _DRESDEN + "30": "gruene-fraktion@dresden.de",
    _DRESDEN + "32": "spd-fraktion@dresden.de",
    _DRESDEN + "121": "fdp-fb-fraktion@dresden.de",
    # BSW Fraktion; OParl lists it again under the party's new name from
    # 2026-10-12, same office
    _DRESDEN + "205": "bsw-fraktion@dresden.de",
    _DRESDEN + "217": "bsw-fraktion@dresden.de",
    # Imprint of a 2025 Fraktion publication (afd-fraktion-dresden.de)
    _DRESDEN + "120": "afd-fraktion@dresden.de",
    # linke-fraktion-dresden.de contact block
    _DRESDEN + "33": "linke-fraktion@dresden.de",
    # team-zastrow.de: no Fraktion address, the party contact (Rathaus phone)
    _DRESDEN + "212": "kontakt@team-zastrow.de",
    # Provided by the user
    _DRESDEN + "209": "post@pvp-kooperation.de",
}
