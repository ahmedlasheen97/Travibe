import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/features/stories/cubit/stories_cubit.dart';
import 'package:travibe/features/stories/cubit/story_viewer_cubit.dart';
import 'package:travibe/features/stories/cubit/story_viewers_cubit.dart';
import 'package:travibe/features/stories/data/story_model.dart';
import 'package:travibe/features/stories/widgets/your_story_button.dart';

import 'story_owner_controls_test.dart' show OwnerRepo, viewersPage;
import 'story_publishing_test.dart' show pageJson, groupJson;

void main() {
  final session = PreferencesManager();
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await session.init();
    await session.saveToken('management-test-session');
  });
  tearDown(() async => session.clear());

  test(
    'refresh supersedes an in-flight page and rejects its late rows',
    () async {
      final oldPage = Completer<StoryViewersPage>();
      var firstReads = 0;
      final repo = OwnerRepo()
        ..viewersHandler = (page) async {
          if (page == 2) return oldPage.future;
          return StoryViewersPage.fromJson(
            viewersPage([++firstReads == 1 ? 8 : 10], last: 2),
          );
        };
      final cubit = StoryViewersCubit(
        storyId: 1,
        repo: repo,
        isOwner: () => true,
      );
      await cubit.refresh();
      final pagination = cubit.loadMore();
      await cubit.refresh();
      expect(repo.pages, [1, 2, 1]);
      expect(cubit.state.users.single.author.id, 10);
      oldPage.complete(
        StoryViewersPage.fromJson(viewersPage([9], page: 2, last: 2)),
      );
      await pagination;
      expect(cubit.state.users.single.author.id, 10);
      expect(cubit.state.loading, false);
      await cubit.loadMore();
      expect(repo.pages.last, 2);
      await cubit.close();
    },
  );

  test(
    'duplicate refreshes and pagination during refresh are suppressed',
    () async {
      final pending = Completer<StoryViewersPage>();
      final repo = OwnerRepo()..viewersHandler = (_) => pending.future;
      final cubit = StoryViewersCubit(
        storyId: 1,
        repo: repo,
        isOwner: () => true,
      );
      final first = cubit.refresh();
      await cubit.refresh();
      await cubit.loadMore();
      expect(repo.pages, [1]);
      pending.complete(StoryViewersPage.fromJson(viewersPage([8])));
      await first;
      await cubit.refresh();
      expect(repo.pages, [1, 1]);
      await cubit.close();
    },
  );

  test(
    'failed superseded page cannot overwrite a refresh error or retry',
    () async {
      final oldPage = Completer<StoryViewersPage>();
      var reads = 0;
      final repo = OwnerRepo()
        ..viewersHandler = (page) async {
          if (page == 2) return oldPage.future;
          if (++reads == 2) throw ApiError(message: 'Refresh failed');
          return StoryViewersPage.fromJson(viewersPage([8], last: 2));
        };
      final cubit = StoryViewersCubit(
        storyId: 1,
        repo: repo,
        isOwner: () => true,
      );
      await cubit.refresh();
      final pagination = cubit.loadMore();
      await cubit.refresh();
      oldPage.completeError(ApiError(message: 'Old page failed'));
      await pagination;
      expect(cubit.state.error!.message, 'Refresh failed');
      await cubit.refresh();
      expect(cubit.state.error, isNull);
      expect(cubit.state.users.single.author.id, 8);
      await cubit.close();
    },
  );

  for (final changedSession in [false, true]) {
    test(
      'refresh completion is ignored after ${changedSession ? 'account change' : 'disposal'}',
      () async {
        final pending = Completer<StoryViewersPage>();
        final repo = OwnerRepo()..viewersHandler = (_) => pending.future;
        final cubit = StoryViewersCubit(
          storyId: 1,
          repo: repo,
          isOwner: () => true,
        );
        final read = cubit.refresh();
        if (changedSession) {
          await session.saveToken('new-management-session');
        } else {
          await cubit.close();
        }
        pending.complete(StoryViewersPage.fromJson(viewersPage([8])));
        await read;
        expect(cubit.state.users, isEmpty);
        if (changedSession) await cubit.close();
      },
    );
  }

  testWidgets(
    'confirmed last deletion refreshes Home and returns popup to Add Story',
    (tester) async {
      final pending = Completer<void>();
      var reads = 0, additions = 0;
      final repo = OwnerRepo()
        ..deleteHandler = ((_) => pending.future)
        // Deliberately stale backend list must not resurrect the deleted story.
        ..groupsHandler = (_) async {
          reads++;
          final json = groupJson(7, storyId: 1);
          ((json['stories'] as List).single as Map)['expires_at'] =
              DateTime.now().add(const Duration(hours: 1)).toIso8601String();
          return StoriesPage.fromJson(pageJson([json]));
        };
      final home = StoriesCubit(repo: repo);
      await home.refresh();
      final viewer = StoryViewerCubit(
        groups: home.state.groups,
        initialAuthorId: 7,
        currentUserId: 7,
        repo: repo,
        onDeleted: home.confirmedDelete,
      );
      await viewer.start();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BlocBuilder<StoriesCubit, StoriesState>(
              bloc: home,
              builder: (_, state) => YourStoryButton(
                group: state.groups.isEmpty ? null : state.groups.single,
                currentUserId: 7,
                onAddStory: () => additions++,
                child: const SizedBox(
                  width: 80,
                  height: 80,
                  child: Text('Your Story'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Your Story'));
      await tester.pumpAndSettle();
      expect(find.text('View Story'), findsOneWidget);
      final deletion = viewer.deleteCurrent();
      expect(home.state.groups, hasLength(1));
      expect(viewer.state.detail!.id, 1);
      pending.complete();
      await deletion;
      await tester.pumpAndSettle();
      expect(viewer.state.status, StoryViewerStatus.finished);
      expect(home.state.groups, isEmpty);
      expect(reads, 2);
      expect(find.text('View Story'), findsNothing);
      await tester.tap(find.text('Your Story'));
      await tester.pumpAndSettle();
      expect(additions, 1);
      await tester.pumpWidget(const SizedBox.shrink());
      await viewer.close();
      await home.close();
    },
  );
}
