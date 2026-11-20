import 'package:flutter_test/flutter_test.dart';
import 'package:meinimpact/src/features/feed/data/opportunity_relevance_ranker.dart';
import 'package:meinimpact/src/features/feed/domain/home_location.dart';
import 'package:meinimpact/src/features/feed/domain/locality_config.dart';
import 'package:meinimpact/src/features/feed/domain/opportunity.dart';
import 'package:meinimpact/src/features/feed/domain/user_profile.dart';

// Areas as the server sends them for Dresden.
const _dresden = Umkreis(lat: 51.0466, lon: 13.7445, km: 12.4);
const _schoenfeld = Umkreis(lat: 51.0333, lon: 13.8947, km: 2.5);

const _prohlis = HomeLocation(kreis: '14612', lat: 51.0065, lon: 13.7986);
const _schoenfeldHome =
    HomeLocation(kreis: '14612', lat: 51.0350, lon: 13.8900);
const _leipzig = HomeLocation(kreis: '14713', lat: 51.3397, lon: 12.3731);

Opportunity _card(
  String id, {
  String gebiet = '',
  String? reichweite,
  Umkreis? umkreis,
}) =>
    Opportunity(
      id: id,
      sourceOrg: 'Ratsinformationssystem Dresden',
      sourceUrl: 'https://example.org/$id',
      kind: OpportunityKind.decision,
      isAnnounced: false,
      region: 'dresden',
      title: id,
      summary: id,
      affectedTags: const [],
      werteRelevanz: const {},
      proArgumente: const [],
      contraArgumente: const [],
      personalImpactSnippets: const {},
      firstSeenAt: DateTime(2026, 11, 1),
      gebiet: gebiet,
      reichweite: reichweite,
      umkreis: umkreis,
    );

final _pool = [
  _card(
    'rastplatz',
    gebiet: '14612',
    reichweite: 'nachbarschaft',
    umkreis: _schoenfeld,
  ),
  _card('kita', gebiet: '14612', reichweite: 'stadt', umkreis: _dresden),
  _card('rente'),
];

List<String> _order(HomeLocation? home) => const OpportunityRelevanceRanker()
    .rank(_pool, UserProfile(home: home))
    .map((r) => r.opportunity.id)
    .toList();

void main() {
  group('nearness', () {
    test('is 1 inside the area and halves per radius beyond it', () {
      expect(nearness(_dresden, _prohlis), 1);
      // About two radii (5 km) east of the Schönfeld area's edge.
      final away = HomeLocation(
        kreis: '14612',
        lat: _schoenfeld.lat,
        lon: _schoenfeld.lon + 7.5 / 70.0,
      );
      expect(nearness(_schoenfeld, away), closeTo(0.25, 0.03));
    });

    test('distance matches the server', () {
      expect(
        distanceKm(51.0504, 13.7373, 51.3397, 12.3731),
        closeTo(100, 2),
      );
    });
  });

  group('ranking by distance', () {
    test('another neighbourhood sinks below city and Bund matters', () {
      expect(_order(_prohlis), ['kita', 'rente', 'rastplatz']);
    });

    test("one's own neighbourhood comes first", () {
      expect(_order(_schoenfeldHome).first, 'rastplatz');
    });

    test("another city's matters sink, Bund ones stay", () {
      expect(_order(_leipzig).first, 'rente');
      const config = LocalityConfig();
      expect(
        config.adjustment(_pool[1], _leipzig),
        closeTo(-config.farPenalty, 0.01),
      );
    });

    test('without a home nothing moves', () {
      const config = LocalityConfig();
      for (final card in _pool) {
        expect(config.adjustment(card, null), 0);
      }
      expect(config.adjustment(_pool[2], _prohlis), 0);
    });
  });
}
