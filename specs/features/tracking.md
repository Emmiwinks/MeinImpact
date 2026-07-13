# Tracking

## Purpose
Defines how civic action outcomes are tracked, communicated to users,
and displayed in the app. Tracking is the key differentiator from
existing civic platforms.

---

## Decisions

- **Two tracking tiers in MVP:** Tier 1 (fully automatic via DIP API)
  and Tier 2 (semi-automatic via scraping and Tavily).
  No manual curation (Tier 3) in MVP.

- **MdB statement tracking is proactive.** If no statement is found,
  this is communicated explicitly: "Has not commented publicly yet."

- **Tracking is opt-in per action.** Users subscribe to tracking on
  the confirmation screen after completing an action. Not all users
  track all actions.

- **Tracking outcomes are honest about causality.** The app never
  claims the user's action caused an outcome. It shows what happened
  and lets the user draw their own conclusions.

- **Push notifications are the primary delivery channel** for tracking
  events. In-app tracking history is secondary.

---

## Tracking Tier 1: Fully Automatic (DIP API)

Applies to: Bundestagsabstimmungen, Bundestag-Petitionen

### Abstimmung (Vote) Tracking

```python
# Runs as part of daily pipeline (separate from ingestion)
async def track_bundestag_votes():
    # Get all active vote-type actions with push subscribers
    tracked_votes = await db.fetch("""
        SELECT DISTINCT a.id, a.external_id, a.title
        FROM actions a
        JOIN push_subscriptions ps ON a.id = ANY(ps.action_ids)
        WHERE a.type = 'abstimmung'
        AND a.active = true
        AND NOT EXISTS (
            SELECT 1 FROM tracking_events te
            WHERE te.action_id = a.id
            AND te.event_type = 'vote_result'
        )
    """)

    for vote in tracked_votes:
        result = await dip_client.get_abstimmung(vote.external_id)
        if result.get('ergebnis'):
            # Vote has concluded
            outcome = determine_outcome(result, vote)
            await db.execute("""
                INSERT INTO tracking_events (
                    action_id, event_type, title, description,
                    outcome, source_url, occurred_at
                ) VALUES (...)
            """, {
                'action_id': vote.id,
                'event_type': 'vote_result',
                'title': format_vote_title(result),
                'description': format_vote_description(result),
                'outcome': outcome,
                'source_url': f"https://bundestag.de/...",
                'occurred_at': result['datum'],
            })
            await send_push_for_action(vote.id, 'vote_result')
```

**Outcome determination:**
```python
def determine_outcome(dip_result: dict, action: Action) -> str:
    # Positive = the majority of pro_argumente were supported
    ja_stimmen = dip_result.get('ja', 0)
    nein_stimmen = dip_result.get('nein', 0)

    if not action.werte_relevanz:
        return 'neutral'

    # If action was oriented toward change (wandel > 0) and passed: positive
    # Simplified heuristic for MVP:
    passed = ja_stimmen > nein_stimmen
    action_supports_change = any(
        v > 0 for v in action.werte_relevanz.values()
    )
    if passed and action_supports_change:
        return 'positive'
    if not passed and not action_supports_change:
        return 'positive'  # Status quo preserved
    return 'negative'
```

### Petition Tracking (Bundestag)

```python
async def track_bundestag_petitions():
    tracked = await db.fetch("""
        SELECT DISTINCT a.id, a.external_id, a.title,
               a.source_url
        FROM actions a
        JOIN push_subscriptions ps ON a.id = ANY(ps.action_ids)
        WHERE a.type = 'petition'
        AND a.source_url LIKE '%bundestag.de%'
        AND a.active = true
    """)

    for petition in tracked:
        status = await dip_client.get_petition_status(petition.external_id)

        # Milestone: reached 50,000 signatures
        if (status.get('signature_count', 0) >= 50000 and
            not await tracking_event_exists(petition.id, 'petition_milestone')):
            await record_tracking_event(petition.id, 'petition_milestone',
                title="Quorum erreicht: 50.000 Unterschriften",
                description="Die Petition wird dem Petitionsausschuss vorgelegt.",
                outcome='positive')
            await send_push_for_action(petition.id, 'petition_milestone')

        # Conclusion: petition submitted to committee
        if (status.get('status') == 'dem_petitionsausschuss_ueberwiesen' and
            not await tracking_event_exists(petition.id, 'petition_submitted')):
            await record_tracking_event(petition.id, 'petition_submitted',
                title="Petition dem Ausschuss vorgelegt",
                description=status.get('ausschuss_beschluss', ''),
                outcome='neutral')
            await send_push_for_action(petition.id, 'petition_submitted')
```

---

## Tracking Tier 2: Semi-Automatic

### WeAct Petition Tracking

```python
async def track_weact_petitions():
    tracked = await db.fetch("""
        SELECT DISTINCT a.id, a.source_url, a.title
        FROM actions a
        JOIN push_subscriptions ps ON a.id = ANY(ps.action_ids)
        WHERE a.source_url LIKE '%weact.campact.de%'
        AND a.active = true
    """)

    for petition in tracked:
        # Scrape current signature count
        count = await weact_scraper.get_signature_count(petition.source_url)
        status = await weact_scraper.get_status_banner(petition.source_url)

        # Carry the current count forward as previous_signature_count so
        # the next ingestion pipeline run can compute momentum for state A
        # re-evaluation. See data/ingestion-pipeline.md "State Determination:
        # Petition Actions".
        await db.execute("""
            UPDATE actions SET previous_signature_count = :count
            WHERE id = :id
        """, {'count': count, 'id': petition.id})

        # Check for success banner
        if status == 'erfolgreich':
            await record_and_push(petition.id, 'petition_success',
                title="Petition erfolgreich!",
                description="Das Ziel dieser Petition wurde erreicht.",
                outcome='positive')
```

### MdB Statement Tracking

Run as part of daily pipeline Stage 8. See `data/ingestion-pipeline.md`
for the full implementation.

Results are stored in `mdb_statements` table and surfaced in the
tracking detail screen.

---

## Push Notification Content

```python
PUSH_TEMPLATES = {
    'vote_result': {
        'positive': {
            'title': 'Ergebnis: Abstimmung',
            'body': '"{action_title}" wurde angenommen. 🟢',
        },
        'negative': {
            'title': 'Ergebnis: Abstimmung',
            'body': '"{action_title}" wurde abgelehnt.',
        },
        'neutral': {
            'title': 'Abstimmungsergebnis verfügbar',
            'body': 'Schau was aus deiner Aktion zu "{action_title}" geworden ist.',
        },
    },
    'petition_milestone': {
        'title': 'Meilenstein erreicht',
        'body': 'Die Petition "{action_title}" hat das Quorum erreicht! 🎉',
    },
    'petition_submitted': {
        'title': 'Petition eingereicht',
        'body': '"{action_title}" liegt jetzt dem Petitionsausschuss vor.',
    },
    'mdb_statement': {
        'title': '{mdb_name} hat sich geäußert',
        'body': 'Zu "{action_title}" gibt es jetzt ein Statement.',
    },
}
```

All push payloads contain only `action_id` and `event_type`.
No political content in the payload itself (displayed only after
opening the app, from local data).

---

## Tracking Detail Screen

Accessed from confirmation screen or notification tap.

```
┌─────────────────────────────────────────────┐
│ ← Zurück              [Aktion-Titel]        │
├─────────────────────────────────────────────┤
│ DAMALIGE LAGE                               │
│ Abstimmung am 18. April                     │
│ (state_reason zum Zeitpunkt deiner Aktion)  │
├─────────────────────────────────────────────┤
│ DEIN BEITRAG                                │
│ Brief gesendet am 15. April                 │
│ an Sarah Müller (CDU)                       │
├─────────────────────────────────────────────┤
│ WAS PASSIERT IST                            │
│                                             │
│ 🟢 18. April — Abstimmung                   │
│    Das Gesetz wurde mit 412 zu 187          │
│    Stimmen angenommen.                      │
│    Sarah Müller hat mit JA gestimmt.        │
│    [Zur Abstimmung →]                       │
│                                             │
│ 💬 15. April — Sarah Müller                 │
│    "Die Förderung erneuerbarer Energien     │
│    ist ein wichtiger Schritt..."            │
│    [Quelle →]                               │
│                                             │
│ ○  Noch kein weiteres Statement gefunden   │
├─────────────────────────────────────────────┤
│ DEIN EINFLUSS                               │
│ Du warst eine von 1.247 Personen die        │
│ diese Woche aktiv wurden.                   │
└─────────────────────────────────────────────┘
```

**"Damalige Lage" section:** Shows the action's `state_reason` as it was
at the moment the user completed the action — e.g. "Abstimmung am 18.
April" or "Dein MdB hat sich noch nicht öffentlich geäußert". This is a
snapshot copied into the local Hive completion record at completion
time (not re-fetched live), since `engagement_state`/`state_reason` on
the server continue to update as the pipeline re-runs. It gives the
user context for why they acted, distinct from "WAS PASSIERT IST" which
shows what happened afterward.

**Honest causality framing:**
- Never: "Dein Brief hat bewirkt dass..."
- Always: "Du warst eine von X Personen die aktiv wurden."
- Always: "Was danach passiert ist:"

**MdB vote display:**
If PLZ is set, the user sees specifically how their own MdB voted.
If PLZ not set: shows overall vote result only.

---

## Tracking History Screen

Accessible from bottom navigation (📊 icon).

Lists all completed actions chronologically with their current status:

```
Meine Aktionen

● Brief: Solaranlagen auf Bundesgebäuden
  Gesendet 15. Apr — 🟢 Angenommen
  [Details →]

● Petition: Transparenz bei Lobbyregistern
  Unterschrieben 8. Apr — ⏳ Läuft noch (43.218 / 50.000)
  [Details →]

● Anfrage: Kindergrundsicherung
  Gestellt 1. Apr — Keine Antwort bisher
  [Details →]
```

Status indicators:
- 🟢 Angenommen / Erfolgreich
- 🔴 Abgelehnt
- ⏳ Läuft noch
- 💬 Statement verfügbar
- ○ Kein Ergebnis bisher

All tracking history is stored locally in Hive `gamification.history[]`.
The backend only provides tracking events; the user's own action record
is never on the server.

---

## "No Statement" Explicit Communication

When `mdb_statements.found = false` for a tracked action:

```
💬 [MdB Name]
   Hat sich in den letzten 30 Tagen nicht öffentlich
   zu diesem Thema geäußert.
   Zuletzt geprüft: [Datum]
```

This is shown proactively on the tracking detail screen, not hidden.
The date "last checked" prevents the impression of stale data.

---

## Accessibility

- Tracking events use semantic list structure
- Status icons have text equivalents
- All external links labelled with destination
- Timeline is screenreader-navigable

---

## Dependencies

- Reads: `data/database-schema.md`, `data/sources-federal.md`,
  `data/ingestion-pipeline.md`, `user/authentication.md`
- Referenced by: `features/gamification.md`, `technical/api-endpoints.md`

---

## Open Questions

- [ ] WeAct success banner: confirm exact CSS/HTML selector for
      status detection during scraping.
- [ ] MdB individual vote via AW API: confirm that
      `GET /votes?politician={id}&poll={poll_id}` reliably returns
      individual MdB vote within 24h of the vote occurring.
