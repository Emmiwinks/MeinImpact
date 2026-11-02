"""The Lebenslagen catalog stays consistent, because ids are matched
verbatim between the enrichment output and the app's stored profile."""

import re

from meinimpact.infrastructure.ai.lebenslagen import (
    AREAS,
    LEBENSLAGEN,
    LEBENSLAGEN_BY_ID,
)


def test_ids_are_unique_ascii_snake_case() -> None:
    ids = [item.id for item in LEBENSLAGEN]

    assert len(ids) == len(set(ids)) == len(LEBENSLAGEN_BY_ID)
    assert all(re.fullmatch(r"[a-z][a-z0-9_]*", i) for i in ids)


def test_every_entry_has_a_label_and_a_known_area() -> None:
    for item in LEBENSLAGEN:
        assert item.label.strip()
        assert item.area in AREAS


def test_every_area_is_used() -> None:
    assert {item.area for item in LEBENSLAGEN} == set(AREAS)


def test_synonyms_are_lower_case_and_unique_per_entry() -> None:
    for item in LEBENSLAGEN:
        assert all(s == s.lower() for s in item.synonyms), item.id
        assert len(item.synonyms) == len(set(item.synonyms)), item.id


def test_special_category_groups_are_marked_private() -> None:
    for private_id in ("lgbtq", "behinderung", "religioes", "gefluechtet"):
        assert LEBENSLAGEN_BY_ID[private_id].private


def test_occupations_are_never_private() -> None:
    assert not any(i.private for i in LEBENSLAGEN if i.area == "Beruf")
