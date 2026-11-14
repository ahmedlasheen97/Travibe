import 'package:travibe/core/widgets/glass_confirm_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:travibe/core/constants/app_sizes.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/core/theme/action_button_style.dart';
import 'package:travibe/core/theme/dark_colors.dart';
import 'package:travibe/core/widgets/more_options_button.dart';
import 'package:travibe/core/widgets/options_sheet.dart';
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

enum ProfileOption { share, copyLink, removeFollower, report, block, unblock }

/// Other user's profile ⋮ menu (same frame as the post ⋮ menu).
/// A blocked user only offers Unblock. Share/Copy need the backend `url`.
class ProfileOptionsSheet extends StatelessWidget {
  const ProfileOptionsSheet({
    super.key,
    required this.followsYou,
    this.blocked = false,
    this.pending = false,
    this.canShare = false,
  });
  final bool followsYou, blocked, pending, canShare;

  static Future<ProfileOption?> show(
    BuildContext context, {
    required WidgetBuilder builder,
  }) => showOptionsSheet<ProfileOption>(context, builder: builder);

  @override
  Widget build(BuildContext context) {
    Widget row(
      ProfileOption option,
      String label,
      String icon, {
      bool danger = false,
      Color? tint,
    }) => OptionSheetTile(
      key: ValueKey('profile-option-${option.name}'),
      icon: optionSvg(
        'assets/images/icons/$icon',
        tint: danger ? DarkColors.dangerColor : tint ?? DarkColors.greyColor,
      ),
      label: label,
      color: danger ? DarkColors.dangerColor : null,
      onTap: pending ? null : () => Navigator.pop(context, option),
    );
    return OptionsSheetBody(
      children: blocked
          ? [row(ProfileOption.unblock, 'Unblock user', 'user-remove.svg')]
          : [
              if (canShare) ...[
                row(ProfileOption.share, 'Share profile', 'send-2.svg'),
                row(ProfileOption.copyLink, 'Copy profile link', 'link-2.svg'),
              ],
              if (followsYou)
                row(
                  ProfileOption.removeFollower,
                  'Remove follower',
                  'user-remove.svg',
                  tint: DarkColors.whiteColor,
                ),
              row(ProfileOption.report, 'Report user', 'flag.svg'),
              row(
                ProfileOption.block,
                'Block user',
                'user-remove.svg',
                danger: true,
              ),
            ],
    );
  }
}

/// Profile header ⋮: the post card button at its responsive size.
class ProfileMoreButton extends StatelessWidget {
  const ProfileMoreButton({super.key, required this.onTap});
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsetsDirectional.only(end: AppSizes.adaptiveWidth(20)),
    child: Center(
      child: MoreOptionsButton(
        tooltip: 'Profile options',
        onTap: onTap,
        size: AppSizes.adaptiveRadius(38),
        radius: AppSizes.adaptiveRadius(20),
      ),
    ),
  );
}

/// ⋮ for a profile the viewer has blocked (the profile body is unavailable):
/// the only action is Unblock, confirmed with the glass dialog.
class BlockedProfileOptionsButton extends StatelessWidget {
  const BlockedProfileOptionsButton({super.key, required this.userId});
  final String userId;

  @override
  Widget build(BuildContext context) => ProfileMoreButton(
    onTap: () async {
      final block = context.read<BlockCubit>();
      if (block.state.pending.contains(userId)) return;
      final action = await ProfileOptionsSheet.show(
        context,
        builder: (_) => BlocBuilder<BlockCubit, BlockState>(
          bloc: block,
          builder: (_, state) => ProfileOptionsSheet(
            followsYou: false,
            blocked: true,
            pending: state.pending.contains(userId),
          ),
        ),
      );
      if (action != ProfileOption.unblock || !context.mounted) return;
      await confirmBlockChange(context, userId, blocked: false);
    },
  );
}

/// Uses the existing shared follow state, confirmed Conversation API and native
/// share channel. Sharing uses the backend `url` as-is; none is fabricated.
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
    final id = widget.profile.id;
    final blockCubit = context.read<BlockCubit?>();
    if (_sheetOpen ||
        _busy ||
        !_valid ||
        blockCubit?.state.pending.contains(id) == true) {
      return;
    }
    _sheetOpen = true;
    final follow = context.read<FollowCubit>();
    Widget sheet(BlockState? blocks) => BlocBuilder<FollowCubit, FollowState>(
      bloc: follow,
      builder: (_, state) => ProfileOptionsSheet(
        followsYou: state.followsYou[id] ?? widget.profile.followsYou == true,
        canShare: widget.profile.url != null,
        blocked:
            widget.profile.isBlocked == true || blocks?.isBlocked(id) == true,
        pending:
            state.pending.contains(id) || blocks?.pending.contains(id) == true,
      ),
    );
    final action = await ProfileOptionsSheet.show(
      context,
      builder: (_) => blockCubit == null
          ? sheet(null)
          : BlocBuilder<BlockCubit, BlockState>(
              bloc: blockCubit,
              builder: (_, blocks) => sheet(blocks),
            ),
    );
    _sheetOpen = false;
    if (!mounted || !_valid || action == null) return;
    // Only Unblock is valid against a blocked user.
    if (_blocked != (action == ProfileOption.unblock)) return;
    setState(() => _busy = true);
    try {
      switch (action) {
        case ProfileOption.share:
          final box = context.findRenderObject() as RenderBox?;
          final origin = box == null
              ? const Rect.fromLTWH(0, 0, 1, 1)
              : box.localToGlobal(Offset.zero) & box.size;
          await PostShareActions(
            verifiedPostUri: widget.profile.url,
          ).moreOptions(origin);
        case ProfileOption.copyLink:
          await PostShareActions(
            verifiedPostUri: widget.profile.url,
          ).copyLink();
          if (mounted && _valid) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text('Link copied')));
          }
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
        case ProfileOption.unblock:
          if (context.read<BlockCubit?>() != null) {
            await confirmBlockChange(
              context,
              widget.profile.id,
              blocked: action == ProfileOption.block,
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
      return ProfileMoreButton(onTap: _valid && !_busy ? _options : null);
    }
    return FollowActionBuilder(
      userId: widget.profile.id,
      initialFollowing: widget.profile.isFollowing == true,
      initialRequested: widget.profile.followRequested == true,
      builder: (context, relation, pending, onToggle) => Padding(
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
            SizedBox(width: AppSizes.w12),
            Expanded(
              child: FilledButton(
                style: _style(
                  relation == FollowRelation.follow,
                  muted: relation.isRequested && !pending,
                ),
                onPressed: _valid && !_blocked ? onToggle : null,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(pending ? 'Updating…' : relation.label),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  ButtonStyle _style(bool orange, {bool muted = false}) =>
      FilledButton.styleFrom(
        backgroundColor: orange
            ? DarkColors.primaryColor
            : DarkColors.darkgreyColor,
        foregroundColor: muted ? requestedFollowColor : Colors.white,
        minimumSize: Size(0, AppSizes.h44),
        fixedSize: Size.fromHeight(AppSizes.h44),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        padding: EdgeInsets.symmetric(horizontal: AppSizes.pw12),
        shape: ActionButtonStyle.shape,
        textStyle: ActionButtonStyle.label.copyWith(fontSize: AppSizes.sp18),
      );
}
