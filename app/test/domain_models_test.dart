import 'package:flutter_test/flutter_test.dart';
import 'package:meinimpact/src/features/feed/data/opportunity_relevance_ranker.dart';
import 'package:meinimpact/src/features/feed/domain/betroffenheitsprofil.dart';
import 'package:meinimpact/src/features/feed/domain/opportunity.dart';
import 'package:meinimpact/src/features/feed/domain/user_profile.dart';

Opportunity _opportunity({
  String id = 'opp-1',
  List<String> affectedTags = const [],
  Map<String, double> werteRelevanz = const {},
  Map<String, String> personalImpactSnippets = const {},
  OpportunityKind kind = OpportunityKind.petition,
  DateTime? closesOn,
  int? supportCount,
  int? everyday,
  int? accessible,
}) {
  return Opportunity(
    id: id,
    sourceOrg: 'openPetition',
    sourceUrl: 'https://example.org/$id',
    kind: kind,
    isAnnounced: false,
    region: 'bund',
    title: 'Title $id',
    summary: 'Summary $id',
    affectedTags: affectedTags,
    werteRelevanz: werteRelevanz,
    proArgumente: const [],
    contraArgumente: const [],
    personalImpactSnippets: personalImpactSnippets,
    firstSeenAt: DateTime(2026, 11, 1),
    closesOn: closesOn,
    supportCount: supportCount,
    everydayRelevance: everyday,
    accessibility: accessible,
  );
}

void main() {
  group('Opportunity.fromJson', () {
    test('maps the full backend shape', () {
      final opportunity = Opportunity.fromJson({
        'id': 'opp-1',
        'source_org': 'Beteiligungsportal Sachsen',
        'source_url': 'https://buergerbeteiligung.sachsen.de/portal/x',
        'kind': 'public_display',
        'status': 'announced',
        'region': 'dresden',
        'locality': 'Landeshauptstadt Dresden',
        'organizer': 'Landeshauptstadt Dresden',
        'title': 'Soll am Alten Leipziger Bahnhof gebaut werden?',
        'summary': 'Zusammenfassung.',
        'affected_tags': ['Wohnen/Miete'],
        'werte_relevanz': {'equality_markets': -0.8},
        'pro_argumente': ['Argument 1'],
        'contra_argumente': ['Gegenargument 1'],
        'personal_impact_snippets': {
          'wohnsituation:mieter': 'Betrifft dich direkt.',
        },
        'districts': ['Mockritz'],
        'opens_on': '2026-11-02',
        'closes_on': '2026-12-04',
        'support_count': 3,
        'support_goal': null,
        'support_count_as_of': '2026-11-01T12:00:00Z',
        'first_seen_at': '2026-11-01T12:00:00Z',
      });

      expect(opportunity.kind, OpportunityKind.publicDisplay);
      expect(opportunity.isAnnounced, isTrue);
      expect(opportunity.region, 'dresden');
      expect(opportunity.organizer, 'Landeshauptstadt Dresden');
      expect(opportunity.districts, ['Mockritz']);
      expect(opportunity.affectedTags, ['Wohnen/Miete']);
      expect(opportunity.werteRelevanz, {'equality_markets': -0.8});
      expect(opportunity.opensOn, DateTime.parse('2026-11-02'));
      expect(opportunity.closesOn, DateTime.parse('2026-12-04'));
      expect(opportunity.supportCount, 3);
      expect(
        opportunity.personalImpactSnippets['wohnsituation:mieter'],
        'Betrifft dich direkt.',
      );
    });

    test('handles absent optional fields and unknown kinds', () {
      final opportunity = Opportunity.fromJson({
        'id': 'opp-2',
        'source_org': 'WeAct',
        'source_url': 'https://example.org',
        'kind': 'something_new',
        'status': 'open',
        'region': 'bund',
        'title': 'x',
        'summary': 'x',
        'first_seen_at': '2026-11-01T12:00:00Z',
      });

      expect(opportunity.kind, OpportunityKind.other);
      expect(opportunity.isAnnounced, isFalse);
      expect(opportunity.districts, isEmpty);
      expect(opportunity.affectedTags, isEmpty);
      expect(opportunity.werteRelevanz, isEmpty);
      expect(opportunity.closesOn, isNull);
      expect(opportunity.supportCount, isNull);
      expect(opportunity.personalImpactSnippets, isEmpty);
    });
  });

  group('Opportunity.daysLeft', () {
    final now = DateTime(2026, 11, 1, 18, 30);

    test('counts whole calendar days, 0 on the last day', () {
      expect(_opportunity(closesOn: DateTime(2026, 11, 4)).daysLeft(now), 3);
      expect(_opportunity(closesOn: DateTime(2026, 11, 1)).daysLeft(now), 0);
    });

    test('is null without an end date or after it', () {
      expect(_opportunity().daysLeft(now), isNull);
      expect(
        _opportunity(closesOn: DateTime(2026, 10, 31)).daysLeft(now),
        isNull,
      );
    });
  });

  group('OpportunityKind', () {
    test('maps every backend kind and labels its call to action', () {
      expect(
        OpportunityKind.fromWire('petition').callToAction,
        'Petition unterschreiben',
      );
      expect(
        OpportunityKind.fromWire('consultation').callToAction,
        'Stellung nehmen',
      );
      expect(
        OpportunityKind.fromWire('public_display'),
        OpportunityKind.publicDisplay,
      );
      expect(OpportunityKind.fromWire('survey'), OpportunityKind.survey);
      expect(OpportunityKind.fromWire(null), OpportunityKind.other);
    });
  });
  group('Betroffenheitsprofil.matchingKeys', () {
    test('is empty for an unanswered profile', () {
      expect(const Betroffenheitsprofil().matchingKeys(), isEmpty);
    });

    test('includes only set/true fields, formatted like the backend keys', () {
      const profile = Betroffenheitsprofil(
        wohnsituation: Wohnsituation.mieter,
        oepnvNutzung: true,
        hatKinder: true,
        erwerbsstatus: Erwerbsstatus.schuelerStudent,
        migrationshintergrund: true,
      );

      expect(profile.matchingKeys(), {
        'wohnsituation:mieter',
        'oepnv_nutzung:true',
        'hat_kinder:true',
        'erwerbsstatus:schueler_student',
        'migrationshintergrund:true',
      });
    });

    test('false booleans and null migrationshintergrund produce no key', () {
      const profile = Betroffenheitsprofil(
        oepnvNutzung: false,
        migrationshintergrund: null,
      );
      expect(profile.matchingKeys(), isEmpty);
    });

    test('migrationshintergrund:false is distinct from null (no key either)',
        () {
      const profile = Betroffenheitsprofil(migrationshintergrund: false);
      expect(profile.matchingKeys(), isEmpty);
    });
  });

  group('UserProfile axis derivation', () {
    test('derives axes from werte question scores under the new names', () {
      const profile = UserProfile(
        werte: {
          'wirtschaft_gleichheit': -2,
          'wirtschaft_staat': -1,
          'diplomatie_nation': 2,
        },
      );

      expect(profile.axisEqualityMarkets, -1.5);
      expect(profile.axisNationGlobe, 1.0);
      expect(profile.axisLibertyAuthority, 0.0);
      expect(profile.axisTraditionProgress, 0.0);
    });

    test('axisValues keys match the backend werte_relevanz vocabulary', () {
      const profile = UserProfile(werte: {'wirtschaft_gleichheit': 2});
      expect(profile.axisValues.keys, {
        'equality_markets',
        'nation_globe',
        'liberty_authority',
        'tradition_progress',
      });
    });
  });

  group('OpportunityRelevanceRanker', () {
    const ranker = OpportunityRelevanceRanker();

    test('never drops an opportunity, regardless of match', () {
      final pool = [
        _opportunity(id: 'a'),
        _opportunity(id: 'b', affectedTags: const ['Wohnen/Miete']),
      ];
      final ranked = ranker.rank(pool, const UserProfile());
      expect(ranked, hasLength(2));
    });

    test('opportunities with a matched personal snippet rank above others', () {
      final matched = _opportunity(
        id: 'matched',
        personalImpactSnippets: const {
          'wohnsituation:mieter': 'Betrifft dich.',
        },
      );
      final unmatched = _opportunity(id: 'unmatched');
      const profile = UserProfile(
        betroffenheitsprofil: Betroffenheitsprofil(
          wohnsituation: Wohnsituation.mieter,
        ),
      );

      final ranked = ranker.rank([unmatched, matched], profile);

      expect(ranked.first.opportunity.id, 'matched');
      expect(ranked.first.matchedSnippet, 'Betrifft dich.');
      expect(ranked.last.matchedSnippet, isNull);
    });

    test('orders by werte alignment when profile is sufficiently answered', () {
      final aligned = _opportunity(
        id: 'aligned',
        werteRelevanz: const {'equality_markets': 1.0},
      );
      final opposed = _opportunity(
        id: 'opposed',
        werteRelevanz: const {'equality_markets': -1.0},
      );
      // 4 answered questions — meets _minAnsweredForWerteMatch.
      const profile = UserProfile(
        werte: {
          'wirtschaft_gleichheit': 2,
          'wirtschaft_staat': 2,
          'diplomatie_nation': 1,
          'freiheit_staat': 1,
        },
      );

      final ranked = ranker.rank([opposed, aligned], profile);

      expect(ranked.first.opportunity.id, 'aligned');
      expect(ranked.first.werteAlignment, greaterThan(0.5));
      expect(ranked.last.werteAlignment, lessThan(0.5));
    });

    test('easy everyday cards rank above niche ones, after the match', () {
      final niche = _opportunity(id: 'niche', everyday: 1, accessible: 3);
      final everyday = _opportunity(id: 'everyday', everyday: 5, accessible: 5);
      final matchedNiche = _opportunity(
        id: 'matched-niche',
        everyday: 2,
        accessible: 2,
        personalImpactSnippets: const {'hat_kinder:true': 'Betrifft dich.'},
      );
      const profile = UserProfile(
        betroffenheitsprofil: Betroffenheitsprofil(hatKinder: true),
      );

      final ranked = ranker.rank([niche, everyday, matchedNiche], profile);

      expect(
        ranked.map((r) => r.opportunity.id),
        ['matched-niche', 'everyday', 'niche'],
      );
    });

    test('unscored opportunities count as average appeal', () {
      expect(_opportunity().appeal, 0.5);
      expect(_opportunity(everyday: 5, accessible: 5).appeal, 1.0);
      expect(_opportunity(everyday: 1, accessible: 1).appeal, 0.0);
    });

    test('werte alignment stays neutral when profile has under 4 answers', () {
      final opportunity = _opportunity(
        werteRelevanz: const {'equality_markets': 1.0},
      );
      const profile = UserProfile(werte: {'wirtschaft_gleichheit': 2});

      final ranked = ranker.rank([opportunity], profile);

      expect(ranked.single.werteAlignment, 0.5);
    });
  });
}
