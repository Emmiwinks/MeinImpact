import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meinimpact/src/core/profile/user_profile_store.dart';
import 'package:meinimpact/src/features/feed/domain/user_profile.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('saves and loads a profile', () async {
    FlutterSecureStorage.setMockInitialValues({});
    const store = UserProfileStore();

    await store.save(const UserProfile(lebenslagen: {'eltern'}));

    expect((await store.load())?.lebenslagen, {'eltern'});
  });

  test('an unreadable profile is kept aside and never breaks startup',
      () async {
    FlutterSecureStorage.setMockInitialValues({
      'user_profile_v1': '{"werte": "not a map"}',
    });
    const store = UserProfileStore();

    expect(await store.load(), isNull);
    expect(await store.load(), isNull);
    expect(
      await const FlutterSecureStorage()
          .read(key: 'user_profile_v1_unreadable'),
      '{"werte": "not a map"}',
    );
  });
}
