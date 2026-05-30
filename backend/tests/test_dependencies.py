"""Dependency factory tests."""

from meinimpact.api.dependencies import get_ai_generator
from meinimpact.core.config import Settings
from meinimpact.infrastructure.ai.mistral_client import MistralTextGenerator


def test_get_ai_generator_uses_mistral_when_api_key_exists() -> None:
    generator = get_ai_generator(
        Settings(
            mistral_api_key="secret",
            mistral_base_url="https://api.example.test/v1",
            mistral_model="model-name",
        )
    )

    assert isinstance(generator, MistralTextGenerator)
