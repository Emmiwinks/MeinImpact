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
  List<String> actionTypes = const ['petition'],
  DateTime? deadline,
  int? supportCount,
}) {
  return Opportunity(
    id: id,
    sourceOrg: 'openPetition',
    decisionObject: 'Decision $id',
    plainLanguageTitle: 'Title $id',
    plainLanguageSummary: 'Summary $id',
    affectedTags: affectedTags,
    region: 'bund',
    werteRelevanz: werteRelevanz,
    sourceUrl: 'https://example.org/$id',
    actionTypes: actionTypes,
    proArgumente: const [],
    contraArgumente: const [],
    personalImpactSnippets: personalImpactSnippets,
    retrievedAt: DateTime(2026, 9, 27),
    deadline: deadline,
    supportCount: supportCount,
  );
}

void main() {
  group('Opportunity.fromJson', () {
    test('maps the full backend shape', () {
      final opportunity = Opportunity.fromJson({
        'id': 'opp-1',
        'source_org': 'openPetition',
        'decision_object': 'Mietendeckel einführen',
        'plain_language_title': 'Soll ein Mietendeckel eingeführt werden?',
        'plain_language_summary': 'Zusammenfassung.',
        'affected_tags': ['Wohnen/Miete'],
        'region': 'bund',
        'werte_relevanz': {'equality_markets': -0.8},
        'deadline': '2026-12-01',
        'support_count': 12345,
        'support_count_as_of': '2026-09-27T00:00:00Z',
        'content_published_at': null,
        'retrieved_at': '2026-09-27T10:00:00Z',
        'source_url': 'https://openpetition.de/petition/online/x',
        'action_types': ['petition'],
        'pro_argumente': ['Argument 1'],
        'contra_argumente': ['Gegenargument 1'],
        'personal_impact_snippets': {
          'wohnsituation:mieter': 'Betrifft dich direkt.',
        },
      });

      expect(opportunity.id, 'opp-1');
      expect(opportunity.sourceOrg, 'openPetition');
      expect(opportunity.affectedTags, ['Wohnen/Miete']);
      expect(opportunity.werteRelevanz, {'equality_markets': -0.8});
      expect(opportunity.deadline, DateTime.parse('2026-12-01'));
      expect(opportunity.supportCount, 12345);
      expect(
        opportunity.personalImpactSnippets['wohnsituation:mieter'],
        'Betrifft dich direkt.',
      );
    });

    test('handles absent optional fields without throwing', () {
      final opportunity = Opportunity.fromJson({
        'id': 'opp-2',
        'source_org': 'WeAct/Campact',
        'decision_object': 'x',
        'plain_language_title': 'x',
        'plain_language_summary': 'x',
        'region': 'bund',
        'retrieved_at': '2026-09-27T10:00:00Z',
        'source_url': 'https://example.org',
      });

      expect(opportunity.affectedTags, isEmpty);
      expect(opportunity.werteRelevanz, isEmpty);
      expect(opportunity.deadline, isNull);
      expect(opportunity.supportCount, isNull);
      expect(opportunity.personalImpactSnippets, isEmpty);
    });
  });

  group('ActionCta.forOpportunity', () {
    test('labels a petition', () {
      final cta = ActionCta.forOpportunity(
        _opportunity(actionTypes: const ['petition']),
      );
      expect(cta.label, 'Petition unterschreiben');
    });

    test('labels a consultation', () {
      final cta = ActionCta.forOpportunity(
        _opportunity(actionTypes: const ['consultation']),
      );
      expect(cta.label, 'Jetzt mitmachen');
    });

    test('falls back to a generic label with no action types', () {
      final cta = ActionCta.forOpportunity(
        _opportunity(actionTypes: const []),
      );
      expect(cta.label, isNotEmpty);
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
