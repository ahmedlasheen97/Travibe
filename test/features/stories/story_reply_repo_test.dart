import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/features/stories/data/stories_repo.dart';
import 'story_publishing_test.dart' show StoryAdapter, repository, response;

void main() {
  final session = PreferencesManager();
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await session.init();
    await session.saveToken('story-reply-test');
  });
  tearDown(() async => session.clear());

  test('posts a trimmed text reply tagged with the session revision', () async {
    final adapter = StoryAdapter()
      ..handler = (_) async => response({
        'data': {'id': 601, 'conversation_id': 42},
      }, status: 201);
    await repository(adapter).reply(33, '  Love this!  ');
    final request = adapter.requests.single;
    expect(request.method, 'POST');
    expect(request.path, 'stories/33/replies');
    expect(request.data, {'type': 'text', 'body': 'Love this!'});
    expect(request.extra['sessionRevision'], session.sessionRevision);
  });

  test('empty or over-long replies are rejected without a request', () async {
    final adapter = StoryAdapter();
    final repo = repository(adapter);
    await expectLater(repo.reply(33, '   '), throwsA(isA<StoryReplyError>()));
    await expectLater(
      repo.reply(33, 'a' * 5001),
      throwsA(isA<StoryReplyError>()),
    );
    expect(adapter.requests, isEmpty);
  });

  for (final (status, message) in [
    (403, 'You can\'t reply to this story.'),
    (404, 'This story is no longer available.'),
    (422, StoryReplyError.fallback),
  ]) {
    test('HTTP $status becomes "$message"', () async {
      final adapter = StoryAdapter()
        ..handler = (_) async =>
            response({'message': 'server text'}, status: status);
      final error = await repository(adapter)
          .reply(33, 'Hi')
          .then<StoryReplyError?>((_) => null)
          .catchError((Object e) => e as StoryReplyError);
      expect(error!.statusCode, status);
      expect(error.message, message);
      expect(error.storyGone, status == 404);
    });
  }

  test('a 200 is not treated as a confirmed reply', () async {
    final adapter = StoryAdapter()
      ..handler = (_) async => response({'data': null});
    await expectLater(
      repository(adapter).reply(33, 'Hi'),
      throwsA(isA<StoryReplyError>()),
    );
  });
}
