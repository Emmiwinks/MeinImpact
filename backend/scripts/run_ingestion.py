#!/usr/bin/env python3
"""Runs one full opportunity ingestion against the configured database.

Same composition as the admin route (`services/ingestion.py`), but in the
foreground with the summary printed. Needs MEINIMPACT_MISTRAL_API_KEY.

Run inside the API container:
  docker compose exec api python scripts/run_ingestion.py
"""

import asyncio
import logging
from dataclasses import asdict
from pprint import pprint

from meinimpact.core.config import get_settings
from meinimpact.services.ingestion import run_configured_ingestion


async def main() -> None:
    logging.basicConfig(level=logging.WARNING)
    summary = await run_configured_ingestion(get_settings())
    pprint(asdict(summary), sort_dicts=False, width=100)


if __name__ == "__main__":
    asyncio.run(main())
