import 'local_coverage.dart';
import 'mdb.dart';

/// Where the user lives, as the server located their PLZ. Kept on the
/// device; only [kreis] is ever sent again, to narrow the pool to their
/// Land. The point ranks nearby opportunities up.
class HomeLocation {
  const HomeLocation({
    required this.kreis,
    required this.lat,
    required this.lon,
  });

  factory HomeLocation.fromJson(Map<String, Object?> json) {
    return HomeLocation(
      kreis: json['kreis'] as String,
      lat: (json['lat'] as num).toDouble(),
      lon: (json['lon'] as num).toDouble(),
    );
  }

  // Official key (AGS) of the Kreis or kreisfreie Stadt, e.g. "14612".
  final String kreis;
  final double lat;
  final double lon;

  Map<String, Object?> toJson() => {'kreis': kreis, 'lat': lat, 'lon': lon};
}

/// What locating a PLZ gives: where it lies, its members of the Bundestag
/// (several where it straddles Wahlkreise, none while the Bundestag's data
/// is unavailable), and what the app has topics from there.
class PlzLookup {
  const PlzLookup({
    required this.home,
    this.wahlkreise = const [],
    this.coverage = LocalCoverage.local,
  });

  factory PlzLookup.fromJson(Map<String, Object?> json) {
    return PlzLookup(
      home: HomeLocation.fromJson(json),
      wahlkreise: (json['wahlkreise'] as List<Object?>? ?? const [])
          .whereType<Map<String, Object?>>()
          .map(MdbOption.fromJson)
          .toList(growable: false),
      coverage: LocalCoverage.fromWire(json['coverage'] as String?),
    );
  }

  final HomeLocation home;
  final List<MdbOption> wahlkreise;
  final LocalCoverage coverage;
}
