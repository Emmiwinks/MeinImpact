# Values and Priorities (draft)

**Status: draft for review, 2026-11-20. Nothing here is built yet.**

## Purpose
Defines how the user's political values and budget priorities influence the
feed and the letter, replacing the axis matching in `value-profile.md`
("Feed Scoring: Werte Match").

---

## Why the old matching failed

A probe on the live pool (133 open cards, 2026-11-20, two Mistral runs)
asked which of the 8 questionnaire statements *directly* predicts whether
someone is for or against a card:

| Level   | Cards | A statement fits | Plausible (manual read) |
|---------|-------|------------------|-------------------------|
| Bund    | 37    | 25               | 19                      |
| EU      | 23    | 15               | 14                      |
| Sachsen | 14    | 7                | 1                       |
| Dresden | 59    | 11               | 5                       |

- The statements work for national and EU questions and for real
  disputes (Streitfragen). They do not carry over to most local cards:
  being for change in society says nothing about keeping your Kita.
- Half of the Dresden matches were money questions (Kita closures, budget,
  culture funding) forced onto "the state should regulate markets".
- Energy vs. nature conflicts in Sachsen (wind turbines in a forest, a
  power line through a forest) put green values on both sides.
- 3 direction errors, all on "stop X" cards: the model matched the topic,
  not the side.
- The two Wandel statements measure different things (society vs.
  climate sacrifice), so averaging them into one axis loses signal.

---

## Decisions (proposed)

- **The 8values questionnaire stays unchanged**, including Bewahren/Wandel.
  Only the matching changes: per statement, not per axis average.
- **Local money questions get their own signal: "Kämmerer".** The user
  distributes a city budget over 8 areas once; cards that move money
  between areas match against it.
- **Petitions vs. open procedures.** A petition can only be supported, so
  its direction ranks it. Council decisions, consultations and public
  displays can be argued from either side, so only *how much the user
  cares* ranks them; the direction becomes a side suggestion in the letter.
- **Rank, never filter.** Both signals only add or subtract a little
  appeal, like learned topic interest.
- **Scores and priorities never leave the device**, same as today's werte.
- **Counter-funding is optional to add**, never a field to fill in.
- **Context is one short line**, only when the source says why.

---

## 1. Enrichment changes (backend)

`ENRICHMENT_VERSION` bumps once for all three fields (re-enriches the pool
once; ~133 active cards).

### 1a. `werte_relevanz`: per statement

Keys become the app's `werteQuestionKeys` (`wirtschaft_gleichheit`, ...).
Value `-1` = whoever agrees with the LEFT statement is FOR the card,
`+1` = whoever agrees with the RIGHT statement is FOR it (left = -2 in the
app, so the signs line up). Empty when no statement directly decides it.

Built as enrichment 13 (`listing_enricher.py`). The model first writes
"dafuer" (what supporters want, one sentence) and "streit"/"einig" (both
thinking steps, not stored), then per statement pair a short "warum" (who
would support the dafuer sentence) and "dafuer_ist": "links" | "rechts".

Probe 2026-11-21 on the 133 live cards:
- Capitalised emphasis made no measurable difference (122/133 identical
  statements, the same spread as two identical runs), so the prompt is
  written in normal case.
- Asking "is whoever agrees with the left statement for or against?" gave
  wrong sides on ~10 of 38 cards (double negation). Asking who supports
  the dafuer sentence ("links"/"rechts", reason first) left 3 of 36, all
  energy-vs-nature or similar edge cases.
- Statements on Bund 20/37, EU 7/23, Sachsen 5/14, Dresden 4/59; `geld`
  on Dresden 38/59.

### 1b. `geld` (new, JSONB)

```json
[{"bereich": "kinder_bildung", "richtung": 1}]
```

"If what supporters want happens, does a budget area get more (+1) or less
(-1) money?" At most 2 entries, `[]` if it is not about money. Areas are the
Kämmerer areas below. This is a factual question, checkable against the
source text.

### 1c. `anlass` (new, text, max ~140 characters)

One sentence: why is this on the table now ("Die Stadt muss bis 2028
sparen, und es werden weniger Kinder geboren."). Only from the source text,
no invented numbers, empty if the source does not say. Council papers come
with their PDF text (first 6 pages, `oparl.py`); whether the financial
section is usually inside that range still needs checking.

---

## 2. Kämmerer (app)

### Areas (8)

| id               | Label                         |
|------------------|-------------------------------|
| `kinder_bildung` | Kitas & Schulen               |
| `soziales`       | Soziales, Pflege & Gesundheit |
| `oepnv_rad`      | Bus, Bahn & Rad               |
| `strassen`       | Straßen & Brücken             |
| `kultur`         | Kultur                        |
| `sport_freizeit` | Sport, Bäder & Freizeit       |
| `sicherheit`     | Sicherheit & Ordnung          |
| `gruen_klima`    | Grün, Umwelt & Klima          |

These 8 stay (decided 2026-11-21): no ninth area. "Kämmerer" is only the
internal name; in the app there is no job title (Sachsen says
Finanzbürgermeister), the step asks "Wohin mit dem Geld deiner Stadt?"
and the result is "Dein Stadthaushalt".

### Interaction (concept, to be sketched with impeccable)

- 20 coins of 5 € in the "Stadtkasse", 8 pots. Tap a pot to drop a coin,
  tap the coin to take it back. "Fertig" once all 20 are spent.
- Running out of coins is the point: you feel the trade-off.
- The result settles into a small picture of your budget, like Dein
  Wertebild. "Neu verteilen" in the profile, like "Neu malen".
- Optional reveal "So verteilt Dresden": needs the real shares from the
  Haushaltsplan. Only with sourced numbers, otherwise left out.

### Placement (decided 2026-11-21)

A required onboarding step, no "Überspringen": in the beta everyone fills
in everything, so the app needs no "what if it is missing" paths and every
tester exercises the full ranking. The step carries one line: "Entscheide
aus dem Bauch heraus. Du kannst deine Angaben jederzeit ändern." Changing
later = "Neu verteilen" in the profile. The Werte questionnaire loses its
"Überspringen" too and gets the same line; the start of onboarding says
how long the whole thing takes (estimate ~3 minutes, to be measured).

Intro (decided 2026-11-21): "Mitreden, wo es dich betrifft." + three
plain items with small previews of the real elements (Deine Werte /
Deine Lebenslage / Deine Prioritäten, each with one explaining line),
button "Los geht's · ca. 3 Minuten", link "Nur mal reinschnuppern? Nimm
das Beispielprofil." (example mode marked in the profile, with "Eigenes
Profil anlegen"). No privacy line on the intro: each step says it where
the data is entered, like PLZ and Lebenslagen already do.

### Storage

`UserProfile.prioritaeten: Map<String, int>` (coins per area, sum 20),
on device only.

---

## 3. Ranking (app)

Two signals per card, each in -1..1:

- **Werte**, for each statement key `q` on the card with user score
  `s` (-2..2, skip 0) and card value `v` (±1):
  `lean = mean(s * v / 2)`, `care = mean(|s| / 2)`.
- **Priorities**, for each `geld` entry with area share `p` (coins) and
  `u = 2.5` (even share): `t = clamp((p - u) / u, -1, 1)`,
  `lean = mean(t * richtung)`, `care = mean(|t|)`.

Card signal = mean of the available signals, using `lean` for petitions
and `care` for everything else. Score:

```
appeal + matchBonus * matchStrength
       + rankingInfluence * interest
       + valuesInfluence * signal        // new, InterestConfig
```

`valuesInfluence` starts below `rankingInfluence` (proposal 0.15) and is
tuned with the calibration harness (`interest_calibration_test.dart`), not
guessed. The old tie-break on `werteAlignment` goes away.

---

## 4. Letter (app + backend)

- Two chips above "Was ist dir wichtig?": **Ich bin dafür / Ich bin
  dagegen**. Nothing is preselected. When the card's lean is clear
  (|lean| ≥ 0.3), the matching chip gets a small hint: "passt zu deinem
  Wertebild" or "passt zu deinen Prioritäten". The chosen stance stays on
  the device and only feeds the user's own ranking (decided 2026-11-21).
  The letter takes its stance from the user's own notes, as today. Sending
  feedback to the server for improvement is planned but needs its own
  privacy design first.
- **"+ Gegenvorschlag"** appears only on money cards when the chosen side
  spends money. A small sheet lists the 8 areas (the user's lowest
  priorities first, none preselected) plus "Eigene Idee" (150 characters).
  Sent as `counter_funding`. The letter prompt turns it into one
  constructive sentence; it never calls anything waste and never invents
  amounts.

---

## 5. Card

The card back gets one line above pro/contra when `anlass` is set:
"Warum jetzt: ...". Nothing on the front.

---

## Build order

1. Backend: enrichment v13 (1a-1c), migration for `geld` and `anlass`,
   API fields; probe on the Fly pool before deploy.
2. App ranking (section 3) with calibration test.
3. Kämmerer: impeccable sketch, review, then build.
4. Letter stance chips and counter-funding.
5. "Warum jetzt" line.

Old app versions keep working: unknown `werte_relevanz` keys give them a
neutral 0.5, and new fields are ignored.

---

## Open questions

- Real shares for "So verteilt <Stadt>": must scale to many cities.
  Municipal budgets share the same Produktbereiche, so either the official
  municipal accounts statistics (if broken down per city) or a one-off
  Mistral extraction of each Haushaltsplan's Produktbereich overview,
  checked by hand. Optional extra; the Kämmerer works without it.
- Should the Gegenvorschlag area choice slowly adjust priorities, or do
  priorities change only through "Neu verteilen"? (Proposal: only
  explicitly, for v1.)

## Dependencies

- Replaces "Feed Scoring: Werte Match" in `user/value-profile.md`
- Touches `features/feed.md`, `features/letter-generation.md`,
  `data/ingestion-pipeline.md`
