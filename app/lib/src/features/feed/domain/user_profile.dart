class UserProfile {
  const UserProfile({
    this.werte = const {},
    this.region,
    this.plz,
    this.mdbName,
    this.mdbParty,
    this.mdbWahlkreis,
  });

  factory UserProfile.fromJson(Map<String, Object?> json) {
    final werteRaw = json['werte'] as Map<String, Object?>? ?? {};
    return UserProfile(
      werte: werteRaw.map((k, v) => MapEntry(k, v as int)),
      region: json['region'] as String?,
      plz: json['plz'] as String?,
      mdbName: json['mdb_name'] as String?,
      mdbParty: json['mdb_party'] as String?,
      mdbWahlkreis: json['mdb_wahlkreis'] as String?,
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
    };
  }
}
