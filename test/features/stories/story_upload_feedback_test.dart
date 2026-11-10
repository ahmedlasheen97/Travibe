import 'dart:async';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/core/media/media_upload_service.dart';
import 'package:travibe/features/stories/data/story_editor_draft.dart';
import 'package:travibe/features/stories/data/story_model.dart';
import 'package:travibe/features/stories/data/stories_repo.dart';
import 'package:travibe/features/stories/screens/story_editor_screen.dart';
import 'package:travibe/features/stories/widgets/story_canvas.dart';
import 'fixtures.dart';
import 'story_publishing_test.dart' show storyDetail;

class _Uploads extends MediaUploadService {
  var result = Completer<int>();
  int calls = 0;
  void Function(MediaUploadStage)? stage;
  @override
  Future<int> upload({
    required String filename,
    required String contentType,
    required Uint8List bytes,
    required bool Function() isActive,
    required CancelToken cancelToken,
    required void Function(MediaUploadStage) onStage,
    void Function(int sent, int total)? onProgress,
  }) {
    calls++;
    stage = onStage;
    return result.future;
  }
}

class _Repo extends StoriesRepo {
  final requests = <CreateStoryRequest>[];
  @override
  Future<StoryDetail> create(
    CreateStoryRequest request, {
    CancelToken? cancelToken,
  }) async {
    requests.add(request);
    return StoryDetail.fromJson(storyDetail(mediaId: request.mediaId));
  }
}

void main() {
  late _Uploads uploads;
  late _Repo repo;
  late StoryEditorDraft value;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await PreferencesManager().init();
    await PreferencesManager().saveToken('upload-feedback-test');
    uploads = _Uploads();
    repo = _Repo();
    value = draft().withLayers([
      const StoryTextLayer(id: 'hello', text: 'Keep this draft'),
    ]);
  });
  tearDown(() async {
    uploads.close();
    await PreferencesManager().clear();
  });

  Future<void> show(
    WidgetTester tester, {
    Future<void> Function()? onPublished,
  }) async {
    // Construct the pending result inside the widget test's fake-async zone.
    uploads.result = Completer<int>();
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => StoryEditorScreen(
                    draft: value,
                    uploads: uploads,
                    storiesRepo: repo,
                    onPublished: onPublished,
                  ),
                ),
              ),
              child: const Text('Open editor'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open editor'));
    await tester.pumpAndSettle();
  }

  void expectCompactProgress(WidgetTester tester) {
    expect(find.byType(CupertinoActivityIndicator), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('story-post')),
        matching: find.byType(CupertinoActivityIndicator),
      ),
      findsOneWidget,
    );
    for (final label in [
      'Uploading Story',
      'Uploading photo…',
      'Processing photo…',
      'Publishing Story…',
    ]) {
      expect(find.text(label), findsNothing);
    }
    expect(
      tester
          .widget<FilledButton>(find.byKey(const ValueKey('story-post')))
          .onPressed,
      isNull,
    );
  }

  testWidgets(
    'one compact Post indicator keeps upload safe through confirmed success and refresh',
    (tester) async {
      var refreshed = 0;
      final refresh = Completer<void>();
      await show(
        tester,
        onPublished: () {
          refreshed++;
          return refresh.future;
        },
      );
      final post = tester
          .widget<FilledButton>(find.byKey(const ValueKey('story-post')))
          .onPressed!;
      post();
      post();
      await tester.pump();
      await tester.pump();
      expect(uploads.calls, 1);
      expectCompactProgress(tester);
      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      await navigator.maybePop();
      await tester.pump();
      await tester.pump();
      expect(find.byType(StoryEditorScreen), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey('story-back')),
        warnIfMissed: false,
      );
      uploads.stage!(MediaUploadStage.processing);
      await tester.pump();
      await tester.pump();
      expectCompactProgress(tester);
      uploads.result.complete(19);
      await tester.pump();
      await tester.pump();
      await tester.pump();
      await tester.pump();
      expect(repo.requests, hasLength(1));
      expect(refreshed, 1);
      expectCompactProgress(tester);
      refresh.complete();
      await tester.pumpAndSettle();
      expect(find.byType(StoryEditorScreen), findsNothing);
      expect(find.byType(CupertinoActivityIndicator), findsNothing);
      expect(find.text('Story published'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'upload failure keeps photo and text draft with an enabled explicit retry',
    (tester) async {
      await show(tester);
      await tester.tap(find.byKey(const ValueKey('story-post')));
      await tester.pump();
      await tester.pump();
      uploads.result.completeError(
        ApiError(message: 'Photo upload failed. Tap Post to retry.'),
      );
      await tester.pumpAndSettle();
      expect(find.byType(StoryEditorScreen), findsOneWidget);
      expect(
        find.text('Photo upload failed. Tap Post to retry.'),
        findsOneWidget,
      );
      expect(find.byType(CupertinoActivityIndicator), findsNothing);
      final retained = tester
          .widget<StoryCanvas>(find.byType(StoryCanvas))
          .draft;
      expect(retained.image, same(value.image));
      expect(
        (retained.layers.single as StoryTextLayer).text,
        'Keep this draft',
      );
      expect(repo.requests, isEmpty);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const ValueKey('story-post')))
            .onPressed,
        isNotNull,
      );
      uploads.result = Completer<int>();
      await tester.tap(find.byKey(const ValueKey('story-post')));
      await tester.pump();
      await tester.pump();
      expect(uploads.calls, 2);
      expectCompactProgress(tester);
      uploads.result.complete(19);
      await tester.pumpAndSettle();
      expect(repo.requests, hasLength(1));
      expect(find.byType(StoryEditorScreen), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
