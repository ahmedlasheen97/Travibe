import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/core/models/public_user_model.dart';
import 'package:travibe/features/home/data/post_model.dart';
import 'package:travibe/features/shares/data/send_post_repo.dart';
import 'package:travibe/features/shares/data/share_post_messenger.dart';

class SendPostState {
  const SendPostState({
    this.query = '',
    this.users = const [],
    this.loading = false,
    this.loadingMore = false,
    this.page = 0,
    this.lastPage = 1,
    this.error,
    this.selected = const [],
    this.sending = false,
    this.failures = const {},
  });
  final String query;
  final List<PublicUserModel> users;
  final bool loading;
  final bool loadingMore;
  final int page;
  final int lastPage;
  final String? error;

  /// Selected recipients, in selection order.
  final List<PublicUserModel> selected;
  final bool sending;

  /// User ID → message for recipients whose last send failed.
  final Map<String, String> failures;

  bool get hasMore => page > 0 && page < lastPage;
  bool get validQuery =>
      query.isEmpty || (query.runes.length >= 3 && query.runes.length <= 100);
  bool isSelected(String id) => selected.any((u) => u.id == id);

  /// Selected people missing from the current results stay visible, first.
  List<PublicUserModel> get visibleUsers {
    final ids = {for (final u in users) u.id};
    return [...selected.where((u) => !ids.contains(u.id)), ...users];
  }

  /// Search/pagination fields reset; selection and send state are kept.
  SendPostState withResults({
    required String query,
    List<PublicUserModel> users = const [],
    bool loading = false,
    bool loadingMore = false,
    int page = 0,
    int lastPage = 1,
    String? error,
  }) => SendPostState(
    query: query,
    users: users,
    loading: loading,
    loadingMore: loadingMore,
    page: page,
    lastPage: lastPage,
    error: error,
    selected: selected,
    sending: sending,
    failures: failures,
  );

  SendPostState withSelection({
    List<PublicUserModel>? selected,
    bool? sending,
    Map<String, String>? failures,
  }) => SendPostState(
    query: query,
    users: users,
    loading: loading,
    loadingMore: loadingMore,
    page: page,
    lastPage: lastPage,
    error: error,
    selected: selected ?? this.selected,
    sending: sending ?? this.sending,
    failures: failures ?? this.failures,
  );
}

class SendPostCubit extends Cubit<SendPostState> {
  SendPostCubit({
    required this.post,
    SendPostRepo? repo,
    SharePostMessenger? messenger,
  }) : _repo = repo ?? SendPostRepo(),
       _messenger = messenger ?? SharePostMessenger(),
       super(const SendPostState());

  final PostModel post;
  final SendPostRepo _repo;
  final SharePostMessenger _messenger;
  Timer? _debounce;
  int _generation = 0;

  void search(String value) {
    if (isClosed) return;
    final query = value.trim();
    if (query == state.query && (state.loading || state.page > 0)) return;
    _debounce?.cancel();
    final generation = ++_generation;
    final valid = SendPostState(query: query).validQuery;
    emit(state.withResults(query: query, loading: valid));
    if (valid) {
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
    emit(state.withResults(query: state.query, loading: true));
    await _load(generation);
  }

  Future<void> more() async {
    if (isClosed || state.loading || state.loadingMore || !state.hasMore) {
      return;
    }
    final previous = state;
    emit(
      previous.withResults(
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
        state.withResults(
          query: query,
          users: List.unmodifiable(users.values),
          page: page.currentPage,
          lastPage: page.lastPage,
        ),
      );
    } catch (error) {
      if (isClosed || generation != _generation) return;
      emit(
        state.withResults(
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

  void toggle(PublicUserModel user) {
    if (isClosed || state.sending || user.id.isEmpty) return;
    final selected = state.isSelected(user.id)
        ? state.selected.where((u) => u.id != user.id).toList()
        : [...state.selected, user];
    emit(
      state.withSelection(
        selected: List.unmodifiable(selected),
        failures: Map.unmodifiable({...state.failures}..remove(user.id)),
      ),
    );
  }

  /// People from the last [send] who got the post but not the note.
  List<PublicUserModel> noteFailed = const [];

  /// Sends to every selected person. Returns the people it was sent to, or
  /// null when nothing was attempted. Failed recipients stay selected.
  Future<List<PublicUserModel>?> send(String note) async {
    if (isClosed || state.sending || state.selected.isEmpty) return null;
    final recipients = state.selected;
    emit(state.withSelection(sending: true, failures: const {}));
    final result = await _messenger.send(
      post: post,
      to: recipients,
      note: note,
    );
    noteFailed = result.noteFailed;
    if (isClosed) return result.sent;
    emit(
      state.withSelection(
        sending: false,
        selected: List.unmodifiable(
          recipients.where((u) => result.failed.containsKey(u.id)),
        ),
        failures: result.failed,
      ),
    );
    return result.sent;
  }

  @override
  Future<void> close() {
    _debounce?.cancel();
    ++_generation;
    return super.close();
  }
}
