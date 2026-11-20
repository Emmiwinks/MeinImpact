/// What the app has topics from for where the user lives, as the server
/// knows it from the sources it reads. Said once, when the PLZ is entered.
enum LocalCoverage {
  // Their city or Kreis, and up.
  local('local'),
  // Their Land, Bund and EU.
  land('land'),
  // Bund and EU only.
  none('none');

  const LocalCoverage(this.wire);

  final String wire;

  /// Unknown or missing values count as [local]: better no note than a
  /// wrong one.
  static LocalCoverage fromWire(String? value) => values.firstWhere(
        (coverage) => coverage.wire == value,
        orElse: () => LocalCoverage.local,
      );

  /// The note under the PLZ, or null when nothing is missing.
  String? get note => switch (this) {
        local => null,
        land => 'Aus deiner Stadt oder deinem Landkreis haben wir noch '
            'keine Themen, nur aus deinem Bundesland, Deutschland und der '
            'EU. Unterstütze uns gern, damit wir weiter wachsen können.',
        none => 'Aus deiner Gegend und deinem Bundesland haben wir noch '
            'keine Themen, nur aus Deutschland und der EU. Unterstütze uns '
            'gern, damit wir weiter wachsen können.',
      };
}
