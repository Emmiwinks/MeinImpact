"""Database engine factory."""

from collections.abc import AsyncIterator

from sqlalchemy.ext.asyncio import (
    AsyncEngine,
    AsyncSession,
    async_sessionmaker,
    create_async_engine,
)


class Database:
    """Owns the SQLAlchemy async engine and session factory."""

    def __init__(self, database_url: str) -> None:
        """Initializes the database engine."""
        self.engine: AsyncEngine = create_async_engine(
            database_url,
            pool_pre_ping=True,
        )
        self._session_factory = async_sessionmaker(
            bind=self.engine,
            expire_on_commit=False,
        )

    async def session(self) -> AsyncIterator[AsyncSession]:
        """Yields one async database session."""
        async with self._session_factory() as session:
            yield session

    async def close(self) -> None:
        """Disposes the database engine."""
        await self.engine.dispose()
