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
        'region': 'Germany',
        'effort_minutes': 3,
        'impact_hint': 'Track later.',
        'source_url': 'https://example.org',
      },
      'score': 91,
      'reasons': ['Passt zu deinen Werten.'],
    });

    expect(recommendation.score, 91);
    expect(recommendation.reasons, ['Passt zu deinen Werten.']);
    expect(recommendation.action.id, 'action-1');
    expect(recommendation.action.actionType, 'representative_letter');
    expect(recommendation.action.effortMinutes, 3);
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
}
