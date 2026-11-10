import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/features/home/cubit/posts_cubit.dart';
import 'package:travibe/features/home/data/hidden_post_response.dart';
import 'package:travibe/features/home/data/posts_repo.dart';

class HiddenPostsState {
  HiddenPostsState({
    Set<String> hidden = const {},
    Set<String> pending = const {},
    this.response,
  }) : hidden = Set.unmodifiable(hidden),
       pending = Set.unmodifiable(pending);
  final Set<String> hidden;
  final Set<String> pending;
  final HiddenPostResponse? response;
}

/// Coordinates confirmed hide state across the two cached feed tabs.
class HiddenPostsCubit extends Cubit<HiddenPostsState> {
  HiddenPostsCubit({required this.repo, required List<PostsCubit> feeds})
    : _feeds = Set.of(feeds),
      super(HiddenPostsState()) {
    PreferencesManager().addListener(_sessionChanged);
  }
  final PostsRepo repo;
  final Set<PostsCubit> _feeds;
  void registerFeeds(Iterable<PostsCubit> feeds) => _feeds.addAll(feeds);
  void unregisterFeeds(Iterable<PostsCubit> feeds) => _feeds.removeAll(feeds);
  void _sessionChanged() {
    if (!isClosed) emit(HiddenPostsState());
  }

  @override
  Future<void> close() {
    PreferencesManager().removeListener(_sessionChanged);
    return super.close();
  }

  Future<ApiError?> setHidden(String postId, bool hidden) async {
    if (isClosed || state.pending.contains(postId)) return null;
    emit(
      HiddenPostsState(
        hidden: state.hidden,
        pending: {...state.pending, postId},
      ),
    );
    final session = PreferencesManager().sessionRevision;
    try {
      final response = await repo.setHidden(postId, hidden);
      if (isClosed || session != PreferencesManager().sessionRevision) {
        return null;
      }
      // Also validate injected repositories before altering any feed state.
      if (response.isHidden != hidden) {
        throw ApiError(
          message: 'The server did not confirm the requested hidden state',
        );
      }
      for (final feed in _feeds) {
        feed.setPostHidden(postId, response.isHidden);
      }
      final ids = {...state.hidden};
      if (response.isHidden) {
        ids.add(postId);
      } else {
        ids.remove(postId);
      }
      emit(
        HiddenPostsState(
          hidden: ids,
          pending: {...state.pending}..remove(postId),
          response: response,
        ),
      );
      return null;
    } catch (e) {
      if (!isClosed && session == PreferencesManager().sessionRevision) {
        emit(
          HiddenPostsState(
            hidden: state.hidden,
            pending: {...state.pending}..remove(postId),
          ),
        );
      }
      return e is ApiError
          ? e
          : ApiError(message: 'Unable to update this post. Please try again.');
    }
  }
}
