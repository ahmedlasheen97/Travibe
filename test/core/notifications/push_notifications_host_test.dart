import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/core/notifications/push_notification_service.dart';
import 'package:travibe/core/notifications/push_notifications_host.dart';
import 'package:travibe/features/profile/cubit/current_user_cubit.dart';
import 'package:travibe/features/profile/data/profile_model.dart';
import 'push_fakes.dart';

class ControlledCurrentUser extends CurrentUserCubit {
  @override
  Future<void> load() async {}
  void unverified(String id) =>
      emit(CurrentUserState(profile: ProfileModel(id: id)));
  void confirm(String id) => emit(
    CurrentUserState(
      profile: ProfileModel(id: id, emailVerifiedAt: '2026-01-01'),
    ),
  );
}

void main() {
  testWidgets(
    'host rejects queued old profiles on rapid switch and disposes its listener',
    (tester) async {
      final prefs = PreferencesManager();
      SharedPreferences.setMockInitialValues({'_token': 'auth-a'});
      await prefs.init();
      final user = ControlledCurrentUser(), client = FakeMessagingClient();
      final repo = FakePushRepository();
      final service = PushNotificationService(client: client, repository: repo);
      await tester.pumpWidget(
        BlocProvider<CurrentUserCubit>.value(
          value: user,
          child: PushNotificationsHost(
            service: service,
            child: const MaterialApp(home: Scaffold()),
          ),
        ),
      );
      await tester.pump();
      // emit is synchronous, but its stream callback is queued. Switch credentials
      // synchronously before that callback can use the old confirmed profile.
      user.unverified('1');
      await tester.pump();
      await drainPush();
      expect(repo.registered, isEmpty);
      user.confirm('1');
      final switched = prefs.saveToken('auth-b');
      await switched;
      await tester.pump();
      await drainPush();
      expect(repo.registered, isEmpty);
      client.currentToken = 'device-b';
      user.confirm('2');
      await tester.pump();
      await drainPush();
      expect(repo.registered.single.account.userId, '2');
      expect(repo.registered.single.account.authorizationToken, 'auth-b');
      await tester.pumpWidget(const SizedBox());
      user.confirm('3');
      await tester.pump();
      await drainPush();
      expect(repo.registered, hasLength(1));
      expect(client.starts, 1);
      service.dispose();
      await client.close();
      await user.close();
      await prefs.clear();
    },
  );
}
