import 'package:travibe/core/widgets/app_loaders.dart';
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:travibe/core/constants/app_sizes.dart';
import 'package:travibe/core/cubit/cursor_list_cubit.dart';
import 'package:travibe/core/models/public_user_model.dart';
import 'package:travibe/core/theme/dark_colors.dart';
import 'package:travibe/core/utils/formatters.dart';
import 'package:travibe/core/utils/viewer_identity.dart';
import 'package:travibe/core/widgets/error_retry_view.dart';
import 'package:travibe/core/widgets/sheet_handle.dart';
import 'package:travibe/core/widgets/user_profile_link.dart';
import 'package:travibe/features/block/cubit/block_cubit.dart';
import 'package:travibe/features/block/widgets/block_user_button.dart';
import 'package:travibe/features/chats/screens/chat_navigation.dart';
import 'package:travibe/features/follow/cubit/follow_cubit.dart';
import 'package:travibe/features/follow/widgets/follow_action_builder.dart';
import 'package:travibe/features/follow/widgets/follow_pill.dart';
import 'package:travibe/features/home/widgets/home_user_avatar.dart';
import 'package:travibe/features/home/widgets/post_options_sheet.dart';
import 'package:travibe/features/likes/cubit/likes_users_cubit.dart';
import 'package:travibe/features/likes/data/like_model.dart';
import 'package:travibe/features/likes/data/likes_repo.dart';

/// Figma "Liked by": users who liked a post (`GET posts/{post}/likes`).
class LikedBySheet extends StatefulWidget {
  const LikedBySheet({super.key, required this.cubit, required this.count});
  final LikesUsersCubit cubit;
  final int count;

  static Future<void> show(
    BuildContext context, {
    required int postId,
    required int count,
    LikesRepo? repo,
  }) async {
    if (postId < 1) return;
    final cubit = LikesUsersCubit(target: LikeTarget.post(postId), repo: repo);
    unawaited(cubit.load());
    try {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: Colors.transparent,
        barrierColor: Colors.black.withValues(alpha: 0.6),
        constraints: const BoxConstraints(maxWidth: 560),
        builder: (_) =>
            chatRouteScope(context, LikedBySheet(cubit: cubit, count: count)),
      );
    } finally {
      await cubit.close();
    }
  }

  @override
  State<LikedBySheet> createState() => _LikedBySheetState();
}

class _LikedBySheetState extends State<LikedBySheet> {
  LikesUsersCubit get _cubit => widget.cubit;

  @override
  Widget build(BuildContext context) => Material(
    color: const Color(0xFF0A0A0A),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      side: BorderSide(color: Color(0x66595959)),
    ),
    clipBehavior: Clip.antiAlias,
    child: SafeArea(
      top: false,
      child: SizedBox(
        height: math.min(614, MediaQuery.sizeOf(context).height * .75),
        child: Column(
          children: [
            SizedBox(height: AppSizes.adaptiveHeight(16)),
            const SheetHandle(),
            SizedBox(height: AppSizes.adaptiveHeight(32)),
            Padding(
              padding: EdgeInsets.symmetric(
                horizontal: AppSizes.adaptiveWidth(24),
              ),
              child: Row(
                children: [
                  Text(
                    'Liked by',
                    style: TextStyle(
                      color: DarkColors.whiteColor,
                      fontSize: AppSizes.adaptiveFont(18),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  SizedBox(width: AppSizes.adaptiveWidth(8)),
                  Text(
                    formatCount(widget.count),
                    key: const ValueKey('liked-by-count'),
                    style: TextStyle(
                      color: DarkColors.greyColor,
                      fontSize: AppSizes.adaptiveFont(14),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: AppSizes.adaptiveHeight(16)),
            Expanded(
              child:
                  BlocBuilder<
                    LikesUsersCubit,
                    CursorListState<PublicUserModel>
                  >(bloc: _cubit, builder: (context, state) => _body(state)),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _body(CursorListState<PublicUserModel> state) {
    if (state.status == CursorListStatus.initial ||
        state.status == CursorListStatus.loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.status == CursorListStatus.failure) {
      return Center(
        child: ErrorRetryView(
          message: state.error!.message,
          onRetry: _cubit.refresh,
        ),
      );
    }
    final users = state.items;
    return AppRefreshIndicator(
      onRefresh: _cubit.refresh,
      child: NotificationListener<ScrollNotification>(
        onNotification: (event) {
          if (event.depth == 0 && event.metrics.extentAfter < 240) {
            _cubit.more();
          }
          return false;
        },
        child: ListView.builder(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.symmetric(horizontal: AppSizes.adaptiveWidth(24)),
          itemCount: users.length + 1,
          itemBuilder: (context, index) {
            if (index < users.length) return _LikerRow(user: users[index]);
            if (users.isEmpty) {
              return const Padding(
                padding: EdgeInsets.all(24),
                child: Center(
                  child: Text(
                    'No likes yet',
                    style: TextStyle(color: DarkColors.greyColor),
                  ),
                ),
              );
            }
            if (state.loadingMore) {
              return const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            if (state.paginationError != null) {
              return ErrorRetryView(
                message: state.paginationError!.message,
                onRetry: () => _cubit.more(retry: true),
              );
            }
            return const SizedBox(height: 16);
          },
        ),
      ),
    );
  }
}

class _LikerRow extends StatelessWidget {
  const _LikerRow({required this.user});
  final PublicUserModel user;

  @override
  Widget build(BuildContext context) {
    final mine = isViewer(context, user.id);
    final follow = context.read<FollowCubit?>();
    final blocks = context.read<BlockCubit?>();
    return Padding(
      key: ValueKey('liker-${user.id}'),
      padding: EdgeInsets.symmetric(vertical: AppSizes.adaptiveHeight(8)),
      child: Row(
        children: [
          Expanded(
            child: UserProfileLink(
              userId: user.id,
              child: Row(
                children: [
                  HomeUserAvatar(
                    url: user.avatarUrl,
                    size: AppSizes.adaptiveRadius(48),
                  ),
                  SizedBox(width: AppSizes.adaptiveWidth(10)),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          user.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: DarkColors.whiteColor,
                            fontSize: AppSizes.adaptiveFont(16),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        if (user.handle.isNotEmpty)
                          Text(
                            user.handle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: DarkColors.greyColor,
                              fontSize: AppSizes.adaptiveFont(14),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (!mine && follow != null) ...[
            SizedBox(width: AppSizes.adaptiveWidth(8)),
            _follow(context),
          ],
          if (!mine && blocks != null)
            IconButton(
              tooltip: 'User options',
              icon: const Icon(Icons.more_vert, color: DarkColors.greyColor),
              onPressed: () => _options(context),
            ),
        ],
      ),
    );
  }

  Widget _follow(BuildContext context) => FollowActionBuilder(
    userId: user.id,
    initialFollowing: user.isFollowing,
    builder: (context, following, pending, toggle) {
      final block = context.watch<BlockCubit?>()?.state;
      final blocked =
          block?.isBlocked(user.id, fallback: user.isBlocked) ?? user.isBlocked;
      return ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 120),
        child: FollowPill(
          following: following,
          pending: pending,
          onPressed: blocked || block?.pending.contains(user.id) == true
              ? null
              : toggle,
          style: ButtonStyle(
            backgroundColor: const WidgetStatePropertyAll(
              FollowPill.backgroundColor,
            ),
            foregroundColor: const WidgetStatePropertyAll(Colors.white),
            overlayColor: const WidgetStatePropertyAll(Colors.white10),
            padding: WidgetStatePropertyAll(
              EdgeInsets.symmetric(horizontal: AppSizes.adaptiveWidth(14)),
            ),
          ),
        ),
      );
    },
  );

  Future<void> _options(BuildContext context) async {
    final blocks = context.read<BlockCubit>();
    if (blocks.state.pending.contains(user.id)) return;
    final action = await PostOptionsSheet.show(
      context,
      actions: const {PostOptionAction.blockUser},
    );
    if (action == PostOptionAction.blockUser && context.mounted) {
      await confirmBlockChange(
        context,
        user.id,
        blocked: true,
        name: user.name,
      );
    }
  }
}
