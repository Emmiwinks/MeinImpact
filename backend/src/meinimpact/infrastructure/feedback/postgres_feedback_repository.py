"""Beta feedback in Postgres: card reasons and free-text messages.

Each reason points at one ranking knob: `too_far` at LocalityConfig,
`not_interested` at the interest weights, `not_affected` at the Lebenslagen
match, `too_much_effort` at appeal, `unclear_text` at the enrichment prompts,
`dont_support` at the Werte match. `already_done` and `other` are read by
hand.
"""

import uuid
from collections import Counter
from dataclasses import dataclass, field
from datetime import date
from typing import Any, Literal

from sqlalchemy import delete, func, select, update
from sqlalchemy.ext.asyncio import AsyncSession

from meinimpact.infrastructure.models import (
    BetaFeedbackRecord,
    CardFeedbackRecord,
    OpportunityRecord,
)

CardReason = Literal[
    "too_far",
    "not_interested",
    "not_affected",
    "too_much_effort",
    "unclear_text",
    "dont_support",
    "already_done",
    "other",
]
MessageKind = Literal["bug", "idea", "praise", "other"]


@dataclass(frozen=True)
class CardFeedback:
    tester: str
    day: date
    opportunity_id: uuid.UUID
    reason: CardReason
    note: str | None
    ranking: dict[str, float | int | bool]
    app_version: str


@dataclass(frozen=True)
class Message:
    tester: str
    day: date
    kind: MessageKind
    message: str
    screen: str | None
    app_version: str
    platform: str


@dataclass(frozen=True)
class ReasonCounts:
    # reason -> the card's reach (geo/locality.py Reach; None if unknown or
    # the card is gone) -> how often
    by_reach: dict[str, dict[str | None, int]]
    # reason -> how many different testers gave it
    testers: dict[str, int]


@dataclass(frozen=True)
class DismissedCard:
    opportunity_id: uuid.UUID
    title: str
    source_url: str
    count: int
    testers: int
    reasons: dict[str, int] = field(default_factory=dict)


@dataclass(frozen=True)
class CardNote:
    day: date
    tester: str
    reason: str
    note: str
    title: str | None


@dataclass(frozen=True)
class StoredMessage:
    id: uuid.UUID
    day: date
    tester: str
    kind: str
    message: str
    screen: str | None
    app_version: str
    platform: str
    handled: bool


# Opportunity fields the export carries next to each reason
_EXPORT_FIELDS = (
    "source_id",
    "kind",
    "region",
    "reach",
    "free_topic",
    "lebenslagen",
    "everyday_relevance",
    "accessibility",
)


class PostgresFeedbackRepository:
    def __init__(self, session: AsyncSession) -> None:
        self._session = session

    async def commit(self) -> None:
        await self._session.commit()

    async def add_card(self, feedback: CardFeedback) -> None:
        # The hash of the text the tester saw; an unknown id is kept without
        # a link, so a card deleted meanwhile still counts
        card = (
            await self._session.execute(
                select(
                    OpportunityRecord.id, OpportunityRecord.enrichment_input_hash
                ).where(OpportunityRecord.id == feedback.opportunity_id)
            )
        ).first()
        self._session.add(
            CardFeedbackRecord(
                created_on=feedback.day,
                tester=feedback.tester,
                opportunity_id=card[0] if card else None,
                enrichment_input_hash=card[1] if card else None,
                reason=feedback.reason,
                note=feedback.note,
                ranking=feedback.ranking,
                app_version=feedback.app_version,
            )
        )

    async def add_message(self, message: Message) -> None:
        self._session.add(
            BetaFeedbackRecord(
                created_on=message.day,
                tester=message.tester,
                kind=message.kind,
                message=message.message,
                screen=message.screen,
                app_version=message.app_version,
                platform=message.platform,
            )
        )

    async def prune(self, before: date) -> int:
        """Deletes everything from days before [before]; returns how many."""
        removed = 0
        for table in (CardFeedbackRecord, BetaFeedbackRecord):
            result = await self._session.execute(
                delete(table).where(table.created_on < before)
            )
            removed += getattr(result, "rowcount", 0) or 0
        return removed

    async def reason_counts(self, since: date) -> ReasonCounts:
        by_reach: dict[str, dict[str | None, int]] = {}
        rows = await self._session.execute(
            select(CardFeedbackRecord.reason, OpportunityRecord.reach, func.count())
            .outerjoin(
                OpportunityRecord,
                OpportunityRecord.id == CardFeedbackRecord.opportunity_id,
            )
            .where(CardFeedbackRecord.created_on >= since)
            .group_by(CardFeedbackRecord.reason, OpportunityRecord.reach)
        )
        for reason, reach, count in rows.all():
            by_reach.setdefault(reason, {})[reach] = count
        testers = await self._session.execute(
            select(
                CardFeedbackRecord.reason,
                func.count(func.distinct(CardFeedbackRecord.tester)),
            )
            .where(CardFeedbackRecord.created_on >= since)
            .group_by(CardFeedbackRecord.reason)
        )
        return ReasonCounts(
            by_reach=by_reach,
            testers={reason: count for reason, count in testers.all()},
        )

    async def most_dismissed(self, since: date, limit: int) -> list[DismissedCard]:
        rows = await self._session.execute(
            select(
                CardFeedbackRecord.opportunity_id,
                CardFeedbackRecord.reason,
                CardFeedbackRecord.tester,
                func.coalesce(
                    OpportunityRecord.bundle_title,
                    OpportunityRecord.title,
                    OpportunityRecord.registry_title,
                ),
                OpportunityRecord.source_url,
            )
            .join(
                OpportunityRecord,
                OpportunityRecord.id == CardFeedbackRecord.opportunity_id,
            )
            .where(CardFeedbackRecord.created_on >= since)
        )
        reasons: dict[uuid.UUID, Counter[str]] = {}
        testers: dict[uuid.UUID, set[str]] = {}
        cards: dict[uuid.UUID, tuple[str, str]] = {}
        for opportunity_id, reason, tester, title, url in rows.all():
            if opportunity_id is None:  # never, after the join; for the types
                continue
            reasons.setdefault(opportunity_id, Counter())[reason] += 1
            testers.setdefault(opportunity_id, set()).add(tester)
            cards[opportunity_id] = (title, url)
        ranked = sorted(
            reasons, key=lambda key: (-reasons[key].total(), -len(testers[key]))
        )
        return [
            DismissedCard(
                opportunity_id=key,
                title=cards[key][0],
                source_url=cards[key][1],
                count=reasons[key].total(),
                testers=len(testers[key]),
                reasons=dict(reasons[key].most_common()),
            )
            for key in ranked[:limit]
        ]

    async def card_notes(self, limit: int) -> list[CardNote]:
        rows = await self._session.execute(
            select(
                CardFeedbackRecord.created_on,
                CardFeedbackRecord.tester,
                CardFeedbackRecord.reason,
                CardFeedbackRecord.note,
                func.coalesce(OpportunityRecord.bundle_title, OpportunityRecord.title),
            )
            .outerjoin(
                OpportunityRecord,
                OpportunityRecord.id == CardFeedbackRecord.opportunity_id,
            )
            .where(CardFeedbackRecord.note.is_not(None))
            .order_by(CardFeedbackRecord.created_on.desc())
            .limit(limit)
        )
        return [
            CardNote(
                day=day, tester=tester, reason=reason, note=note or "", title=title
            )
            for day, tester, reason, note, title in rows.all()
        ]

    async def messages(self, limit: int) -> list[StoredMessage]:
        """Open messages first, each group newest first."""
        rows = await self._session.scalars(
            select(BetaFeedbackRecord)
            .order_by(BetaFeedbackRecord.handled, BetaFeedbackRecord.created_on.desc())
            .limit(limit)
        )
        return [
            StoredMessage(
                id=row.id,
                day=row.created_on,
                tester=row.tester,
                kind=row.kind,
                message=row.message,
                screen=row.screen,
                app_version=row.app_version,
                platform=row.platform,
                handled=row.handled,
            )
            for row in rows.all()
        ]

    async def set_handled(self, message_id: uuid.UUID, handled: bool) -> None:
        await self._session.execute(
            update(BetaFeedbackRecord)
            .where(BetaFeedbackRecord.id == message_id)
            .values(handled=handled)
        )

    async def export_cards(self) -> list[dict[str, Any]]:
        """Every card reason with the opportunity's fields, for calibration."""
        rows = await self._session.execute(
            select(
                CardFeedbackRecord,
                *(getattr(OpportunityRecord, name) for name in _EXPORT_FIELDS),
            )
            .outerjoin(
                OpportunityRecord,
                OpportunityRecord.id == CardFeedbackRecord.opportunity_id,
            )
            .order_by(CardFeedbackRecord.created_on)
        )
        exported = []
        for record, *values in rows.all():
            exported.append(
                {
                    "day": record.created_on.isoformat(),
                    "tester": record.tester,
                    "opportunity_id": str(record.opportunity_id or ""),
                    "enrichment_input_hash": record.enrichment_input_hash or "",
                    "reason": record.reason,
                    "note": record.note or "",
                    "app_version": record.app_version,
                    **{f"ranking_{key}": v for key, v in record.ranking.items()},
                    **dict(zip(_EXPORT_FIELDS, values, strict=True)),
                }
            )
        return exported
