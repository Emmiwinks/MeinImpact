# API Endpoints

## Purpose
Defines all backend HTTP endpoints: request/response shapes, auth
requirements, error codes, and which feature spec each endpoint serves.

---

## Decisions

- **All endpoints require a valid beta token** via
  `Authorization: Bearer {token}` header. No public endpoints in MVP.

- **All responses are JSON** except the letter stream (SSE).

- **All error responses follow a consistent shape:**
  `{ "error": "human-readable message", "code": "MACHINE_CODE" }`

- **No pagination in MVP.** The action pool is small enough (≤ 100)
  to return in a single response.

- **No versioning in MVP.** Path prefix `/api/v1/` is used but no
  version negotiation is implemented.

---

## Base URL

```
Production:  https://api.meinimpact.app/api/v1
Development: http://localhost:8000/api/v1
```

---

## Authentication

All requests must include:
```
Authorization: Bearer {beta_token}
```

Token validation:
```python
async def validate_token(
    credentials: HTTPAuthorizationCredentials = Security(security)
) -> str:
    token = credentials.credentials
    exists = await db.fetchval(
        "SELECT EXISTS(SELECT 1 FROM beta_tokens WHERE token = $1)",
        uuid.UUID(token)
    )
    if not exists:
        raise HTTPException(401, detail={
            "error": "Invalid or expired token",
            "code": "INVALID_TOKEN"
        })
    return token
```

---

## Endpoints

### Health & Pool Version

```
GET /health

Response 200:
{
  "status": "ok",
  "pool_version": "2026-06-04",   // ISO date of last pipeline run
  "app_version_min": "1.0.0"      // Minimum supported app version
}
```

Used by the app on startup to check connectivity and pool freshness.
No token required (only endpoint without auth — allows connectivity
check before token validation).

---

### Action Pool

```
GET /actions/pool

Response 200:
{
  "version": "2026-06-04",
  "generated_at": "2026-06-04T03:12:00Z",
  "actions": [
    {
      "id": "uuid",
      "title": "Brief an deinen Abgeordneten: Solaranlagen",
      "action_type": "representative_letter",
      "summary": "Kurzfassung der Maßnahme...",
      "urgency": "high",
      "deadline": "2026-06-14",       // null if no deadline
      "source_url": "https://...",
      "effort_minutes": 15,
      "impact_hint": "Abstimmung oder Frist steht kurz bevor",
      "pro_argumente": ["...", "..."],
      "contra_argumente": ["...", "..."],
      "werte_relevanz": {
        "wirtschaft": 0.6,
        "diplomatie": 0.0,
        "freiheit": -0.3,
        "wandel": 0.8
      },
      "action_types": ["brief", "petition"],
      "is_controversial": false,
      "position_required": false,
      "engagement_state": "A",
      "state_reason": "Abstimmung am 14. Juni",
      "pipeline_source": "parliamentary",
      "created_at": "2026-06-03T03:10:00Z"
    }
  ]
}

Note: tavily_context is NOT included in pool response.
```

---

### Action Context ("What This Means for You")

```
POST /actions/{action_id}/context

Body:
{
  "lebenssituation": ["elternteil"],   // [] if not set
  "sektor": "gesundheit",              // null if not set
  "plz_prefix": "01",                  // null if not set
  "wohnsituation": "mieter"            // null if not set
}

Response 200:
{
  "action_id": "uuid",
  "context": "Als Pflegekraft in Sachsen betrifft dich diese..."
}

Response 503:
{
  "error": "AI generation temporarily unavailable",
  "code": "AI_UNAVAILABLE",
  "fallback": true
}
```

Body fields are Category D data (transient, not stored, not logged).
See `architecture/dsgvo.md`.

---

### Letter / Question Generation (Streaming)

```
POST /letters/stream

Body:
{
  "action_id": "uuid",
  "type": "brief",                        // "brief" | "anfrage"
  "recipient_name": "Sarah Müller",
  "recipient_party": "CDU",
  "recipient_wahlkreis": "Dresden-Nord",  // brief only, null for anfrage
  "tone_descriptors": ["community-oriented", "reform-minded"],
  "lebenssituation": ["elternteil"],
  "sektor": "gesundheit",
  "plz_prefix": "01",
  "wohnsituation": "mieter"
}

Response: text/event-stream
  data: "Sehr"
  data: " geehrte"
  data: " Frau"
  ...
  data: [DONE]

Response 429:
{
  "error": "Daily letter generation limit reached",
  "code": "RATE_LIMIT_EXCEEDED",
  "retry_after": "tomorrow"
}

Response 503:
{
  "error": "AI generation temporarily unavailable",
  "code": "AI_UNAVAILABLE",
  "fallback": true
}
```

See `technical/streaming.md` for SSE implementation details.
See `technical/rate-limiting.md` for limit values.

---

### Action Completion

```
POST /actions/{action_id}/complete

Body:
{
  "action_type": "brief"    // "brief" | "petition" | "anfrage"
}

Response 200:
{
  "ok": true,
  "completion_count": 1248    // Updated anonymous total
}
```

Increments `action_stats.completion_count`. No user linkage stored.

---

### MdB Lookup

```
GET /mdb?plz={plz}

Path params:
  plz: 5-digit German PLZ string

Response 200:
{
  "name": "Sarah Müller",
  "party": "CDU",
  "wahlkreis": "Dresden-Nord",
  "wahlkreis_number": 160,
  "profile_url": "https://www.abgeordnetenwatch.de/profile/sarah-mueller",
  "photo_url": "https://..."
}

Response 404:
{
  "error": "No MdB found for this PLZ",
  "code": "MDB_NOT_FOUND"
}
```

PLZ is used for Abgeordnetenwatch lookup and Redis cache key.
PLZ is NOT stored in the database. See `architecture/dsgvo.md`.

---

### Push Registration

```
POST /push/register

Body:
{
  "push_token": "fcm_or_apns_token_string",
  "platform": "fcm"    // "fcm" | "apns"
}

Response 200:
{ "ok": true }
```

---

### Push Subscription to Action

```
POST /push/subscribe

Body:
{
  "push_token": "...",
  "action_id": "uuid"
}

Response 200:
{ "ok": true }

POST /push/unsubscribe

Body:
{
  "push_token": "...",
  "action_id": "uuid"
}

Response 200:
{ "ok": true }
```

---

### Feedback

```
POST /feedback

Body:
{
  "action_id": "uuid",    // null for general app feedback
  "rating": 4,            // 1–5
  "comment": "..."        // max 500 chars, optional
}

Response 200:
{ "ok": true }
```

---

### Tracking Events

```
GET /actions/{action_id}/tracking

Response 200:
{
  "action_id": "uuid",
  "events": [
    {
      "id": "uuid",
      "event_type": "vote_result",
      "title": "Abstimmung: Angenommen",
      "description": "Das Gesetz wurde mit 412 zu 187 Stimmen angenommen.",
      "outcome": "positive",
      "source_url": "https://...",
      "occurred_at": "2026-06-18T14:00:00Z"
    }
  ],
  "mdb_statements": [
    {
      "mdb_name": "Sarah Müller",
      "found": true,
      "statement_summary": "Müller begrüßt den Beschluss als wichtigen Schritt...",
      "source_url": "https://...",
      "searched_at": "2026-06-18T03:00:00Z"
    },
    {
      "mdb_name": "Thomas Weber",
      "found": false,
      "statement_summary": null,
      "source_url": null,
      "searched_at": "2026-06-18T03:00:00Z"
    }
  ]
}
```

---

### Beta Token Activation

```
POST /beta/activate

Body:
{
  "token": "uuid-string"
}

Response 200:
{ "valid": true }

Response 404:
{
  "error": "Token not found or already used",
  "code": "TOKEN_INVALID"
}
```

---

## Error Code Reference

| Code | HTTP | Meaning |
|---|---|---|
| `INVALID_TOKEN` | 401 | Beta token not found or invalid |
| `NOT_FOUND` | 404 | Resource does not exist |
| `MDB_NOT_FOUND` | 404 | No MdB for given PLZ |
| `TOKEN_INVALID` | 404 | Beta token not found or used |
| `RATE_LIMIT_EXCEEDED` | 429 | Per-device daily limit hit |
| `AI_UNAVAILABLE` | 503 | Mistral API down or budget exceeded |
| `VALIDATION_ERROR` | 400 | Request body malformed |

---

## Request Body Logging Policy

The following endpoints must have request body logging **disabled**
in all environments:

- `POST /actions/{id}/context` (contains Category D data)
- `POST /letters/stream` (contains Category D data + tone descriptors)

All other endpoints may log request metadata (method, path, status,
duration) but never request bodies containing user-originated data.

---

## OpenAPI

FastAPI generates OpenAPI documentation automatically at:
```
http://localhost:8000/docs      (Swagger UI)
http://localhost:8000/openapi.json
```

All endpoints are documented with request/response schemas via
Pydantic models. This is the source of truth for the Flutter API client.

---

## Dependencies

- Reads: `architecture/overview.md`, `architecture/data-flow.md`,
  `architecture/dsgvo.md`, `data/database-schema.md`
- Referenced by: all `features/` specs, `technical/rate-limiting.md`

---

## Open Questions

- None.
