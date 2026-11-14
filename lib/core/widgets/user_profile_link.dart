import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:travibe/core/navigation/my_profile_tab.dart';
import 'package:travibe/core/utils/viewer_identity.dart';
import 'package:travibe/features/block/cubit/block_cubit.dart';
import 'package:travibe/features/profile/screens/profile_screen.dart';

/// The one profile destination for every user row, avatar and name. The
/// signed-in user's own id opens their Profile tab (never a second profile
/// page with Follow); a blocked user opens nothing.
Future<void> openUserProfile(BuildContext context, Object? userId) async {
  final id = int.tryParse(userId?.toString() ?? '');
  if (id == null || id < 1) return;
  if (isViewer(context, id)) {
    if (MyProfileTab.show()) return;
    await ProfileScreen.open(context);
    return;
  }
  if (context.read<BlockCubit?>()?.state.isBlocked('$id') == true) return;
  await ProfileScreen.open(context, userId: id);
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
