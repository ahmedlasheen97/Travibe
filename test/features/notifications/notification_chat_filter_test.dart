import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/core/models/cursor_pagination.dart';
import 'package:travibe/features/notifications/cubit/notifications_cubit.dart';
import 'package:travibe/features/notifications/data/notifications_repo.dart';

Map<String, dynamic> row(String id, String type, {bool request = false}) => {
  'id': id,
  'type': type,
  'read_at': null,
  'data': {if (request) 'is_request': true},
};

/// Serves fixed pages keyed by cursor (null = first page).
class PagedRepo extends NotificationsRepo {
  PagedRepo(this.pages);
  final Map<String?, (List<Map<String, dynamic>>, String?)> pages;
  final reads = <String?>[];
  @override
  Future<CursorPage<Map<String, dynamic>>> list({
    String? cursor,
    int perPage = 15,
  }) async {
    reads.add(cursor);
    final (items, next) = pages[cursor]!;
    return CursorPage(
      items: items,
      pagination: CursorPaginationMeta(
        path: 'notifications',
        perPage: perPage,
        nextCursor: next,
      ),
    );
  }
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await PreferencesManager().init();
    await PreferencesManager().saveToken('filter-session');
  });
  tearDown(() => PreferencesManager().clear());

  List<Object?> ids(NotificationsCubit cubit) =>
      cubit.state.items.map((n) => n['id']).toList();

  test('direct chat messages are hidden; message requests stay', () async {
    final cubit = NotificationsCubit(
      repo: PagedRepo({
        null: (
          [
            row('like', 'post_liked'),
            row('dm', 'message_received'),
            row('request', 'message_received', request: true),
            row('accepted', 'message_request_accepted'),
          ],
          null,
        ),
      }),
    );
    addTearDown(cubit.close);
    await cubit.load();
    expect(ids(cubit), ['like', 'request', 'accepted']);
  });

  test('a page of only chat messages is skipped to the next page', () async {
    final repo = PagedRepo({
      null: (
        [row('a', 'message_received'), row('b', 'message_received')],
        'c2',
      ),
      'c2': ([row('c', 'user_followed')], 'c3'),
      'c3': ([row('d', 'post_liked')], null),
    });
    final cubit = NotificationsCubit(repo: repo);
    addTearDown(cubit.close);
    await cubit.load();
    expect(ids(cubit), ['c']);
    expect(cubit.state.hasMore, true);
    await cubit.more();
    expect(ids(cubit), ['c', 'd']);
    expect(repo.reads, [null, 'c2', 'c3']);
  });

  test('skipping is bounded and leaves a cursor for more()', () async {
    final pages = <String?, (List<Map<String, dynamic>>, String?)>{
      for (var i = 0; i < 10; i++)
        (i == 0 ? null : 'p$i'): (
          [row('m$i', 'message_received')],
          'p${i + 1}',
        ),
      'p10': ([row('like', 'post_liked')], null),
    };
    final repo = PagedRepo(pages);
    final cubit = NotificationsCubit(repo: repo);
    addTearDown(cubit.close);
    await cubit.load();
    expect(ids(cubit), isEmpty);
    expect(repo.reads, hasLength(6));
    expect(cubit.state.hasMore, true);
  });
}
