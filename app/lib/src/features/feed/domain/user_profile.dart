// Mockup demographic profile used for the meetup demo — the app has no UI
// yet to collect these fields, so every profile is seeded with this persona
// unless overridden. Feeds both the on-screen bio card and the
// lebenssituation/sektor/wohnsituation sent to the personalised-context AI.
const _demoCity = 'Dresden';
const _demoOccupation = 'Krankenschwester';
const _demoFamilyStatus = 'Verheiratet, 40 Jahre · 1 Kind (9 Jahre)';
const _demoWohnsituation = 'Mietwohnung';
const _demoSektor = 'Gesundheitswesen';
const _demoLebenssituation = ['elternteil', 'berufstaetig'];
const _demoPlz = '01067';

class UserProfile {
  const UserProfile({
    this.werte = const {},
    this.region,
    this.plz = _demoPlz,
    this.mdbName,
    this.mdbParty,
    this.mdbWahlkreis,
    this.city = _demoCity,
    this.occupation = _demoOccupation,
    this.familyStatus = _demoFamilyStatus,
    this.wohnsituation = _demoWohnsituation,
    this.sektor = _demoSektor,
    this.lebenssituation = _demoLebenssituation,
  });

  factory UserProfile.fromJson(Map<String, Object?> json) {
    final werteRaw = json['werte'] as Map<String, Object?>? ?? {};
    return UserProfile(
      werte: werteRaw.map((k, v) => MapEntry(k, v as int)),
      region: json['region'] as String?,
      plz: json['plz'] as String? ?? _demoPlz,
      mdbName: json['mdb_name'] as String?,
      mdbParty: json['mdb_party'] as String?,
      mdbWahlkreis: json['mdb_wahlkreis'] as String?,
      city: json['city'] as String? ?? _demoCity,
      occupation: json['occupation'] as String? ?? _demoOccupation,
      familyStatus: json['family_status'] as String? ?? _demoFamilyStatus,
      wohnsituation: json['wohnsituation'] as String? ?? _demoWohnsituation,
      sektor: json['sektor'] as String? ?? _demoSektor,
      lebenssituation:
          (json['lebenssituation'] as List<Object?>?)?.cast<String>() ??
              _demoLebenssituation,
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

  // Demographic bio — mocked for the demo (see defaults above).
  final String? city;
  final String? occupation;
  final String? familyStatus;
  final String? wohnsituation;
  final String? sektor;
  final List<String> lebenssituation;

  // Derived axes (-2.0 to +2.0)
  double get axisWirtschaft =>
      (_q('wirtschaft_gleichheit') + _q('wirtschaft_staat')) / 2.0;
  double get axisDiplomatie =>
      (_q('diplomatie_nation') + _q('diplomatie_welt')) / 2.0;
  double get axisFreiheit =>
      (_q('freiheit_staat') + _q('freiheit_sicherheit')) / 2.0;
  double get axisWandel =>
      (_q('wandel_tradition') + _q('wandel_zukunft')) / 2.0;

  int get answeredCount => werte.values.where((v) => v != 0).length;

  List<String> deriveToneDescriptors() {
    final result = <String>[];
    if (axisWirtschaft < -0.5) result.add('community-oriented');
    if (axisWirtschaft > 0.5) result.add('pragmatic');
    if (axisDiplomatie < -0.5) result.add('nationally-focused');
    if (axisDiplomatie > 0.5) result.add('internationally-minded');
    if (axisFreiheit < -0.5) result.add('rights-conscious');
    if (axisFreiheit > 0.5) result.add('security-oriented');
    if (axisWandel < -0.5) result.add('stability-oriented');
    if (axisWandel > 0.5) result.add('reform-minded');
    if (result.isEmpty) result.add('balanced');
    return result;
  }

  double _q(String key) => (werte[key] ?? 0).toDouble();

  Map<String, Object?> toJson() {
    return {
      'werte': werte,
      'region': region,
      'plz': plz,
      'mdb_name': mdbName,
      'mdb_party': mdbParty,
      'mdb_wahlkreis': mdbWahlkreis,
      'city': city,
      'occupation': occupation,
      'family_status': familyStatus,
      'wohnsituation': wohnsituation,
      'sektor': sektor,
      'lebenssituation': lebenssituation,
    };
  }
}
