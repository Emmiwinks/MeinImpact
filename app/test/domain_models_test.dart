import 'package:flutter_test/flutter_test.dart';
import 'package:meinimpact/src/features/feed/data/opportunity_relevance_ranker.dart';
import 'package:meinimpact/src/features/feed/domain/lebenslagen_search.dart';
import 'package:meinimpact/src/features/feed/domain/opportunity.dart';
import 'package:meinimpact/src/features/feed/domain/user_profile.dart';
import 'package:meinimpact/src/features/feed/presentation/hand/action_card.dart';

Opportunity _opportunity({
  String id = 'opp-1',
  List<String> affectedTags = const [],
  List<String> lebenslagen = const [],
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
    lebenslagen: lebenslagen,
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
  group('UserProfile Lebenslagen', () {
    test('unlock the backend snippet keys, formatted exactly', () {
      const profile = UserProfile(
        lebenslagen: {'mieter', 'oepnv', 'kita_kinder', 'studierend', 'lgbtq'},
      );

      expect(profile.snippetKeys, {
        'wohnsituation:mieter',
        'oepnv_nutzung:true',
        'hat_kinder:true',
        'erwerbsstatus:schueler_student',
      });
      expect(const UserProfile().snippetKeys, isEmpty);
    });

    test('a profile saved before the catalog keeps its answers', () {
      final profile = UserProfile.fromJson(const {
        'betroffenheitsprofil': {
          'wohnsituation': 'eigentuemer',
          'oepnv_nutzung': false,
          'auto_nutzung': true,
          'hat_kinder': true,
          'erwerbsstatus': 'arbeitslos',
          'pflege_betroffen': true,
          'migrationshintergrund': false,
        },
      });

      expect(profile.lebenslagen, {
        'eigentuemer',
        'autofahrer',
        'eltern',
        'arbeitssuchend',
        'pflegende_angehoerige',
      });
    });

    test('round-trips through JSON and drops ids the catalog lacks', () {
      const profile = UserProfile(lebenslagen: {'eltern', 'beruf_kita'});

      final restored = UserProfile.fromJson({
        ...profile.toJson(),
        'lebenslagen': ['eltern', 'beruf_kita', 'removed_later'],
      });

      expect(
        UserProfile.fromJson(profile.toJson()).lebenslagen,
        profile.lebenslagen,
      );
      expect(restored.lebenslagen, {'eltern', 'beruf_kita'});
    });
  });

  group('searchLebenslagen', () {
    List<String> ids(String query) =>
        searchLebenslagen(query).map((l) => l.id).toList();

    test('finds occupations through synonyms', () {
      expect(ids('Erzieherin'), contains('beruf_kita'));
      expect(ids('Bäcker'), contains('beruf_lebensmittel'));
    });

    test('tolerates umlaut spelling and a typo', () {
      expect(ids('baecker'), contains('beruf_lebensmittel'));
      expect(ids('erziherin'), contains('beruf_kita'));
    });

    test('puts word starts before inner matches, empty query finds nothing',
        () {
      final arzt = ids('arzt');
      expect(arzt.first, 'beruf_medizin'); // synonym "arzt"
      expect(arzt, contains('beruf_tier')); // inside "tierarzt"
      expect(ids(''), isEmpty);
      expect(ids('   '), isEmpty);
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
      const profile = UserProfile(lebenslagen: {'mieter'});

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

    test('a match outweighs a small appeal gap but not a large one', () {
      final niche = _opportunity(id: 'niche', everyday: 1, accessible: 3);
      final everyday = _opportunity(id: 'everyday', everyday: 5, accessible: 5);
      final matchedNiche = _opportunity(
        id: 'matched-niche',
        everyday: 2,
        accessible: 2,
        personalImpactSnippets: const {'hat_kinder:true': 'Betrifft dich.'},
      );
      final matchedAverage = _opportunity(
        id: 'matched-average',
        everyday: 3,
        accessible: 3,
        personalImpactSnippets: const {'hat_kinder:true': 'Betrifft dich.'},
      );
      final good = _opportunity(id: 'good', everyday: 4, accessible: 4);
      const profile = UserProfile(lebenslagen: {'eltern'});

      final ranked = ranker.rank(
        [niche, everyday, matchedNiche, matchedAverage, good],
        profile,
      );

      // matched-average (0.5 + bonus) beats the better unmatched 'good'
      // (0.75); an unmatched perfect card (1.0) beats a matched niche one.
      expect(
        ranked.map((r) => r.opportunity.id),
        ['everyday', 'matched-average', 'good', 'matched-niche', 'niche'],
      );
    });

    test('a picked Lebenslage on the card counts as a situation match', () {
      final matched = _opportunity(id: 'matched', lebenslagen: ['lgbtq']);
      final other = _opportunity(id: 'other', lebenslagen: ['rentner']);
      const profile = UserProfile(lebenslagen: {'lgbtq'});

      final ranked = ranker.rank([other, matched], profile);

      expect(ranked.first.opportunity.id, 'matched');
      expect(ranked.first.matchedLebenslage, 'lgbtq');
      expect(ranked.first.isSituationMatch, isTrue);
      expect(ranked.last.isSituationMatch, isFalse);
    });

    test('a rare Lebenslage counts more than one on most cards', () {
      // 'eltern' on 9 of 10 cards, 'pflegende_angehoerige' on one.
      final pool = [
        for (var i = 0; i < 8; i++)
          _opportunity(id: 'broad$i', lebenslagen: ['eltern']),
        _opportunity(id: 'eltern', lebenslagen: ['eltern']),
        _opportunity(id: 'pflege', lebenslagen: ['pflegende_angehoerige']),
      ];
      const profile = UserProfile(
        lebenslagen: {'eltern', 'pflegende_angehoerige'},
      );

      final ranked = ranker.rank(pool, profile);
      final pflege = ranked.firstWhere((r) => r.opportunity.id == 'pflege');
      final eltern = ranked.firstWhere((r) => r.opportunity.id == 'eltern');

      expect(ranked.first.opportunity.id, 'pflege');
      expect(pflege.matchStrength, 1.0);
      expect(eltern.matchStrength, lessThan(0.4));
      expect(eltern.matchStrength, greaterThan(0));
    });

    test('only the card main Lebenslage is named, secondary ones still rank',
        () {
      final card = _opportunity(lebenslagen: ['wohngeld', 'eltern']);
      final other = _opportunity(id: 'other', lebenslagen: ['rentner']);

      final secondary = ranker.rank(
        [card, other],
        const UserProfile(lebenslagen: {'eltern'}),
      ).firstWhere((r) => r.opportunity.id == 'opp-1');
      final main = ranker.rank(
        [card, other],
        const UserProfile(lebenslagen: {'wohngeld'}),
      ).firstWhere((r) => r.opportunity.id == 'opp-1');

      expect(secondary.matchedLebenslage, isNull);
      expect(secondary.isSituationMatch, isTrue);
      expect(main.matchedLebenslage, 'wohngeld');
    });

    test('card reason names a public Lebenslage but never a private one', () {
      RankedOpportunity ranked(String? lebenslage, {String? tag}) =>
          RankedOpportunity(
            opportunity: _opportunity(),
            matchedSnippet: null,
            werteAlignment: 0.5,
            matchedLebenslage: lebenslage,
            interestTag: tag,
          );

      expect(whyLine(ranked('eltern')), 'Weil du „Eltern“ angegeben hast');
      expect(whyLine(ranked('lgbtq')), 'Weil es zu deinen Angaben passt');
      expect(
        whyLine(ranked(null, tag: 'Umwelt/Natur')),
        'Weil du dich für Umwelt/Natur interessierst',
      );
      expect(whyLine(ranked(null)), isNull);
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
