import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/features/profile/cubit/current_user_cubit.dart';

final _userIdDigits = RegExp(r'^[0-9]+$');

/// Canonical positive user id ("007" and 7 both become "7"), or null.
String? normalizeUserId(Object? value) {
  if (value is! int && value is! String) return null;
  final text = value.toString().trim();
  if (!_userIdDigits.hasMatch(text)) return null;
  final id = BigInt.tryParse(text);
  return id != null && id > BigInt.zero ? id.toString() : null;
}

/// The signed-in user's id. Prefers the app-level [CurrentUserCubit], which
/// clears synchronously on account changes; otherwise uses [fallbackId] only
/// if it was loaded in the current session ([fallbackSession]).
String? viewerUserId(
  BuildContext context, {
  Object? fallbackId,
  int? fallbackSession,
}) {
  final session = PreferencesManager();
  final current = context.read<CurrentUserCubit?>();
  if (current != null && !session.hasSession) return null;
  final shared = normalizeUserId(current?.state.profile?.id);
  if (shared != null) return shared;
  return fallbackSession == session.sessionRevision
      ? normalizeUserId(fallbackId)
      : null;
}

/// True only when both ids are known and equal; unknown identity is never
/// treated as ownership.
bool isViewer(
  BuildContext context,
  Object? userId, {
  Object? fallbackId,
  int? fallbackSession,
}) {
  final author = normalizeUserId(userId);
  final viewer = viewerUserId(
    context,
    fallbackId: fallbackId,
    fallbackSession: fallbackSession,
  );
  return author != null && viewer != null && author == viewer;
}
