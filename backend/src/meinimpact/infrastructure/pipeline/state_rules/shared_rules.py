"""Rules identical across both pipelines.

Kept in one place instead of duplicated in `parliamentary_rules.py` and
`petition_rules.py`, since the spec defines this exact trigger the same way
for a Bundestag petition regardless of which pipeline surfaced it.
"""

from meinimpact.infrastructure.pipeline.state_rules.protocol import (
    RuleContext,
    RuleResult,
)

_QUORUM_TARGET = 50_000
_QUORUM_NEAR_THRESHOLD = 40_000


class PetitionNearQuorumRule:
    """State A: a Bundestag petition is close to the 50,000-signature quorum."""

    name = "petition_near_quorum"

    def evaluate(self, context: RuleContext) -> RuleResult | None:
        if context.item.get("type") != "petition":
            return None
        count = context.item.get("signature_count")
        if count is None or count <= _QUORUM_NEAR_THRESHOLD:
            return None
        return RuleResult(
            state="A",
            reason=f"Petition kurz vor dem Quorum: {count} von {_QUORUM_TARGET}",
            rule_name=self.name,
            evidence={"signature_count": count, "quorum_target": _QUORUM_TARGET},
        )
