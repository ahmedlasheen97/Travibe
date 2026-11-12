import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/core/theme/dark_colors.dart';
import 'package:travibe/core/theme/dark_theme.dart';
import 'package:travibe/core/widgets/post_card.dart';
import 'package:travibe/features/home/data/hidden_post_response.dart';
import 'package:travibe/features/home/data/report_reason.dart';
import 'package:travibe/root.dart';
import 'home_experience_fixtures.dart' as home;
import 'own_post_menu_test.dart' show MenuFeeds;

/// Records report and hide calls for post 20 (authored by user 2).
class ReportingFeeds extends MenuFeeds {
  final reports = <(String, ReportReason, String?)>[];
  final hides = <(String, bool)>[];
  ApiError? reportError;

  @override
  Future<void> reportPost(
    String postId,
    ReportReason reason, {
    String? description,
  }) async {
    if (reportError != null) throw reportError!;
    reports.add((postId, reason, description));
  }

  @override
  Future<HiddenPostResponse> setHidden(String postId, bool hidden) async {
    hides.add((postId, hidden));
    return HiddenPostResponse(isHidden: hidden, message: 'Done');
  }
}

String _asset(WidgetTester tester, String key) {
  final svg = tester.widget<SvgPicture>(
    find.descendant(
      of: find.byKey(ValueKey(key)),
      matching: find.byType(SvgPicture),
    ),
  );
  return (svg.bytesLoader as SvgAssetLoader).assetName;
}

void main() {
  final preferences = PreferencesManager();
  late ReportingFeeds feeds;

  setUp(() async {
    SharedPreferences.setMockInitialValues({'onboarding_completed': true});
    await preferences.init();
    await preferences.saveToken('token');
    feeds = ReportingFeeds();
  });
  tearDown(() => preferences.clear());

  Future<void> pumpHome(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final account = home.AccountRepo();
    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (_, _) => MaterialApp(
          theme: darkTheme,
          home: Root(
            postsRepo: feeds,
            homeAccountRepo: account,
            followRepo: home.PeopleRepo(account),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openMenu(WidgetTester tester) async {
    final card = find.ancestor(
      of: find.text('Post 20'),
      matching: find.byType(PostCard),
    );
    final more = find.descendant(
      of: card,
      matching: find.byIcon(Icons.more_vert),
    );
    await tester.ensureVisible(more);
    await tester.pumpAndSettle();
    await tester.tap(more);
    await tester.pumpAndSettle();
  }

  Future<void> report(WidgetTester tester, String reason) async {
    await openMenu(tester);
    await tester.tap(find.text('Report'));
    await tester.pumpAndSettle();
    expect(find.text('Why are you reporting this?'), findsOneWidget);
    await tester.tap(find.text(reason));
    await tester.pumpAndSettle();
  }

  testWidgets('other post menu matches Figma rows, icons and colours', (
    tester,
  ) async {
    await pumpHome(tester);
    await openMenu(tester);
    final labels = ['Not interested', 'Hide post', 'Report', 'Block user'];
    final tops = [for (final l in labels) tester.getTopLeft(find.text(l)).dy];
    expect(tops, [...tops]..sort());
    expect(
      _asset(tester, 'post-option-not-interested'),
      'assets/images/icons/slash.svg',
    );
    expect(
      _asset(tester, 'post-option-hide'),
      'assets/images/onboarding/eye-slash.svg',
    );
    expect(
      _asset(tester, 'post-option-report'),
      'assets/images/icons/flag.svg',
    );
    expect(
      _asset(tester, 'post-option-block'),
      'assets/images/icons/user-remove.svg',
    );
    expect(
      tester.widget<Text>(find.text('Block user')).style!.color,
      const Color(0xFFDD312A),
    );
    final blockIcon = tester.widget<SvgPicture>(
      find.descendant(
        of: find.byKey(const ValueKey('post-option-block')),
        matching: find.byType(SvgPicture),
      ),
    );
    expect(
      blockIcon.colorFilter,
      const ColorFilter.mode(DarkColors.dangerColor, BlendMode.srcIn),
    );
    expect(find.text('Delete post'), findsNothing);
  });

  testWidgets('Report submits the reason, closes and thanks', (tester) async {
    await pumpHome(tester);
    await report(tester, 'Spam or scam');
    await tester.tap(find.text('Submit Report'));
    await tester.pumpAndSettle();
    expect(feeds.reports, [('20', ReportReason.spamOrScam, null)]);
    expect(find.text('Why are you reporting this?'), findsNothing);
    expect(find.text("Thanks, we'll review this post"), findsOneWidget);
    // Reporting does not remove the post.
    expect(find.text('Post 20'), findsOneWidget);
  });

  testWidgets('Something else sends the free-text description', (tester) async {
    await pumpHome(tester);
    await report(tester, 'Something else');
    await tester.enterText(
      find.byKey(const ValueKey('report-details')),
      'Impersonating a guide',
    );
    await tester.tap(find.text('Submit Report'));
    await tester.pumpAndSettle();
    expect(feeds.reports, [
      ('20', ReportReason.somethingElse, 'Impersonating a guide'),
    ]);
  });

  testWidgets('an already-pending report says so', (tester) async {
    feeds.reportError = ApiError(
      message: 'You have already reported this post.',
      statusCode: 422,
    );
    await pumpHome(tester);
    await report(tester, 'Harassment');
    await tester.tap(find.text('Submit Report'));
    await tester.pumpAndSettle();
    expect(
      find.text("You've already reported this post. We're reviewing it."),
      findsOneWidget,
    );
    expect(find.text('Retry'), findsNothing);
  });

  testWidgets('other failures explain and offer Retry', (tester) async {
    feeds.reportError = ApiError(message: 'No response from server');
    await pumpHome(tester);
    await report(tester, 'Inappropriate content');
    await tester.tap(find.text('Submit Report'));
    await tester.pumpAndSettle();
    expect(find.text('No response from server'), findsOneWidget);
    feeds.reportError = null;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(feeds.reports, [('20', ReportReason.inappropriateContent, null)]);
    expect(find.text("Thanks, we'll review this post"), findsOneWidget);
  });

  testWidgets('Not interested hides the post via the hide endpoint', (
    tester,
  ) async {
    await pumpHome(tester);
    await openMenu(tester);
    await tester.tap(find.text('Not interested'));
    await tester.pumpAndSettle();
    expect(feeds.hides, [('20', true)]);
    expect(find.text('Post 20'), findsNothing);
    expect(
      find.text("Got it. We'll show you fewer posts like this."),
      findsOneWidget,
    );
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(feeds.hides.last, ('20', false));
  });

  testWidgets('Hide post still hides as before', (tester) async {
    await pumpHome(tester);
    await openMenu(tester);
    await tester.tap(find.text('Hide post'));
    await tester.pumpAndSettle();
    expect(feeds.hides, [('20', true)]);
    expect(find.text('Post hidden'), findsOneWidget);
  });
}
