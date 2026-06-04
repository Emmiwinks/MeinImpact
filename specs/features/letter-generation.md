# Letter Generation

## Purpose
Defines the complete letter and question draft generation flow: the
streaming pipeline, prompts, placeholder system, fallback behaviour,
and rate limiting.

---

## Decisions

- **Generation is server-proxied.** The app never calls Mistral directly.
  The backend proxies the request, enforces rate limits, and streams the
  response back via SSE.

- **Demographic fields are sent, not value scores.** The backend receives
  tone descriptors (strings) and demographic fields. Raw value scores
  never leave the device. See `architecture/data-flow.md` Flow 4.

- **Placeholders are inserted by the app, replaced by the app.**
  The backend and Mistral work with `{{USER_FULL_NAME}}` etc.
  Real values are substituted on-device before the user sends.

- **Every generated draft is linguistically unique.** Mistral is prompted
  to vary sentence structure, vocabulary, and opening. Two users with
  identical profiles should receive noticeably different letters.

- **Fallback on AI failure is a graceful empty state.** If Mistral is
  unavailable, the user sees an editable blank field with a hint message.
  The action is still completable by typing their own text.

- **Rate limiting is enforced per device per day.** Free tier: 3 letter
  generations per day. See `technical/rate-limiting.md`.

---

## Backend Endpoint

```
POST /letters/stream
Authorization: Bearer {beta_token}
Content-Type: application/json

Body:
{
  "action_id": "uuid",
  "type": "brief" | "anfrage",
  "recipient_name": "Sarah Müller",
  "recipient_party": "CDU",
  "recipient_wahlkreis": "Dresden-Nord",      // brief only
  "tone_descriptors": ["community-oriented", "reform-minded"],
  "lebenssituation": ["elternteil"],          // may be []
  "sektor": "gesundheit",                     // may be null
  "plz_prefix": "01",                         // may be null
  "wohnsituation": "mieter"                   // may be null
}

Response: text/event-stream
  data: token1
  data: token2
  ...
  data: [DONE]

Error responses:
  429: rate limit exceeded → { "retry_after": "tomorrow" }
  503: Mistral unavailable → { "fallback": true }
  400: missing required fields
```

---

## Backend Handler

```python
@app.post("/letters/stream")
async def stream_letter(request: LetterRequest, token: str = Depends(validate_token)):

    # Rate limit check
    if await rate_limit_exceeded(token, 'letter'):
        raise HTTPException(429, detail={"retry_after": "tomorrow"})

    # Budget check
    if await budget_exceeded():
        raise HTTPException(503, detail={"fallback": True})

    # Fetch action context from DB
    action = await db.fetch_action(request.action_id)
    if not action:
        raise HTTPException(404)

    # Build prompt
    prompt = build_prompt(request, action)

    # Stream response
    async def event_generator():
        try:
            async with mistral_client.messages.stream(
                model="mistral-medium-latest",
                messages=[{"role": "user", "content": prompt}],
                max_tokens=300,
            ) as stream:
                async for token in stream:
                    yield f"data: {token}\n\n"
                    await track_spend('mistral', 'letter', token_count=1)
            yield "data: [DONE]\n\n"
        except MistralAPIError as e:
            sentry.capture_exception(e)
            yield "data: [ERROR]\n\n"

    return StreamingResponse(
        event_generator(),
        media_type="text/event-stream",
        headers={
            "Cache-Control": "no-cache",
            "X-Accel-Buffering": "no",
        }
    )
```

---

## Prompts

### Brief (Letter to MdB)

```python
BRIEF_PROMPT = """
Du schreibst einen persönlichen Brief eines deutschen Staatsbürgers an
seinen/ihren Bundestagsabgeordneten.

Empfänger: {recipient_name} ({recipient_party}), Wahlkreis {recipient_wahlkreis}

Politisches Thema: {action_title}
Hintergrund: {action_why_now}

Bürger-Profil:
- Orientierung: {tone_descriptors_joined}
- Lebenssituation: {lebenssituation_joined}
- Beruflicher Bereich: {sektor_label}
- Region: {plz_region_label}

Schreibe einen Brief der:
- Mit "Sehr geehrte/r {{USER_FULL_NAME}}" NICHT beginnt — lass die Anrede weg,
  sie wird vom System ergänzt
- 150–200 Wörter hat
- Persönlich klingt, nicht wie eine Vorlage
- Eine konkrete Bitte oder Frage enthält
- Keine Parteinamen nennt außer dem Empfänger
- Keine politischen Schlagwörter wie "Agenda", "Narrativ" o.ä. verwendet
- Mit einer Grußformel endet, aber OHNE Namen — Platzhalter {{USER_FULL_NAME}}
  am Ende

Variiere Satzbau und Wortschatz. Dieser Brief soll sich von anderen
Briefen zu diesem Thema sprachlich deutlich unterscheiden.
"""
```

### Anfrage (Public Question)

```python
ANFRAGE_PROMPT = """
Du formulierst eine öffentliche Anfrage eines deutschen Staatsbürgers
an seinen/ihren Bundestagsabgeordneten via Abgeordnetenwatch.

Empfänger: {recipient_name} ({recipient_party})

Thema: {action_title}
Kontext: {action_why_now}

Bürger-Profil:
- Orientierung: {tone_descriptors_joined}
- Lebenssituation: {lebenssituation_joined}
- Region: {plz_region_label}

Schreibe eine öffentliche Frage die:
- 2–3 Sätze lang ist
- Konkret und beantwortbar ist (keine Ja/Nein-Frage)
- Sachlich und respektvoll formuliert ist
- Mit der direkten Frage beginnt, ohne langen Einleitungssatz
- Keinen Vorwurf enthält

Keine Anrede, keine Grußformel. Nur die Frage selbst.
"""
```

---

## Prompt Context Helpers

```python
def tone_descriptors_joined(descriptors: list[str]) -> str:
    labels = {
        'community-oriented': 'gemeinschaftsorientiert',
        'pragmatic': 'eigenverantwortlich denkend',
        'nationally-focused': 'national orientiert',
        'internationally-minded': 'international orientiert',
        'rights-conscious': 'bürgerrechtsbewusst',
        'security-oriented': 'sicherheitsorientiert',
        'stability-oriented': 'stabilitätsorientiert',
        'reform-minded': 'reformorientiert',
        'balanced': 'ausgewogen',
    }
    return ', '.join(labels.get(d, d) for d in descriptors) or 'ausgewogen'

def lebenssituation_joined(keys: list[str]) -> str:
    labels = {
        'elternteil': 'Elternteil',
        'eigentuemer': 'Wohneigentümer/in',
        'pflegend': 'pflegend tätig',
        'rentner': 'Rentner/in',
        'ausbildung': 'in Ausbildung',
        'berufstaetig': 'berufstätig',
    }
    joined = ', '.join(labels.get(k, k) for k in keys)
    return joined or 'keine Angabe'

def plz_region_label(plz_prefix: str | None) -> str:
    regions = {
        '0': 'Sachsen / Thüringen',
        '1': 'Berlin / Brandenburg',
        '2': 'Hamburg / Schleswig-Holstein',
        '3': 'Niedersachsen',
        '4': 'Nordrhein-Westfalen Nord',
        '5': 'Nordrhein-Westfalen Süd / Rheinland',
        '6': 'Hessen / Rheinland-Pfalz',
        '7': 'Baden-Württemberg',
        '8': 'Bayern',
        '9': 'Bayern / Franken',
    }
    if not plz_prefix:
        return 'Deutschland'
    return regions.get(plz_prefix[0], 'Deutschland')
```

---

## Flutter Streaming Client

```dart
class LetterGenerationService {
  final _controller = StreamController<String>();
  Stream<String> get tokenStream => _controller.stream;

  Future<void> generate(LetterRequest request) async {
    final client = http.Client();
    final req = http.Request(
      'POST',
      Uri.parse('$apiBase/letters/stream?token=$betaToken'),
    );
    req.headers['Content-Type'] = 'application/json';
    req.body = jsonEncode(request.toJson());

    final response = await client.send(req);

    if (response.statusCode == 429) {
      _controller.addError(RateLimitException());
      return;
    }
    if (response.statusCode == 503) {
      _controller.addError(AIUnavailableException());
      return;
    }

    await response.stream
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .where((line) => line.startsWith('data: '))
      .map((line) => line.substring(6))
      .takeWhile((token) => token != '[DONE]')
      .forEach((token) {
        if (token == '[ERROR]') {
          _controller.addError(AIUnavailableException());
        } else {
          _controller.add(token);
        }
      });

    _controller.close();
  }
}
```

---

## Placeholder System

Placeholders in generated text:

| Placeholder | Replaced with | Source |
|---|---|---|
| `{{USER_FULL_NAME}}` | `${vorname} ${nachname}` | Hive profile |
| `{{USER_ADDRESS}}` | `${strasse}, ${plz} ${ort}` | Hive profile |
| `{{USER_CITY}}` | `${ort}` | Hive profile |

Replacement happens on-device in the edit screen, just before the
user sees the final version. The app renders placeholders as
highlighted inline chips until replaced:

```dart
// Placeholder chips shown as tappable inline elements
// Tapping a chip opens a mini-form to enter the value
// Value saved to Hive profile for future use
```

If a placeholder value is not set, the chip remains highlighted in
amber as a visual reminder. The user can still send without filling it.

---

## Fallback Behaviour

### Mistral unavailable (503)
```
[Blank editable text field]

"Die Texterstellung ist gerade nicht verfügbar.
 Du kannst deinen Brief auch selbst schreiben —
 oder es später nochmal versuchen."

[Später versuchen]  [Selbst schreiben]
```

### Rate limit exceeded (429)
```
"Du hast heute bereits 3 Briefe erstellt.
 Morgen kannst du wieder neue Entwürfe generieren."

[Brief selbst schreiben]
```

### No position possible (position_required=true, neutral profile)
```
"Zu diesem Thema haben wir keine klare Richtung
 in deinem Profil gefunden."

[Argumente ansehen]  [Selbst schreiben]
```

In all fallback cases, a manual text entry field is available.
The action is fully completable without AI generation.

---

## Cost Tracking

After each successful generation:
```python
await db.execute("""
    INSERT INTO api_spend (date, provider, endpoint, tokens_used, cost_eur)
    VALUES (CURRENT_DATE, 'mistral', 'letter', :tokens, :cost)
""", {
    'tokens': response.usage.total_tokens,
    'cost': response.usage.total_tokens * MISTRAL_MEDIUM_COST_PER_TOKEN,
})
```

`MISTRAL_MEDIUM_COST_PER_TOKEN` is a configuration constant, not
hardcoded, to allow updates when pricing changes.

---

## Accessibility

- Streaming text is announced progressively to screenreader
- Edit field meets WCAG AA contrast requirements
- Placeholder chips are keyboard-navigable
- Fallback states are fully accessible

---

## Dependencies

- Reads: `architecture/data-flow.md`, `user/value-profile.md`,
  `user/general-profile.md`, `data/database-schema.md`
- Referenced by: `features/action-types.md`, `technical/api-endpoints.md`,
  `technical/streaming.md`, `technical/rate-limiting.md`

---

## Open Questions

- [ ] Mistral model: confirm whether mistral-medium-latest is
      within budget at scale, or whether mistral-small-latest
      produces acceptable quality for letter generation.
      Test both during beta and compare user ratings.
