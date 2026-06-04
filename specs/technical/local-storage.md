# Local Storage

## Purpose
Defines the complete Hive schema on the Flutter device: all boxes,
keys, value types, defaults, and migration rules.

---

## Decisions

- **Hive is the only local storage mechanism.** No SQLite, no shared
  preferences, no in-memory-only state that needs persistence.

- **Five Hive boxes.** Each box has a single clear responsibility.
  No cross-box dependencies in read/write operations.

- **The `auth` box is never cleared by "delete my data".** Beta token
  survives profile resets so the user does not lose app access.

- **Schema version is in the `meta` box.** All migrations read from
  and write to `meta.schema_version`.

- **All box keys are constants.** No dynamic key generation. All keys
  are defined in a single `StorageKeys` class.

---

## Box Definitions

### Box: `auth`
Access control only. Never deleted by user data reset.

```dart
// Keys
const kBetaToken = 'beta_token';  // String UUID | null

// Usage
final box = Hive.box('auth');
final token = box.get(kBetaToken);
box.put(kBetaToken, tokenUuid);
```

---

### Box: `meta`
App state and schema versioning.

```dart
const kSchemaVersion       = 'schema_version';       // int, default 1
const kOnboardingCompleted = 'onboarding_completed'; // bool, default false
const kOnboardingStep      = 'onboarding_step';      // int 0–6, default 0
const kMinAgeConfirmed     = 'min_age_confirmed';    // bool, default false
const kConsentsConfirmed   = 'consents_confirmed';   // bool, default false
const kConsentTimestamp    = 'consent_timestamp';    // String ISO8601 | null
const kPendingBadge        = 'pending_badge';        // String | null
const kAppVersion          = 'app_version';          // String semver
```

---

### Box: `profile`
Political profile and demographic data. Cleared on "delete my data".

```dart
// Value profile (8values axes)
const kWertWirtschaftGleichheit  = 'wert_wirtschaft_gleichheit';  // int -2..2
const kWertWirtschaftStaat       = 'wert_wirtschaft_staat';       // int -2..2
const kWertDiplomatieNation      = 'wert_diplomatie_nation';      // int -2..2
const kWertDiplomatieWelt        = 'wert_diplomatie_welt';        // int -2..2
const kWertFreiheitStaat         = 'wert_freiheit_staat';         // int -2..2
const kWertFreiheitSicherheit    = 'wert_freiheit_sicherheit';    // int -2..2
const kWertWandelTradition       = 'wert_wandel_tradition';       // int -2..2
const kWertWandelZukunft         = 'wert_wandel_zukunft';         // int -2..2

// Topic selection
const kTopics     = 'topics';     // List<String>
const kBlacklist  = 'blacklist';  // List<String>

// Demographic profile
const kPlz              = 'plz';              // String | null
const kLebenssituation  = 'lebenssituation';  // List<String>
const kSektor           = 'sektor';           // String | null
const kWohnsituation    = 'wohnsituation';    // String | null

// Personal identity (for letter pre-filling)
const kVorname   = 'vorname';    // String | null
const kNachname  = 'nachname';   // String | null
const kStrasse   = 'strasse';    // String | null
const kOrt       = 'ort';        // String | null

// Cached MdB data (refreshed every 30 days)
const kMdbData      = 'mdb_data';       // Map<String, dynamic> | null
const kMdbCachedAt  = 'mdb_cached_at';  // String ISO8601 | null
```

---

### Box: `gamification`
Engagement tracking. Cleared on "delete my data".

```dart
const kCurrentStreak      = 'current_streak';       // int, default 0
const kLongestStreak      = 'longest_streak';        // int, default 0
const kLastActionWeek     = 'last_action_week';      // String "YYYY-Www" | null
const kTotalActions       = 'total_actions';         // int, default 0
const kLetterCount        = 'letter_count';          // int, default 0
const kPetitionCount      = 'petition_count';        // int, default 0
const kAnfrageCount       = 'anfrage_count';         // int, default 0
const kBadges             = 'badges';                // List<String>
const kCompletedThisWeek  = 'completed_this_week';   // List<String> action IDs
const kDismissedThisWeek  = 'dismissed_this_week';   // List<String> action IDs
const kLastWeeklyReset    = 'last_weekly_reset';     // String ISO8601 | null
const kUniqueTopicsActed  = 'unique_topics_acted';   // List<String>
const kHasTrackingEvent   = 'has_tracking_event';    // bool, default false

// Action history for tracking screen
const kActionHistory = 'action_history';
// List<Map> — each entry:
// { 'id': String, 'title': String, 'type': String,
//   'completed_at': String ISO8601, 'tracking_status': String }
```

---

### Box: `settings`
User preferences. Cleared on "delete my data".

```dart
const kLanguage               = 'language';                // String 'de' | 'en'
const kFontSize               = 'font_size';               // String 'normal' | 'large' | 'xlarge'
const kHighContrast           = 'high_contrast';           // bool, default false
const kReducedMotion          = 'reduced_motion';          // bool, default false
const kNotificationsEnabled   = 'notifications_enabled';   // bool, default false
const kPushToken              = 'push_token';              // String | null
```

---

### Box: `pool_cache`
Action pool cache. Cleared when pool version changes (automatic).

```dart
const kPoolVersion   = 'pool_version';   // String date | null
const kPoolData      = 'pool_data';      // String JSON | null
const kPoolCachedAt  = 'pool_cached_at'; // String ISO8601 | null
```

---

### Box: `session_cache`
Cleared on app restart. In-memory persistence within a session.

```dart
const kCurrentActionId    = 'current_action_id';    // String UUID | null
const kCurrentActionData  = 'current_action_data';  // String JSON | null
const kCurrentDraft       = 'current_draft';         // String | null
const kSessionStarted     = 'session_started';       // String ISO8601 | null
```

---

## Initialisation

All boxes are opened on app start before any UI renders:

```dart
Future<void> initHive() async {
  await Hive.initFlutter();
  await Future.wait([
    Hive.openBox('auth'),
    Hive.openBox('meta'),
    Hive.openBox('profile'),
    Hive.openBox('gamification'),
    Hive.openBox('settings'),
    Hive.openBox('pool_cache'),
    Hive.openBox('session_cache'),
  ]);
  await runMigrations();
  clearSessionCache();  // Always clear on fresh start
}
```

---

## Schema Migration

```dart
Future<void> runMigrations() async {
  final meta = Hive.box('meta');
  final current = meta.get(kSchemaVersion, defaultValue: 0);
  const target = 1;  // Increment with each schema change

  if (current >= target) return;

  if (current < 1) {
    // V0 → V1: initial schema, set defaults
    await _migrateV0toV1();
  }
  // Future migrations:
  // if (current < 2) await _migrateV1toV2();

  meta.put(kSchemaVersion, target);
}

Future<void> _migrateV0toV1() async {
  // Set all integer defaults for value profile
  final profile = Hive.box('profile');
  for (final key in [
    kWertWirtschaftGleichheit, kWertWirtschaftStaat,
    kWertDiplomatieNation, kWertDiplomatieWelt,
    kWertFreiheitStaat, kWertFreiheitSicherheit,
    kWertWandelTradition, kWertWandelZukunft,
  ]) {
    profile.putIfAbsent(key, () => 0);
  }
  profile.putIfAbsent(kTopics, () => <String>[]);
  profile.putIfAbsent(kBlacklist, () => <String>[]);
  profile.putIfAbsent(kLebenssituation, () => <String>[]);

  final gamification = Hive.box('gamification');
  gamification.putIfAbsent(kCurrentStreak, () => 0);
  gamification.putIfAbsent(kTotalActions, () => 0);
  gamification.putIfAbsent(kBadges, () => <String>[]);
  gamification.putIfAbsent(kCompletedThisWeek, () => <String>[]);
  gamification.putIfAbsent(kDismissedThisWeek, () => <String>[]);
  gamification.putIfAbsent(kActionHistory, () => <Map>[]);
}
```

---

## "Delete My Data" Implementation

```dart
Future<void> deleteAllUserData() async {
  // Clear all boxes EXCEPT auth (beta token survives)
  await Hive.box('meta').clear();
  await Hive.box('profile').clear();
  await Hive.box('gamification').clear();
  await Hive.box('settings').clear();
  await Hive.box('pool_cache').clear();
  await Hive.box('session_cache').clear();

  // Re-initialise defaults
  await runMigrations();

  // Navigate to onboarding
  // (meta.onboarding_completed is now false)
}
```

---

## Data Export ("Download My Data")

```dart
Future<Map<String, dynamic>> exportUserData() async {
  return {
    'exported_at': DateTime.now().toIso8601String(),
    'app_version': Hive.box('meta').get(kAppVersion),
    'profile': {
      'werte': {
        'wirtschaft_gleichheit': Hive.box('profile').get(kWertWirtschaftGleichheit),
        // ... all werte keys
      },
      'topics': Hive.box('profile').get(kTopics),
      // Note: PLZ and demographic fields included
      // Note: personal identity (name, address) NOT included in export
      //       — user manages those themselves
    },
    'gamification': {
      'streak': Hive.box('gamification').get(kCurrentStreak),
      'total_actions': Hive.box('gamification').get(kTotalActions),
      'badges': Hive.box('gamification').get(kBadges),
      'action_history': Hive.box('gamification').get(kActionHistory),
    },
    'settings': {
      'language': Hive.box('settings').get(kLanguage),
      'font_size': Hive.box('settings').get(kFontSize),
      'high_contrast': Hive.box('settings').get(kHighContrast),
    },
  };
}
```

---

## Storage Size Estimates

| Box | Max size | Notes |
|---|---|---|
| auth | < 1 KB | One UUID |
| meta | < 2 KB | Small flags and strings |
| profile | < 10 KB | Profile + MdB cache |
| gamification | ~50 KB | History grows over time |
| settings | < 2 KB | |
| pool_cache | ~150 KB | Pool JSON |
| session_cache | ~20 KB | One action + draft |
| **Total** | **~235 KB** | Well within device limits |

---

## Dependencies

- Reads: `architecture/overview.md`, `user/value-profile.md`,
  `user/general-profile.md`, `features/gamification.md`
- Referenced by: `features/feed.md`, `technical/api-endpoints.md`

---

## Open Questions

- None.
