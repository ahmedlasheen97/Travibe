import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/core/models/public_user_model.dart';
import 'package:travibe/features/shares/data/send_post_repo.dart';

class SendPostState {
  const SendPostState({
    this.query = '',
    this.users = const [],
    this.loading = false,
    this.loadingMore = false,
    this.page = 0,
    this.lastPage = 1,
    this.error,
  });
  final String query;
  final List<PublicUserModel> users;
  final bool loading;
  final bool loadingMore;
  final int page;
  final int lastPage;
  final String? error;
  bool get hasMore => page > 0 && page < lastPage;
  bool get validQuery =>
      query.isEmpty || (query.runes.length >= 3 && query.runes.length <= 100);
}

class SendPostCubit extends Cubit<SendPostState> {
  SendPostCubit({SendPostRepo? repo})
    : _repo = repo ?? SendPostRepo(),
      super(const SendPostState());

  final SendPostRepo _repo;
  Timer? _debounce;
  int _generation = 0;

  void search(String value) {
    if (isClosed) return;
    final query = value.trim();
    if (query == state.query && (state.loading || state.page > 0)) return;
    _debounce?.cancel();
    final generation = ++_generation;
    final next = SendPostState(query: query);
    emit(SendPostState(query: query, loading: next.validQuery));
    if (next.validQuery) {
      _debounce = Timer(
        const Duration(milliseconds: 300),
        () => _load(generation),
      );
    }
  }

  Future<void> load() async {
    if (isClosed || state.loading || state.loadingMore || !state.validQuery) {
      return;
    }
    _debounce?.cancel();
    final generation = ++_generation;
    emit(SendPostState(query: state.query, loading: true));
    await _load(generation);
  }

  Future<void> more() async {
    if (isClosed || state.loading || state.loadingMore || !state.hasMore) {
      return;
    }
    final previous = state;
    emit(
      SendPostState(
        query: previous.query,
        users: previous.users,
        page: previous.page,
        lastPage: previous.lastPage,
        loadingMore: true,
      ),
    );
    await _load(_generation, previous: previous);
  }

  Future<void> _load(int generation, {SendPostState? previous}) async {
    final query = state.query;
    try {
      final page = await _repo.users(query, page: (previous?.page ?? 0) + 1);
      if (isClosed || generation != _generation) return;
      if (page.currentPage != (previous?.page ?? 0) + 1 ||
          page.lastPage < page.currentPage) {
        throw ApiError(message: 'Unable to read people. Please try again.');
      }
      final users = {
        for (final user in [...?previous?.users, ...page.users])
          if (user.id.isNotEmpty && !user.isBlocked) user.id: user,
      };
      emit(
        SendPostState(
          query: query,
          users: List.unmodifiable(users.values),
          page: page.currentPage,
          lastPage: page.lastPage,
        ),
      );
    } catch (error) {
      if (isClosed || generation != _generation) return;
      emit(
        SendPostState(
          query: query,
          users: previous?.users ?? const [],
          page: previous?.page ?? 0,
          lastPage: previous?.lastPage ?? 1,
          error: error is ApiError
              ? error.message
              : 'Unable to load people. Please try again.',
        ),
      );
    }
  }

  @override
  Future<void> close() {
    _debounce?.cancel();
    ++_generation;
    return super.close();
  }
}
