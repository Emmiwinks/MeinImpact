# Onboarding

## Purpose
Defines the complete onboarding flow: screen sequence, required vs optional
steps, consent collection, and the transition to the main feed.

---

## Decisions

- **Onboarding is a one-time flow.** Once completed, `meta.onboarding_completed`
  is set to true in Hive. The app never shows onboarding again unless local
  data is deleted.

- **Two screens are mandatory and blocking.** Consent and value profile
  must be completed before the feed is shown. There is no topic selection
  — the feed covers all actionable civic items and is personalised purely
  by political value alignment.

- **Demographic profile is optional and presented after the mandatory steps.**
  Skipping it degrades personalisation quality but does not block access.

- **No account creation during onboarding.** The beta token is already stored
  from the invite link activation. Onboarding is purely profile setup.

- **All data collected during onboarding is stored locally in Hive only.**
  Nothing is transmitted to the backend during onboarding except the beta
  token validation on app start (which happens before onboarding).

---

## Screen Sequence

```
1. Welcome screen              (informational, no input)
2. Age + consent screen        (blocking, all items required)
3. Value profile               (blocking, min. 4 of 8 questions answered)
4. Demographic profile         (optional, skippable)
5. Notification opt-in         (optional, skippable)
6. Feed                        (onboarding complete)
```

---

## Screen 1: Welcome

**Content:**
- App name and tagline
- Three-line value proposition:
  "One action per week. Matched to your values. With real follow-up."
- Single CTA: "Get started"

**Data collected:** None
**Validation:** None
**Skip:** Not applicable

---

## Screen 2: Age + Consent

**Content:**
Three checkboxes, all required:

1. "I confirm I am at least 18 years old."
2. "My political profile stays on my device. I agree that MeinImpact stores
   an anonymous access token on a server in the EU to enable app access."
3. "Recommendations and letter drafts are pre-drafted by AI based on my
   profile. I review and send everything myself."

Link to full privacy policy (opens in-app browser).
Link to terms of service.

**Data collected:**
- `meta.min_age_confirmed = true`
- `meta.consents_confirmed = true`
- `meta.consent_timestamp = ISO8601`

**Validation:** All three checkboxes must be ticked. CTA disabled otherwise.
**Skip:** Not possible.

---

## Screen 3: Value Profile (8values)

**Content:**
Headline: "Where do you stand?"
Subline: "No right or wrong answers. Helps us write letters that sound like you."

Eight questions presented one per screen (sub-flow within screen 4),
with a progress indicator showing "Question X of 8".

Each question shows:
- Left pole label (bold)
- Left pole description (small, grey)
- Slider (5 positions, default: centre)
- Right pole description (small, grey, right-aligned)
- Right pole label (bold, right-aligned)

5-position slider values map to: -2, -1, 0, +1, +2

The user must move the slider away from centre on at least 4 of 8 questions
before the CTA is enabled. Leaving a slider at centre is valid for up to 4
questions.

**The 8 questions:**

Q1 — Wirtschaft (Equality axis)
- Left: **Umverteilung** / "Der Staat sollte große Vermögen und Einkommen
  stärker ausgleichen."
- Right: **Eigenverantwortung** / "Wer Leistung bringt, sollte davon
  profitieren — mit möglichst wenig staatlichem Eingriff."

Q2 — Wirtschaft (State axis)
- Left: **Staatliche Steuerung** / "Der Staat muss Märkte regulieren und
  wichtige Bereiche selbst kontrollieren."
- Right: **Freier Markt** / "Privatwirtschaft und Wettbewerb lösen Probleme
  besser als der Staat."

Q3 — Diplomatie (Nation axis)
- Left: **Nationale Interessen** / "Deutschland sollte seine eigenen
  Interessen klar vertreten, auch wenn das Partner vor den Kopf stößt."
- Right: **Internationale Kooperation** / "Globale Probleme lassen sich
  nur gemeinsam lösen — nationale Alleingänge bringen nichts."

Q4 — Diplomatie (World axis)
- Left: **Souveränität** / "Deutschland sollte außenpolitisch unabhängiger
  werden und weniger Verpflichtungen eingehen."
- Right: **Globale Verantwortung** / "Deutschland muss mehr globale
  Verantwortung übernehmen, auch wenn das kostet."

Q5 — Freiheit/Autorität (Liberty axis)
- Left: **Persönliche Freiheit** / "Der Staat soll so wenig wie möglich
  in das Leben der Menschen eingreifen."
- Right: **Gesellschaftliche Ordnung** / "Mehr staatliche Regeln und
  Kontrolle sind nötig um Sicherheit und Zusammenhalt zu gewährleisten."

Q6 — Freiheit/Autorität (Authority axis)
- Left: **Bürgerrechte** / "Im Zweifel sind Bürgerrechte wichtiger als
  staatliche Sicherheitsinteressen."
- Right: **Innere Sicherheit** / "Im Zweifel ist Sicherheit wichtiger
  als individuelle Freiheiten."

Q7 — Tradition/Wandel (Tradition axis)
- Left: **Bewährtes erhalten** / "Gesellschaftliche Strukturen die sich
  bewährt haben, sollten erhalten bleiben — schneller Wandel schafft
  mehr Probleme als er löst."
- Right: **Wandel gestalten** / "Die Gesellschaft muss sich mutig
  weiterentwickeln, auch wenn das unbequem ist."

Q8 — Tradition/Wandel (Progress axis)
- Left: **Generationengerechtigkeit** / "Wir fordern zu viel von der
  heutigen Generation für Probleme die erst in der Zukunft spürbar werden."
- Right: **Zukunftsverantwortung** / "Ich bin bereit, heute auf Komfort
  zu verzichten, damit zukünftige Generationen es besser haben."

**Data collected:**
- `profile.werte.wirtschaft_gleichheit` (-2 to +2)
- `profile.werte.wirtschaft_staat` (-2 to +2)
- `profile.werte.diplomatie_nation` (-2 to +2)
- `profile.werte.diplomatie_welt` (-2 to +2)
- `profile.werte.freiheit_staat` (-2 to +2)
- `profile.werte.freiheit_sicherheit` (-2 to +2)
- `profile.werte.wandel_tradition` (-2 to +2)
- `profile.werte.wandel_zukunft` (-2 to +2)

**Validation:** At least 4 sliders moved from centre (value ≠ 0).
**Skip:** Not possible for the sub-flow. Individual questions may stay at
centre (value = 0) up to a maximum of 4.

---

## Screen 4: Demographic Profile (Optional)

**Content:**
Headline: "Tell us a bit more (optional)"
Subline: "Helps us explain what decisions mean for your life. Skip anytime."

Three optional questions, each as a tile-selection (not free text):

**Q1: Lebenssituation** (multi-select)
- 👶 Elternteil
- 🏠 Wohneigentümer
- 🏥 Pflegend tätig
- 👴 Rentner/in
- 🎓 In Ausbildung
- 💼 Berufstätig

**Q2: Beruflicher Sektor** (single select)
- 🏥 Gesundheit & Pflege
- 🔧 Handwerk & Industrie
- 📚 Bildung & Soziales
- 💻 IT & Digital
- 🌱 Landwirtschaft
- 🏛️ Öffentlicher Dienst
- 🏢 Sonstiges / Privat

**Q3: PLZ** (free text, numeric, 5 digits)
- Label: "Deine Postleitzahl"
- Subtext: "Damit wir dir deinen Abgeordneten zuordnen können.
  Bleibt auf deinem Gerät."
- Validation: must be a valid German PLZ format if entered

Skip button visible at top right throughout this screen.

**Data collected:**
- `profile.lebenssituation[]` (array of selected keys)
- `profile.sektor` (single key or null)
- `profile.plz` (string or null)

**Validation:** None required. Any combination (including empty) is valid.
**Skip:** Entire screen skippable. Individual questions skippable.

---

## Screen 5: Notification Opt-In (Optional)

**Content:**
Headline: "Stay informed"
Body: "We'll notify you when an action you took has a result.
      You can turn this off anytime in settings."
CTA: "Enable notifications"
Secondary: "Maybe later" (skip)

On "Enable notifications":
1. App shows system permission dialog (iOS/Android native)
2. If granted: register push token (Flow 6 in data-flow.md)
3. If denied: store `settings.notifications_enabled = false`, continue

**Data collected:**
- `settings.notifications_enabled` (bool)

**Skip:** Yes, via "Maybe later".

---

## Completion

After screen 6 (or skip):
- Set `meta.onboarding_completed = true` in Hive
- Navigate to Feed (replacing onboarding stack)
- Show a brief welcome toast: "Welcome. Here's your first week."

---

## Re-entry and Edge Cases

**App killed during onboarding:**
On next launch, check `meta.onboarding_completed`. If false, resume from
the last incomplete screen (tracked via `meta.onboarding_step` integer).

**Local data deleted:**
`meta.onboarding_completed` is deleted with it. Full onboarding runs again.
Beta token must be re-entered via invite link (or stored separately outside
the profile Hive box — see `technical/local-storage.md`).

**Beta token stored separately:**
`meta.beta_token` lives in a separate Hive box (`auth`) that is NOT deleted
when the user clears their profile. This allows profile reset without losing
beta access.

---

## Accessibility

- All tiles and sliders must have Semantics labels for screenreader.
- Slider must be operable via keyboard/switch access with step size 1.
- Minimum tap target: 48×48 dp.
- Progress indicator must announce current step to screenreader.
- High-contrast: tile borders increase to 2px in high-contrast mode.

---

## Localisation

All strings are in `l10n/` files. No hardcoded text. German is default.
Topic emoji are locale-independent and need no translation.

---

## Dependencies

- Reads: `architecture/dsgvo.md`, `user/value-profile.md`,
  `user/general-profile.md`, `user/authentication.md`
- Referenced by: `features/feed.md`, `technical/local-storage.md`

---

## Open Questions

- None.
