import 'dart:math' as math;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/features/shares/data/share_model.dart';
import 'package:travibe/features/shares/data/shares_repo.dart';

part 'shares_state.dart';

/// Session state shared by both feeds. Counts and personal ownership are separate.
class SharesCubit extends Cubit<SharesState> {
  SharesCubit({SharesRepo? repo, this.currentUserId})
    : _repo = repo ?? SharesRepo(),
      super(SharesState({}));
  final SharesRepo _repo;
  final Future<int> Function()? currentUserId;
  final Map<int, int> _versions = {};
  final Map<int, Future<void>> _loads = {};
  Future<int>? _identity;
  int? _userId;
  int _revision = 0;
  int get revision => _revision;
  PostShareState post(int id) => state.post(id);
  void _put(int id, PostShareState value) {
    if (!isClosed) emit(SharesState({...state.posts, id: value}));
  }

  Future<int> _viewer() => _identity ??= _loadViewer();
  Future<int> _loadViewer() async {
    try {
      final id = await (currentUserId?.call() ?? _repo.currentUserId());
      if (id < 1) throw ApiError(message: 'Unable to verify your account.');
      return _userId = id;
    } catch (_) {
      _identity = null;
      rethrow;
    }
  }

  void acceptCounts(Map<int, int> counts, {required int requestRevision}) {
    if (isClosed) return;
    final values = {...state.posts};
    var changed = false;
    for (final entry in counts.entries) {
      final current = post(entry.key);
      if (entry.value < 0 ||
          current.pending ||
          (_versions[entry.key] ?? 0) > requestRevision ||
          (current.count == entry.value && current.syncError == null)) {
        continue;
      }
      values[entry.key] = current.copyWith(
        count: entry.value,
        clearSyncError: true,
      );
      changed = true;
    }
    if (changed) emit(SharesState(values));
  }

  /// Exhaust pagination before concluding that this viewer has not shared.
  Future<void> inspect(int postId, {bool force = false}) {
    if (isClosed ||
        post(postId).pending ||
        (!force && post(postId).ownershipKnown)) {
      return Future.value();
    }
    return _loads[postId] ??= _inspect(postId, force: force).whenComplete(() {
      _loads.remove(postId);
    });
  }

  Future<void> _inspect(int postId, {required bool force}) async {
    final version = _versions[postId] ?? 0;
    final refreshCount =
        force ||
        post(postId).count == null ||
        post(postId).error != null ||
        post(postId).syncError != null;
    _put(postId, post(postId).copyWith(loading: true, clearError: true));
    try {
      final viewer = await _viewer();
      ShareModel? own;
      var page = 1;
      while (true) {
        final result = await _repo.list(postId, page: page);
        if (isClosed || (_versions[postId] ?? 0) != version) return;
        for (final share in result.shares) {
          if (share.userId == viewer) {
            own = share;
            break;
          }
        }
        if (own != null || !result.hasMore) break;
        page = result.currentPage + 1;
      }
      // List total includes external records; only PostResource is a count source.
      final count = refreshCount
          ? await _repo.count(postId)
          : post(postId).count;
      if (isClosed || (_versions[postId] ?? 0) != version) return;
      _put(
        postId,
        post(postId).copyWith(
          count: count,
          ownShare: own,
          clearOwn: own == null,
          ownershipKnown: true,
          loading: false,
          clearError: true,
          clearSyncError: true,
        ),
      );
    } catch (error) {
      if (!isClosed && (_versions[postId] ?? 0) == version) {
        _put(
          postId,
          post(postId).copyWith(
            loading: false,
            ownershipKnown: false,
            error: _error(error),
          ),
        );
      }
    }
  }

  bool canDelete(int postId) {
    final share = post(postId).ownShare;
    return post(postId).ownershipKnown &&
        share != null &&
        share.postId == postId &&
        share.userId == _userId &&
        share.id > 0;
  }

  Future<ShareOutcome> create(int postId, CreateShareRequest request) =>
      _change(postId, request: request);
  Future<ShareOutcome> delete(int postId) => _change(postId, remove: true);

  Future<ShareOutcome> _change(
    int postId, {
    CreateShareRequest? request,
    bool remove = false,
  }) async {
    final previous = post(postId);
    if (isClosed || previous.pending || previous.loading) {
      return const ShareOutcome();
    }
    if (!previous.ownershipKnown || (remove && !canDelete(postId))) {
      return ShareOutcome(
        error: ApiError(message: 'Check your share status before continuing.'),
      );
    }
    if (!remove && previous.ownShare != null) {
      return ShareOutcome(
        error: ApiError(message: 'You have already shared this post.'),
      );
    }
    if (!remove && request!.validationError != null) {
      final error = ApiError(message: request.validationError!);
      _put(postId, previous.copyWith(error: error));
      return ShareOutcome(error: error);
    }
    _versions[postId] = ++_revision;
    _put(
      postId,
      previous.copyWith(pending: true, clearError: true, clearSyncError: true),
    );
    ShareModel? share;
    try {
      if (remove) {
        await _repo.delete(postId, previous.ownShare!.id);
      } else {
        share = await _repo.create(postId, request!);
        if (share.userId != _userId || share.postId != postId || share.id < 1) {
          throw ApiError(
            message: 'Unable to verify your share. Please check its status.',
          );
        }
      }
    } catch (error) {
      _versions[postId] = ++_revision;
      final failure = _error(error);
      // A timeout, duplicate 422 or malformed success may hide a committed write.
      // Recheck ownership before retrying; never fabricate an ID or decrement on 404.
      _put(postId, previous.copyWith(ownershipKnown: false, error: failure));
      return ShareOutcome(error: failure);
    }
    if (isClosed) return ShareOutcome(confirmed: true, removed: remove);
    _versions[postId] = ++_revision;
    final internal =
        (remove ? previous.ownShare : share)!.platform ==
        SharePlatform.internal;
    final count = previous.count == null
        ? null
        : math.max(0, previous.count! + (internal ? (remove ? -1 : 1) : 0));
    _put(
      postId,
      previous.copyWith(
        count: count,
        ownShare: share,
        clearOwn: remove,
        ownershipKnown: true,
        pending: true,
        clearError: true,
        clearSyncError: true,
      ),
    );
    ApiError? syncError;
    try {
      final authoritative = await _repo.count(postId);
      _put(postId, post(postId).copyWith(count: authoritative));
    } catch (error) {
      syncError = _error(error);
    }
    _versions[postId] = ++_revision;
    _put(
      postId,
      post(postId).copyWith(
        pending: false,
        syncError: syncError,
        clearSyncError: syncError == null,
      ),
    );
    return ShareOutcome(confirmed: true, removed: remove, error: syncError);
  }

  /// Retry count synchronization without repeating a confirmed POST or DELETE.
  Future<void> refreshCount(int postId) {
    if (isClosed || post(postId).pending) return Future.value();
    return _loads[postId] ??= _refreshCount(postId).whenComplete(() {
      _loads.remove(postId);
    });
  }

  Future<void> _refreshCount(int postId) async {
    _versions[postId] = ++_revision;
    _put(postId, post(postId).copyWith(loading: true));
    try {
      final count = await _repo.count(postId);
      _put(postId, post(postId).copyWith(count: count, clearSyncError: true));
    } catch (error) {
      _put(postId, post(postId).copyWith(syncError: _error(error)));
    }
    _versions[postId] = ++_revision;
    _put(postId, post(postId).copyWith(loading: false));
  }

  ApiError _error(Object error) => error is ApiError
      ? error
      : ApiError(message: 'Unable to update share. Please try again.');
}
