import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/features/home/data/home_account_cache.dart';
import 'package:travibe/features/home/data/home_account_repo.dart';

enum HomeAccountStatus { loading, loaded, failure }

class HomeAccountState {
  const HomeAccountState({
    this.status = HomeAccountStatus.loading,
    this.account,
    this.error,
  });
  final HomeAccountStatus status;
  final HomeAccount? account;
  final ApiError? error;
  bool get hasVerifiedCount =>
      status == HomeAccountStatus.loaded && account?.followingCount != null;
  bool get followsNobody => hasVerifiedCount && account!.followingCount == 0;
}

class HomeAccountCubit extends Cubit<HomeAccountState> {
  /// Seeds the last cached account of this session (name/avatar only; the
  /// following count is never cached, so it is never treated as verified).
  HomeAccountCubit({HomeAccountRepo? repo, HomeAccountCache? cache})
    : _repo = repo ?? HomeAccountRepo(),
      _cache = cache ?? HomeAccountCache(),
      super(const HomeAccountState()) {
    _revision = _cache.sessionRevision;
    final cached = _cache.read();
    if (cached != null) emit(HomeAccountState(account: cached));
  }
  final HomeAccountRepo _repo;
  final HomeAccountCache _cache;
  late int _revision;
  int _generation = 0;
  Future<void>? _pending;

  Future<void> load({bool force = false}) {
    if (isClosed) return Future.value();
    if (!force && _pending != null) return _pending!;
    final generation = ++_generation;
    return _pending = _load(generation).whenComplete(() {
      if (_generation == generation) _pending = null;
    });
  }

  Future<void> _load(int generation) async {
    final revision = _cache.sessionRevision;
    // A different account must not keep showing the previous one's name.
    final previous = revision == _revision ? state.account : _cache.read();
    _revision = revision;
    emit(HomeAccountState(account: previous));
    try {
      final account = await _repo.getAccount();
      if (!isClosed && _generation == generation) {
        emit(
          HomeAccountState(status: HomeAccountStatus.loaded, account: account),
        );
        unawaited(_cache.write(account, sessionRevision: revision));
      }
    } catch (error) {
      if (!isClosed && _generation == generation) {
        emit(
          HomeAccountState(
            status: HomeAccountStatus.failure,
            account: state.account,
            error: error is ApiError
                ? error
                : ApiError(
                    message: 'Unable to load your account. Please try again.',
                  ),
          ),
        );
      }
    }
  }
}
