import 'package:flutter_test/flutter_test.dart';
import 'package:meinimpact/src/features/feed/domain/civic_action.dart';
import 'package:meinimpact/src/features/feed/domain/user_profile.dart';

void main() {
  test('maps civic action recommendation from backend JSON', () {
    final recommendation = ActionRecommendation.fromJson({
      'action': {
        'id': 'action-1',
        'title': 'Action title',
        'action_type': 'representative_letter',
        'summary': 'Action summary',
        'topics': ['democracy', 'climate'],
        'region': 'Germany',
        'effort_minutes': 3,
        'impact_hint': 'Track later.',
        'source_url': 'https://example.org',
      },
      'score': 91,
      'reasons': ['Matches democracy.'],
    });

    expect(recommendation.score, 91);
    expect(recommendation.reasons, ['Matches democracy.']);
    expect(recommendation.action.id, 'action-1');
    expect(recommendation.action.actionType, 'representative_letter');
    expect(recommendation.action.topics, ['democracy', 'climate']);
    expect(recommendation.action.effortMinutes, 3);
  });

  test('serializes user profile for backend requests', () {
    const profile = UserProfile(
      topics: ['climate'],
      valueAxes: {'civil_rights': 2},
      region: 'Germany',
    );

    expect(profile.toJson(), {
      'topics': ['climate'],
      'value_axes': {'civil_rights': 2},
      'region': 'Germany',
    });
  });
}
