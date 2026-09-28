import 'betroffenheitsprofil.dart';

class UserProfile {
  const UserProfile({
    this.werte = const {},
    this.region,
    this.plz,
    this.mdbName,
    this.mdbParty,
    this.mdbWahlkreis,
    this.betroffenheitsprofil = const Betroffenheitsprofil(),
  });

  factory UserProfile.fromJson(Map<String, Object?> json) {
    final werteRaw = json['werte'] as Map<String, Object?>? ?? {};
    final betroffenheitRaw =
        json['betroffenheitsprofil'] as Map<String, Object?>?;
    return UserProfile(
      werte: werteRaw.map((k, v) => MapEntry(k, v as int)),
      region: json['region'] as String?,
      plz: json['plz'] as String?,
      mdbName: json['mdb_name'] as String?,
      mdbParty: json['mdb_party'] as String?,
      mdbWahlkreis: json['mdb_wahlkreis'] as String?,
      betroffenheitsprofil: betroffenheitRaw != null
          ? Betroffenheitsprofil.fromJson(betroffenheitRaw)
          : const Betroffenheitsprofil(),
    );
  }

  /// Raw 8values question scores (-2 to +2, 0 = neutral/unanswered).
  /// Keys: wirtschaft_gleichheit, wirtschaft_staat, diplomatie_nation,
  ///       diplomatie_welt, freiheit_staat, freiheit_sicherheit,
  ///       wandel_tradition, wandel_zukunft
  final Map<String, int> werte;
  final String? region;
  final String? plz;
  final String? mdbName;
  final String? mdbParty;
  final String? mdbWahlkreis;

  // Concrete personal-situation profile (Betroffenheitsprofil) — on-device
  // only, drives feed relevance. Never sent to the backend. See
  // Betroffenheitsprofil's docstring for why this is separate from werte.
  final Betroffenheitsprofil betroffenheitsprofil;

  // Derived axes (-2.0 to +2.0). Names match the backend's werte_relevanz
  // axis vocabulary (opportunity_extractor.py's TAG_AXES) — renamed from
  // the pre-rebuild wirtschaft/diplomatie/freiheit/wandel keys, same
  // underlying 8values questions, no change to the quiz itself.
  double get axisEqualityMarkets =>
      (_q('wirtschaft_gleichheit') + _q('wirtschaft_staat')) / 2.0;
  double get axisNationGlobe =>
      (_q('diplomatie_nation') + _q('diplomatie_welt')) / 2.0;
  double get axisLibertyAuthority =>
      (_q('freiheit_staat') + _q('freiheit_sicherheit')) / 2.0;
  double get axisTraditionProgress =>
      (_q('wandel_tradition') + _q('wandel_zukunft')) / 2.0;

  /// All four axes keyed exactly like an opportunity's `werteRelevanz` map,
  /// for direct comparison in `OpportunityRelevanceRanker`.
  Map<String, double> get axisValues => {
        'equality_markets': axisEqualityMarkets,
        'nation_globe': axisNationGlobe,
        'liberty_authority': axisLibertyAuthority,
        'tradition_progress': axisTraditionProgress,
      };

  int get answeredCount => werte.values.where((v) => v != 0).length;

  double _q(String key) => (werte[key] ?? 0).toDouble();

  Map<String, Object?> toJson() {
    return {
      'werte': werte,
      'region': region,
      'plz': plz,
      'mdb_name': mdbName,
      'mdb_party': mdbParty,
      'mdb_wahlkreis': mdbWahlkreis,
      'betroffenheitsprofil': betroffenheitsprofil.toJson(),
    };
  }
}
