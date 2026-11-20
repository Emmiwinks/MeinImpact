"""Bundling opportunities on one matter (`ai/bundler.py`), with a fake model."""

import uuid
from collections.abc import Mapping
from datetime import date
from typing import Any

from meinimpact.infrastructure.ai.bundler import (
    BundleItem,
    Bundler,
    allowed,
    build_describe_prompt,
    build_grouping_prompt,
    bundle_input_hash,
    parse_bundle,
    parse_groups,
)


def _item(n: int, *, kind: str = "petition", **changes: Any) -> BundleItem:
    fields: dict[str, Any] = {
        "id": uuid.UUID(int=n),
        "key": ("src", str(n)),
        "kind": kind,
        "source_org": "openPetition",
        "organizer": None,
        "registry_title": f"Original {n}",
        "title": f"Frage {n}?",
        "summary": f"Text {n}.",
        "closes_on": date(2026, 12, 1),
        "enrichment_input_hash": f"h{n}",
    }
    fields.update(changes)
    return BundleItem(**fields)


class FakeCompleter:
    def __init__(self, *answers: Mapping[str, Any]) -> None:
        self.answers = list(answers)
        self.prompts: list[str] = []

    async def complete_json(self, prompt: str) -> dict[str, Any]:
        self.prompts.append(prompt)
        return dict(self.answers.pop(0))


def test_rules_the_model_cannot_overrule() -> None:
    assert allowed([_item(1), _item(2)])
    assert not allowed([_item(1)])
    assert not allowed([_item(n) for n in range(1, 6)])  # more than 4
    assert not allowed([_item(1), _item(2, kind="consultation")])
    # One budget in two bodies goes to two sets of recipients.
    assert not allowed(
        [
            _item(1, kind="decision", organizer="Jugendhilfeausschuss"),
            _item(2, kind="decision", organizer="Ortschaftsrat Schönborn"),
        ]
    )
    assert allowed(
        [
            _item(1, kind="decision", organizer="Stadtrat"),
            _item(2, kind="decision", organizer="Stadtrat"),
        ]
    )


def test_parse_groups_drops_malformed_and_repeated_members() -> None:
    raw = {"gruppen": [[1, 2], [2, 3], [4], "x", [5, 99, 6]]}

    # 2 is taken by the first group, so [2, 3] keeps only 3 and is dropped.
    assert parse_groups(raw, 6) == [[0, 1], [4, 5]]
    assert parse_groups({}, 6) == []


def test_parse_bundle_keeps_only_the_options_on_one_matter() -> None:
    items = [_item(1), _item(2), _item(3)]
    raw = {
        "zusammen": [1, 3],
        "kopfzeile": "2 Petitionen · ähnliches Gesetz",
        "titel": "Bleibt das Gesetz?",
        "zusammenfassung": "Es geht um ein Gesetz.",
        "optionen": [
            {"nummer": 1, "label": "An den Bundestag", "unterschied": "Will A."},
            {"nummer": 3, "label": "An die SPD", "unterschied": "Will B."},
        ],
    }

    bundle = parse_bundle(raw, items)

    assert bundle is not None
    assert bundle.header == "2 Petitionen · ähnliches Gesetz"
    assert set(bundle.options) == {items[0].id, items[2].id}
    assert bundle.options[items[2].id].difference == "Will B."


def test_parse_bundle_rejects_unsure_or_incomplete_answers() -> None:
    items = [_item(1), _item(2)]
    full = {
        "zusammen": [1, 2],
        "kopfzeile": "k",
        "titel": "t",
        "zusammenfassung": "z",
        "optionen": [
            {"nummer": 1, "label": "a", "unterschied": "x"},
            {"nummer": 2, "label": "b", "unterschied": "y"},
        ],
    }

    assert parse_bundle(full, items) is not None
    assert parse_bundle({**full, "zusammen": []}, items) is None
    assert parse_bundle({**full, "zusammen": [1]}, items) is None
    # Every option needs its difference sentence.
    missing = {**full, "optionen": [full["optionen"][0]]}
    assert parse_bundle(missing, items) is None


async def test_propose_adds_identical_titles_the_list_pass_missed() -> None:
    items = [
        _item(1, title="Darf der Staat Geheimnisse haben?"),
        _item(2),
        _item(3, title="darf der Staat Geheimnisse haben? "),
        _item(4),
        _item(5),
    ]
    completer = FakeCompleter({"gruppen": [[2, 4]]})

    groups = await Bundler(completer).propose_groups(items)

    assert [[i.id.int for i in g] for g in groups] == [[2, 4], [1, 3]]
    assert "Original 3" in completer.prompts[0]


async def test_describe_sends_full_texts_and_registry_titles() -> None:
    items = [_item(1), _item(2)]
    completer = FakeCompleter({"zusammen": []})

    assert await Bundler(completer).describe(items, ["Volltext eins", None]) is None
    prompt = completer.prompts[0]
    assert "Volltext eins" in prompt and "(kein weiterer Text)" in prompt
    assert "Originaltitel: Original 2" in prompt


def test_input_hash_follows_members_and_their_texts() -> None:
    one, two = _item(1), _item(2)

    assert bundle_input_hash([one, two]) == bundle_input_hash([two, one])
    assert bundle_input_hash([one, two]) != bundle_input_hash(
        [one, _item(2, enrichment_input_hash="changed")]
    )


def test_prompts_list_every_item() -> None:
    items = [_item(1), _item(2)]
    assert "1. [petition" in build_grouping_prompt(items)
    assert "OPTION 2" in build_describe_prompt(items, [None, None])
