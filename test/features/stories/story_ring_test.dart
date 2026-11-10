import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/core/media/media_upload_service.dart';
import 'package:travibe/core/theme/dark_colors.dart';
import 'package:travibe/features/home/widgets/home_stories.dart';
import 'package:travibe/features/stories/cubit/stories_cubit.dart';
import 'package:travibe/features/stories/cubit/story_publish_cubit.dart';
import 'package:travibe/features/stories/data/story_model.dart';
import 'package:travibe/features/stories/widgets/story_ring.dart';
import '../../core/media/media_upload_test.dart' as media;
import 'fixtures.dart';
import 'story_publishing_test.dart'
    show PageRepo, pageJson, groupJson, StoryAdapter, repository;

final _now = DateTime.utc(2026, 11, 4);

Map<String, dynamic> _group(int count) {
  final value = groupJson(7);
  value['stories'] = List.generate(
    count,
    (index) => <String, dynamic>{
      'id': index + 1,
      'views_count': 9999,
      'has_seen': index.isOdd,
      'expires_at': _now.add(const Duration(days: 3650)).toIso8601String(),
    },
  );
  return value;
}

Future<List<int>> _pixels(List<Color> colors, {bool image = false}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder)..scale(4);
  if (image) {
    canvas.drawCircle(const Offset(32, 32), 32, Paint()..color = Colors.blue);
  }
  StoryRingPainter(colors: colors).paint(canvas, const Size.square(64));
  final picture = recorder.endRecording();
  final raster = await picture.toImage(256, 256);
  try {
    final bytes = await raster.toByteData(
      format: ui.ImageByteFormat.rawStraightRgba,
    );
    return List.of(bytes!.buffer.asUint8List());
  } finally {
    raster.dispose();
    picture.dispose();
  }
}

List<int> _pixel(List<int> pixels, double angle, {double radius = 31}) {
  final x = ((32 + radius * math.cos(angle)) * 4).floor().clamp(0, 255);
  final y = ((32 + radius * math.sin(angle)) * 4).floor().clamp(0, 255);
  final offset = (y * 256 + x) * 4;
  return pixels.sublist(offset, offset + 4);
}

void main() {
  setUp(() async {
    ScreenUtil.configure(
      data: const MediaQueryData(size: Size(390, 844)),
      designSize: const Size(390, 844),
      minTextAdapt: false,
      splitScreenMode: false,
    );
    SharedPreferences.setMockInitialValues({});
    await PreferencesManager().init();
    await PreferencesManager().saveToken('ring-test');
  });
  tearDown(() async => PreferencesManager().clear());

  Future<void> show(WidgetTester tester, StoryGroup group) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StoryRing(
            stories: group.stories,
            now: () => _now,
            child: const SizedBox.square(dimension: 64),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  StoryRingPainter painter(WidgetTester tester) =>
      tester
              .widget<CustomPaint>(
                find.descendant(
                  of: find.byType(StoryRing),
                  matching: find.byType(CustomPaint),
                ),
              )
              .foregroundPainter!
          as StoryRingPainter;

  for (final count in [1, 2, 3, 4, 10]) {
    testWidgets('$count active API stories produce $count ordered segments', (
      tester,
    ) async {
      await show(tester, StoryGroup.fromJson(_group(count)));
      expect(painter(tester).colors, [
        for (var i = 0; i < count; i++)
          i.isOdd ? Colors.white24 : DarkColors.primaryColor,
      ]);
      expect(StoryRingPainter.strokeWidth, 2);
      expect(StoryRingPainter.gapRadians, closeTo(3 * math.pi / 180, .000001));
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets(
    'expired, unknown-expiry, deleted and duplicate records do not add active segments',
    (tester) async {
      final json = _group(5);
      final rows = json['stories'] as List;
      rows[1]['expires_at'] = _now
          .subtract(const Duration(seconds: 1))
          .toIso8601String();
      rows[2]['expires_at'] = null;
      rows[3]['id'] = 1;
      final group = StoryGroup.fromJson(json).reconcile({}, {5});
      await show(tester, group);
      expect(painter(tester).colors, [DarkColors.primaryColor]);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('all individually viewed stories have grey segments', (
    tester,
  ) async {
    final group = StoryGroup.fromJson(
      _group(4),
    ).reconcile({1: 1, 2: 1, 3: 1, 4: 1}, {});
    await show(tester, group);
    expect(painter(tester).colors, List.filled(4, Colors.white24));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'single-story pixels form a continuous 2px circle with no track or inner padding',
    (tester) async {
      final pixels = (await tester.runAsync(
        () => _pixels([DarkColors.primaryColor]),
      ))!;
      for (var i = 0; i < 24; i++) {
        expect(_pixel(pixels, i * math.pi / 12).last, 255);
      }
      expect(_pixel(pixels, 0, radius: 29).last, 0);
      expect(_pixel(pixels, 0, radius: 30.5).last, 255);
      expect(_pixel(pixels, 0, radius: 31.5).last, 255);
      // Image edge is radius 32; ring spans radii 30–32 directly over it.
      expect(
        (64 - StoryRingPainter.strokeWidth) / 2 +
            StoryRingPainter.strokeWidth / 2,
        32,
      );
    },
  );

  for (final count in [2, 4]) {
    testWidgets(
      '$count segments leave transparent 3-degree gaps and reveal the underlying image',
      (tester) async {
        final colors = List.filled(count, DarkColors.primaryColor);
        final transparent = (await tester.runAsync(() => _pixels(colors)))!;
        final photo = (await tester.runAsync(
          () => _pixels(colors, image: true),
        ))!;
        final step = math.pi * 2 / count;
        for (var index = 0; index < count; index++) {
          final gap = -math.pi / 2 + index * step;
          expect(_pixel(transparent, gap).last, 0);
          expect(_pixel(photo, gap), [33, 150, 243, 255]);
          expect(_pixel(transparent, gap + step / 2), [228, 92, 16, 255]);
          // Just inside/outside the 1.5-degree half-gap checks clean butt ends.
          expect(_pixel(transparent, gap + math.pi / 180).last, 0);
          expect(_pixel(transparent, gap + 3 * math.pi / 180).last, 255);
        }
      },
    );
  }

  testWidgets(
    'painted segment colors follow viewed order and empty data draws nothing',
    (tester) async {
      final pixels = (await tester.runAsync(
        () => _pixels([DarkColors.primaryColor, Colors.white24]),
      ))!;
      expect(_pixel(pixels, 0), [228, 92, 16, 255]);
      expect(_pixel(pixels, math.pi), [255, 255, 255, 61]);
      final empty = (await tester.runAsync(() => _pixels([])))!;
      expect(empty.every((channel) => channel == 0), true);
    },
  );

  testWidgets(
    'publish updates own segments once; view stays local and deletion retains its canonical refresh',
    (tester) async {
      var count = 1;
      var viewed = false;
      final repo = PageRepo()
        ..handler = (_) async {
          final value = _group(count);
          if (viewed) {
            (value['stories'] as List).first['has_seen'] = true;
          }
          return StoriesPage.fromJson(pageJson([value]));
        };
      final home = StoriesCubit(repo: repo);
      await home.refresh();
      final uploads = MediaUploadService(
        api: media.MediaApi()..statuses = ['ready'],
        storageAdapter: media.StorageAdapter(),
        wait: (_) async {},
      );
      var refreshes = 0;
      final publisher = StoryPublishCubit(
        repo: repository(StoryAdapter()),
        uploads: uploads,
        onPublished: () async {
          refreshes++;
          count = 2;
          await home.refresh();
        },
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BlocBuilder<StoriesCubit, StoriesState>(
              bloc: home,
              builder: (_, state) =>
                  HomeStories(stories: state.groups, currentUserId: 7),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(painter(tester).colors, hasLength(1));
      final list = find.descendant(
        of: find.byType(HomeStories),
        matching: find.byType(Scrollable),
      );
      final position = tester.state<ScrollableState>(list).position;
      await tester.runAsync(() => publisher.publish(draft()));
      await tester.pump();
      await tester.pump();
      expect(painter(tester).colors, hasLength(2));
      expect(refreshes, 1);
      expect(repo.calls, hasLength(2));
      expect(tester.state<ScrollableState>(list).position, same(position));
      viewed = true;
      home.confirmedView(1, 12);
      await tester.pump();
      await tester.pump();
      expect(painter(tester).colors, [Colors.white24, Colors.white24]);
      expect(repo.calls, hasLength(2));
      count = 1;
      home.confirmedDelete(2);
      await tester.pumpAndSettle();
      expect(painter(tester).colors, [Colors.white24]);
      expect(repo.calls, hasLength(3));
      await tester.pumpWidget(const SizedBox());
      await publisher.close();
      uploads.close();
      await home.close();
    },
  );
}
