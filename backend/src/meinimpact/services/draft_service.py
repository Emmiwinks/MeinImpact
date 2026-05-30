"""AI-assisted draft orchestration."""

from collections.abc import AsyncIterator

from meinimpact.domain.entities import CivicAction, UserProfile
from meinimpact.infrastructure.ai.base import AiTextGenerator


class DraftService:
    """Creates neutral prompts and streams generated action drafts."""

    def __init__(self, ai_generator: AiTextGenerator) -> None:
        """Initializes the service with an AI generator."""
        self._ai_generator = ai_generator

    async def stream_draft(
        self,
        action: CivicAction,
        profile: UserProfile,
        personal_context: str | None,
        tone: str,
    ) -> AsyncIterator[str]:
        """Streams a draft for a civic action."""
        prompt = self._build_prompt(
            action=action,
            profile=profile,
            personal_context=personal_context,
            tone=tone,
        )
        async for delta in self._ai_generator.stream_text(prompt):
            yield delta

    def _build_prompt(
        self,
        action: CivicAction,
        profile: UserProfile,
        personal_context: str | None,
        tone: str,
    ) -> str:
        """Builds a neutral text generation prompt."""
        context = personal_context or "No additional personal context provided."
        topics = ", ".join(profile.topics)
        return (
            "Draft a concise civic action text in English. "
            "The user must be able to edit it before sending. "
            "Stay neutral, factual, and respectful. "
            f"Tone: {tone}. "
            f"Action title: {action.title}. "
            f"Action summary: {action.summary}. "
            f"User topics: {topics}. "
            f"User region: {profile.region or 'unknown'}. "
            f"Personal context: {context}"
        )
