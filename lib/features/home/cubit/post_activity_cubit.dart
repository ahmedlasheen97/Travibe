import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/features/home/data/post_model.dart';

class PostActivityState {
  PostActivityState({
    Map<String, int> comments = const {},
    Set<String> deleted = const {},
    Map<String, bool> commentsDisabled = const {},
    this.publicationRevision = 0,
    this.authorId,
    required this.session,
  }) : comments = Map.unmodifiable(comments),
       deleted = Set.unmodifiable(deleted),
       commentsDisabled = Map.unmodifiable(commentsDisabled);
  final Map<String, int> comments;

  /// Posts the viewer deleted this session; every list drops them.
  final Set<String> deleted;

  /// Confirmed commenting overrides from the author's own menu.
  final Map<String, bool> commentsDisabled;
  final int publicationRevision;
  final String? authorId;
  final int session;
}

/// Confirmed comment counts and publication notices, shared by existing lists.
class PostActivityCubit extends Cubit<PostActivityState> {
  PostActivityCubit({PreferencesManager? preferences})
    : preferences = preferences ?? PreferencesManager(),
      super(
        PostActivityState(
          session: (preferences ?? PreferencesManager()).sessionRevision,
        ),
      ) {
    this.preferences.addListener(_sessionChanged);
  }
  final PreferencesManager preferences;
  int _revision = 0;
  int get revision => _revision;
  final _versions = <String, int>{};
  void _sessionChanged() {
    if (isClosed || preferences.sessionRevision == state.session) return;
    _versions.clear();
    _revision = 0;
    emit(PostActivityState(session: preferences.sessionRevision));
  }

  void setCommentsCount(String id, int count) {
    if (isClosed || count < 0) return;
    _versions[id] = ++_revision;
    _put({...state.comments, id: count});
  }

  void accept(
    List<PostModel> posts, {
    required int requestRevision,
    required int requestSession,
  }) {
    if (isClosed || requestSession != state.session) return;
    final counts = {...state.comments};
    var changed = false;
    for (final post in posts) {
      if (!post.hasCommentCount) continue;
      if ((_versions[post.id] ?? 0) > requestRevision ||
          counts[post.id] == post.commentsCount) {
        continue;
      }
      counts[post.id] = post.commentsCount;
      changed = true;
    }
    if (changed) _put(counts);
  }

  void _put(
    Map<String, int> comments, {
    Set<String>? deleted,
    Map<String, bool>? commentsDisabled,
  }) => emit(
    PostActivityState(
      comments: comments,
      deleted: deleted ?? state.deleted,
      commentsDisabled: commentsDisabled ?? state.commentsDisabled,
      publicationRevision: state.publicationRevision,
      authorId: state.authorId,
      session: state.session,
    ),
  );
  void published(PostModel post) {
    if (isClosed) return;
    emit(
      PostActivityState(
        comments: state.comments,
        deleted: state.deleted,
        commentsDisabled: state.commentsDisabled,
        publicationRevision: state.publicationRevision + 1,
        authorId: post.userId.isNotEmpty ? post.userId : post.user.id,
        session: state.session,
      ),
    );
  }

  /// Call only after the backend confirmed the delete.
  void postDeleted(String id) {
    if (isClosed || state.deleted.contains(id)) return;
    _put(state.comments, deleted: {...state.deleted, id});
  }

  /// Call only after the backend confirmed the change.
  void setCommentsDisabled(String id, bool disabled) {
    if (isClosed || state.commentsDisabled[id] == disabled) return;
    _put(
      state.comments,
      commentsDisabled: {...state.commentsDisabled, id: disabled},
    );
  }

  @override
  Future<void> close() {
    preferences.removeListener(_sessionChanged);
    return super.close();
  }
}
