import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/features/chats/cubit/chat_activity_controller.dart';

class _Activity implements ChatActivityRepository {
  int beats = 0, typings = 0, leaves = 0, cancellations = 0;
  @override
  Future<void> heartbeat() async {
    beats++;
  }

  @override
  Future<void> leavePresence() async {
    leaves++;
  }

  @override
  Future<void> typing(String conversationId) async {
    typings++;
  }

  @override
  void cancel() {
    cancellations++;
  }
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await PreferencesManager().init();
    await PreferencesManager().saveToken('fixture');
  });
  ChatActivityController controller(_Activity repo) => ChatActivityController(
    repository: repo,
    heartbeatInterval: const Duration(seconds: 10),
    typingInterval: const Duration(seconds: 2),
  );
  testWidgets(
    'heartbeat coalesces resume and pauses without background timers',
    (tester) async {
      final repo = _Activity();
      final activity = controller(repo);
      activity.resume();
      activity.resume();
      await tester.pump();
      expect(repo.beats, 1);
      await tester.pump(const Duration(seconds: 10));
      expect(repo.beats, 2);
      activity.pause();
      await tester.pump(const Duration(seconds: 30));
      expect(repo.beats, 2);
      await activity.dispose();
    },
  );
  testWidgets('typing is throttled and stops on leaving route', (tester) async {
    final repo = _Activity();
    final activity = controller(repo);
    activity.resume();
    for (var i = 0; i < 20; i++) {
      activity.typing('conversation');
    }
    await tester.pump();
    expect(repo.typings, 1);
    await tester.pump(const Duration(seconds: 2));
    activity.typing('conversation');
    await tester.pump();
    expect(repo.typings, 2);
    activity.pause();
    activity.typing('conversation');
    expect(repo.typings, 2);
    await activity.dispose();
  });
  testWidgets('account switch stops timers and avoids old-account cleanup', (
    tester,
  ) async {
    final repo = _Activity();
    final activity = controller(repo);
    activity.resume();
    await tester.pump();
    await PreferencesManager().saveToken('replacement');
    await tester.pump(const Duration(seconds: 30));
    activity.resume();
    activity.typing('conversation');
    expect(repo.beats, 1);
    expect(repo.typings, 0);
    expect(repo.cancellations, greaterThan(0));
    await activity.dispose();
    expect(repo.leaves, 0);
  });
}
