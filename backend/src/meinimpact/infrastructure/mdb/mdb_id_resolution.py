"""Resolves and caches an MdB's DIP person ID.

`dip_reden_adapter.py` needs a DIP-internal person ID (`f.person.id`),
distinct from the Abgeordnetenwatch ID already resolved via `wks_service.py`.
Per specs/data/sources-federal.md Source 6 ("resolved once and cached
alongside the Abgeordnetenwatch ID"), this is a one-time lookup (DIP's
`/person` endpoint matched by name) with persistent caching — resolving
~630 MdBs against 3 external sources on every restart would be wasteful,
and the ID essentially never changes.

The cache is a small Protocol so this module doesn't depend on a specific
storage backend. A Postgres-backed implementation (`mdb_id_mappings` table)
is wired in once the ingestion pipeline is fully assembled; tests and
in-process use can use `InMemoryMdbIdCache`.
"""

import logging
from typing import Protocol
from urllib.parse import quote, urlencode

import httpx

logger = logging.getLogger(__name__)

_BASE_URL = "https://search.dip.bundestag.de/api/v1"


class MdbIdCache(Protocol):
    async def get(self, mdb_name: str) -> str | None: ...

    async def set(self, mdb_name: str, dip_person_id: str) -> None: ...


class InMemoryMdbIdCache:
    """Dict-backed cache — used in tests, and as an in-process fallback."""

    def __init__(self) -> None:
        self._store: dict[str, str] = {}

    async def get(self, mdb_name: str) -> str | None:
        return self._store.get(mdb_name)

    async def set(self, mdb_name: str, dip_person_id: str) -> None:
        self._store[mdb_name] = dip_person_id


class MdbIdResolver:
    """Resolves an MdB's DIP person ID by name, caching the result."""

    def __init__(self, api_key: str, cache: MdbIdCache) -> None:
        self._api_key = api_key
        self._cache = cache

    async def resolve(self, mdb_name: str) -> str | None:
        """Returns the cached DIP person ID, resolving and caching it on a
        cache miss. Returns None if DIP has no matching person record."""
        cached = await self._cache.get(mdb_name)
        if cached is not None:
            return cached

        dip_person_id = await self._lookup(mdb_name)
        if dip_person_id is not None:
            await self._cache.set(mdb_name, dip_person_id)
        return dip_person_id

    async def _lookup(self, mdb_name: str) -> str | None:
        params = [
            ("apikey", self._api_key),
            ("format", "json"),
            ("f.name", mdb_name),
        ]
        # Use quote (not quote_plus) so spaces encode as %20, not + —
        # DIP rejects + encoding in filter values (see dip_adapter.py).
        qs = urlencode(params, quote_via=quote)
        try:
            async with httpx.AsyncClient(timeout=15.0) as client:
                response = await client.get(f"{_BASE_URL}/person?{qs}")
                response.raise_for_status()
            data: dict[str, object] = response.json()
        except Exception as exc:
            logger.warning("DIP person lookup failed for %r: %s", mdb_name, exc)
            return None

        documents = data.get("documents") or []
        if not isinstance(documents, list) or not documents:
            return None
        first = documents[0]
        if not isinstance(first, dict):
            return None
        person_id = first.get("id")
        return str(person_id) if person_id is not None else None
