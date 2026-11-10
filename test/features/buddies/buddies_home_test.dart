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
import 'package:travibe/features/buddies/data/buddies_home_response.dart';
import 'package:travibe/features/buddies/data/buddies_repo.dart';
import 'package:travibe/features/buddies/cubit/buddies_cubit.dart';
import 'package:travibe/features/buddies/screens/buddies_screen.dart';
import 'package:travibe/features/buddies/widgets/buddies_visibility_invitation.dart';
import 'package:travibe/features/buddies/widgets/buddies_traveler_card.dart';

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
  @override
  Future<dynamic> post(String endpoint, Map<String, dynamic> data) async {
    recent.add(data);
    return {};
  }

  String? path;
  Map<String, dynamic>? query;
  @override
  Future<dynamic> get(
    String endpoint, {
    Map<String, dynamic>? queryParameters,
  }) async {
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

  testWidgets(
    'metadata controls banners and no-city state, visibility remains disabled',
    (tester) async {
      await show(tester, FakeApi(home(complete: false, visible: false)));
      expect(find.text('Complete your profile'), findsOneWidget);
      expect(find.byType(BuddiesVisibilityInvitation), findsOneWidget);
      expect(find.text('No current city is available.'), findsOneWidget);
      final button = tester.widget<TextButton>(
        find.widgetWithText(TextButton, 'Allow Location'),
      );
      expect(button.onPressed, isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'completed visible profile hides banners and displays actual city and users',
    (tester) async {
      await show(tester, FakeApi(home(city: true, users: [buddy()])));
      expect(find.text('Complete your profile'), findsNothing);
      expect(find.byType(BuddiesVisibilityInvitation), findsNothing);
      expect(find.text('Cairo'), findsOneWidget);
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
    expect(find.byType(CupertinoActivityIndicator), findsOneWidget);
    pending.completeError(ApiError(message: 'Network unavailable'));
    await tester.pumpAndSettle();
    expect(find.text('Network unavailable'), findsOneWidget);
    api.result = home();
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
      final api = FakeApi(home(users: [buddy()]));
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
    await show(tester, FakeApi(home(users: [buddy()])));
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
}
