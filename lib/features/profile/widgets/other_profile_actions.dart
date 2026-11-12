import 'package:travibe/core/widgets/glass_confirm_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:travibe/core/constants/app_sizes.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/core/theme/action_button_style.dart';
import 'package:travibe/core/theme/dark_colors.dart';
import 'package:travibe/core/widgets/sheet_handle.dart';
import 'package:travibe/features/block/cubit/block_cubit.dart';
import 'package:travibe/features/block/widgets/block_user_button.dart';
import 'package:travibe/features/chats/data/chat_repository.dart';
import 'package:travibe/features/chats/screens/chat_navigation.dart';
import 'package:travibe/features/chats/screens/conversation_screen.dart';
import 'package:travibe/features/follow/cubit/follow_cubit.dart';
import 'package:travibe/features/follow/widgets/follow_action_builder.dart';
import 'package:travibe/features/home/widgets/report_reason_sheet.dart';
import 'package:travibe/features/profile/cubit/current_user_cubit.dart';
import 'package:travibe/features/profile/cubit/profile_cubit.dart';
import 'package:travibe/features/profile/data/profile_model.dart';
import 'package:travibe/features/shares/data/post_share_actions.dart';

enum ProfileOption { share, removeFollower, report, block }

class ProfileOptionsSheet extends StatelessWidget {
  const ProfileOptionsSheet({
    super.key,
    required this.followsYou,
    this.pending = false,
  });
  final bool followsYou, pending;
  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: Padding(
      padding: EdgeInsets.fromLTRB(AppSizes.w20, 12, AppSizes.w20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SheetHandle(),
          const SizedBox(height: 12),
          _action(context, ProfileOption.share, 'Share Profile', 'send-2.svg'),
          if (followsYou)
            _action(
              context,
              ProfileOption.removeFollower,
              'Remove Follower',
              'user-remove.svg',
            ),
          _action(context, ProfileOption.report, 'Report', 'flag.svg'),
          _action(
            context,
            ProfileOption.block,
            'Block User',
            'user_remove_2.svg',
          ),
        ],
      ),
    ),
  );
  Widget _action(
    BuildContext context,
    ProfileOption option,
    String title,
    String icon,
  ) => ListTile(
    enabled: !pending,
    leading: SvgPicture.asset(
      'assets/images/icons/$icon',
      width: 24,
      height: 24,
    ),
    title: Text(
      title,
      style: TextStyle(
        color: option == ProfileOption.block
            ? const Color(0xFFDD312A)
            : Colors.white,
      ),
    ),
    onTap: pending ? null : () => Navigator.pop(context, option),
  );
}

/// Uses the existing shared follow state, confirmed Conversation API and native
/// share channel. No public profile URL is fabricated.
class OtherProfileActions extends StatefulWidget {
  const OtherProfileActions({
    super.key,
    required this.profile,
    this.repository,
    this.optionsOnly = false,
  });
  final ProfileModel profile;
  final ChatRepository? repository;
  final bool optionsOnly;
  @override
  State<OtherProfileActions> createState() => _OtherProfileActionsState();
}

class _OtherProfileActionsState extends State<OtherProfileActions> {
  final _preferences = PreferencesManager();
  late final _session = _preferences.sessionRevision;
  ChatRepository? _chat;
  bool _busy = false, _sheetOpen = false;
  bool get _valid =>
      mounted &&
      _preferences.hasSession &&
      _session == _preferences.sessionRevision;
  bool get _blocked {
    final id = widget.profile.id;
    final block = context.read<BlockCubit?>();
    return widget.profile.isBlocked == true ||
        block?.state.isBlocked(id) == true ||
        block?.state.pending.contains(id) == true;
  }

  void _error(Object error) {
    if (!mounted || !_valid) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          error is ApiError
              ? error.message
              : 'Unable to complete this action. Please retry.',
        ),
      ),
    );
  }

  Future<void> _message() async {
    if (_busy || !_valid || _blocked) return;
    setState(() => _busy = true);
    try {
      _chat ??= widget.repository ?? LaravelChatRepository();
      final conversation = await _chat!.create(widget.profile.id);
      if (!mounted || !_valid || _blocked) return;
      final screen = chatRouteScope(
        context,
        ConversationScreen(
          conversation: conversation,
          repository: widget.repository,
        ),
      );
      await Navigator.of(
        context,
      ).push(MaterialPageRoute<void>(builder: (_) => screen));
    } catch (error) {
      _error(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _options() async {
    if (_sheetOpen || _busy || !_valid || _blocked) return;
    _sheetOpen = true;
    final follow = context.read<FollowCubit>();
    final action = await showModalBottomSheet<ProfileOption>(
      context: context,
      backgroundColor: DarkColors.darkgreyColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) => BlocBuilder<FollowCubit, FollowState>(
        bloc: follow,
        builder: (_, state) => ProfileOptionsSheet(
          followsYou:
              state.followsYou[widget.profile.id] ??
              widget.profile.followsYou == true,
          pending: state.pending.contains(widget.profile.id),
        ),
      ),
    );
    _sheetOpen = false;
    if (!mounted || !_valid || action == null || _blocked) return;
    setState(() => _busy = true);
    try {
      switch (action) {
        case ProfileOption.share:
          final box = context.findRenderObject() as RenderBox?;
          final origin = box == null
              ? const Rect.fromLTWH(0, 0, 1, 1)
              : box.localToGlobal(Offset.zero) & box.size;
          final profile = widget.profile;
          await PostShareActions(
            text: [
              profile.displayName,
              if (profile.username?.isNotEmpty == true) '@${profile.username}',
            ].join(' '),
          ).moreOptions(origin);
        case ProfileOption.removeFollower:
          if (!(follow.state.followsYou[widget.profile.id] ??
              widget.profile.followsYou == true)) {
            break;
          }
          final confirmed = await showGlassConfirmDialog(
            context,
            title: 'Remove follower?',
            message: '${widget.profile.displayName} will no longer follow you.',
            confirmLabel: 'Remove',
          );
          if (!mounted || !_valid || !confirmed || _blocked) break;
          final error = await follow.removeFollower(widget.profile.id);
          if (!mounted || !_valid) break;
          if (error != null) {
            _error(error);
            break;
          }
          // The shared follow revision starts a canonical refresh. Join it
          // instead of superseding that in-flight read with a duplicate.
          await context.read<ProfileCubit>().loadProfile();
          if (mounted && _valid) {
            await context.read<CurrentUserCubit?>()?.load();
          }
        case ProfileOption.report:
          final report = await ReportReasonSheet.show(context);
          if (!mounted || !_valid || report == null || _blocked) break;
          await context.read<ProfileCubit>().reportUser(report.reason.apiValue);
          if (mounted && _valid) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text('Report submitted.')));
          }
        case ProfileOption.block:
          if (context.read<BlockCubit?>() != null) {
            await confirmBlockChange(
              context,
              widget.profile.id,
              blocked: true,
              name: widget.profile.displayName,
            );
          }
      }
    } catch (error) {
      _error(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _chat?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final follow = context.read<FollowCubit?>();
    if (follow == null) return const SizedBox.shrink();
    if (widget.optionsOnly) {
      return IconButton(
        tooltip: 'Profile options',
        onPressed: _valid && !_busy ? _options : null,
        icon: const Icon(Icons.more_horiz),
      );
    }
    return FollowActionBuilder(
      userId: widget.profile.id,
      initialFollowing: widget.profile.isFollowing == true,
      builder: (context, following, pending, onToggle) => Padding(
        padding: EdgeInsets.symmetric(horizontal: AppSizes.w20),
        child: Row(
          children: [
            Expanded(
              child: FilledButton(
                style: _style(false),
                onPressed: _valid && !_busy && !_blocked ? _message : null,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(_busy ? 'Opening…' : 'Message'),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                style: _style(!following),
                onPressed: _valid && !_blocked ? onToggle : null,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    pending
                        ? 'Updating…'
                        : following
                        ? 'Following'
                        : 'Follow',
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  ButtonStyle _style(bool orange) => FilledButton.styleFrom(
    backgroundColor: orange
        ? DarkColors.primaryColor
        : DarkColors.darkgreyColor,
    foregroundColor: Colors.white,
    minimumSize: const Size(0, 44),
    padding: const EdgeInsets.symmetric(horizontal: 12),
    shape: ActionButtonStyle.shape,
    textStyle: ActionButtonStyle.label,
  );
}
