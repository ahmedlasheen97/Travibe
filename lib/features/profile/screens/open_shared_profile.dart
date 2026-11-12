import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/features/block/cubit/block_cubit.dart';
import 'package:travibe/features/home/data/posts_repo.dart';
import 'package:travibe/features/profile/cubit/current_user_cubit.dart';
import 'package:travibe/features/profile/data/profile_model.dart';
import 'package:travibe/features/profile/data/profile_repo.dart';
import 'package:travibe/features/profile/screens/profile_screen.dart';

const sharedProfileUnavailable = 'This profile is unavailable.';

/// Opens a profile from a `travibe://users/{id}` link. The signed-in user's
/// own id opens the Profile tab via [showMyProfile]. `GET users/{id}` with
/// `data: null` (blocked), 404 or any other failure shows
/// [sharedProfileUnavailable].
Future<void> openSharedProfile(
  BuildContext context,
  int id, {
  VoidCallback? showMyProfile,
  ProfileRepo? profileRepo,
  PostsRepo? postsRepo,
}) async {
  final preferences = PreferencesManager();
  if (!preferences.hasSession || id < 1) return;
  final session = preferences.sessionRevision;
  final messenger = ScaffoldMessenger.maybeOf(context);
  void unavailable() => messenger?.showSnackBar(
    const SnackBar(content: Text(sharedProfileUnavailable)),
  );
  Future<void> openMine() async {
    if (showMyProfile != null) return showMyProfile();
    await ProfileScreen.open(
      context,
      profileRepo: profileRepo,
      postsRepo: postsRepo,
    );
  }

  if (context.read<CurrentUserCubit?>()?.state.profile?.id == '$id') {
    return openMine();
  }
  ProfileModel? profile;
  try {
    profile = await (profileRepo ?? ProfileRepo()).getPublicProfile(id);
  } catch (_) {
    if (session == preferences.sessionRevision) unavailable();
    return;
  }
  if (!context.mounted ||
      !preferences.hasSession ||
      session != preferences.sessionRevision) {
    return;
  }
  if (profile == null ||
      profile.isBlocked == true ||
      context.read<BlockCubit?>()?.state.isBlocked('$id') == true) {
    unavailable();
    return;
  }
  if (profile.isMe == true) return openMine();
  await ProfileScreen.open(
    context,
    userId: id,
    profileRepo: profileRepo,
    postsRepo: postsRepo,
  );
}
