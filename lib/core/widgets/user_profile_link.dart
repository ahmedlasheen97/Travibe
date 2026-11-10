import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:travibe/features/block/cubit/block_cubit.dart';
import 'package:travibe/features/profile/screens/profile_screen.dart';

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
    if (_opening ||
        context.read<BlockCubit?>()?.state.isBlocked('$id') == true) {
      return;
    }
    _opening = true;
    try {
      await ProfileScreen.open(context, userId: id);
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
