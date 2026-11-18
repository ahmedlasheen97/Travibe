import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:travibe/features/block/cubit/block_cubit.dart';
import 'package:travibe/features/follow/cubit/follow_cubit.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/core/datasource/remotedata/api_service.dart';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/core/theme/dark_theme.dart';
import 'package:travibe/features/buddies/widgets/buddies_traveler_skeleton.dart';
import 'package:travibe/features/buddies/data/buddies_home_response.dart';
import 'package:travibe/features/buddies/data/buddies_repo.dart';
import 'package:travibe/features/buddies/cubit/buddies_cubit.dart';
import 'package:travibe/features/buddies/screens/buddies_screen.dart';
import 'package:travibe/features/buddies/widgets/buddies_visibility_invitation.dart';
import 'package:travibe/features/buddies/widgets/buddies_traveler_card.dart';
import 'package:travibe/features/buddies/widgets/buddies_complete_profile_card.dart';
import 'package:travibe/features/profilesetup/screens/profile_setup_screen.dart';

Map<String, dynamic> buddy({int id = 7}) => {
  'id': id,
  'name': 'API traveler',
  'username': null,
  'city': null,
  'country_code': null,
  'shared_interests_count': 0,
  'is_following': false,
  'trip': null,
};
Map<String, dynamic> home({
  bool complete = true,
  bool visible = true,
  bool city = false,
  List<dynamic>? users,
}) => {
  'data': {'in_your_city': users ?? [], 'with_same_interests': []},
  'meta': {
    'profile_completed': complete,
    'show_in_travel_buddy': visible,
    'has_current_city': city,
    'current_city': city ? {'city': 'Cairo', 'country_code': null} : null,
  },
};

class FakeApi extends ApiService {
  FakeApi(this.result);
  dynamic result;
  int calls = 0;
  final recent = <Map<String, dynamic>>[];

  /// Server-side `buddies/search/recent` history, newest first.
  final recentItems = <Map<String, dynamic>>[];
  final deleted = <String>[];
  int _recentId = 0;
  @override
  Future<dynamic> post(String endpoint, Map<String, dynamic> data) async {
    recent.add(data);
    if (endpoint != 'buddies/search/recent') return {};
    final destination = data['destination'] as String;
    recentItems.removeWhere(
      (item) =>
          (item['destination'] as String).toLowerCase() ==
          destination.toLowerCase(),
    );
    final item = {
      'id': ++_recentId,
      'destination': destination,
      'searched_at': null,
    };
    recentItems.insert(0, item);
    if (recentItems.length > 10) recentItems.removeLast();
    return {'data': item};
  }

  @override
  Future<dynamic> delete(String endpoint) async {
    deleted.add(endpoint);
    if (endpoint == 'buddies/search/recent') {
      recentItems.clear();
    } else if (endpoint.startsWith('buddies/search/recent/')) {
      final id = int.parse(endpoint.split('/').last);
      recentItems.removeWhere((item) => item['id'] == id);
    }
    return null;
  }

  String? path;
  Map<String, dynamic>? query;
  @override
  Future<dynamic> get(
    String endpoint, {
    Map<String, dynamic>? queryParameters,
  }) async {
    // History reads are not part of the discovery call counts.
    if (endpoint == 'buddies/search/recent') {
      return {'data': List.of(recentItems)};
    }
    calls++;
    path = endpoint;
    query = queryParameters;
    if (result is ApiError) throw result as ApiError;
    if (result is Completer<dynamic>) {
      return (result as Completer<dynamic>).future;
    }
    return result;
  }
}

class TestBlockCubit extends BlockCubit {
  TestBlockCubit(FollowCubit follow) : super(follow: follow);
  void blockForTest(String id) => emit(BlockState(blocked: {id: true}));
}

void main() {
  final preferences = PreferencesManager();
  setUp(() async {
    ScreenUtil.configure(
      data: const MediaQueryData(size: Size(390, 844)),
      designSize: const Size(390, 844),
      splitScreenMode: false,
      minTextAdapt: false,
    );
    SharedPreferences.setMockInitialValues({});
    await preferences.init();
    await preferences.saveToken('test-session');
  });
  tearDown(() => preferences.clear());

  test(
    'object home, empty arrays, nullable city/trip and absent optional fields',
    () {
      final result = BuddiesHomeResponse.fromJson(home(users: [buddy()]));
      expect(result.withSameInterests, isEmpty);
      final person = result.inYourCity.single;
      expect(person.id, 7);
      expect(person.avatarUrl, isNull);
      expect(person.city, isNull);
      expect(person.countryCode, isNull);
      expect(person.trip, isNull);
      expect(person.interests, isEmpty);
      expect(result.meta.currentCity, isNull);
      expect(result.meta.hasCurrentCity, false);
      expect(() => result.inYourCity.clear(), throwsUnsupportedError);
    },
  );
  test('preserves interest slugs, labels, avatar and full trip', () {
    final person = BuddyResource.fromJson({
      ...buddy(),
      'avatar_url': 'https://example.com/avatar.jpg',
      'interests': [
        {'slug': 'hiking', 'name': 'Hiking'},
      ],
      'trip': {
        'destination_city': 'Cairo',
        'destination_country_code': 'EG',
        'starts_on': '2026-11-01',
        'ends_on': null,
      },
    });
    expect(person.interests.single.slug, 'hiking');
    expect(person.interests.single.name, 'Hiking');
    expect(person.trip!.destinationCity, 'Cairo');
    expect(person.trip!.endsOn, isNull);
    expect(person.avatarUrl, 'https://example.com/avatar.jpg');
  });
  test(
    'rejects malformed data and metadata instead of guessing banner flags',
    () {
      expect(
        () => BuddiesHomeResponse.fromJson({'data': [], 'meta': {}}),
        throwsFormatException,
      );
      expect(
        () => BuddiesHomeResponse.fromJson({...home(), 'meta': {}}),
        throwsFormatException,
      );
      expect(
        () => BuddyResource.fromJson({...buddy(), 'id': '7'}),
        throwsFormatException,
      );
      expect(
        () => BuddyResource.fromJson({...buddy(), 'interests': 'hiking'}),
        throwsFormatException,
      );
    },
  );
  test(
    'repository uses buddies without invented queries; deduplicates stable IDs',
    () async {
      final api = FakeApi(home(users: [buddy(), buddy()]));
      final result = await BuddiesRepo(apiService: api).getHome();
      expect(api.path, 'buddies');
      expect(api.query, isNull);
      expect(result.inYourCity, hasLength(1));
    },
  );
  test('malformed response becomes ApiError', () async {
    final repo = BuddiesRepo(apiService: FakeApi({'data': []}));
    await expectLater(repo.getHome(), throwsA(isA<ApiError>()));
  });
  for (final status in [401, 403, 500]) {
    test('API $status preserved and retry succeeds', () async {
      final api = FakeApi(
        ApiError(message: 'Request failed', statusCode: status),
      );
      final cubit = BuddiesCubit(repo: BuddiesRepo(apiService: api));
      addTearDown(cubit.close);
      await cubit.load();
      expect(cubit.state.error!.statusCode, status);
      api.result = home();
      await cubit.load();
      expect(cubit.state.error, isNull);
      expect(cubit.state.home, isNotNull);
      expect(api.calls, 2);
    });
  }
  test('duplicate loads share request; refresh loads fresh snapshot', () async {
    final pending = Completer<dynamic>();
    final api = FakeApi(pending);
    final cubit = BuddiesCubit(repo: BuddiesRepo(apiService: api));
    addTearDown(cubit.close);
    final first = cubit.load();
    final second = cubit.load();
    expect(cubit.state.loading, true);
    expect(api.calls, 1);
    pending.complete(home());
    await Future.wait([first, second]);
    api.result = home(users: [buddy()]);
    await cubit.load();
    expect(api.calls, 2);
    expect(cubit.state.home!.inYourCity, hasLength(1));
  });
  test(
    'account switching clears data and rejects old in-flight response',
    () async {
      final old = Completer<dynamic>();
      final api = FakeApi(old);
      final cubit = BuddiesCubit(repo: BuddiesRepo(apiService: api));
      addTearDown(cubit.close);
      final first = cubit.load();
      api.result = home(users: [buddy(id: 8)]);
      await preferences.saveToken('second-session');
      await cubit.load();
      old.complete(home(users: [buddy(id: 7)]));
      await first;
      expect(cubit.state.home!.inYourCity.single.id, 8);
      await preferences.clear();
      expect(cubit.state.home, isNull);
    },
  );
  test('disposal ignores pending response', () async {
    final pending = Completer<dynamic>();
    final cubit = BuddiesCubit(repo: BuddiesRepo(apiService: FakeApi(pending)));
    final request = cubit.load();
    await cubit.close();
    pending.complete(home());
    await request;
    expect(cubit.isClosed, true);
  });

  Future<void> show(WidgetTester tester, FakeApi api) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: darkTheme,
        home: BuddiesScreen(repo: BuddiesRepo(apiService: api)),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('incomplete and hidden profile shows both cards, profile first', (
    tester,
  ) async {
    await show(tester, FakeApi(home(complete: false, visible: false)));
    final profile = find.byType(BuddiesCompleteProfileCard);
    final visibility = find.byType(BuddiesVisibilityInvitation);
    expect(profile, findsOneWidget);
    expect(find.text('Complete Profile'), findsOneWidget);
    expect(visibility, findsOneWidget);
    expect(find.text('Turn On Visibility'), findsOneWidget);
    expect(
      tester.getTopLeft(profile).dy,
      lessThan(tester.getTopLeft(visibility).dy),
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Complete Profile card matches the Figma layout', (tester) async {
    await show(tester, FakeApi(home(complete: false, city: true)));
    final card = find.byType(BuddiesCompleteProfileCard);
    final art = find.byKey(const ValueKey('complete-profile-art'));
    final title = find.text('Complete your profile');
    final button = find.widgetWithText(TextButton, 'Complete Profile');
    expect(
      find.text('Add more details so people can get to know you more.'),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: art,
        matching: find.image(
          const AssetImage('assets/images/buddies/completeprofile.png'),
        ),
      ),
      findsOneWidget,
    );
    // Picture on the left in a ~80 circle; text and button on the right.
    expect(tester.getSize(art).width, closeTo(80, 1));
    expect(
      (tester.widget<Container>(art).decoration! as BoxDecoration).shape,
      BoxShape.circle,
    );
    expect(tester.getTopRight(art).dx, lessThan(tester.getTopLeft(title).dx));
    expect(
      tester.getTopLeft(button).dy,
      greaterThan(tester.getBottomLeft(title).dy),
    );
    // Button is right-aligned inside the card padding.
    expect(
      tester.getTopRight(card).dx - tester.getTopRight(button).dx,
      lessThan(20),
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Complete Profile card fits narrow screens with 2x text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: darkTheme,
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(320, 640),
            textScaler: TextScaler.linear(2),
          ),
          child: Scaffold(
            body: SingleChildScrollView(
              child: BuddiesCompleteProfileCard(onComplete: () {}),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('incomplete but visible profile shows only the profile card', (
    tester,
  ) async {
    await show(tester, FakeApi(home(complete: false, city: true)));
    expect(find.byType(BuddiesCompleteProfileCard), findsOneWidget);
    expect(find.byType(BuddiesVisibilityInvitation), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('no current city counts as incomplete', (tester) async {
    await show(tester, FakeApi(home()));
    expect(find.byType(BuddiesCompleteProfileCard), findsOneWidget);
    expect(find.byType(BuddiesVisibilityInvitation), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('complete but hidden profile shows the Figma visibility card', (
    tester,
  ) async {
    await show(tester, FakeApi(home(visible: false, city: true)));
    expect(find.byType(BuddiesCompleteProfileCard), findsNothing);
    expect(find.byType(BuddiesVisibilityInvitation), findsOneWidget);
    expect(find.text('Meet People in Your City'), findsOneWidget);
    expect(find.text('Turn On Visibility'), findsOneWidget);
    expect(find.text('You can turn this off from settings.'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Complete Profile opens setup and returns to Buddies', (
    tester,
  ) async {
    await show(tester, FakeApi(home(complete: false)));
    await tester.tap(find.text('Complete Profile'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(ProfileSetupScreen), findsOneWidget);
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.byType(ProfileSetupScreen), findsNothing);
    expect(find.byType(BuddiesCompleteProfileCard), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'completed visible profile hides banners and shows traveler sections',
    (tester) async {
      await show(tester, FakeApi(home(city: true, users: [buddy()])));
      expect(find.byType(BuddiesCompleteProfileCard), findsNothing);
      expect(find.byType(BuddiesVisibilityInvitation), findsNothing);
      expect(find.text('In Your City'), findsOneWidget);
      expect(find.text('See All'), findsOneWidget);
      expect(find.text('API traveler'), findsOneWidget);
      expect(find.byType(BuddiesTravelerCard), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('loading, retry and empty state use real request outcome', (
    tester,
  ) async {
    final pending = Completer<dynamic>();
    final api = FakeApi(pending);
    await tester.pumpWidget(
      MaterialApp(
        theme: darkTheme,
        home: BuddiesScreen(repo: BuddiesRepo(apiService: api)),
      ),
    );
    await tester.pump();
    expect(find.byType(BuddiesSectionSkeleton), findsNWidgets(2));
    expect(find.byType(CupertinoActivityIndicator), findsNothing);
    pending.completeError(ApiError(message: 'Network unavailable'));
    await tester.pumpAndSettle();
    expect(find.byType(BuddiesSectionSkeleton), findsNothing);
    expect(find.text('Network unavailable'), findsOneWidget);
    api.result = home(city: true);
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('No travelers found yet.'), findsOneWidget);
    expect(api.calls, 2);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'confirmed block state hides users without another discovery request',
    (tester) async {
      final follow = FollowCubit();
      final block = TestBlockCubit(follow);
      final api = FakeApi(home(city: true, users: [buddy()]));
      await tester.pumpWidget(
        MaterialApp(
          theme: darkTheme,
          home: BlocProvider<BlockCubit>.value(
            value: block,
            child: BuddiesScreen(repo: BuddiesRepo(apiService: api)),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('API traveler'), findsOneWidget);
      block.blockForTest('7');
      await tester.pumpAndSettle();
      expect(find.text('API traveler'), findsNothing);
      expect(api.calls, 1);
      await tester.pumpWidget(const SizedBox());
      await block.close();
      await follow.close();
    },
  );

  testWidgets('session logout removes visible travelers immediately', (
    tester,
  ) async {
    await show(tester, FakeApi(home(city: true, users: [buddy()])));
    expect(find.text('API traveler'), findsOneWidget);
    await preferences.clear();
    await tester.pump();
    expect(find.text('API traveler'), findsNothing);
    final cubit = tester
        .element(find.byType(BuddiesLandingView))
        .read<BuddiesCubit>();
    expect(cubit.state.home, isNull);
    await tester.pumpWidget(const SizedBox());
  });

  for (final users in [
    <dynamic>[],
    [buddy()],
  ]) {
    testWidgets(
      'incomplete profile shows only the cards (${users.length} travelers)',
      (tester) async {
        await show(
          tester,
          FakeApi(home(complete: false, visible: false, users: users)),
        );
        expect(find.byType(BuddiesCompleteProfileCard), findsOneWidget);
        expect(find.byType(BuddiesVisibilityInvitation), findsOneWidget);
        expect(find.text('No travelers found yet.'), findsNothing);
        expect(
          find.text('Traveler discovery is not available yet.'),
          findsNothing,
        );
        expect(find.byType(BuddiesSectionSkeleton), findsNothing);
        expect(find.text('In Your City'), findsNothing);
        expect(find.byType(BuddiesTravelerCard), findsNothing);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets(
    'tapping a traveler opens their profile; back keeps the scroll position',
    (tester) async {
      tester.view.physicalSize = const Size(390, 500);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final pushed = <String?>[];
      final api = FakeApi({
        'data': {
          'in_your_city': [buddy(id: 7)],
          'with_same_interests': [buddy(id: 8)],
        },
        'meta': home(city: true)['meta'],
      });
      await tester.pumpWidget(
        MaterialApp(
          theme: darkTheme,
          navigatorObservers: [_PushObserver(pushed)],
          home: BuddiesScreen(repo: BuddiesRepo(apiService: api)),
        ),
      );
      await tester.pumpAndSettle();
      final scrollable = find
          .descendant(
            of: find.byType(BuddiesLandingView),
            matching: find.byWidgetPredicate(
              (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
            ),
          )
          .first;
      await tester.ensureVisible(find.byType(BuddiesTravelerCard).last);
      await tester.pumpAndSettle();
      final offset = tester.state<ScrollableState>(scrollable).position.pixels;
      expect(offset, greaterThan(0));

      pushed.clear();
      await tester.tap(find.byType(BuddiesTravelerCard).last);
      await tester.pump();
      expect(pushed, ['user-profile/8']);

      tester.state<NavigatorState>(find.byType(Navigator)).pop();
      await tester.pumpAndSettle();
      expect(find.byType(BuddiesLandingView), findsOneWidget);
      expect(tester.state<ScrollableState>(scrollable).position.pixels, offset);
      expect(api.calls, 1);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    },
  );
}

class _PushObserver extends NavigatorObserver {
  _PushObserver(this.names);
  final List<String?> names;
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      names.add(route.settings.name);
}
