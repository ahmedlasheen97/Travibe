import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/features/home/data/post_model.dart';

class PostActivityState {
  PostActivityState({
    Map<String, int> comments = const {},
    this.publicationRevision = 0,
    this.authorId,
    required this.session,
  }) : comments = Map.unmodifiable(comments);
  final Map<String, int> comments;
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

  void _put(Map<String, int> comments) => emit(
    PostActivityState(
      comments: comments,
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
        publicationRevision: state.publicationRevision + 1,
        authorId: post.userId.isNotEmpty ? post.userId : post.user.id,
        session: state.session,
      ),
    );
  }

  @override
  Future<void> close() {
    preferences.removeListener(_sessionChanged);
    return super.close();
  }
}
