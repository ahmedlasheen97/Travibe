import 'package:travibe/core/models/cursor_pagination.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/features/comments/data/comment_model.dart';
import 'package:travibe/features/comments/data/comments_repo.dart';
import 'package:travibe/features/likes/cubit/likes_cubit.dart';
import 'package:travibe/features/likes/data/like_model.dart';

part 'comments_state.dart';

/// One post, with independent pagination for its root thread and every reply thread.
class CommentsCubit extends Cubit<CommentsState> {
  CommentsCubit({
    required this.postId,
    int initialCount = 0,
    CommentsRepo? repo,
    LikesCubit? likes,
    this.onCountChanged,
    this.onSyncError,
  }) : _repo = repo ?? CommentsRepo(),
       _likes = likes ?? LikesCubit(),
       _ownsLikes = likes == null,
       super(CommentsState(count: initialCount)) {
    _session.addListener(_sessionChanged);
    _likesSubscription = _likes.stream.listen((_) => _emit());
  }
  final _session = PreferencesManager();
  final _cursors = <int?, CursorProgress>{};
  void _sessionChanged() {
    if (isClosed) return;
    for (final key in _generations.keys.toList()) {
      _generations[key] = _generations[key]! + 1;
    }
    _cursors.clear();
    _loads.clear();
    _more.clear();
    ++_syncGeneration;
    _syncRequest = null;
    emit(CommentsState(count: 0));
  }

  final LikesCubit _likes;
  final bool _ownsLikes;
  late final StreamSubscription<LikesState> _likesSubscription;
  LikeTarget _likeTarget(int id) => LikeTarget.comment(postId, id);
  bool isLikePending(int id) => _likes.value(_likeTarget(id))?.pending == true;

  Future<ApiError?> toggleLike(CommentModel comment) {
    if (isClosed || state.busy || state.deleted.containsKey(comment.id)) {
      return Future.value();
    }
    final current = state.known[comment.id] ?? comment;
    return _likes.toggle(
      _likeTarget(current.id),
      initial:
          current.isLiked != null &&
              current.likesCount != null &&
              current.likesCount! >= 0
          ? LikeValue(isLiked: current.isLiked!, count: current.likesCount!)
          : null,
    );
  }

  CommentModel _withLikeState(CommentModel comment) {
    final value = _likes.value(_likeTarget(comment.id));
    if (value == null ||
        (comment.isLiked == value.isLiked &&
            comment.likesCount == value.count)) {
      return comment;
    }
    return comment.copyWithLikes(
      isLiked: value.isLiked,
      likesCount: value.count,
    );
  }

  void _acceptLikes(List<CommentModel> comments, int revision) =>
      _likes.accept({
        for (final comment in comments)
          if (comment.isLiked != null &&
              comment.likesCount != null &&
              comment.likesCount! >= 0)
            _likeTarget(comment.id): LikeValue(
              isLiked: comment.isLiked!,
              count: comment.likesCount!,
            ),
      }, requestRevision: revision);
  final int postId;
  final CommentsRepo _repo;
  final void Function(int count)? onCountChanged;
  final void Function(ApiError error)? onSyncError;
  final Map<int?, int> _generations = {};
  final Map<int?, Future<void>> _loads = {};
  final Set<int?> _more = {};
  Future<void>? _syncRequest;
  int _syncGeneration = 0;

  void _emit({
    Map<int?, CommentThreadState>? threads,
    Map<int, CommentModel>? known,
    Map<int, CommentModel>? deleted,
    int? count,
    bool? busy,
    bool? syncing,
    ApiError? syncError,
    bool clearSyncError = false,
  }) {
    if (isClosed) return;
    emit(
      CommentsState(
        threads: {
          for (final entry in (threads ?? state.threads).entries)
            entry.key: entry.value.copyWith(
              comments: entry.value.comments.map(_withLikeState).toList(),
            ),
        },
        known: {
          for (final entry in (known ?? state.known).entries)
            entry.key: _withLikeState(entry.value),
        },
        deleted: deleted ?? state.deleted,
        count: count ?? state.count,
        busy: busy ?? state.busy,
        syncing: syncing ?? state.syncing,
        syncError: clearSyncError ? null : syncError ?? state.syncError,
      ),
    );
  }

  void _thread(int? id, CommentThreadState value) =>
      _emit(threads: {...state.threads, id: value});

  Future<void> load({int? parentId, bool force = false}) {
    if (isClosed) return Future.value();
    if (!force && _loads.containsKey(parentId)) return _loads[parentId]!;
    final generation = (_generations[parentId] ?? 0) + 1;
    _generations[parentId] = generation;
    _more.remove(parentId);
    final future = _load(parentId, generation).whenComplete(() {
      if (_generations[parentId] == generation) _loads.remove(parentId);
    });
    _loads[parentId] = future;
    return future;
  }

  Future<void> _load(int? parentId, int generation) async {
    final likeRevision = _likes.revision;
    final previous = state.thread(parentId);
    _thread(
      parentId,
      CommentThreadState(
        status: previous.status == CommentsStatus.loaded
            ? CommentsStatus.loaded
            : CommentsStatus.loading,
        comments: previous.comments,
        nextCursor: previous.nextCursor,
        prevCursor: previous.prevCursor,
        hasMore: previous.hasMore,
        refreshing: previous.status == CommentsStatus.loaded,
      ),
    );
    try {
      final page = await _repo.list(postId, parentId: parentId);
      if (isClosed || _generations[parentId] != generation) return;
      final progress = _cursors.putIfAbsent(parentId, CursorProgress.new);
      progress.accept(page.pagination);
      _accept(page.comments, likeRevision: likeRevision);
      _thread(
        parentId,
        CommentThreadState(
          status: CommentsStatus.loaded,
          comments: {
            for (final comment in page.comments) comment.id: comment,
          }.values.toList(),
          nextCursor: progress.nextCursor,
          prevCursor: progress.prevCursor,
          hasMore: progress.hasMore,
        ),
      );
    } catch (e) {
      if (isClosed || _generations[parentId] != generation) return;
      _thread(
        parentId,
        CommentThreadState(
          status: previous.status == CommentsStatus.loaded
              ? CommentsStatus.loaded
              : CommentsStatus.failure,
          comments: state.thread(parentId).comments,
          nextCursor: previous.nextCursor,
          prevCursor: previous.prevCursor,
          hasMore: previous.hasMore,
          error: _error(e),
        ),
      );
    }
  }

  Future<void> more({int? parentId, bool retry = false}) async {
    final previous = state.thread(parentId);
    if (isClosed ||
        _loads.containsKey(parentId) ||
        _more.contains(parentId) ||
        previous.status != CommentsStatus.loaded ||
        !previous.hasMore ||
        (previous.paginationError != null && !retry)) {
      return;
    }
    final generation = _generations[parentId];
    final likeRevision = _likes.revision;
    _more.add(parentId);
    _thread(
      parentId,
      CommentThreadState(
        status: CommentsStatus.loaded,
        comments: previous.comments,
        nextCursor: previous.nextCursor,
        prevCursor: previous.prevCursor,
        hasMore: previous.hasMore,
        loadingMore: true,
        error: previous.error,
      ),
    );
    try {
      final page = await _repo.list(
        postId,
        parentId: parentId,
        cursor: previous.nextCursor,
      );
      if (isClosed || _generations[parentId] != generation) return;
      final progress = _cursors[parentId]!;
      progress.accept(page.pagination, requestedCursor: previous.nextCursor);
      _accept(page.comments, likeRevision: likeRevision);
      final items = {for (final c in state.thread(parentId).comments) c.id: c};
      for (final c in page.comments) {
        items[c.id] = c;
      }
      _thread(
        parentId,
        CommentThreadState(
          status: CommentsStatus.loaded,
          comments: items.values.toList(),
          nextCursor: progress.nextCursor,
          prevCursor: progress.prevCursor,
          hasMore: progress.hasMore,
          error: previous.error,
        ),
      );
    } catch (e) {
      if (isClosed || _generations[parentId] != generation) return;
      _thread(
        parentId,
        CommentThreadState(
          status: CommentsStatus.loaded,
          comments: state.thread(parentId).comments,
          nextCursor: previous.nextCursor,
          prevCursor: previous.prevCursor,
          hasMore: previous.hasMore,
          error: previous.error,
          paginationError: _error(e),
        ),
      );
    } finally {
      if (_generations[parentId] == generation) _more.remove(parentId);
    }
  }

  void _accept(List<CommentModel> comments, {required int likeRevision}) {
    _acceptLikes(comments, likeRevision);
    _emit(
      known: {
        ...state.known,
        for (final comment in comments) comment.id: comment,
      },
    );
  }

  // Remembering a widget snapshot is not an authoritative network read.
  void remember(CommentModel comment) => _emit(
    known: {...state.known, comment.id: state.known[comment.id] ?? comment},
  );

  void _patch(
    CommentModel comment, {
    bool insert = false,
    required int likeRevision,
  }) {
    _acceptLikes([comment], likeRevision);
    final threads = {...state.threads};
    for (final entry in threads.entries.toList()) {
      final list = entry.value.comments
          .map((c) => c.id == comment.id ? comment : c)
          .toList();
      if (insert &&
          entry.key == comment.parentId &&
          !list.any((c) => c.id == comment.id)) {
        list.insert(0, comment);
      }
      threads[entry.key] = entry.value.copyWith(comments: list);
    }
    _emit(threads: threads, known: {...state.known, comment.id: comment});
  }

  Future<CommentMutationResult> create(String content, {int? parentId}) {
    final request = CommentTextRequest(content, parentId: parentId);
    if (request.validationError != null) {
      return Future.value(
        CommentMutationResult(
          error: ApiError(message: request.validationError!),
        ),
      );
    }
    if (parentId != null && state.deleted.containsKey(parentId)) {
      return Future.value(
        CommentMutationResult(
          error: ApiError(message: 'This comment was deleted.'),
        ),
      );
    }
    return _mutate(
      () => _repo.create(postId, request),
      (comment, revision) =>
          _patch(comment!, insert: true, likeRevision: revision),
    );
  }

  Future<CommentMutationResult> edit(CommentModel comment, String content) {
    if (isLikePending(comment.id)) {
      return Future.value(
        CommentMutationResult(
          error: ApiError(message: 'Wait for the like update to finish.'),
        ),
      );
    }
    final current = state.known[comment.id] ?? comment;
    final request = CommentTextRequest(content);
    if (!current.permissions.canEdit || request.validationError != null) {
      return Future.value(
        CommentMutationResult(
          error: ApiError(
            message: request.validationError ?? 'You cannot edit this comment.',
          ),
        ),
      );
    }
    return _mutate(
      () => _repo.edit(postId, comment.id, request),
      (value, revision) => _patch(value!, likeRevision: revision),
      changesCount: false,
    );
  }

  Future<CommentMutationResult> delete(CommentModel comment) {
    if (isLikePending(comment.id)) {
      return Future.value(
        CommentMutationResult(
          error: ApiError(message: 'Wait for the like update to finish.'),
        ),
      );
    }
    final current = state.known[comment.id] ?? comment;
    if (!current.permissions.canDelete) {
      return Future.value(
        CommentMutationResult(
          error: ApiError(message: 'You cannot delete this comment.'),
        ),
      );
    }
    return _mutate(
      () async {
        await _repo.delete(postId, comment.id);
        return null;
      },
      (_, _) {
        _likes.reset(_likeTarget(comment.id));
        final threads = {
          for (final e in state.threads.entries)
            e.key: e.value.copyWith(
              comments: e.value.comments
                  .where((c) => c.id != comment.id)
                  .toList(),
            ),
        };
        _emit(
          threads: threads,
          deleted: {...state.deleted, comment.id: current},
        );
      },
      deleted: current,
    );
  }

  Future<CommentMutationResult> restore(int id) {
    if (!state.deleted.containsKey(id)) {
      return Future.value(const CommentMutationResult());
    }
    return _mutate(() => _repo.restore(postId, id), (comment, revision) {
      final deleted = {...state.deleted}..remove(id);
      _emit(deleted: deleted);
      _patch(comment!, likeRevision: revision);
    });
  }

  Future<CommentMutationResult> _mutate(
    Future<CommentModel?> Function() operation,
    void Function(CommentModel?, int likeRevision) apply, {
    bool changesCount = true,
    CommentModel? deleted,
  }) async {
    if (isClosed || state.busy) return const CommentMutationResult();
    _emit(busy: true);
    final likeRevision = _likes.revision;
    final session = _session.sessionRevision;
    CommentModel? value;
    try {
      value = await operation();
      if (session != _session.sessionRevision) {
        return const CommentMutationResult();
      }
    } catch (e) {
      if (session != _session.sessionRevision) {
        return const CommentMutationResult();
      }
      _emit(busy: false);
      return CommentMutationResult(error: _error(e));
    }
    // Invalidate a metadata retry that began before this confirmed write.
    _syncGeneration++;
    _syncRequest = null;
    _emit(syncing: false);
    if (!isClosed) {
      apply(value, likeRevision);
      // Mutations can change cursor membership or cascade to reply threads.
      // Supersede every active read before revalidating the loaded threads.
      final reloads = [
        for (final key in state.threads.keys.toList())
          load(parentId: key, force: true),
      ];
      if (changesCount) await synchronize(force: true);
      await Future.wait(reloads);
    } else if (changesCount) {
      // The write may finish after navigation; the still-mounted feed receives
      // its authoritative count without emitting to a disposed CommentsCubit.
      await synchronize(force: true);
    }
    _emit(busy: false);
    return CommentMutationResult(confirmed: true, comment: value ?? deleted);
  }

  Future<void> synchronize({bool force = false}) {
    if (!force && _syncRequest != null) return _syncRequest!;
    if (!force && (isClosed || state.busy)) return Future.value();
    final generation = ++_syncGeneration;
    final future = _synchronize(generation).whenComplete(() {
      if (generation == _syncGeneration) _syncRequest = null;
    });
    _syncRequest = future;
    return future;
  }

  Future<void> _synchronize(int generation) async {
    _emit(syncing: true, clearSyncError: true);
    ApiError? failure;
    final session = _session.sessionRevision;
    try {
      final count = await _repo.commentCount(postId);
      if (generation != _syncGeneration ||
          session != _session.sessionRevision) {
        return;
      }
      onCountChanged?.call(count);
      _emit(count: count);
    } catch (e) {
      failure = _error(e);
    }
    if (!isClosed && generation == _syncGeneration) {
      for (final parentId in state.threads.keys.whereType<int>().toList()) {
        if (state.deleted.containsKey(parentId)) continue;
        try {
          final likeRevision = _likes.revision;
          final parent = await _repo.get(postId, parentId);
          if (isClosed || generation != _syncGeneration) return;
          _patch(parent, likeRevision: likeRevision);
        } catch (e) {
          failure ??= _error(e);
        }
      }
    }
    if (generation != _syncGeneration || session != _session.sessionRevision) {
      return;
    }
    _emit(syncing: false, syncError: failure, clearSyncError: failure == null);
    if (failure != null && isClosed) onSyncError?.call(failure);
  }

  ApiError _error(Object error) => error is ApiError
      ? error
      : ApiError(message: 'Unable to load comments. Please try again.');

  @override
  Future<void> close() async {
    _session.removeListener(_sessionChanged);
    await _likesSubscription.cancel();
    if (_ownsLikes) await _likes.close();
    return super.close();
  }
}
