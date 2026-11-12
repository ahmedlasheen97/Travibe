import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/core/datasource/remotedata/api_service.dart';
import 'package:travibe/features/auth/data/auth_repo.dart';
import 'package:travibe/features/auth/data/user_model.dart';
import 'package:travibe/features/profile/data/profile_model.dart';
import 'package:travibe/features/profile/data/profile_repo.dart';
import 'fixtures.dart';

class ProfileApi extends ApiService {
  final calls = <String>[];
  dynamic response;
  Object? error;
  @override
  Future<dynamic> get(
    String endpoint, {
    Map<String, dynamic>? queryParameters,
  }) async {
    calls.add(endpoint);
    if (error != null) throw error!;
    return response;
  }
}

void main() {
  test(
    'own profile uses profile and parses account/about/reference data',
    () async {
      final api = ProfileApi()
        ..response = {
          'data': {
            ...profileJson(),
            'locale': 'ar',
            'profile_completed': true,
            'email_verified_at': '2026-10-19T12:00:00Z',
          },
        };
      final result = await ProfileRepo(apiService: api).getMyProfile();
      expect(api.calls, ['profile']);
      expect(result.id, '7');
      expect(result.name, 'Mona Hassan');
      expect(result.email, 'mona@example.invalid');
      expect(result.locale, 'ar');
      expect(result.profileCompleted, true);
      expect(result.emailVerifiedAt, '2026-10-19T12:00:00Z');
      expect(result.bio, 'Exploring Egypt');
      expect(result.postsCount, 5);
      expect(result.followersCount, 12);
      expect(result.languageSelections.single.slug, 'arabic');
      expect(result.languages, ['العربية']);
      expect(result.interestSelections.single.slug, 'photography');
      expect(result.travelStyleSelections.single.name, 'Solo travel');
    },
  );
  test(
    'public profile validates integer target and retains viewer flags',
    () async {
      final api = ProfileApi()
        ..response = {
          'data': {
            ...profileJson(id: 23),
            'is_me': false,
            'is_following': '1',
            'follows_you': true,
          },
        };
      final repo = ProfileRepo(apiService: api);
      final result = (await repo.getPublicProfile(23))!;
      expect(api.calls, ['users/23']);
      expect(result.isMe, false);
      expect(result.isFollowing, true);
      expect(result.followsYou, true);
      expect(result.isBlocked, isNull);
      expect(() => repo.getPublicProfile(0), throwsArgumentError);
      expect(api.calls, hasLength(1));
      await expectLater(repo.getPublicProfile(99), throwsA(isA<ApiError>()));
    },
  );
  test(
    'nullable and absent fields stay unknown, without fabricated counts or identity',
    () {
      final result = ProfileModel.fromJson({
        'id': 7,
        'name': null,
        'email': 'private@example.invalid',
        'username': null,
        'avatar_url': null,
        'languages_spoken': null,
        'followers_count': null,
      });
      expect(result.displayName, '');
      expect(result.avatarUrl, isNull);
      expect(result.followersCount, isNull);
      expect(result.postsCount, isNull);
      expect(result.isFollowing, isNull);
      expect(result.isBlocked, isNull);
      expect(result.languages, isEmpty);
    },
  );
  test(
    'existing UserResource languages spelling preserves slugs and labels',
    () {
      final result = ProfileModel.fromJson({
        'id': 7,
        'languages': [
          {'slug': 'en', 'name': 'English'},
        ],
      });
      expect(result.languageSelections.single.slug, 'en');
      expect(result.languages, ['English']);
      expect(() => result.languageSelections.clear(), throwsUnsupportedError);
    },
  );
  group('share url', () {
    const link = 'https://example.invalid/u/7';
    test('is parsed as-is from users/{id}, profile and user', () async {
      final api = ProfileApi()
        ..response = {
          'data': {...profileJson(), 'url': link},
        };
      final repo = ProfileRepo(apiService: api);
      expect((await repo.getPublicProfile(7))!.url, Uri.parse(link));
      expect((await repo.getMyProfile()).url, Uri.parse(link));
      api.response = {
        'data': {
          ...profileJson(),
          'url': link,
          'email_verified_at': null,
          'profile_completed': true,
        },
      };
      expect(
        (await AuthRepo(apiService: api).currentUser()).url.toString(),
        link,
      );
      expect(api.calls, ['users/7', 'profile', 'user']);
    });

    test('survives settings and location copies', () {
      final model = ProfileModel.fromJson({...profileJson(), 'url': link});
      expect(model.withLocation('Cairo, EG').url, Uri.parse(link));
      expect(
        model
            .withSettings(
              ProfileModel.fromJson({
                ...profileJson(),
                'locale': 'en',
                'currency_code': 'EGP',
                'show_active_status': true,
                'show_in_travel_buddy': true,
                'push_notifications_enabled': true,
              }),
            )
            .url,
        Uri.parse(link),
      );
    });

    test('missing or non-https values are null, never built or fatal', () {
      for (final value in [
        null,
        '',
        42,
        'not a link',
        'http://example.invalid/u/7',
        'travibe://users/7',
        'https://user:pass@example.invalid/u/7',
      ]) {
        final json = {...profileJson(), 'url': value};
        expect(ProfileModel.fromJson(json).url, isNull, reason: '$value');
        expect(UserModel.fromJson(json).url, isNull, reason: '$value');
      }
      expect(ProfileModel.fromJson(profileJson()).url, isNull);
    });

    test('login/register user carries the url', () {
      final user = UserModel.fromJson({...profileJson(), 'url': link});
      expect(user.url, Uri.parse(link));
      expect(user.toJson()['url'], link);
    });
  });

  test('only explicit public data:null means unavailable', () async {
    final api = ProfileApi()..response = {'data': null};
    final repo = ProfileRepo(apiService: api);
    expect(await repo.getPublicProfile(7), isNull);
    await expectLater(repo.getMyProfile(), throwsA(isA<ApiError>()));
    for (final response in [
      null,
      {},
      {'data': []},
      {'data': {}},
      {'data': 'wrong'},
      {'id': 7},
    ]) {
      api.response = response;
      await expectLater(repo.getPublicProfile(7), throwsA(isA<ApiError>()));
      await expectLater(repo.getMyProfile(), throwsA(isA<ApiError>()));
    }
  });
  test('malformed fields are errors rather than coerced display values', () {
    for (final fields in [
      {'id': '7'},
      {'name': {}},
      {'posts_count': -1},
      {'followers_count': '12'},
      {'is_me': 'maybe'},
      {
        'languages_spoken': ['Arabic'],
      },
      {
        'interests': [
          {'name': 'Photo'},
        ],
      },
    ]) {
      expect(
        () => ProfileModel.fromJson({...profileJson(), ...fields}),
        throwsA(isA<ApiError>()),
      );
    }
  });
  test(
    '401 ApiError/status is preserved and Dio network failures are mapped',
    () async {
      final failure = ApiError(message: 'Unauthenticated', statusCode: 401);
      final api = ProfileApi()..error = failure;
      final repo = ProfileRepo(apiService: api);
      await expectLater(repo.getMyProfile(), throwsA(same(failure)));
      await expectLater(repo.getPublicProfile(7), throwsA(same(failure)));
      api.error = DioException(
        requestOptions: RequestOptions(path: 'profile'),
        type: DioExceptionType.connectionError,
      );
      await expectLater(
        repo.getMyProfile(),
        throwsA(
          isA<ApiError>().having(
            (e) => e.message,
            'message',
            contains('internet'),
          ),
        ),
      );
    },
  );
}
