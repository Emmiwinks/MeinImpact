# Notifications

Status: stage 1 built 2026-11-21 (Android only, no Firebase).

## Principle

The server never learns whom a notification concerns. The app loads the same
public data as everyone (`/v1/opportunities/pool`, `/v1/opportunities/news`),
matches it against what is on the device (action log, stars, cards looked at,
profile) and shows local notifications itself. No push tokens, no per-action
subscriptions. The legacy `/v1/push/*` routes and `push_subscriptions` table
store device-to-action links and are to be removed.

## Kinds (in priority order)

| Kind | When | Channel |
|---|---|---|
| Ergebnis: petition goal reached | a signed petition passes its goal (signatures at signing < goal <= now) | Neuigkeiten & Ergebnisse |
| Morgen wird entschieden | 18:00 the day before a council vote the user wrote about | Neuigkeiten & Ergebnisse |
| Neues zu Aktionen mit Stern | new `exact`/`issue` reports on a starred action; reports present when starring count as known | Neuigkeiten & Ergebnisse |
| Flamme | Sunday 17:00, only when the streak would end at midnight (second empty week) | Flamme |
| Frist | 09:00 two days before a card the user turned over or opened closes; max 1 a week | Erinnerungen |
| Neue Woche | Monday 09:00, count of opportunities new in the past week that fit (situation match or learned interest); skipped if the app was open that Monday | Neue Woche |
| Abgeschickt? | 19:00 the day after leaving an action's site without "Fertig"; buttons "Ja, erledigt" (logs it) / "Nein". **Off for the beta** (`kAskIfTookPart`, may feel pushy) | Erinnerungen |

Rules: max 1 a day and 3 a week (Monday to Sunday), results exempt; the more
important kind wins a day; nothing from 21:00 to 08:00; each key is shown once
ever. Texts rotate by week (`notification_texts.dart`).

Privacy: an action tagged with a private Lebenslage (or a log entry saved
before Lebenslagen were kept, unless the pool still has it) is never named;
those notifications use neutral wording that others also get, never hints
like "persönlich". Titles may show on the lock screen (user decision).

## Mechanics

- `planNotifications` (pure, tested) decides; `Notifications` applies the plan
  with `flutter_local_notifications` (inexact alarms, no exact-alarm
  permission) and keeps state encrypted in secure storage.
- Checks run on app start/resume, after actions, stars, card views and setting
  changes, and in the background via WorkManager about every 2 hours (only
  with notification permission, network required). The pool (~200 KB) is
  reloaded at most every 12 hours, the news (~8 KB) on every check.
- No question of our own: setting a star shows a short hint ("Du bekommst ab
  jetzt alle Neuigkeiten dazu. Ein Tipp auf den Stern beendet das."), taking
  it away "Keine Neuigkeiten mehr dazu.". The first star brings up Android's
  permission dialog (required since Android 13); if refused, the hint offers
  "Einschalten" into the Android settings.
- No in-app switches: the four kinds are Android channels, switched in the
  system's notification settings; Mein Profil only links there. Each check
  reads which channels are off, so an off channel never takes a day's place.

## Not yet

- Council vote results and other outcomes need a public outcome feed on the
  server; until then "Ergebnis" covers petition goals only.
- iOS (needs APNs/background fetch setup), Firebase broadcast for faster news.
