import 'package:flutter_test/flutter_test.dart';
import 'package:meinimpact/src/features/feed/domain/home_location.dart';
import 'package:meinimpact/src/features/feed/domain/local_coverage.dart';

Map<String, Object?> _response(String? coverage) => {
      'kreis': '14627',
      'lat': 51.144,
      'lon': 13.5707,
      'wahlkreise': const [],
      if (coverage != null) 'coverage': coverage,
    };

void main() {
  test('reads what the server has topics from', () {
    expect(PlzLookup.fromJson(_response('land')).coverage, LocalCoverage.land);
    expect(PlzLookup.fromJson(_response('none')).coverage, LocalCoverage.none);
  });

  test('a missing or unknown value says nothing rather than something wrong',
      () {
    expect(PlzLookup.fromJson(_response(null)).coverage, LocalCoverage.local);
    expect(PlzLookup.fromJson(_response('mars')).coverage, LocalCoverage.local);
    expect(LocalCoverage.local.note, isNull);
  });

  test('only a gap gets a note', () {
    expect(LocalCoverage.land.note, contains('Landkreis'));
    expect(LocalCoverage.none.note, contains('Bundesland'));
  });
}
