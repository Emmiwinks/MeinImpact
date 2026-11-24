import 'package:flutter_test/flutter_test.dart';
import 'package:meinimpact/src/app/meinimpact_app.dart';
import 'package:meinimpact/src/core/profile/user_profile_store.dart';
import 'package:meinimpact/src/features/feed/domain/home_location.dart';
import 'package:meinimpact/src/features/feed/domain/letter_recipients.dart';
import 'package:meinimpact/src/features/feed/domain/mdb.dart';
import 'package:meinimpact/src/features/feed/domain/opportunity.dart';
import 'package:meinimpact/src/features/feed/domain/opportunity_repository.dart';
import 'package:meinimpact/src/features/feed/domain/user_profile.dart';
import 'package:meinimpact/src/features/tracking/data/action_log_store.dart';
import 'package:meinimpact/src/features/tracking/domain/action_log.dart';
import 'package:meinimpact/src/features/tracking/domain/impact_news.dart';

const _dresden = HomeLocation(kreis: '14612', lat: 51.05, lon: 13.73);

const _mdb = MdbOption(
  wahlkreisNr: 159,
  wahlkreisName: 'Dresden I',
  mdbName: 'Jana Beispiel',
  mdbParty: 'Partei A',
);

void main() {
  group('Opportunity locality', () {
    Map<String, Object?> json(Map<String, Object?> extra) => {
          'id': 'opp-1',
          'source_org': 'Ratsinformationssystem Dresden',
          'source_url': 'https://example.org',
          'kind': 'decision',
          'status': 'open',
          'region': 'dresden',
          'title': 'x',
          'summary': 'x',
          'first_seen_at': '2026-11-01T12:00:00Z',
          ...extra,
        };

    test('maps gebiet, reichweite and umkreis', () {
      final opportunity = Opportunity.fromJson(
        json({
          'gebiet': '14612',
          'reichweite': 'nachbarschaft',
          'umkreis': {'lat': 51.03, 'lon': 13.89, 'km': 2.5},
        }),
      );

      expect(opportunity.gebiet, '14612');
      expect(opportunity.reichweite, 'nachbarschaft');
      expect(
        (
          opportunity.umkreis?.lat,
          opportunity.umkreis?.lon,
          opportunity.umkreis?.km,
        ),
        (51.03, 13.89, 2.5),
      );
    });

    test('a pool from before the locality concerns everyone', () {
      final opportunity = Opportunity.fromJson(json({}));

      expect(opportunity.gebiet, '');
      expect(opportunity.reichweite, isNull);
      expect(opportunity.umkreis, isNull);
    });
  });

  group('UserProfile home', () {
    test('round-trips through JSON and survives copyWith', () {
      const profile = UserProfile(plz: '01067', home: _dresden);

      final restored = UserProfile.fromJson(profile.toJson());
      final changed = restored.copyWith(lebenslagen: {'mieter'});

      expect(restored.home?.kreis, '14612');
      expect((restored.home?.lat, restored.home?.lon), (51.05, 13.73));
      expect(changed.home?.kreis, '14612');
    });

    test('a profile saved before it has none', () {
      expect(UserProfile.fromJson(const {'plz': '01067'}).home, isNull);
    });
  });

  test('PlzLookup reads the location response', () {
    final lookup = PlzLookup.fromJson({
      'kreis': '14627',
      'lat': 51.144,
      'lon': 13.5707,
      'wahlkreise': [
        {
          'wahlkreis_nr': 154,
          'wahlkreis_name': 'Meißen',
          'mdb_name': 'Test Person',
          'mdb_party': 'Test Partei',
          'mdb_link': null,
        },
      ],
    });

    expect(lookup.home.kreis, '14627');
    expect(lookup.wahlkreise.single.wahlkreisName, 'Meißen');
  });

  group('the app locates a PLZ it has no place for', () {
    Future<_Profiles> start(
      WidgetTester tester,
      UserProfile profile,
      _Repository repository,
    ) async {
      final profiles = _Profiles();
      await tester.pumpWidget(
        MeinImpactApp.withProfile(
          opportunityRepository: repository,
          profileStore: profiles,
          actionLogStore: _ActionLogs(),
          // Past the consent and the Stadthaushalt, straight to the tabs.
          initialProfile: profile.copyWith(
            einwilligung: DateTime(2026, 11, 24),
            prioritaeten: const {'kultur': 20},
          ),
        ),
      );
      await tester.pumpAndSettle();
      return profiles;
    }

    testWidgets('on start, and asks for the pool of its Kreis', (
      tester,
    ) async {
      final repository = _Repository(
        found: const PlzLookup(home: _dresden, wahlkreise: [_mdb]),
      );

      final profiles = await start(
        tester,
        const UserProfile(plz: '01067'),
        repository,
      );

      expect(repository.located, ['01067']);
      expect(profiles.saved?.home?.kreis, '14612');
      expect(profiles.saved?.mdbName, 'Jana Beispiel');
      // The first load ran before the answer came; the next one narrows.
      expect(repository.poolKreise.last, isNull);
    });

    testWidgets('never asks again once it has one', (tester) async {
      final repository = _Repository();

      await start(
        tester,
        const UserProfile(plz: '01067', home: _dresden),
        repository,
      );

      expect(repository.located, isEmpty);
      expect(repository.poolKreise, ['14612']);
    });

    testWidgets('offline, it keeps the profile as it was', (tester) async {
      final repository = _Repository(offline: true);

      final profiles = await start(
        tester,
        const UserProfile(plz: '01067'),
        repository,
      );

      expect(repository.located, ['01067']);
      expect(profiles.saved, isNull);
    });
  });
}

class _Repository implements OpportunityRepository {
  _Repository({this.found, this.offline = false});

  final PlzLookup? found;
  final bool offline;
  final located = <String>[];
  final poolKreise = <String?>[];

  @override
  Future<PlzLookup?> locate(String plz) async {
    located.add(plz);
    if (offline) throw StateError('offline');
    return found;
  }

  @override
  Future<List<Opportunity>> pool({String? kreis}) async {
    poolKreise.add(kreis);
    return const [];
  }

  @override
  Future<ImpactNewsFeed> impactNews() async => const ImpactNewsFeed();

  @override
  Stream<String> streamLetter(String opportunityId, {String? notes}) =>
      const Stream.empty();

  @override
  Future<LetterRecipients> letterRecipients(String opportunityId) async =>
      const LetterRecipients();

  @override
  Future<void> markTracked(String opportunityId) async {}
}

class _Profiles extends UserProfileStore {
  UserProfile? saved;

  @override
  Future<void> save(UserProfile profile) async => saved = profile;
}

class _ActionLogs extends ActionLogStore {
  @override
  Future<ActionLog> load() async => const ActionLog();

  @override
  Future<void> save(ActionLog log) async {}
}
