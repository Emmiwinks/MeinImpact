# Rate Limiting

## Purpose
Defines per-device limits for AI-powered endpoints and the global daily
budget ceiling that protects against runaway costs.

---

## Decisions

- **Rate limiting state lives in Redis.** TTL-based counters, no DB writes.

- **Limits are per beta-token, not per IP.** IP-based limiting is
  unreliable on mobile (shared IPs, NAT). Token-based is accurate.

- **Global budget ceiling is a hard stop.** If the daily AI budget is
  exceeded, all AI endpoints return 503 until midnight. Non-AI
  endpoints are unaffected.

- **Limits are configurable via environment variables.** No hardcoded
  values in application code.

---

## Per-Device Limits

| Endpoint | MVP limit | Key pattern | TTL |
|---|---|---|---|
| `POST /letters/stream` | 3/day | `ratelimit:letter:{token}:{date}` | 86400s |
| `POST /actions/{id}/context` | 20/day | `ratelimit:context:{token}:{date}` | 86400s |
| `GET /actions/pool` | 10/hour | `ratelimit:pool:{token}:{hour}` | 3600s |
| `POST /feedback` | 10/day | `ratelimit:feedback:{token}:{date}` | 86400s |

All other endpoints: no per-device limit in MVP.

---

## Implementation

```python
LIMITS = {
    'letter':   int(os.getenv('RATE_LIMIT_LETTER',   '3')),
    'context':  int(os.getenv('RATE_LIMIT_CONTEXT',  '20')),
    'pool':     int(os.getenv('RATE_LIMIT_POOL',     '10')),
    'feedback': int(os.getenv('RATE_LIMIT_FEEDBACK', '10')),
}

async def check_rate_limit(token: str, endpoint: str) -> None:
    """Raises HTTPException 429 if limit is exceeded."""
    today = date.today().isoformat()
    hour  = datetime.now().strftime('%Y-%m-%dT%H')

    key_suffix = today if endpoint != 'pool' else hour
    key = f"ratelimit:{endpoint}:{token}:{key_suffix}"
    ttl = 86400 if endpoint != 'pool' else 3600

    count = await redis.incr(key)
    if count == 1:
        await redis.expire(key, ttl)

    limit = LIMITS.get(endpoint, 999)
    if count > limit:
        raise HTTPException(
            status_code=429,
            detail={
                "error": f"Daily limit of {limit} reached for this endpoint",
                "code": "RATE_LIMIT_EXCEEDED",
                "retry_after": "tomorrow" if endpoint != 'pool' else "next_hour",
            }
        )
```

---

## Global Daily Budget Ceiling

```python
DAILY_BUDGET_EUR = float(os.getenv('DAILY_BUDGET_EUR', '5.0'))
# Covers both ingestion pipeline AND request-time AI calls

async def check_budget() -> None:
    """Raises HTTPException 503 if daily budget is exceeded."""
    key = f"budget:daily:{date.today().isoformat()}"
    spent = float(await redis.get(key) or 0)

    if spent >= DAILY_BUDGET_EUR:
        raise HTTPException(
            status_code=503,
            detail={
                "error": "Service temporarily at capacity",
                "code": "AI_UNAVAILABLE",
                "fallback": True,
            }
        )

async def record_spend(provider: str, endpoint: str,
                       tokens: int, cost_eur: float) -> None:
    """Records spend in Redis (real-time) and PostgreSQL (permanent)."""
    # Redis: real-time budget tracking
    key = f"budget:daily:{date.today().isoformat()}"
    await redis.incrbyfloat(key, cost_eur)
    await redis.expire(key, 86400)

    # PostgreSQL: permanent cost log
    await db.execute("""
        INSERT INTO api_spend (date, provider, endpoint, tokens_used, cost_eur)
        VALUES (CURRENT_DATE, $1, $2, $3, $4)
    """, provider, endpoint, tokens, cost_eur)
```

---

## Usage in Endpoints

Every AI endpoint calls both checks before processing:

```python
@app.post("/api/v1/letters/stream")
async def stream_letter(request: LetterRequest,
                        token: str = Depends(validate_token)):
    await check_rate_limit(token, 'letter')   # Per-device limit
    await check_budget()                       # Global ceiling
    # ... proceed with generation
```

---

## Cost Constants

```python
# Per-token costs in EUR (update when Mistral pricing changes)
MISTRAL_SMALL_INPUT_EUR_PER_TOKEN  = 0.0000002   # €0.20 / 1M tokens
MISTRAL_SMALL_OUTPUT_EUR_PER_TOKEN = 0.0000006   # €0.60 / 1M tokens
MISTRAL_MEDIUM_INPUT_EUR_PER_TOKEN = 0.0000028   # €2.80 / 1M tokens
MISTRAL_MEDIUM_OUTPUT_EUR_PER_TOKEN= 0.0000080   # €8.00 / 1M tokens
TAVILY_COST_PER_CREDIT             = 0.001        # $0.001 / credit ≈ €0.001

def calculate_mistral_cost(model: str, input_tokens: int,
                            output_tokens: int) -> float:
    if 'medium' in model:
        return (input_tokens  * MISTRAL_MEDIUM_INPUT_EUR_PER_TOKEN +
                output_tokens * MISTRAL_MEDIUM_OUTPUT_EUR_PER_TOKEN)
    return (input_tokens  * MISTRAL_SMALL_INPUT_EUR_PER_TOKEN +
            output_tokens * MISTRAL_SMALL_OUTPUT_EUR_PER_TOKEN)
```

---

## Monitoring Alerts

Alerts configured in Sentry / Fly.io metrics:

| Condition | Alert |
|---|---|
| Daily spend > 80% of ceiling | Email alert |
| Daily spend > 100% of ceiling | Email alert + Sentry error |
| Single device > 50% of letter limit in 1 hour | Sentry warning (potential abuse) |
| 429 rate > 10% of requests on any endpoint | Sentry warning |

---

## Dependencies

- Reads: `architecture/overview.md`, `data/caching.md`
- Referenced by: `features/letter-generation.md`,
  `technical/api-endpoints.md`, `technical/monitoring.md`

---

## Open Questions

- None.
