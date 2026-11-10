import 'dart:math' as math;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/features/likes/data/like_model.dart';
import 'package:travibe/features/likes/data/likes_repo.dart';

class LikesState {
  LikesState(Map<LikeTarget, LikeValue> values)
    : values = Map.unmodifiable(values);
  final Map<LikeTarget, LikeValue> values;
}

/// Owned by the Home session and shared by both feeds and all comment sheets.
class LikesCubit extends Cubit<LikesState> {
  LikesCubit({LikesRepo? repo})
    : _repo = repo ?? LikesRepo(),
      super(LikesState({}));
  final LikesRepo _repo;
  final Map<LikeTarget, int> _versions = {};
  int _revision = 0;
  int get revision => _revision;

  LikeValue? value(LikeTarget target) => state.values[target];

  /// A read begun before a mutation must not undo optimism, confirmation or rollback.
  void accept(
    Map<LikeTarget, LikeValue> snapshots, {
    required int requestRevision,
  }) {
    if (isClosed) return;
    final values = {...state.values};
    var changed = false;
    for (final entry in snapshots.entries) {
      final current = values[entry.key];
      if ((_versions[entry.key] ?? 0) > requestRevision ||
          current?.pending == true) {
        continue;
      }
      if (current?.isLiked == entry.value.isLiked &&
          current?.count == entry.value.count) {
        continue;
      }
      values[entry.key] = entry.value;
      changed = true;
    }
    if (changed) emit(LikesState(values));
  }

  void reset(LikeTarget target) {
    if (isClosed) return;
    _versions[target] = ++_revision;
    emit(
      LikesState({
        ...state.values,
        target: const LikeValue(isLiked: false, count: 0),
      }),
    );
  }

  Future<ApiError?> toggle(LikeTarget target, {LikeValue? initial}) async {
    if (isClosed || value(target)?.pending == true) return null;
    final previous = value(target) ?? initial;
    if (previous == null || previous.count < 0) {
      return ApiError(message: 'Like status is unavailable. Please refresh.');
    }
    final liked = !previous.isLiked;
    final count = math.max(0, previous.count + (liked ? 1 : -1));
    final version = ++_revision;
    _versions[target] = version;
    emit(
      LikesState({
        ...state.values,
        target: LikeValue(isLiked: liked, count: count, pending: true),
      }),
    );
    var confirmed = false;
    try {
      final result = await _repo.setLiked(target, liked);
      confirmed = true;
      final authoritative = result ?? await _repo.getState(target);
      if (!isClosed && _versions[target] == version) {
        _versions[target] = ++_revision;
        emit(LikesState({...state.values, target: authoritative}));
      }
      return null;
    } catch (error) {
      if (!isClosed && _versions[target] == version) {
        _versions[target] = ++_revision;
        emit(
          LikesState({
            ...state.values,
            target: confirmed
                ? LikeValue(isLiked: liked, count: count)
                : previous,
          }),
        );
      }
      final failure = error is ApiError
          ? error
          : ApiError(message: 'Unable to update like. Please try again.');
      return confirmed
          ? ApiError(
              message: 'Like updated. ${failure.message}',
              statusCode: failure.statusCode,
            )
          : failure;
    }
  }
}
