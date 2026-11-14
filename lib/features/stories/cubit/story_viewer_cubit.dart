import 'dart:async';
import 'package:travibe/features/stories/cubit/story_likes_cubit.dart';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/features/block/cubit/block_cubit.dart';
import 'package:travibe/features/stories/data/story_editor_draft.dart';
import 'package:travibe/features/stories/data/story_elements.dart';
import 'package:travibe/features/stories/data/story_model.dart';
import 'package:travibe/features/stories/data/stories_repo.dart';

enum StoryViewerStatus { loading, ready, failure, finished }

class StoryViewerState {
  const StoryViewerState({
    this.status = StoryViewerStatus.loading,
    this.detail,
    this.layers = const [],
    this.index = 0,
    this.count = 0,
    this.progress = 0,
    this.paused = false,
    this.imageReady = false,
    this.error,
    this.request = 0,
    this.viewsCount,
  });
  final StoryViewerStatus status;
  final StoryDetail? detail;
  final List<StoryEditorLayer> layers;
  final int index, count, request;

  /// Latest view count, already excluding the owner's own view.
  final int? viewsCount;

  /// What the owner sees: never includes their own view.
  int? get visibleViewsCount => viewsCount ?? detail?.viewsCountExcludingOwner;
  final double progress;
  final bool paused, imageReady;
  final ApiError? error;
  StoryViewerState playback({
    int? viewsCount,
    double? progress,
    bool? paused,
    bool? imageReady,
  }) => StoryViewerState(
    viewsCount: viewsCount ?? this.viewsCount,
    status: status,
    detail: detail,
    layers: layers,
    index: index,
    count: count,
    request: request,
    error: error,
    progress: progress ?? this.progress,
    paused: paused ?? this.paused,
    imageReady: imageReady ?? this.imageReady,
  );
}

/// Playback of the loaded author order with confirmed, session-scoped writes.
class StoryViewerCubit extends Cubit<StoryViewerState> {
  StoryViewerCubit({
    required List<StoryGroup> groups,
    required int initialAuthorId,
    StoriesRepo? repo,
    PreferencesManager? session,
    this.blocks,
    this.currentUserId,
    this.onViewed,
    this.onDeleted,
    this.likes,
    this.duration = const Duration(seconds: 5),
    DateTime Function()? now,
  }) : repo = repo ?? StoriesRepo(),
       session = session ?? PreferencesManager(),
       _now = now ?? DateTime.now,
       super(const StoryViewerState()) {
    if (duration <= Duration.zero) {
      throw ArgumentError.value(duration, 'duration');
    }
    final seenAuthors = <int>{};
    _groups = [
      for (final group in groups)
        if (seenAuthors.add(group.user.id))
          (
            author: group.user,
            stories: List<StorySummary>.unmodifiable(
              group.stories.where((story) => !_expired(story)),
            ),
          ),
    ];
    _group = _groups.indexWhere((g) => g.author.id == initialAuthorId);
    if (_validGroup) {
      final unseen = _groups[_group].stories.indexWhere(
        (story) => !story.hasSeen,
      );
      _story = unseen < 0 ? 0 : unseen;
    }
    _sessionRevision = this.session.sessionRevision;
    this.session.addListener(_sessionChanged);
    _blockSubscription = blocks?.stream.listen((_) {
      if (!isClosed &&
          state.status != StoryViewerStatus.finished &&
          _validGroup &&
          _blocked(_group)) {
        unawaited(_nextAuthor());
      }
    });
  }
  final StoryLikesCubit? likes;
  final int? currentUserId;
  final void Function(int id, int count)? onViewed;
  final void Function(int id)? onDeleted;
  bool get ownsCurrent =>
      _active &&
      state.detail?.isMine == true &&
      currentUserId != null &&
      state.detail!.userId == currentUserId;
  bool deleting = false;
  final _viewed = <int>{};
  final _viewPending = <int>{};
  Future<void> _recordView() async {
    final detail = state.detail;
    if (!_active ||
        detail == null ||
        _viewed.contains(detail.id) ||
        !_viewPending.add(detail.id)) {
      return;
    }
    final request = _generation;
    bool sameSession() =>
        session.hasSession && session.sessionRevision == _sessionRevision;
    try {
      await repo.recordView(detail.id);
      if (!sameSession()) return;
      _viewed.add(detail.id);
      // Confirmed success establishes seen state. Retain the last verified count;
      // no response fields or increment are inferred from the POST body.
      onViewed?.call(detail.id, detail.viewsCountExcludingOwner);
      if (!_active) return;
      final likeRevision = likes?.revision;
      final fresh = await repo.getStory(detail.id);
      if (!_active || request != _generation) return;
      if (fresh.id != detail.id || fresh.userId != detail.userId) {
        throw ApiError(
          message: 'The Story response did not match this author.',
        );
      }
      if (fresh.expiresAt?.isAfter(_now()) == false) {
        throw ApiError(message: 'This Story has expired.', statusCode: 404);
      }
      if (likeRevision != null) {
        likes?.accept(fresh, requestRevision: likeRevision);
      }
      onViewed?.call(detail.id, fresh.viewsCountExcludingOwner);
      if (_active &&
          request == _generation &&
          state.status == StoryViewerStatus.ready) {
        emit(state.playback(viewsCount: fresh.viewsCountExcludingOwner));
      }
    } catch (error) {
      if (_active &&
          request == _generation &&
          error is ApiError &&
          [401, 403, 404].contains(error.statusCode)) {
        _timer?.cancel();
        emit(
          StoryViewerState(
            status: StoryViewerStatus.failure,
            index: state.index,
            count: state.count,
            request: request,
            error: ApiError(
              statusCode: error.statusCode,
              message: switch (error.statusCode) {
                401 => 'Your session has expired. Please sign in again.',
                403 => 'You do not have access to this Story.',
                _ => 'This Story has expired or is no longer available.',
              },
            ),
          ),
        );
      }
      // Tracking/network failures never crash playback or manufacture a count.
      // Once POST succeeds, a failed detail refresh cannot cause a duplicate POST.
    } finally {
      _viewPending.remove(detail.id);
    }
  }

  final _uncertainDeletes = <int>{};
  Future<ApiError?> deleteCurrent() async {
    if (!ownsCurrent || deleting) return null;
    deleting = true;
    pause(true, reason: 'deleting');
    final id = state.detail!.id;
    final request = _generation;
    try {
      var alreadyAbsent = false;
      if (_uncertainDeletes.contains(id)) {
        try {
          await repo.getStory(id);
        } on ApiError catch (error) {
          if (error.statusCode == 404) {
            alreadyAbsent = true;
          } else {
            rethrow;
          }
        }
        if (!_active || request != _generation) return null;
      }
      if (!alreadyAbsent) await repo.deleteStory(id);
      _uncertainDeletes.remove(id);
      if (session.hasSession && session.sessionRevision == _sessionRevision) {
        onDeleted?.call(id);
      }
      if (!_active || request != _generation) return null;
      final group = _groups[_group];
      _groups[_group] = (
        author: group.author,
        stories: group.stories.where((s) => s.id != id).toList(),
      );
      await _load();
      return null;
    } catch (error) {
      if (!_active || request != _generation) return null;
      if (error is! ApiError ||
          error.statusCode == null ||
          (error.statusCode ?? 0) >= 500) {
        _uncertainDeletes.add(id);
        return ApiError(
          message:
              'Deletion could not be confirmed. Retry will check whether this story still exists first.',
        );
      }
      return error;
    } finally {
      deleting = false;
      pause(false, reason: 'deleting');
    }
  }

  final StoriesRepo repo;
  final PreferencesManager session;
  final BlockCubit? blocks;
  final Duration duration;
  final DateTime Function() _now;
  late final List<({StoryAuthor author, List<StorySummary> stories})> _groups;
  late final int _sessionRevision;
  StreamSubscription<BlockState>? _blockSubscription;
  int _group = -1, _story = 0, _generation = 0;
  Timer? _timer;
  final _pauses = <String>{};
  Duration _elapsed = Duration.zero;
  bool get _validGroup => _group >= 0 && _group < _groups.length;
  bool _blocked(int group) =>
      blocks?.state.blockedIds.contains(_groups[group].author.id.toString()) ==
      true;
  bool _expired(StorySummary story) =>
      story.expiresAt != null && !story.expiresAt!.isAfter(_now());
  bool get _active =>
      !isClosed &&
      session.hasSession &&
      session.sessionRevision == _sessionRevision;

  void _sessionChanged() {
    if (session.sessionRevision != _sessionRevision && !isClosed) finish();
  }

  Future<void> start() => _load();
  Future<void> retry() =>
      state.status == StoryViewerStatus.failure ? _load() : Future.value();

  Future<void> _load() async {
    _timer?.cancel();
    final request = ++_generation;
    _elapsed = Duration.zero;
    // Skip only known-expired or blocked entries. Missing summary expiry still
    // goes through the authoritative detail endpoint.
    while (_validGroup &&
        (_blocked(_group) ||
            _story >= _groups[_group].stories.length ||
            _expired(_groups[_group].stories[_story]))) {
      if (!_blocked(_group) && _story < _groups[_group].stories.length) {
        _story++;
      } else {
        _group++;
        _story = 0;
      }
    }
    if (!_active || !_validGroup) {
      finish();
      return;
    }
    final summary = _groups[_group].stories[_story];
    emit(
      StoryViewerState(
        index: _story,
        count: _groups[_group].stories.length,
        request: request,
        paused: _pauses.isNotEmpty,
      ),
    );
    try {
      final likeRevision = likes?.revision;
      final detail = await repo.getStory(summary.id);
      if (!_active || request != _generation) return;
      if (_blocked(_group)) {
        await _nextAuthor();
        return;
      }
      if (detail.id != summary.id ||
          detail.userId != _groups[_group].author.id) {
        throw ApiError(
          message: 'The Story response did not match this author.',
        );
      }
      if (detail.expiresAt != null && !detail.expiresAt!.isAfter(_now())) {
        throw ApiError(message: 'This Story has expired.', statusCode: 404);
      }
      final url = detail.media.url;
      final uri = url == null ? null : Uri.tryParse(url);
      if (uri == null ||
          !['https', 'http'].contains(uri.scheme) ||
          uri.host.isEmpty ||
          uri.userInfo.isNotEmpty) {
        throw ApiError(message: 'This Story has no available photo.');
      }
      if (likeRevision != null) {
        likes?.accept(detail, requestRevision: likeRevision);
      }
      List<StoryEditorLayer> layers;
      try {
        layers = StoryElements.decode(detail.elements);
      } on FormatException {
        throw ApiError(
          message: 'This Story contains an unsupported text document.',
        );
      }
      emit(
        StoryViewerState(
          status: StoryViewerStatus.ready,
          detail: detail,
          layers: layers,
          index: _story,
          count: _groups[_group].stories.length,
          request: request,
          paused: _pauses.isNotEmpty,
        ),
      );
      // The photo widget must acknowledge a decoded frame before timing starts.
    } catch (error) {
      if (!_active || request != _generation) return;
      final api = error is ApiError
          ? error
          : ApiError(message: 'Unable to load this Story. Please retry.');
      final message = switch (api.statusCode) {
        403 => 'You do not have access to this Story.',
        404 => 'This Story has expired or is no longer available.',
        _ => api.message,
      };
      emit(
        StoryViewerState(
          status: StoryViewerStatus.failure,
          index: _story,
          count: _groups[_group].stories.length,
          request: request,
          error: ApiError(message: message, statusCode: api.statusCode),
        ),
      );
    }
  }

  void imageDisplayed(int request) {
    if (!_active ||
        request != _generation ||
        state.status != StoryViewerStatus.ready ||
        state.imageReady) {
      return;
    }
    emit(state.playback(imageReady: true));
    _runTimer();
  }

  void imageFailed(int request) {
    if (!_active ||
        request != _generation ||
        state.status != StoryViewerStatus.ready) {
      return;
    }
    _timer?.cancel();
    emit(
      StoryViewerState(
        status: StoryViewerStatus.failure,
        index: _story,
        count: state.count,
        request: request,
        error: ApiError(
          message: 'Unable to display this Story photo. Please retry.',
        ),
      ),
    );
  }

  void pause(bool paused, {String reason = 'press'}) {
    if (isClosed || state.status == StoryViewerStatus.finished) return;
    if (paused) {
      _pauses.add(reason);
    } else {
      _pauses.remove(reason);
    }
    emit(state.playback(paused: _pauses.isNotEmpty));
    _timer?.cancel();
    _runTimer();
  }

  void _runTimer() {
    _timer?.cancel();
    if (!_active ||
        state.status != StoryViewerStatus.ready ||
        !state.imageReady ||
        _pauses.isNotEmpty) {
      return;
    }
    if (state.detail?.expiresAt?.isAfter(_now()) == false) {
      unawaited(next());
      return;
    }
    unawaited(_recordView());
    final request = _generation;
    const tick = Duration(milliseconds: 50);
    _timer = Timer.periodic(tick, (_) {
      if (!_active || request != _generation) {
        _timer?.cancel();
        return;
      }
      if (state.detail?.expiresAt?.isAfter(_now()) == false) {
        unawaited(next());
        return;
      }
      _elapsed += tick;
      if (_elapsed >= duration) {
        unawaited(next());
      } else {
        emit(
          state.playback(
            progress: _elapsed.inMicroseconds / duration.inMicroseconds,
          ),
        );
      }
    });
  }

  Future<void> next() {
    if (deleting || isClosed || state.status == StoryViewerStatus.finished) {
      return Future.value();
    }
    _story++;
    return _load();
  }

  Future<void> _nextAuthor() {
    _group++;
    _story = 0;
    return _load();
  }

  Future<void> previous() {
    if (deleting || isClosed || state.status == StoryViewerStatus.finished) {
      return Future.value();
    }
    final originalGroup = _group;
    final originalStory = _story;
    var group = _group;
    var story = _story - 1;
    while (group >= 0) {
      if (story < 0 || _blocked(group)) {
        group--;
        if (group >= 0) {
          story = _groups[group].stories.length - 1;
        }
        continue;
      }
      if (!_expired(_groups[group].stories[story])) {
        _group = group;
        _story = story;
        return _load();
      }
      story--;
    }
    _group = originalGroup;
    _story = originalStory;
    return _load();
  }

  void finish() {
    _timer?.cancel();
    ++_generation;
    if (!isClosed) {
      emit(const StoryViewerState(status: StoryViewerStatus.finished));
    }
  }

  @override
  Future<void> close() {
    _timer?.cancel();
    ++_generation;
    session.removeListener(_sessionChanged);
    unawaited(_blockSubscription?.cancel());
    return super.close();
  }
}
