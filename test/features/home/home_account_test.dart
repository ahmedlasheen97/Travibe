import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/core/datasource/remotedata/api_service.dart';
import 'package:travibe/features/home/cubit/home_account_cubit.dart';
import 'package:travibe/features/home/data/home_account_repo.dart';
import 'home_experience_fixtures.dart';

class Api extends ApiService {
  String? endpoint;
  final List<String> requests = [];
  Map<String, dynamic>? followingQuery;
  dynamic followingResponse = {
    'data': [],
    'meta': {'current_page': 1, 'total': 0},
  };
  ApiError? followingError;
  Completer<dynamic>? followingGate;
  dynamic response = {
    'data': {'id': 1, 'name': 'Viewer', 'following_count': 0},
  };
  ApiError? error;
  @override
  Future<dynamic> get(
    String endpoint, {
    Map<String, dynamic>? queryParameters,
  }) async {
    this.endpoint = endpoint;
    requests.add(endpoint);
    if (error != null) throw error!;
    if (endpoint == 'users/1/following-list') {
      followingQuery = queryParameters;
      if (followingError != null) throw followingError!;
      if (followingGate != null) return followingGate!.future;
      return followingResponse;
    }
    return response;
  }
}

void main() {
  test(
    'uses authenticated user endpoint and explicit relationship count',
    () async {
      final api = Api();
      final account = await HomeAccountRepo(apiService: api).getAccount();
      expect(api.endpoint, 'user');
      expect(account.id, '1');
      expect(account.followingCount, 0);
      expect(api.requests, ['user']);
    },
  );
  for (final total in [0, 7]) {
    test('following-list meta.total=$total is authoritative', () async {
      final api = Api()
        ..response = {
          'data': {'id': 1, 'name': 'Viewer'},
        }
        ..followingResponse = {
          'data': total == 0
              ? []
              : [
                  {'id': 2},
                ],
          'meta': {'current_page': 1, 'total': total},
        };
      final cubit = HomeAccountCubit(repo: HomeAccountRepo(apiService: api));
      addTearDown(cubit.close);
      await cubit.load();
      expect(cubit.state.account!.followingCount, total);
      expect(cubit.state.followsNobody, total == 0);
      expect(api.requests, ['user', 'users/1/following-list']);
      expect(api.followingQuery, {'per_page': 1});
    });
  }
  test(
    'missing or invalid metadata fails rather than inferring zero',
    () async {
      final api = Api()
        ..response = {
          'data': {'id': 1, 'name': 'Viewer'},
        };
      final cubit = HomeAccountCubit(repo: HomeAccountRepo(apiService: api));
      addTearDown(cubit.close);
      for (final meta in [
        null,
        <String, dynamic>{},
        {'total': null},
        {'total': -1},
        {'total': 'invalid'},
        {'total': 0.5},
        {'total': true},
      ]) {
        api.followingResponse = {'data': [], 'meta': meta};
        await cubit.load(force: true);
        expect(cubit.state.status, HomeAccountStatus.failure);
        expect(cubit.state.hasVerifiedCount, isFalse);
        expect(cubit.state.followsNobody, isFalse);
      }
    },
  );
  test(
    'following-list failure preserves API error and retry recovers',
    () async {
      final error = ApiError(message: 'Network failed', statusCode: 503);
      final api = Api()
        ..response = {
          'data': {'id': 1, 'name': 'Viewer'},
        }
        ..followingError = error;
      final cubit = HomeAccountCubit(repo: HomeAccountRepo(apiService: api));
      addTearDown(cubit.close);
      await cubit.load();
      expect(cubit.state.error, same(error));
      expect(cubit.state.followsNobody, isFalse);
      api.followingError = null;
      await cubit.load(force: true);
      expect(cubit.state.followsNobody, isTrue);
    },
  );
  test('forced relationship refresh rereads following-list total', () async {
    final api = Api()
      ..response = {
        'data': {'id': 1, 'name': 'Viewer'},
      };
    final cubit = HomeAccountCubit(repo: HomeAccountRepo(apiService: api));
    addTearDown(cubit.close);
    await cubit.load();
    expect(cubit.state.followsNobody, isTrue);
    api.followingResponse = {
      'meta': {'total': 1},
      'data': [],
    };
    await cubit.load(force: true);
    expect(cubit.state.account!.followingCount, 1);
    api.followingResponse = {
      'meta': {'total': 0},
      'data': [],
    };
    await cubit.load(force: true);
    expect(cubit.state.followsNobody, isTrue);
    expect(
      api.requests.where((path) => path.endsWith('following-list')).length,
      3,
    );
  });
  test('concurrent loads share one in-flight relationship request', () async {
    final api = Api()
      ..response = {
        'data': {'id': 1, 'name': 'Viewer'},
      }
      ..followingGate = Completer<dynamic>();
    final cubit = HomeAccountCubit(repo: HomeAccountRepo(apiService: api));
    addTearDown(cubit.close);
    final first = cubit.load();
    final second = cubit.load();
    expect(identical(first, second), isTrue);
    await Future<void>.delayed(Duration.zero);
    expect(cubit.state.status, HomeAccountStatus.loading);
    expect(api.requests, ['user', 'users/1/following-list']);
    api.followingGate!.complete(api.followingResponse);
    await first;
    expect(cubit.state.followsNobody, isTrue);
  });
  test(
    'missing and invalid counts remain unknown rather than defaulting to zero',
    () {
      for (final count in [null, -1, '-1', '', 'unknown', 0.5, '0.5', true]) {
        final account = HomeAccount.fromJson({
          'data': {'id': 1, 'name': 'Viewer', 'following_count': count},
        });
        final state = HomeAccountState(
          status: HomeAccountStatus.loaded,
          account: account,
        );
        expect(state.hasVerifiedCount, isFalse);
        expect(state.followsNobody, isFalse);
      }
    },
  );
  test('omitted following_count stays unknown', () {
    final account = HomeAccount.fromJson({
      'data': {'id': 1, 'name': 'Viewer'},
    });
    expect(account.followingCount, isNull);
    expect(
      HomeAccountState(
        status: HomeAccountStatus.loaded,
        account: account,
      ).followsNobody,
      isFalse,
    );
  });
  test('integer string counts preserve zero and positive relationships', () {
    for (final value in ['0', '2', ' 3 ']) {
      final account = HomeAccount.fromJson({
        'data': {'id': 1, 'name': 'Viewer', 'following_count': value},
      });
      expect(account.followingCount, int.parse(value.trim()));
    }
  });
  test('repository reads nested Laravel resource response', () async {
    final api = Api()
      ..response = {
        'data': {
          'data': {'id': 1, 'name': 'Viewer', 'following_count': '0'},
        },
      };
    final cubit = HomeAccountCubit(repo: HomeAccountRepo(apiService: api));
    addTearDown(cubit.close);
    await cubit.load();
    expect(api.endpoint, 'user');
    expect(cubit.state.followsNobody, isTrue);
  });
  test(
    'authenticated request failure preserves error and retry recovers',
    () async {
      final error = ApiError(message: 'Unauthenticated.', statusCode: 401);
      final api = Api()..error = error;
      final cubit = HomeAccountCubit(repo: HomeAccountRepo(apiService: api));
      addTearDown(cubit.close);
      await cubit.load();
      expect(cubit.state.status, HomeAccountStatus.failure);
      expect(cubit.state.error, same(error));
      expect(cubit.state.followsNobody, isFalse);
      api.error = null;
      await cubit.load(force: true);
      expect(cubit.state.status, HomeAccountStatus.loaded);
      expect(cubit.state.followsNobody, isTrue);
    },
  );
  test(
    'zero follows and positive follows with empty feeds are distinct',
    () async {
      final repo = AccountRepo();
      final cubit = HomeAccountCubit(repo: repo);
      addTearDown(cubit.close);
      await cubit.load();
      expect(cubit.state.followsNobody, isTrue);
      repo.followingCount = 3;
      await cubit.load(force: true);
      expect(cubit.state.followsNobody, isFalse);
      expect(cubit.state.account!.followingCount, 3);
    },
  );
  test(
    'loading and failed refresh cannot retain a false zero-follow indication',
    () async {
      final repo = AccountRepo();
      final cubit = HomeAccountCubit(repo: repo);
      addTearDown(cubit.close);
      await cubit.load();
      repo.gate = Completer<HomeAccount>();
      final request = cubit.load(force: true);
      expect(cubit.state.followsNobody, isFalse);
      repo.gate!.completeError(ApiError(message: 'Network failed'));
      await request;
      expect(cubit.state.status, HomeAccountStatus.failure);
      expect(cubit.state.followsNobody, isFalse);
      expect(cubit.state.error!.message, 'Network failed');
    },
  );
  test(
    'old account read cannot overwrite a count refreshed after a follow',
    () async {
      final repo = AccountRepo()..gate = Completer<HomeAccount>();
      final first = repo.gate!;
      final cubit = HomeAccountCubit(repo: repo);
      addTearDown(cubit.close);
      final old = cubit.load();
      repo.gate = Completer<HomeAccount>();
      final fresh = cubit.load(force: true);
      repo.gate!.complete(
        const HomeAccount(id: '1', name: 'Viewer', followingCount: 1),
      );
      await fresh;
      first.complete(
        const HomeAccount(id: '1', name: 'Viewer', followingCount: 0),
      );
      await old;
      expect(cubit.state.account!.followingCount, 1);
    },
  );
}
