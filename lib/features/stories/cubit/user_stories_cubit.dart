import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/features/block/cubit/block_cubit.dart';
import 'package:travibe/features/stories/data/stories_repo.dart';
import 'package:travibe/features/stories/data/story_model.dart';

/// One user's active Stories for their profile ring
/// (`GET /users/{user}/stories`), oldest → newest. Null means no ring: none
/// visible, a block, `403`/`404` or any error (shown as no ring, no message).
/// The scope ([userId]) is immutable; create a new instance per profile.
class UserStoriesCubit extends Cubit<StoryGroup?> {
  UserStoriesCubit({
    required this.userId,
    StoriesRepo? repo,
    PreferencesManager? session,
    this.blocks,
    DateTime Function()? now,
  }) : repo = repo ?? StoriesRepo(),
       session = session ?? PreferencesManager(),
       _now = now ?? DateTime.now,
       super(null) {
    this.session.addListener(_sessionChanged);
    _blockSubscription = blocks?.stream.listen((_) {
      if (_isBlocked) clear();
    });
  }

  final int userId;
  final StoriesRepo repo;
  final PreferencesManager session;
  final BlockCubit? blocks;
  final DateTime Function() _now;
  StreamSubscription<BlockState>? _blockSubscription;
  Timer? _expiry;
  int _generation = 0;

  bool get _isBlocked =>
      blocks?.state.blockedIds.contains(userId.toString()) == true;

  /// Loads [author]'s Stories; a newer call or a session change wins.
  Future<void> load(StoryAuthor author) async {
    if (isClosed) return;
    assert(author.id == userId, 'UserStoriesCubit scope is immutable');
    final generation = ++_generation;
    final revision = session.sessionRevision;
    if (!session.hasSession || _isBlocked || author.id != userId) {
      emit(null);
      return;
    }
    bool current() =>
        !isClosed &&
        generation == _generation &&
        revision == session.sessionRevision &&
        session.hasSession &&
        !_isBlocked;
    StoryGroup? group;
    try {
      group = await repo.getUserStories(author);
    } catch (_) {
      group = null;
    }
    if (current()) emit(group);
  }

  /// Drops the ring and any request in flight.
  void clear() {
    ++_generation;
    if (!isClosed) emit(null);
  }

  void _sessionChanged() => clear();

  @override
  void onChange(Change<StoryGroup?> change) {
    super.onChange(change);
    _scheduleExpiry(change.nextState);
  }

  /// Drops each Story when it expires, so the ring updates without a refetch.
  void _scheduleExpiry(StoryGroup? group) {
    _expiry?.cancel();
    _expiry = null;
    if (group == null || isClosed) return;
    final now = _now();
    final next = group.stories
        .map((s) => s.expiresAt)
        .whereType<DateTime>()
        .fold<DateTime?>(
          null,
          (earliest, at) =>
              earliest == null || at.isBefore(earliest) ? at : earliest,
        );
    if (next == null) return;
    final delay = next.difference(now);
    _expiry = Timer(
      delay.isNegative
          ? Duration.zero
          : delay + const Duration(milliseconds: 1),
      () {
        final current = state;
        if (isClosed || current == null) return;
        final live = current.withoutExpired(_now());
        if (identical(live, current)) return _scheduleExpiry(current);
        emit(live.stories.isEmpty ? null : live);
      },
    );
  }

  @override
  Future<void> close() {
    ++_generation;
    _expiry?.cancel();
    session.removeListener(_sessionChanged);
    unawaited(_blockSubscription?.cancel());
    return super.close();
  }
}
