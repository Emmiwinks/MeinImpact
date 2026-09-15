import 'package:flutter_test/flutter_test.dart';
import 'package:meinimpact/src/features/feed/domain/civic_action.dart';
import 'package:meinimpact/src/features/feed/domain/topic.dart';
import 'package:meinimpact/src/features/feed/domain/user_profile.dart';

CivicAction _action({
  String id = 'action-1',
  String topicId = 'topic-1',
  String actionType = 'representative_letter',
  String engagementState = 'C',
  String? stateReason,
}) {
  return CivicAction(
    id: id,
    title: 'Title $id',
    actionType: actionType,
    summary: 'Summary $id',
    region: 'Germany',
    sourceUrl: 'https://example.org/$id',
    topicId: topicId,
    engagementState: engagementState,
    stateReason: stateReason,
  );
}

void main() {
  test('maps civic action recommendation from backend JSON', () {
    final recommendation = ActionRecommendation.fromJson({
      'action': {
        'id': 'action-1',
        'title': 'Action title',
        'action_type': 'representative_letter',
        'summary': 'Action summary',
        'region': 'Germany',
        'source_url': 'https://example.org',
        'topic_id': 'topic-1',
        'engagement_state': 'B',
        'state_reason': 'Positionen noch offen',
      },
      'score': 91,
      'reasons': ['Passt zu deinen Werten.'],
    });

    expect(recommendation.score, 91);
    expect(recommendation.reasons, ['Passt zu deinen Werten.']);
    expect(recommendation.action.id, 'action-1');
    expect(recommendation.action.actionType, 'representative_letter');
    expect(recommendation.action.topicId, 'topic-1');
    expect(recommendation.action.engagementState, 'B');
    expect(recommendation.action.stateReason, 'Positionen noch offen');
  });

  test('falls back to the action id as topic_id when the field is absent', () {
    final action = CivicAction.fromJson({
      'id': 'action-2',
      'title': 'Title',
      'action_type': 'representative_letter',
      'summary': 'Summary',
      'region': null,
      'source_url': 'https://example.org',
    });

    expect(action.topicId, 'action-2');
    expect(action.engagementState, 'C');
  });

  test('serializes user profile for backend requests', () {
    const profile = UserProfile(
      werte: {'wirtschaft_gleichheit': 2},
      region: 'Germany',
    );

    expect(profile.toJson(), {
      'werte': {'wirtschaft_gleichheit': 2},
      'region': 'Germany',
      'plz': profile.plz,
      'mdb_name': null,
      'mdb_party': null,
      'mdb_wahlkreis': null,
      'city': profile.city,
      'occupation': profile.occupation,
      'family_status': profile.familyStatus,
      'wohnsituation': profile.wohnsituation,
      'sektor': profile.sektor,
      'lebenssituation': profile.lebenssituation,
    });
  });

  test('derives value axes from werte question scores', () {
    const profile = UserProfile(
      werte: {
        'wirtschaft_gleichheit': -2,
        'wirtschaft_staat': -1,
      },
    );

    expect(profile.axisWirtschaft, -1.5);
    expect(profile.axisDiplomatie, 0.0);
  });

  group('groupIntoTopics', () {
    test('groups two options sharing a topic_id into one topic', () {
      final petition = ActionRecommendation(
        action: _action(
          id: 'p1',
          topicId: 'topic-a',
          actionType: 'petition_signature',
          engagementState: 'A',
          stateReason: 'Kurz vor dem Quorum',
        ),
        score: 60,
        reasons: const [],
      );
      final letter = ActionRecommendation(
        action: _action(
          id: 'l1',
          topicId: 'topic-a',
          engagementState: 'C',
        ),
        score: 80,
        reasons: const ['Passt zu deinen Werten.'],
      );

      final topics = groupIntoTopics([petition, letter]);

      expect(topics, hasLength(1));
      expect(topics.single.options, hasLength(2));
      // Existential state aggregate: A (petition) beats C (letter) — the
      // topic surfaces the petition's own honest reason, not a merged one.
      expect(topics.single.engagementState, 'A');
      expect(topics.single.stateReason, 'Kurz vor dem Quorum');
      // Headline text (and its reasons) come from the highest-scored option
      // (the letter, score 80) — a cosmetic tie-break, not a ranking claim.
      expect(topics.single.title, 'Title l1');
      expect(topics.single.reasons, ['Passt zu deinen Werten.']);
    });

    test('items with no matching topic_id become their own singleton topics',
        () {
      final a = ActionRecommendation(
        action: _action(id: 'a', topicId: 'topic-a'),
        score: 50,
        reasons: const [],
      );
      final b = ActionRecommendation(
        action: _action(id: 'b', topicId: 'topic-b'),
        score: 40,
        reasons: const [],
      );

      final topics = groupIntoTopics([a, b]);

      expect(topics, hasLength(2));
      expect(topics.every((t) => t.options.length == 1), isTrue);
    });

    test('sorts topics by descending score', () {
      final low = ActionRecommendation(
        action: _action(id: 'low', topicId: 'topic-low'),
        score: 20,
        reasons: const [],
      );
      final high = ActionRecommendation(
        action: _action(id: 'high', topicId: 'topic-high'),
        score: 90,
        reasons: const [],
      );

      final topics = groupIntoTopics([low, high]);

      expect(topics.map((t) => t.topicId), ['topic-high', 'topic-low']);
    });
  });

  group('optionKindOf', () {
    test('petition_signature is a petition option', () {
      expect(
        optionKindOf(_action(actionType: 'petition_signature')),
        OptionKind.petition,
      );
    });

    test('representative_letter and anything else is a letter option', () {
      expect(
        optionKindOf(_action(actionType: 'representative_letter')),
        OptionKind.letter,
      );
      expect(
        optionKindOf(_action(actionType: 'public_question')),
        OptionKind.letter,
      );
    });
  });
}
