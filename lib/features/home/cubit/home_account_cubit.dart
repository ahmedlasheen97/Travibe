import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
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
  HomeAccountCubit({HomeAccountRepo? repo})
    : _repo = repo ?? HomeAccountRepo(),
      super(const HomeAccountState());
  final HomeAccountRepo _repo;
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
    emit(HomeAccountState(account: state.account));
    try {
      final account = await _repo.getAccount();
      if (!isClosed && _generation == generation) {
        emit(
          HomeAccountState(status: HomeAccountStatus.loaded, account: account),
        );
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
