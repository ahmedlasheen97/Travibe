import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/features/home/data/post_model.dart';
import 'package:travibe/features/home/data/posts_repo.dart';

class SavesState {
  SavesState({
    Map<String, bool> values = const {},
    Set<String> pending = const {},
    this.revision = 0,
    required this.session,
  }) : values = Map.unmodifiable(values),
       pending = Set.unmodifiable(pending);
  final Map<String, bool> values;
  final Set<String> pending;
  final int revision;
  final int session;
}

/// Root owns one instance. Only confirmed mutations change the bookmark.
class SavesCubit extends Cubit<SavesState> {
  SavesCubit({PostsRepo? repo, PreferencesManager? preferences})
    : repo = repo ?? PostsRepo(),
      preferences = preferences ?? PreferencesManager(),
      super(
        SavesState(
          session: (preferences ?? PreferencesManager()).sessionRevision,
        ),
      ) {
    this.preferences.addListener(_sessionChanged);
  }
  final PostsRepo repo;
  final PreferencesManager preferences;
  final Map<String, int> _versions = {};
  bool get authenticated => preferences.hasSession;
  int get revision => state.revision;
  int get session => state.session;

  void _sessionChanged() {
    if (isClosed || preferences.sessionRevision == session) return;
    _versions.clear();
    emit(SavesState(session: preferences.sessionRevision));
  }

  void accept(
    List<PostModel> posts, {
    required int requestRevision,
    required int requestSession,
  }) {
    if (isClosed || requestSession != session || !authenticated) return;
    final values = {...state.values};
    var changed = false;
    for (final post in posts) {
      if (!post.hasSaveState ||
          state.pending.contains(post.id) ||
          (_versions[post.id] ?? 0) > requestRevision) {
        continue;
      }
      if (values[post.id] != post.isSaved) {
        values[post.id] = post.isSaved;
        changed = true;
      }
    }
    if (changed) {
      emit(
        SavesState(
          values: values,
          pending: state.pending,
          revision: revision,
          session: session,
        ),
      );
    }
  }

  PostModel apply(PostModel post) {
    final saved = state.values[post.id];
    return saved == null || (post.hasSaveState && post.isSaved == saved)
        ? post
        : post.copyWith(isSaved: saved, hasSaveState: true);
  }

  Future<ApiError?> toggle(PostModel post) async {
    if (isClosed || state.pending.contains(post.id)) return null;
    if (!authenticated) {
      return ApiError(
        message: 'Please sign in to save posts.',
        statusCode: 401,
      );
    }
    final current =
        state.values[post.id] ?? (post.hasSaveState ? post.isSaved : null);
    if (current == null) {
      return ApiError(
        message: 'Bookmark status is unavailable. Please refresh.',
      );
    }
    if ((int.tryParse(post.id) ?? 0) < 1) {
      return ApiError(message: 'This post is unavailable.', statusCode: 404);
    }
    final requestSession = session;
    emit(
      SavesState(
        values: state.values,
        pending: {...state.pending, post.id},
        revision: revision,
        session: session,
      ),
    );
    try {
      final confirmed = await repo.setSaved(post.id, !current);
      if (isClosed || session != requestSession) return null;
      if (confirmed != !current) {
        throw ApiError(message: 'The server did not confirm the bookmark.');
      }
      final nextRevision = revision + 1;
      _versions[post.id] = nextRevision;
      emit(
        SavesState(
          values: {...state.values, post.id: confirmed},
          pending: state.pending,
          revision: nextRevision,
          session: session,
        ),
      );
      return null;
    } catch (e) {
      if (isClosed || session != requestSession) return null;
      return e is ApiError
          ? e
          : ApiError(
              message: 'Unable to update the bookmark. Please try again.',
            );
    } finally {
      if (!isClosed && session == requestSession) {
        emit(
          SavesState(
            values: state.values,
            pending: {...state.pending}..remove(post.id),
            revision: revision,
            session: session,
          ),
        );
      }
    }
  }

  @override
  Future<void> close() {
    preferences.removeListener(_sessionChanged);
    return super.close();
  }
}
