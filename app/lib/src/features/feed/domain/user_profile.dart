import 'home_location.dart';
import 'interest_weights.dart';
import 'lebenslage.dart';
import 'situation_keys.dart';

/// The questionnaire's questions in order: two per value axis (Wirtschaft,
/// Diplomatie, Freiheit, Wandel).
const werteQuestionKeys = [
  'wirtschaft_gleichheit',
  'wirtschaft_staat',
  'diplomatie_nation',
  'diplomatie_welt',
  'freiheit_staat',
  'freiheit_sicherheit',
  'wandel_tradition',
  'wandel_zukunft',
];

class UserProfile {
  const UserProfile({
    this.werte = const {},
    this.region,
    this.plz,
    this.mdbName,
    this.mdbParty,
    this.mdbWahlkreis,
    this.home,
    this.lebenslagen = const {},
    this.interests = const InterestWeights(),
    this.prioritaeten = const {},
    this.einwilligung,
    this.browsing = false,
  });

  /// Someone who agreed to the consent but put the questionnaire off: only
  /// looking at actions for now.
  const UserProfile.browsing({required DateTime this.einwilligung})
      : werte = const {},
        region = null,
        plz = null,
        mdbName = null,
        mdbParty = null,
        mdbWahlkreis = null,
        home = null,
        lebenslagen = const {},
        interests = const InterestWeights(),
        prioritaeten = const {},
        browsing = true;

  factory UserProfile.fromJson(Map<String, Object?> json) {
    final werteRaw = json['werte'] as Map<String, Object?>? ?? {};
    final lebenslagenRaw = json['lebenslagen'] as List<Object?>?;
    final legacyRaw = json['betroffenheitsprofil'] as Map<String, Object?>?;
    final interestsRaw = json['interests'] as Map<String, Object?>?;
    final homeRaw = json['home'] as Map<String, Object?>?;
    final prioritaetenRaw = json['prioritaeten'] as Map<String, Object?>?;
    final interests = interestsRaw != null
        ? InterestWeights.fromJson(interestsRaw)
        : const InterestWeights();
    final einwilligung =
        DateTime.tryParse(json['einwilligung'] as String? ?? '');
    // The old "Beispielprofil" (no Werte, its fixed PLZ and Lebenslagen)
    // becomes what replaced it: only looking, nothing made up.
    if (einwilligung != null &&
        werteRaw.isEmpty &&
        json['plz'] == '01067' &&
        _isOldExample(lebenslagenRaw)) {
      return UserProfile.browsing(einwilligung: einwilligung)
          .copyWith(interests: interests);
    }
    return UserProfile(
      // Saved as whole steps before the slider went continuous.
      werte: werteRaw.map((k, v) => MapEntry(k, (v as num).toDouble())),
      region: json['region'] as String?,
      plz: json['plz'] as String?,
      mdbName: json['mdb_name'] as String?,
      mdbParty: json['mdb_party'] as String?,
      mdbWahlkreis: json['mdb_wahlkreis'] as String?,
      home: homeRaw != null ? HomeLocation.fromJson(homeRaw) : null,
      // Profiles saved before the catalog carry the old Betroffenheitsprofil
      // instead; their answers are carried over, never dropped.
      lebenslagen: lebenslagenRaw != null
          ? {
              for (final id in lebenslagenRaw)
                if (id is String && lebenslageById.containsKey(id)) id,
            }
          : legacyRaw != null
              ? lebenslagenFromLegacy(legacyRaw)
              : const {},
      interests: interests,
      prioritaeten: prioritaetenRaw?.map(
            (k, v) => MapEntry(k, (v as num).toInt()),
          ) ??
          const {},
      einwilligung: einwilligung,
      browsing: json['nur_schauen'] == true,
    );
  }

  static bool _isOldExample(List<Object?>? lebenslagen) =>
      lebenslagen != null &&
      lebenslagen.length == 3 &&
      lebenslagen.toSet().containsAll(const ['mieter', 'oepnv', 'angestellt']);

  UserProfile copyWith({
    Map<String, double>? werte,
    HomeLocation? home,
    Set<String>? lebenslagen,
    InterestWeights? interests,
    Map<String, int>? prioritaeten,
    DateTime? einwilligung,
  }) {
    return UserProfile(
      werte: werte ?? this.werte,
      region: region,
      plz: plz,
      mdbName: mdbName,
      mdbParty: mdbParty,
      mdbWahlkreis: mdbWahlkreis,
      home: home ?? this.home,
      lebenslagen: lebenslagen ?? this.lebenslagen,
      interests: interests ?? this.interests,
      prioritaeten: prioritaeten ?? this.prioritaeten,
      einwilligung: einwilligung ?? this.einwilligung,
      browsing: browsing,
    );
  }

  /// Raw 8values question scores, anywhere from -2.0 to +2.0 (0 = neutral
  /// or unanswered), keyed by [werteQuestionKeys].
  final Map<String, double> werte;
  final String? region;
  final String? plz;
  final String? mdbName;
  final String? mdbParty;
  final String? mdbWahlkreis;

  // Where the PLZ lies (see HomeLocation); null until the server located
  // it, e.g. when the PLZ was entered offline.
  final HomeLocation? home;

  // Lebenslagen catalog ids the user marked as important to them (see
  // Lebenslage). On-device only, never sent to the backend; drives feed
  // relevance. Separate from werte: this says *what* concerns someone, not
  // how they lean on it.
  final Set<String> lebenslagen;

  /// The server's per-card snippet keys these Lebenslagen unlock.
  Set<String> get snippetKeys => snippetKeysFor(lebenslagen);

  // Learned topic interests (see InterestWeights) — on-device only, reorders
  // the feed, never filters it.
  final InterestWeights interests;

  // Coins per budget area from the Stadthaushalt step (GeldEffekt.bereich
  // keys); on-device only. Empty until the user has distributed them.
  final Map<String, int> prioritaeten;

  // When the user agreed to the consent screen; kept on the device only.
  // Null for profiles made before it existed: they see it once on start.
  final DateTime? einwilligung;

  // The questionnaire was put off ("Lieber später"): the hand is dealt at
  // random and the profile offers the questionnaire instead of its answers.
  final bool browsing;

  // Derived axes (-2.0 to +2.0) for the profile's scales. Ranking matches
  // per question instead (an opportunity's werteRelevanz is keyed by
  // werteQuestionKeys), since the two questions of an axis can disagree.
  double get axisEqualityMarkets =>
      (_q('wirtschaft_gleichheit') + _q('wirtschaft_staat')) / 2.0;
  double get axisNationGlobe =>
      (_q('diplomatie_nation') + _q('diplomatie_welt')) / 2.0;
  double get axisLibertyAuthority =>
      (_q('freiheit_staat') + _q('freiheit_sicherheit')) / 2.0;
  double get axisTraditionProgress =>
      (_q('wandel_tradition') + _q('wandel_zukunft')) / 2.0;

  int get answeredCount => werte.values.where((v) => v != 0).length;

  double _q(String key) => werte[key] ?? 0;

  Map<String, Object?> toJson() {
    return {
      'werte': werte,
      'region': region,
      'plz': plz,
      'mdb_name': mdbName,
      'mdb_party': mdbParty,
      'mdb_wahlkreis': mdbWahlkreis,
      'home': home?.toJson(),
      'lebenslagen': lebenslagen.toList(),
      'interests': interests.toJson(),
      'prioritaeten': prioritaeten,
      'einwilligung': einwilligung?.toIso8601String(),
      if (browsing) 'nur_schauen': true,
    };
  }
}
