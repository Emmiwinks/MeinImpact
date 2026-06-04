# Caching

## Purpose
Defines what is cached, where, for how long, and under what conditions
caches are invalidated. Covers both server-side (Redis) and client-side
(Hive session cache) caching.

---

## Decisions

- **Server-side caching uses Redis.** Managed by Fly.io. Used for
  rate limiting counters, pool version tracking, and Tavily context cache.

- **Client-side caching uses Hive session cache.** Action details and
  generated drafts are cached for the current session only, allowing
  offline editing within a session (e.g. in a tunnel).

- **The action pool is the primary cached asset.** Devices cache the
  full pool locally and refresh it on app start if the server pool
  version has changed.

- **Tavily context is cached server-side per action.** Fresh context
  is fetched during ingestion and reused for all context generation
  requests until the action is re-ingested.

- **Generated "what this means for you" text is NOT cached.**
  It is generated fresh per request because it depends on the
  demographic fields sent in the request body, which vary per user.

---

## Server-Side Cache (Redis)

### Pool version key

```
Key:   pool:version
Value: ISO date string, e.g. "2026-06-04"
TTL:   None (updated by pipeline after each successful run)
```

Used by `GET /health` to tell devices whether to re-download the pool.
Updated by the ingestion pipeline at Stage 6 completion.

### Rate limiting counters

```
Key:   ratelimit:letter:{beta_token}:{YYYY-MM-DD}
Value: integer (increment on each letter generation)
TTL:   86400 seconds (expires at midnight)

Key:   ratelimit:context:{beta_token}:{YYYY-MM-DD}
Value: integer
TTL:   86400 seconds
```

See `technical/rate-limiting.md` for limits per tier.

### Global daily budget sentinel

```
Key:   budget:daily:{YYYY-MM-DD}
Value: float (cumulative EUR spend today)
TTL:   86400 seconds
```

Incremented after each Mistral and Tavily API call with actual cost.
Pipeline and request handlers check this before calling AI.

### MdB lookup cache

```
Key:   mdb:{plz}
Value: JSON string (MdB data from Abgeordnetenwatch)
TTL:   2592000 seconds (30 days)
```

Avoids repeated Abgeordnetenwatch API calls for the same PLZ.
The backend caches this even though the result is not stored in PostgreSQL.

---

## Client-Side Cache (Hive)

### Action pool cache

```
Hive box:   pool_cache
Keys:
  pool_version    String — matches server pool:version
  pool_data       String (JSON-encoded list of actions)
  cached_at       DateTime
```

**Refresh logic:**
```dart
Future<List<Action>> getPool() async {
  final box = Hive.box('pool_cache');
  final serverVersion = await api.getPoolVersion(); // GET /health
  final localVersion = box.get('pool_version');

  if (localVersion == serverVersion) {
    // Use cached pool
    return parseActions(box.get('pool_data'));
  }

  // Download fresh pool
  final fresh = await api.downloadPool();
  box.put('pool_version', serverVersion);
  box.put('pool_data', jsonEncode(fresh));
  box.put('cached_at', DateTime.now().toIso8601String());
  return fresh;
}
```

**Cache size:** ≤ 150 KB JSON (100 actions × ~1.5 KB each).

### Session cache (current action + draft)

```
Hive box:   session_cache
Keys:
  current_action_id    String (UUID)
  current_action_data  String (JSON — full action detail incl. context)
  current_draft        String (letter draft text with placeholders)
  session_started      DateTime
```

**Cleared on app restart.** This allows editing a draft in a tunnel
(no connectivity) but does not persist across sessions.

**Draft is cleared when:**
- User sends the letter
- User navigates away from the action detail screen
- App restarts

**Context (what this means for you) is NOT cached in session.**
It is generated fresh each time the action detail screen is opened,
because it depends on demographic fields that may have changed.
The round-trip is acceptable (~1–2 seconds with streaming).

---

## Cache Invalidation Rules

| Cache | Invalidated when |
|---|---|
| Pool (client) | Server pool version changes (daily after pipeline) |
| Pool (client) | User deletes local data |
| Session draft | App restart, letter sent, navigation away |
| MdB lookup (Redis) | TTL expires (30 days) |
| Rate limit counters (Redis) | TTL expires (daily at midnight) |
| Budget sentinel (Redis) | TTL expires (daily at midnight) |

There is no manual cache invalidation mechanism in MVP. All invalidation
is time-based or event-based.

---

## Cache Size Estimates

| Cache | Max size | Location |
|---|---|---|
| Action pool | ~150 KB | Hive (device) |
| Session cache | ~20 KB | Hive (device) |
| Profile + gamification | ~10 KB | Hive (device) |
| Settings + meta | ~2 KB | Hive (device) |
| Redis (all keys combined) | ~5 MB at 10k users | Fly.io Redis |

Total device storage: ~200 KB per installation.
Redis: Fly.io free tier includes 256 MB — sufficient for >50k users.

---

## Dependencies

- Reads: `architecture/overview.md`, `architecture/data-flow.md`,
  `data/database-schema.md`
- Referenced by: `features/feed.md`, `technical/api-endpoints.md`,
  `technical/rate-limiting.md`

---

## Open Questions

- None.
