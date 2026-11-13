import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/core/datasource/remotedata/api_service.dart';
import 'package:travibe/features/follow/cubit/follow_cubit.dart';
import 'package:travibe/features/follow_requests/cubit/incoming_requests_cubit.dart';
import 'package:travibe/features/follow_requests/data/follow_requests_repo.dart';

import 'follow_requests_fakes.dart';

class RecordingApi extends ApiService {
  final calls = <String>[];
  Map<String, dynamic>? query;
  dynamic response;
  @override
  Future<dynamic> get(
    String endpoint, {
    Map<String, dynamic>? queryParameters,
  }) async {
    calls.add('GET $endpoint');
    query = queryParameters;
    return response;
  }

  @override
  Future<dynamic> post(String endpoint, Map<String, dynamic> data) async {
    calls.add('POST $endpoint');
    return response;
  }

  @override
  Future<dynamic> delete(String endpoint) async {
    calls.add('DELETE $endpoint');
    return {'message': 'ok'};
  }
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({'_token': 'auth'});
    await PreferencesManager().init();
  });

  group('FollowRequestsRepo', () {
    test('uses the documented endpoints and parses page meta', () async {
      final api = RecordingApi()
        ..response = {
          'data': [requesterJson(3)],
          'meta': {'current_page': 1, 'last_page': 2, 'total': 16},
        };
      final repo = FollowRequestsRepo(apiService: api);
      final page = await repo.list(page: 1, perPage: 100);
      expect(api.query, {'page': 1, 'per_page': 100});
      expect(page.users.single.id, '3');
      expect(page.total, 16);
      expect(page.hasMore, isTrue);

      api.response = {'message': 'ok', 'data': requesterJson(3)};
      final accepted = await repo.accept('3');
      expect(accepted.id, '3');
      await repo.decline('4');
      expect(api.calls, [
        'GET follow-requests',
        'POST follow-requests/3/accept',
        'DELETE follow-requests/4',
      ]);
      expect(() => repo.accept('abc'), throwsArgumentError);
    });
  });

  group('IncomingRequestsCubit', () {
    late FakeFollowRequestsRepo repo;
    late FollowCubit follow;
    late CountingCurrentUser current;
    late IncomingRequestsCubit cubit;
    setUp(() {
      repo = FakeFollowRequestsRepo(
        pages: {
          1: requestsPage([3, 4], total: 2),
        },
      );
      follow = FollowCubit();
      current = CountingCurrentUser();
      cubit = IncomingRequestsCubit(
        repo: repo,
        follow: follow,
        currentUser: () => current,
      );
    });
    tearDown(() async {
      await cubit.close();
      await follow.close();
      await current.close();
    });

    test('sync loads ids and total from a 100-item first page', () async {
      await cubit.sync();
      expect(repo.listCalls.single, (1, 100));
      expect(cubit.contains('3'), isTrue);
      expect(cubit.state.total, 2);
      expect(cubit.state.loaded, isTrue);
    });

    test(
      'accept removes immediately, bumps followers, marks follows-you',
      () async {
        await cubit.sync();
        repo.gate = Completer<void>();
        final request = cubit.accept('3');
        expect(cubit.contains('3'), isFalse);
        expect(cubit.state.total, 1);
        expect(cubit.state.pending, contains('3'));
        expect(current.deltas, [1]);
        repo.gate!.complete();
        expect(await request, isNull);
        expect(repo.accepted, ['3']);
        expect(cubit.state.pending, isEmpty);
        expect(follow.state.followsYou['3'], isTrue);
      },
    );

    test('decline failure restores the request and the count', () async {
      await cubit.sync();
      repo.declineError = ApiError(message: 'Server down', statusCode: 500);
      final error = await cubit.decline('4');
      expect(error?.message, 'Server down');
      expect(cubit.contains('4'), isTrue);
      expect(cubit.state.total, 2);
      expect(current.deltas, isEmpty);
    });

    test('accept failure rolls the follower count back', () async {
      await cubit.sync();
      repo.acceptError = ApiError(message: 'Nope', statusCode: 500);
      await cubit.accept('3');
      expect(current.deltas, [1, -1]);
      expect(cubit.contains('3'), isTrue);
    });

    test('a request already handled (409) stays removed', () async {
      await cubit.sync();
      repo.acceptError = ApiError(message: 'Conflict', statusCode: 409);
      final error = await cubit.accept('3');
      expect(error?.message, 'This request was already handled.');
      expect(cubit.state.isHandled('3'), isTrue);
      expect(cubit.contains('3'), isFalse);
    });

    test('duplicate taps while pending are ignored', () async {
      await cubit.sync();
      repo.gate = Completer<void>();
      final first = cubit.accept('3');
      expect(await cubit.accept('3'), isNull);
      expect(await cubit.decline('3'), isNull);
      repo.gate!.complete();
      await first;
      expect(repo.accepted, ['3']);
      expect(repo.declined, isEmpty);
    });

    test('remember adds later pages without changing handled requests', () {
      cubit.remember(['9'], total: 20);
      expect(cubit.contains('9'), isTrue);
      expect(cubit.state.total, 20);
    });
  });
}
