import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/core/media/media_upload_service.dart';
import 'package:travibe/core/widgets/travibe_toast.dart';
import 'package:travibe/features/stories/cubit/story_publish_cubit.dart';
import 'package:travibe/features/stories/cubit/story_upload_cubit.dart';
import 'package:travibe/features/stories/data/stories_repo.dart';
import 'package:travibe/features/stories/data/story_editor_draft.dart';
import 'package:travibe/features/stories/data/story_model.dart';
import 'package:travibe/features/stories/screens/story_editor_screen.dart';
import 'package:travibe/features/stories/widgets/story_image_exporter.dart';
import 'package:travibe/features/stories/widgets/story_upload_toast.dart';
import 'package:travibe/features/stories/widgets/discard_story_dialog.dart';

import '../../core/media/media_upload_test.dart' as media;
import 'fixtures.dart';
import 'story_publishing_test.dart' show storyDetail;

typedef Pixels = ({int width, int height, ByteData rgba});

Future<Uint8List> pngOf(int width, int height, int argb) async {
  final rgba = Uint8List(width * height * 4);
  for (var i = 0; i < rgba.length; i += 4) {
    rgba[i] = (argb >> 16) & 0xFF;
    rgba[i + 1] = (argb >> 8) & 0xFF;
    rgba[i + 2] = argb & 0xFF;
    rgba[i + 3] = 0xFF;
  }
  final buffer = await ui.ImmutableBuffer.fromUint8List(rgba);
  final codec = await ui.ImageDescriptor.raw(
    buffer,
    width: width,
    height: height,
    pixelFormat: ui.PixelFormat.rgba8888,
  ).instantiateCodec();
  final image = (await codec.getNextFrame()).image;
  final png = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return png!.buffer.asUint8List();
}

Future<Pixels> pixelsOf(Uint8List encoded) async {
  final codec = await ui.instantiateImageCodec(encoded);
  final image = (await codec.getNextFrame()).image;
  final rgba = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  final result = (width: image.width, height: image.height, rgba: rgba);
  image.dispose();
  return result;
}

/// (r, g, b) at x,y.
(int, int, int) rgbAt(Pixels p, int x, int y) {
  final i = (y * p.width + x) * 4;
  return (p.rgba.getUint8(i), p.rgba.getUint8(i + 1), p.rgba.getUint8(i + 2));
}

StoryEditorDraft photoDraft(Uint8List bytes, int width, int height) =>
    StoryEditorDraft(
      image: StorySourceImage(
        path: '/local/photo.png',
        name: 'photo.png',
        width: width,
        height: height,
        bytes: bytes,
      ),
    );

class FakeUploads extends MediaUploadService {
  int calls = 0;
  Uint8List? bytes;
  String? contentType;
  Object? failNext;
  @override
  Future<int> upload({
    required String filename,
    required String contentType,
    required Uint8List bytes,
    required bool Function() isActive,
    required CancelToken cancelToken,
    required void Function(MediaUploadStage) onStage,
    void Function(int sent, int total)? onProgress,
  }) async {
    calls++;
    this.bytes = bytes;
    this.contentType = contentType;
    onStage(MediaUploadStage.uploading);
    onProgress?.call(50, 100);
    onProgress?.call(100, 100);
    onStage(MediaUploadStage.processing);
    final fail = failNext;
    failNext = null;
    if (fail != null) throw fail;
    return 19;
  }
}

class FakeRepo extends StoriesRepo {
  int posts = 0;
  final createResults = <Object>[];
  final lookups = <StoryDetail?>[];
  int lookupCalls = 0;

  @override
  Future<StoryDetail> create(
    CreateStoryRequest request, {
    CancelToken? cancelToken,
  }) async {
    posts++;
    if (createResults.isNotEmpty) {
      final result = createResults.removeAt(0);
      if (result is! StoryDetail) throw result;
      return result;
    }
    return StoryDetail.fromJson(storyDetail(mediaId: request.mediaId));
  }

  @override
  Future<StoryDetail?> findStoryByMedia(int mediaId) async {
    lookupCalls++;
    return lookups.isEmpty ? null : lookups.removeAt(0);
  }
}

/// Instant encoder so cubit tests don't depend on isolate timing.
Future<Uint8List> fakeJpeg(
  Uint8List rgba,
  int width,
  int height,
  int quality,
) async => Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xD9]);

/// Worst case for JPEG: full-frame random noise (no compressible detail).
Future<Uint8List> noisePng(int width, int height) async {
  final rgba = Uint8List(width * height * 4);
  var seed = 7;
  for (var i = 0; i < rgba.length; i++) {
    seed = (seed * 1103515245 + 12345) & 0x7fffffff;
    rgba[i] = (i & 3) == 3 ? 255 : seed >> 16 & 0xFF;
  }
  final buffer = await ui.ImmutableBuffer.fromUint8List(rgba);
  final codec = await ui.ImageDescriptor.raw(
    buffer,
    width: width,
    height: height,
    pixelFormat: ui.PixelFormat.rgba8888,
  ).instantiateCodec();
  final image = (await codec.getNextFrame()).image;
  final png = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return png!.buffer.asUint8List();
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await PreferencesManager().init();
    await PreferencesManager().saveToken('story-upload-test');
  });
  tearDown(() => PreferencesManager().clear());

  group('StoryImageExporter', () {
    testWidgets('crops to the editor view and fits 1080×1920 as JPEG', (
      tester,
    ) async {
      // 3000×2000 landscape in a 390×800 viewport: cover crop is 975×2000,
      // scaled to fit 1080×1920 → 936×1920.
      final out = await tester.runAsync(() async {
        final png = await pngOf(3000, 2000, 0xFF3366CC);
        return const StoryImageExporter().export(
          photoDraft(png, 3000, 2000),
          const Size(390, 800),
        );
      });
      expect(out!.contentType, 'image/jpeg');
      expect(out.filename, 'story.jpg');
      expect(out.bytes.take(2), [0xFF, 0xD8]);
      expect((out.width, out.height), (936, 1920));
      expect(out.flattened, isFalse);
      final decoded = (await tester.runAsync(() => pixelsOf(out.bytes)))!;
      expect((decoded.width, decoded.height), (936, 1920));
      // Far smaller than a PNG of the same frame (raw RGBA is ~7.2 MB).
      expect(out.bytes.length, lessThan(1024 * 1024));
    });

    testWidgets('never upscales a small photo', (tester) async {
      final out = await tester.runAsync(
        () => const StoryImageExporter().export(draft(), const Size(100, 100)),
      );
      // 4×2 photo, square view → visible 2×2.
      expect((out!.width, out.height), (2, 2));
    });

    testWidgets('drawings are baked in at the matching position', (
      tester,
    ) async {
      final out = await tester.runAsync(() async {
        final png = await pngOf(400, 400, 0xFF000000);
        return const StoryImageExporter().export(
          photoDraft(png, 400, 400).withStrokes([
            StoryStroke(
              points: const [Offset(.25, 0), Offset(.25, 1)],
              colorArgb: 0xFFFF0000,
              width: .1,
            ),
          ]),
          const Size(200, 200),
        );
      });
      expect(out!.flattened, isTrue);
      expect((out.width, out.height), (400, 400));
      final p = (await tester.runAsync(() => pixelsOf(out.bytes)))!;
      final (r, g, b) = rgbAt(p, 100, 200); // x = .25 of 400
      expect(r, greaterThan(200));
      expect(g, lessThan(60));
      expect(b, lessThan(60));
      final (r2, _, _) = rgbAt(p, 300, 200);
      expect(r2, lessThan(40)); // Untouched black photo.
    });

    testWidgets('a worst-case detailed photo still ends under ~1 MB', (
      tester,
    ) async {
      final out = await tester.runAsync(() async {
        final png = await noisePng(1080, 1920);
        return const StoryImageExporter().export(
          photoDraft(png, 1080, 1920),
          const Size(1080, 1920),
        );
      });
      expect(out!.bytes.take(2), [0xFF, 0xD8]);
      expect(out.bytes.length, lessThanOrEqualTo(950 * 1024));
      expect(out.width, greaterThanOrEqualTo(540));
    });

    testWidgets('steps quality down first, then shrinks, never below half', (
      tester,
    ) async {
      final attempts = <(int, int, int)>[];
      // Size model: bytes grow with pixels and quality.
      Future<Uint8List> sized(Uint8List rgba, int w, int h, int q) async {
        attempts.add((w, h, q));
        return Uint8List(w * h * q ~/ 150);
      }

      final png = (await tester.runAsync(() => pngOf(1080, 1920, 0xFF808080)))!;
      final out = await tester.runAsync(
        () => StoryImageExporter(
          encoder: sized,
        ).export(photoDraft(png, 1080, 1920), const Size(1080, 1920)),
      );
      expect(attempts.take(3).map((a) => a.$3), [85, 75, 65]);
      expect(attempts.take(3).every((a) => (a.$1, a.$2) == (1080, 1920)), true);
      // 1080×1920: q85 ≈ 1.18 MB, q75 ≈ 1.04 MB, q65 ≈ 0.90 MB — only q65 fits…
      expect((out!.width, out.height), (1080, 1920));
      expect(out.bytes.length, lessThanOrEqualTo(950 * 1024));

      // …while a tighter budget shrinks the frame, stopping at half size.
      attempts.clear();
      final tight = await tester.runAsync(
        () => StoryImageExporter(
          encoder: sized,
          maxBytes: 1000,
        ).export(photoDraft(png, 1080, 1920), const Size(1080, 1920)),
      );
      expect(attempts.map((a) => a.$1).toSet().length, greaterThan(1));
      expect(tight!.width, greaterThanOrEqualTo(540));
      expect(tight.height, greaterThanOrEqualTo(960));
    });

    testWidgets('missing viewport exports the whole photo', (tester) async {
      final out = await tester.runAsync(
        () => const StoryImageExporter(encoder: fakeJpeg).export(draft(), null),
      );
      expect((out!.width, out.height), (4, 2));
    });
  });

  group('storage upload timeout', () {
    test('scales with size between 60s and 10 minutes', () {
      expect(storageSendTimeout(400 * 1024), const Duration(seconds: 60));
      expect(storageSendTimeout(5 * 1024 * 1024), const Duration(seconds: 190));
      expect(storageSendTimeout(50 * 1024 * 1024), const Duration(minutes: 10));
    });

    test('the storage PUT carries the size-based timeout', () async {
      final api = media.MediaApi()..statuses = ['ready'];
      final storage = media.StorageAdapter();
      final uploads = MediaUploadService(
        api: api,
        storageAdapter: storage,
        wait: (_) async {},
      );
      addTearDown(uploads.close);
      final bytes = Uint8List(6 * 1024 * 1024);
      await uploads.upload(
        filename: 'story.jpg',
        contentType: 'image/jpeg',
        bytes: bytes,
        isActive: () => true,
        cancelToken: CancelToken(),
        onStage: (_) {},
      );
      expect(storage.request!.sendTimeout, storageSendTimeout(bytes.length));
      expect(
        storage.request!.sendTimeout!,
        greaterThan(const Duration(seconds: 60)),
      );
    });
  });

  group('StoryUploadCubit', () {
    late FakeUploads uploads;
    late FakeRepo repo;
    late StoryUploadCubit cubit;
    late List<StoryUploadState> states;

    setUp(() {
      uploads = FakeUploads();
      repo = FakeRepo();
      cubit = StoryUploadCubit(
        publisher: () => StoryPublishCubit(
          repo: repo,
          uploads: uploads,
          exporter: const StoryImageExporter(encoder: fakeJpeg),
        ),
      );
      states = [];
      cubit.stream.listen(states.add);
    });
    tearDown(() => cubit.close());

    Future<void> settle(WidgetTester tester) async {
      for (var i = 0; i < 200; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)),
        );
        final state = cubit.state;
        if (state is StoryUploadDone || state is StoryUploadFailed) return;
      }
    }

    StoryUploadJob jobFor(StoryEditorDraft value) =>
        StoryUploadJob(draft: value, viewport: const Size(100, 100));

    testWidgets('reports rising progress, then Done with one upload', (
      tester,
    ) async {
      cubit.enqueue(jobFor(draft()));
      await settle(tester);
      expect(cubit.state, isA<StoryUploadDone>());
      final progress = states
          .whereType<StoryUploading>()
          .map((s) => s.progress)
          .toList();
      expect(progress, isNotEmpty);
      expect(progress.any((p) => p > 0 && p < 1), isTrue);
      for (var i = 1; i < progress.length; i++) {
        expect(progress[i], greaterThanOrEqualTo(progress[i - 1]));
      }
      expect(uploads.calls, 1);
      expect(uploads.contentType, 'image/jpeg');
      expect(repo.posts, 1);
    });

    testWidgets('failure shows a plain message; Retry succeeds', (
      tester,
    ) async {
      uploads.failNext = ApiError(
        message:
            'The upload result is uncertain. Your photo and edits are kept.',
      );
      cubit.enqueue(jobFor(draft()));
      await settle(tester);
      final failed = cubit.state as StoryUploadFailed;
      expect(failed.message, 'Couldn’t publish your story');
      expect(failed.message, isNot(contains('uncertain')));
      cubit.retry();
      await settle(tester);
      expect(cubit.state, isA<StoryUploadDone>());
      expect(repo.posts, 1);
    });

    testWidgets('timeout after POST: Retry verifies and never posts twice', (
      tester,
    ) async {
      repo.createResults.add(StoryCreationUncertain());
      // Immediate check: unknown. Retry check: the Story exists.
      repo.lookups.addAll([
        null,
        StoryDetail.fromJson(storyDetail(mediaId: 19)),
      ]);
      cubit.enqueue(jobFor(draft()));
      await settle(tester);
      expect(cubit.state, isA<StoryUploadFailed>());
      cubit.retry();
      await settle(tester);
      expect(cubit.state, isA<StoryUploadDone>());
      expect(repo.posts, 1);
      expect(uploads.calls, 1);
      expect(repo.lookupCalls, 2);
    });

    testWidgets('timeout after POST that did succeed is reported as Done', (
      tester,
    ) async {
      repo.createResults.add(StoryCreationUncertain());
      repo.lookups.add(StoryDetail.fromJson(storyDetail(mediaId: 19)));
      cubit.enqueue(jobFor(draft()));
      await settle(tester);
      expect(cubit.state, isA<StoryUploadDone>());
      expect(repo.posts, 1);
    });

    testWidgets('X discards the failed Story and the next one runs', (
      tester,
    ) async {
      uploads.failNext = ApiError(message: 'offline');
      cubit.enqueue(jobFor(draft()));
      cubit.enqueue(jobFor(draft()));
      await settle(tester);
      expect(cubit.state, isA<StoryUploadFailed>());
      expect(cubit.pending, 2);
      cubit.discard();
      await settle(tester);
      expect(cubit.state, isA<StoryUploadDone>());
      expect(repo.posts, 1);
      expect(cubit.pending, 0);
    });

    testWidgets('signing out cancels and clears the upload', (tester) async {
      uploads.failNext = ApiError(message: 'offline');
      cubit.enqueue(jobFor(draft()));
      await settle(tester);
      await PreferencesManager().clear();
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      expect(cubit.state, isA<StoryUploadIdle>());
      expect(cubit.pending, 0);
    });
  });

  testWidgets('X asks "Discard story?"; only Discard confirms', (tester) async {
    final results = <bool>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async =>
                results.add(await showDiscardStoryDialog(context)),
            child: const Text('X'),
          ),
        ),
      ),
    );
    for (final choice in ['Cancel', 'Discard']) {
      await tester.tap(find.text('X'));
      await tester.pumpAndSettle();
      expect(find.text('Discard story?'), findsOneWidget);
      expect(find.text('Your story won’t be posted.'), findsOneWidget);
      await tester.tap(find.text(choice));
      await tester.pumpAndSettle();
    }
    expect(results, [false, true]);
  });

  group('upload toast', () {
    void noop() {}

    test('uploading → info with progress ring', () {
      final toast = storyUploadToast(
        const StoryUploading(progress: .4),
        onRetry: noop,
        onDiscard: noop,
      )!;
      expect(toast.message, 'Uploading your story');
      expect(toast.variant, TravibeToastVariant.info);
      expect(toast.leading, isNotNull);
    });

    test('failed → red with Retry and X; no developer wording', () {
      var retried = 0, discarded = 0;
      final toast = storyUploadToast(
        const StoryUploadFailed(message: StoryUploadCubit.failureMessage),
        onRetry: () => retried++,
        onDiscard: () => discarded++,
      )!;
      expect(toast.message, 'Couldn’t publish your story');
      expect(toast.variant, TravibeToastVariant.error);
      expect(toast.actionLabel, 'Retry');
      toast.onAction!();
      toast.onClose!();
      expect((retried, discarded), (1, 1));
    });

    test('done/idle clear the sticky toast; success is green', () {
      expect(
        storyUploadToast(
          const StoryUploadDone(null),
          onRetry: noop,
          onDiscard: noop,
        ),
        isNull,
      );
      expect(storyPublishedToast.message, 'Story published successfully');
      expect(storyPublishedToast.variant, TravibeToastVariant.success);
    });
  });

  testWidgets('hosted editor hands over the Story and closes immediately', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final jobs = <StoryUploadJob>[];
    final original = draft();
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) =>
                      StoryEditorScreen(draft: original, onSubmit: jobs.add),
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
    await tester.tap(find.byKey(const ValueKey('story-post')));
    await tester.pumpAndSettle();
    expect(find.byType(StoryEditorScreen), findsNothing);
    expect(jobs, hasLength(1));
    expect(jobs.single.draft.image, same(original.image));
    // The canvas size (no safe-area inset in tests).
    expect(jobs.single.viewport, const Size(390, 844));
    // No in-editor bar or uncertain text.
    expect(find.byType(SnackBar), findsNothing);
    expect(find.textContaining('uncertain'), findsNothing);
  });
}
