# Known platforms

Check these in order for each new level. Each line: what it is, how to check it, what it needs in the place file. Findings from earlier places are in their place files' docstrings (`places/defs/*.py`); read them first, they often settle a platform for the whole Land.

## Kommune

- **OParl** (council papers and decisions; also council members and Fraktionen). Check `https://github.com/OParl/resources/blob/main/endpoints.yml` for the city, then try `<ratsinfo host>/oparl/system` or `/oparl/v1.0/system`. Needs `oparl=OParlBody(...)` with the body URL, the regexes for council, committees and neighbourhood bodies (names differ per Land: Ortschaftsrat, Ortsbeirat, Bezirksvertretung, BVV, Bezirksausschuss) and the link template for papers. The Ratsinformationssystem's own HTML (SessionNet, ALLRIS) is usually robots-blocked; OParl is the official route. No OParl: council decisions are a gap, not a scraper.
- **openPetition region page** `https://www.openpetition.de/region/petition/<Name>`: exists for most towns; check it lists running petitions, not only ended ones. Needs `openpetition_path`.
- **The Land's participation portal** (see Land below): the town is covered if the portal lists its authority. Note the exact authority name ("Mandant") it uses; set `portal_names` when it differs from the place name, and make sure it does not also match the Landkreis.
- **Wikidata districts**: items with P31 Ortsteil (`Q253019`) and P131 = the town. Needs `wikidata_id` and `district_types`. Few or none is fine for small towns.
- **The town's own Bekanntmachungen / Bauleitplanung pages and Amtsblatt**: record them in the docstring as known but unread. No shared adapter reads them yet; a generic Amtsblatt reader is a separate decision for the user.

## Landkreis

- **Kreistag OParl**: as for the Kommune.
- **openPetition region page** for the Kreis.
- **The Land's portal**: the Landratsamt's authority name.

## Land

- **Beteiligungsportal** on the shared software (Jakarta Faces, `/portal/<mandant>/beteiligung/themen`, "x - y von N" paginator, page size 10): confirmed for Sachsen (`buergerbeteiligung.sachsen.de`) and Sachsen-Anhalt (`beteiligung.sachsen-anhalt.de`). Read by `sources/sachsen_beteiligung.py`. Needs `portal_land_markers`: substrings of the Land's own authority names (Staatsministerium, Ministerium, Landesamt, Landesverwaltungsamt ...).
- **openPetition region page** for the Land.
- **Landtag**: agendas and Drucksachen. Dokumentationssysteme (PADOKA, EDAS ...) are often robots-blocked; agenda PDFs on the main site sometimes are not. No shared adapter yet: record as known.
- **Wahlkreise / MdL**: abgeordnetenwatch API (`https://www.abgeordnetenwatch.de/api/v2`) has every Landtag; record whether the current term is there. Not wired yet.

## Bund and EU

Already covered (`bund.py`, `eu.py`): openPetition Deutschland, WeAct, EU "Have your say". Nothing to add per place.

## Checked and not usable

- Bundestag ePetitionen: list needs a JS session token.
- Ratsinformationssystem HTML (SessionNet `si0040.asp`, ALLRIS): robots-blocked in every case seen so far (Dresden, Wittenberg town).
- Overpass/OSM public endpoints for districts: overloaded, discourage automated use. Wikidata instead.
