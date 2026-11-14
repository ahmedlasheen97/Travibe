import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:travibe/features/stories/cubit/story_upload_cubit.dart';
import 'package:travibe/features/stories/screens/story_editor_screen.dart';
import 'package:travibe/features/stories/widgets/post_story_sheet.dart';
import 'package:travibe/features/stories/widgets/start_add_story.dart';

import 'fixtures.dart';

void main() {
  late StubStoryPhotoRepo photos;
  setUp(() => photos = StubStoryPhotoRepo()..selected = draft());

  Future<void> show(
    WidgetTester tester, {
    StoryUploadCubit? uploads,
    Future<void> Function()? onPublished,
  }) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final page = Scaffold(
      body: Builder(
        builder: (context) => Center(
          child: TextButton(
            onPressed: () => startAddStory(
              context,
              photoRepo: photos,
              onPublished: onPublished,
            ),
            child: const Text('Add story'),
          ),
        ),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(useMaterial3: true),
        home: uploads == null
            ? page
            : BlocProvider.value(value: uploads, child: page),
      ),
    );
  }

  testWidgets(
    'opens picker → editor over the current screen and hands the Story to '
    'the shared upload queue',
    (tester) async {
      final uploads = StoryUploadCubit();
      addTearDown(uploads.close);
      await show(tester, uploads: uploads);
      await tester.tap(find.text('Add story'));
      await tester.pumpAndSettle();
      expect(find.byType(PostStorySheet), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('story-gallery')));
      await tester.pumpAndSettle();
      expect(photos.picks, 1);
      final editor = tester.widget<StoryEditorScreen>(
        find.byType(StoryEditorScreen),
      );
      expect(editor.draft, same(photos.selected));
      // Background upload: Root's toast reports it and refreshes the screens.
      expect(editor.onSubmit, isNotNull);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Add story'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('without the upload queue the editor publishes and calls back', (
    tester,
  ) async {
    Future<void> published() async {}
    await show(tester, onPublished: published);
    await tester.tap(find.text('Add story'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('story-gallery')));
    await tester.pumpAndSettle();
    final editor = tester.widget<StoryEditorScreen>(
      find.byType(StoryEditorScreen),
    );
    expect(editor.onSubmit, isNull);
    expect(editor.onPublished, same(published));
  });

  testWidgets('a second tap while the flow is open is ignored', (tester) async {
    await show(tester);
    final add = tester
        .widget<TextButton>(find.widgetWithText(TextButton, 'Add story'))
        .onPressed!;
    add();
    add();
    await tester.pumpAndSettle();
    expect(find.byType(PostStorySheet), findsOneWidget);
    await tester.tapAt(const Offset(10, 100));
    await tester.pumpAndSettle();
    expect(find.byType(PostStorySheet), findsNothing);
    // Closing the sheet frees the flow for the next tap.
    await tester.tap(find.text('Add story'));
    await tester.pumpAndSettle();
    expect(find.byType(PostStorySheet), findsOneWidget);
  });
}
