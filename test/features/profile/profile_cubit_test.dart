import 'package:flutter_test/flutter_test.dart';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/features/profile/cubit/profile_cubit.dart';
import 'fixtures.dart';

void main() {
  late MemoryProfileRepo repo;
  late ProfileCubit cubit;
  setUp(() {
    repo = MemoryProfileRepo();
    cubit = ProfileCubit(profileRepo: repo);
  });
  tearDown(() => cubit.close());

  test('own loading coalesces requests and reaches loaded', () async {
    repo.hold = true;
    final load = cubit.loadProfile();
    final second = cubit.loadProfile();
    expect(cubit.state, isA<ProfileLoading>());
    expect(repo.reads, hasLength(1));
    expect(repo.reads.single.userId, isNull);
    repo.reads.single.result.complete(profile());
    await Future.wait([load, second]);
    expect((cubit.state as ProfileLoaded).profile.id, '7');
  });
  test(
    'public data:null has an explicit unavailable state and can retry',
    () async {
      await cubit.close();
      cubit = ProfileCubit(profileRepo: repo, userId: 23);
      repo.result = null;
      await cubit.loadProfile();
      expect(repo.reads.single.userId, 23);
      expect(cubit.state, isA<ProfileUnavailable>());
      repo.result = profile(id: 23);
      await cubit.loadProfile();
      expect(cubit.state, isA<ProfileLoaded>());
    },
  );
  test('initial authentication failure retains status and retries', () async {
    repo.error = ApiError(message: 'Please sign in', statusCode: 401);
    await cubit.loadProfile();
    expect((cubit.state as ProfileFailure).error.statusCode, 401);
    expect((cubit.state as ProfileFailure).errorMessage, 'Please sign in');
    repo.error = null;
    await cubit.loadProfile();
    expect(cubit.state, isA<ProfileLoaded>());
  });
  test(
    'refresh retains data during a network failure and retries successfully',
    () async {
      await cubit.loadProfile();
      repo.hold = true;
      final refresh = cubit.refresh();
      expect((cubit.state as ProfileLoaded).refreshing, true);
      repo.reads.last.result.completeError(ApiError(message: 'Offline'));
      await refresh;
      expect((cubit.state as ProfileLoaded).profile.id, '7');
      expect((cubit.state as ProfileLoaded).error!.message, 'Offline');
      repo.hold = false;
      repo.result = profile(name: 'Updated name');
      await cubit.refresh();
      expect((cubit.state as ProfileLoaded).profile.name, 'Updated name');
      expect((cubit.state as ProfileLoaded).error, isNull);
    },
  );
  test('401 during refresh clears previously displayed account data', () async {
    await cubit.loadProfile();
    repo.error = ApiError(message: 'Session expired', statusCode: 401);
    await cubit.refresh();
    expect(cubit.state, isA<ProfileFailure>());
  });
  test('newer refresh wins over old successes and failures', () async {
    repo.hold = true;
    final first = cubit.loadProfile();
    final second = cubit.refresh();
    repo.reads[1].result.complete(profile(name: 'Newest'));
    await second;
    repo.reads[0].result.completeError(ApiError(message: 'Old failure'));
    await first;
    expect((cubit.state as ProfileLoaded).profile.name, 'Newest');
    final third = cubit.refresh();
    final fourth = cubit.refresh();
    repo.reads[3].result.complete(profile(name: 'Latest'));
    await fourth;
    repo.reads[2].result.complete(profile(name: 'Stale'));
    await third;
    expect((cubit.state as ProfileLoaded).profile.name, 'Latest');
  });
  test('confirmed block invalidates a pending public response', () async {
    await cubit.close();
    cubit = ProfileCubit(profileRepo: repo, userId: 23);
    repo.hold = true;
    final load = cubit.loadProfile();
    cubit.publicProfileUnavailable();
    repo.reads.single.result.complete(profile(id: 23));
    await load;
    expect(cubit.state, isA<ProfileUnavailable>());
  });
  test('completion and requests after disposal do not emit', () async {
    repo.hold = true;
    final load = cubit.loadProfile();
    await cubit.close();
    repo.reads.single.result.complete(profile());
    await load;
    await cubit.refresh();
    expect(repo.reads, hasLength(1));
  });
}
