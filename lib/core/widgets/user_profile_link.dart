import 'package:flutter/material.dart';
import 'package:travibe/core/navigation/app_cubits.dart';
import 'package:travibe/core/navigation/my_profile_tab.dart';
import 'package:travibe/features/home/data/posts_repo.dart';
import 'package:travibe/features/profile/data/profile_repo.dart';
import 'package:travibe/core/utils/viewer_identity.dart';
import 'package:travibe/features/block/cubit/block_cubit.dart';
import 'package:travibe/features/profile/screens/profile_screen.dart';

/// The one way to open any user's profile (posts, comments, likes, lists,
/// search, Buddies, chat, notifications, Story viewer, mentions, deep links,
/// shared posts). The signed-in user's own id opens their Profile tab (never
/// a second profile page with Follow); a blocked user opens nothing. The
/// pushed profile always gets the app's shared cubits, so ⋮, Message and
/// Follow/Following/Requested are there from every entry point.
Future<void> openUserProfile(
  BuildContext context,
  Object? userId, {
  ProfileRepo? profileRepo,
  PostsRepo? postsRepo,
}) async {
  final id = int.tryParse(userId?.toString() ?? '');
  if (id == null || id < 1) return;
  if (isViewer(context, id)) {
    if (MyProfileTab.show()) return;
    await ProfileScreen.open(
      context,
      profileRepo: profileRepo,
      postsRepo: postsRepo,
    );
    return;
  }
  if (readAppCubit<BlockCubit>(context)?.state.isBlocked('$id') == true) {
    return;
  }
  await ProfileScreen.open(
    context,
    userId: id,
    profileRepo: profileRepo,
    postsRepo: postsRepo,
  );
}

/// One profile destination for avatars and names throughout existing features.
class UserProfileLink extends StatefulWidget {
  const UserProfileLink({super.key, required this.userId, required this.child});
  final Object? userId;
  final Widget child;
  @override
  State<UserProfileLink> createState() => _UserProfileLinkState();
}

class _UserProfileLinkState extends State<UserProfileLink> {
  bool _opening = false;
  Future<void> _open(int id) async {
    if (_opening) return;
    _opening = true;
    try {
      await openUserProfile(context, id);
    } finally {
      _opening = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final id = int.tryParse(widget.userId?.toString() ?? '');
    return InkWell(
      onTap: id == null || id < 1 ? null : () => _open(id),
      borderRadius: BorderRadius.circular(24),
      child: widget.child,
    );
  }
}
