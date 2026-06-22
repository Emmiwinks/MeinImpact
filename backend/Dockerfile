FROM python:3.14-slim

ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1
ENV RUFF_CACHE_DIR=/tmp/.ruff_cache

WORKDIR /app

RUN useradd --create-home --shell /usr/sbin/nologin appuser

COPY pyproject.toml README.md VERSION ./
COPY src ./src
COPY tests ./tests
COPY scripts ./scripts
COPY alembic.ini ./
COPY migrations ./migrations

RUN python -m pip install --no-cache-dir --upgrade pip \
    && python -m pip install --no-cache-dir -e ".[dev]"

USER appuser

EXPOSE 8000

CMD ["uvicorn", "meinimpact.main:app", "--host", "0.0.0.0", "--port", "8000"]
