# Monitoring

## Purpose
Defines what is monitored, where alerts go, and what dashboards exist.
Covers backend health, API costs, pipeline status, and error tracking.

---

## Decisions

- **Three monitoring tools, all on free tiers for MVP:**
  Sentry (errors), Fly.io Metrics (infrastructure), provider dashboards
  (Mistral, Tavily, Supabase).

- **No custom monitoring infrastructure.** No Grafana, no Prometheus,
  no self-hosted dashboards in MVP. All monitoring via existing SaaS.

- **Alerts go to email only.** No Slack, no PagerDuty in MVP.
  Single developer: email is sufficient.

- **Pipeline runs are logged to PostgreSQL.** `pipeline_runs` table
  is the source of truth for ingestion health. See `data/database-schema.md`.

---

## Tool Overview

| Tool | Purpose | Tier |
|---|---|---|
| Sentry | Application errors, exceptions | Free (5k errors/month) |
| Fly.io Metrics | CPU, memory, request latency, restarts | Included |
| Supabase Dashboard | DB size, connection count, query performance | Included |
| Mistral Dashboard | Token usage, cost, API errors | Included |
| Tavily Dashboard | Credit usage, remaining balance | Included |
| NewsData.io Dashboard | Credit usage | Included |

---

## Sentry Configuration

```python
# backend/main.py
import sentry_sdk
from sentry_sdk.integrations.fastapi import FastApiIntegration
from sentry_sdk.integrations.sqlalchemy import SqlalchemyIntegration

sentry_sdk.init(
    dsn=os.getenv('SENTRY_DSN'),
    integrations=[FastApiIntegration(), SqlalchemyIntegration()],
    traces_sample_rate=0.1,   # 10% of requests traced
    profiles_sample_rate=0.0,  # No profiling in MVP
    environment=os.getenv('ENVIRONMENT', 'production'),

    # CRITICAL: never send request bodies
    # Category D data (demographic fields) must not appear in Sentry
    before_send=scrub_sensitive_data,
)

def scrub_sensitive_data(event, hint):
    """Remove request bodies from Sentry events."""
    if 'request' in event:
        event['request'].pop('data', None)      # Remove body
        event['request'].pop('json', None)
    return event
```

**Flutter Sentry:**
```dart
await SentryFlutter.init(
  (options) {
    options.dsn = AppConfig.sentryDsn;
    options.tracesSampleRate = 0.1;
    // Never send user data
    options.beforeSend = (event, hint) {
      // Strip any accidentally captured profile data
      return event.copyWith(user: null);
    };
  },
);
```

---

## Metrics to Watch

### Daily (check each morning)

| Metric | Source | Alert threshold |
|---|---|---|
| Pipeline ran successfully | `pipeline_runs` table | No run in 25h → email |
| Actions inserted yesterday | `pipeline_runs.inserted_count` | 0 for 3 days → email |
| AI spend yesterday (EUR) | `api_spend` table | > €2 → email |
| Error count | Sentry | > 50 new errors → email |
| 429 rate | Fly.io logs | > 10% → Sentry warning |

### Weekly (check each Monday)

| Metric | Source |
|---|---|
| DB size | Supabase dashboard |
| Active push subscriptions | `SELECT COUNT(*) FROM push_subscriptions` |
| Completion rate | `SELECT SUM(completion_count) FROM action_stats` |
| Average feedback rating | `SELECT AVG(rating) FROM feedback WHERE created_at > now() - '7 days'::interval` |
| Mistral spend trend | Mistral dashboard |

---

## Pipeline Health Check

**Status (2026-09-27):** The queries below assume the retired DIP-sourced
pipeline's schema (`pipeline_runs.state_a_count` etc., `actions.
engagement_state`) — see `data/ingestion-pipeline.md` "Status". Kept as a
reference for the query shape until the new pipeline's schema is known.

A simple query to check pipeline status:

```sql
-- Last pipeline run details
SELECT
    ran_at,
    parliamentary_actions_found,
    petition_actions_found,
    state_a_count,
    state_b_count,
    state_c_count,
    state_d_discarded,
    inserted_count,
    ai_cost_eur,
    duration_seconds,
    array_length(errors, 1) AS error_count
FROM pipeline_runs
ORDER BY ran_at DESC
LIMIT 7;

-- Active action pool summary by engagement state
SELECT
    engagement_state,
    COUNT(*) as count,
    MIN(deadline) as next_deadline
FROM actions
WHERE active = true
GROUP BY engagement_state
ORDER BY CASE engagement_state WHEN 'A' THEN 1 WHEN 'B' THEN 2 ELSE 3 END;
```

---

## Cost Monitoring Queries

```sql
-- Daily spend last 14 days
SELECT
    date,
    provider,
    SUM(cost_eur) as total_eur,
    SUM(tokens_used) as total_tokens
FROM api_spend
WHERE date >= CURRENT_DATE - 14
GROUP BY date, provider
ORDER BY date DESC, provider;

-- Monthly projection
SELECT
    ROUND(AVG(daily_total) * 30, 2) as projected_monthly_eur
FROM (
    SELECT date, SUM(cost_eur) as daily_total
    FROM api_spend
    WHERE date >= CURRENT_DATE - 7
    GROUP BY date
) daily;
```

---

## Log Configuration

### What IS logged (backend)
```python
# Fly.io access logs (automatic):
# Method, path, status code, duration, response size
# Example: POST /api/v1/letters/stream 200 4.2s 0b

# Application logs:
logger.info("Pipeline run completed", extra={
    'inserted': n,
    'duration': t,
    'cost_eur': c,
})
logger.warning("Budget 80% consumed", extra={'spent': s, 'limit': l})
```

### What is NEVER logged
- Request bodies (especially `/context` and `/letters/stream`)
- Beta tokens in plain text (only first 8 chars for debugging)
- PLZ values
- Any demographic profile fields
- Letter content (streamed through, never assembled server-side)

---

## Uptime Monitoring

Fly.io provides basic HTTP health check monitoring out of the box.
Configure in `fly.toml`:

```toml
[[services.tcp_checks]]
  interval = "15s"
  timeout = "2s"

[[services.http_checks]]
  interval = "30s"
  timeout = "5s"
  path = "/api/v1/health"
  protocol = "https"
```

External uptime monitoring: not required for MVP beta.

---

## Incident Response

**Pipeline failure (no run in 25h):**
1. Check Sentry for errors during last pipeline run
2. Check Fly.io logs for process crashes
3. Manually trigger: `fly ssh console -C "python -c 'from services.ingestion import run; import asyncio; asyncio.run(run())'"` 
4. If source API is down: wait for recovery, no user impact (pool remains stale but usable)

**Budget exceeded:**
1. AI endpoints return 503 automatically
2. Check `api_spend` for unexpected spend spike
3. Check Sentry for loops or abuse patterns
4. Increase ceiling or wait for midnight reset

**Mistral API down:**
1. All letter generation returns 503 with `fallback: true`
2. Users see fallback state (manual text entry)
3. No action required beyond monitoring for recovery

---

## Dependencies

- Reads: `architecture/overview.md`, `data/database-schema.md`,
  `technical/rate-limiting.md`
- Referenced by: `data/ingestion-pipeline.md`

---

## Open Questions

- None.
