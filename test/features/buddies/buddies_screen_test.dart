import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/core/theme/dark_theme.dart';
import 'package:travibe/features/buddies/data/buddies_landing_data.dart';
import 'package:travibe/features/buddies/screens/buddies_screen.dart';
import 'package:travibe/features/buddies/widgets/buddies_traveler_card.dart';
import 'package:travibe/features/buddies/widgets/buddies_traveler_section.dart';
import 'package:travibe/features/buddies/widgets/buddies_visibility_invitation.dart';
import 'package:travibe/features/follow/cubit/follow_cubit.dart';
import 'package:travibe/root.dart';
import '../home/home_experience_fixtures.dart';
import 'buddies_fixtures.dart';

void main() {
  Future<void> show(
    WidgetTester tester, {
    Widget screen = const BuddiesLandingView(),
    double width = 390,
    double scale = 1,
    bool settle = true,
  }) async {
    tester.view.physicalSize = Size(width, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (_, _) => MaterialApp(
          theme: darkTheme,
          home: MediaQuery(
            data: MediaQueryData(
              size: Size(width, 844),
              textScaler: TextScaler.linear(scale),
            ),
            child: screen,
          ),
        ),
      ),
    );
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
    }
  }

  testWidgets('production defaults contain no sample users or location claims', (
    tester,
  ) async {
    await show(tester);
    expect(find.byType(BuddiesTravelerCard), findsNothing);
    expect(
      find.text('Traveler discovery is not available yet.'),
      findsOneWidget,
    );
    expect(
      find.text(
        'Your current city is saved only after you allow location. You can still search destinations manually.',
      ),
      findsOneWidget,
    );
    expect(find.text('Hazem Ali'), findsNothing);
    expect(find.text('You can turn this off from settings.'), findsNothing);
  });

  testWidgets(
    'visibility landing uses current banner and shared-interest cards',
    (tester) async {
      await show(
        tester,
        screen: const BuddiesLandingView(
          sharedInterestTravelers: sampleSharedInterestTravelers,
        ),
      );
      expect(find.text('BuddiesScreen'), findsNothing);
      expect(find.text('Find people for your next adventure'), findsOneWidget);
      expect(find.byType(BuddiesVisibilityInvitation), findsOneWidget);
      expect(find.text('Allow Location'), findsOneWidget);
      expect(find.text('With Same Interests'), findsOneWidget);
      expect(find.text('In Your City'), findsNothing);
      expect(find.byType(BuddiesTravelerCard), findsNWidgets(2));
      expect(find.text('Add a Trip'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'populated variant has both horizontal sections and Figma card geometry',
    (tester) async {
      await show(
        tester,
        screen: const BuddiesLandingView(
          variant: BuddiesLandingVariant.nearbyTravelers,
          nearbyTravelers: sampleNearbyTravelers,
          sharedInterestTravelers: sampleSharedInterestTravelers,
        ),
      );
      expect(find.byType(BuddiesVisibilityInvitation), findsNothing);
      expect(find.text('In Your City'), findsOneWidget);
      expect(find.text('With Same Interests'), findsOneWidget);
      final card = find.byType(BuddiesTravelerCard).first;
      expect(tester.getSize(card).width, 167);
      final image = find.descendant(of: card, matching: find.byType(Image));
      expect(tester.getSize(image).height, 134);
      final horizontal = find.descendant(
        of: find.byType(BuddiesTravelerSection).first,
        matching: find.byType(SingleChildScrollView),
      );
      final lastCard = find.byKey(const ValueKey('khaled-more'));
      final before = tester.getTopLeft(lastCard).dx;
      await tester.drag(horizontal, const Offset(-170, 0));
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(lastCard).dx, lessThan(before));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'unverified actions stay disabled and do not navigate or request input',
    (tester) async {
      await show(tester);
      for (final button in tester.widgetList<TextButton>(
        find.byType(TextButton),
      )) {
        expect(button.onPressed, isNull);
      }
      expect(find.byType(TextField), findsNothing);
      await tester.tap(find.text('Choose Destination'));
      await tester.tap(find.text('Allow Location'));
      await tester.pumpAndSettle();
      expect(find.byType(BuddiesLandingView), findsOneWidget);
      expect(find.byType(BuddiesVisibilityInvitation), findsOneWidget);
      expect(
        find.byTooltip(
          'Destination search is unavailable until API integration is verified',
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'empty lists do not fall back to sample users or invent result screens',
    (tester) async {
      await show(
        tester,
        screen: const BuddiesLandingView(
          variant: BuddiesLandingVariant.nearbyTravelers,
          nearbyTravelers: [],
          sharedInterestTravelers: [],
        ),
      );
      expect(find.byType(BuddiesTravelerCard), findsNothing);
      expect(find.byType(BuddiesSectionHeader), findsNothing);
      expect(find.text('Choose Destination'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'loading hides sample cards and can resolve to supplied local data',
    (tester) async {
      await show(
        tester,
        screen: const BuddiesLandingView(isLoading: true),
        settle: false,
      );
      expect(find.byType(CupertinoActivityIndicator), findsOneWidget);
      expect(find.byType(BuddiesTravelerCard), findsNothing);
      await show(
        tester,
        screen: const BuddiesLandingView(
          sharedInterestTravelers: [
            BuddiesTraveler(
              id: 'local',
              name: 'Local sample',
              interests: ['Hiking'],
            ),
          ],
        ),
      );
      expect(find.byType(CupertinoActivityIndicator), findsNothing);
      expect(find.text('Local sample'), findsOneWidget);
      expect(find.text('Hazem Ali'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  for (final variant in BuddiesLandingVariant.values) {
    for (final width in [280.0, 320.0]) {
      testWidgets('$variant at ${width}px with 2x text has no overflow', (
        tester,
      ) async {
        await show(
          tester,
          width: width,
          scale: 2,
          screen: BuddiesLandingView(
            variant: variant,
            nearbyTravelers: sampleNearbyTravelers,
            sharedInterestTravelers: sampleSharedInterestTravelers,
          ),
        );
        await tester.drag(
          find.byType(SingleChildScrollView).first,
          const Offset(0, -650),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('long card text and missing photos wrap without overflow', (
    tester,
  ) async {
    await show(
      tester,
      width: 280,
      scale: 3,
      screen: BuddiesLandingView(
        sharedInterestTravelers: [
          BuddiesTraveler(
            id: 'long',
            name: 'A very long traveler display name across several lines',
            destination: 'A long destination description',
            interests: [
              'An unusually long interest label that wraps',
              'Photography',
            ],
          ),
        ],
      ),
    );
    await tester.drag(
      find.byType(SingleChildScrollView).first,
      const Offset(0, -1800),
    );
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.person_outline), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Root keeps its existing navigation and shared controllers', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await PreferencesManager().init();
    final account = AccountRepo();
    final people = PeopleRepo(account);
    await show(
      tester,
      screen: Root(
        homeAccountRepo: account,
        postsRepo: EmptyPostsRepo(),
        followRepo: people,
      ),
    );
    final nav = find.byType(BottomNavigationBar);
    final followBefore = tester.element(nav).read<FollowCubit>();
    await tester.tap(find.descendant(of: nav, matching: find.text('Buddies')));
    await tester.pumpAndSettle();
    expect(find.byType(BuddiesScreen), findsOneWidget);
    expect(tester.widget<BottomNavigationBar>(nav).currentIndex, 3);
    expect(
      tester.element(find.byType(BuddiesScreen)).read<FollowCubit>(),
      same(followBefore),
    );
    await tester.tap(find.descendant(of: nav, matching: find.text('Home')));
    await tester.pumpAndSettle();
    expect(tester.widget<BottomNavigationBar>(nav).currentIndex, 0);
    expect(tester.takeException(), isNull);
  });
}
