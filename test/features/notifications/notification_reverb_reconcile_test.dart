import 'package:travibe/features/notifications/data/notification_model.dart';
import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/core/models/cursor_pagination.dart';
import 'package:travibe/features/notifications/data/notifications_repo.dart';
import 'package:travibe/features/notifications/cubit/notification_activity.dart';
import 'package:travibe/features/notifications/cubit/notifications_cubit.dart';

class ReconcileRepo extends NotificationsRepo {
  bool changed = false;
  final cursors = <String?>[];
  Completer<void>? gate;
  @override
  Future<CursorPage<Map<String, dynamic>>> list({
    String? cursor,
    int perPage = 15,
  }) async {
    cursors.add(cursor);
    final version = changed;
    if (gate != null) await gate!.future;
    final ids = cursor == null
        ? (version ? ['new', 'one'] : ['one'])
        : cursor == 'two'
        ? ['two']
        : ['three'];
    return CursorPage(
      items: [
        for (final id in ids)
          {'id': id, 'read_at': version ? '2026-11-08T10:00:00Z' : null},
      ],
      pagination: CursorPaginationMeta(
        path: 'notifications',
        perPage: 15,
        nextCursor: cursor == null
            ? 'two'
            : cursor == 'two'
            ? 'three'
            : null,
      ),
    );
  }

  @override
  Future<NotificationUnreadCount> unreadCount() async =>
      const NotificationUnreadCount(0);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await PreferencesManager().init();
    await PreferencesManager().saveToken('synthetic');
  });
  test(
    'reconnect replaces read state, adds new rows, retains cached pages and cursor',
    () async {
      final repo = ReconcileRepo();
      final cubit = NotificationsCubit(repo: repo);
      await cubit.load();
      await cubit.more();
      expect(cubit.nextCursor, 'three');
      repo.changed = true;
      await cubit.reconcileCachedPages();
      expect(cubit.state.items.map((i) => i['id']), ['new', 'one', 'two']);
      expect(cubit.state.items.every((i) => i['read_at'] != null), isTrue);
      expect(cubit.nextCursor, 'three');
      await cubit.more();
      expect(cubit.state.items.last['id'], 'three');
      await cubit.close();
    },
  );
  test(
    'late reconnect REST response cannot repopulate an account after logout',
    () async {
      final repo = ReconcileRepo();
      final cubit = NotificationsCubit(repo: repo);
      await cubit.load();
      repo.changed = true;
      repo.gate = Completer();
      final sync = cubit.reconcileCachedPages();
      await PreferencesManager().clearSession();
      repo.gate!.complete();
      await sync;
      expect(cubit.state.items, isEmpty);
      await cubit.close();
    },
  );
  test('activity invalidation reconciles the open inbox from REST', () async {
    final repo = ReconcileRepo();
    final activity = NotificationActivity(repo: repo);
    final cubit = NotificationsCubit(repo: repo, activity: activity);
    await cubit.load();
    repo.changed = true;
    // Ignore unread-count transport here; only typed stream invalidation is under test.
    activity.invalidateFromRealtime();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(cubit.state.items.first['id'], 'new');
    await cubit.close();
    activity.dispose();
  });
}
