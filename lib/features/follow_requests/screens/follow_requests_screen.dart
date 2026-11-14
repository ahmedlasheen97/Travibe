import 'package:travibe/core/widgets/user_profile_link.dart';
import 'package:travibe/core/utils/viewer_identity.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:travibe/core/constants/app_sizes.dart';
import 'package:travibe/core/models/public_user_model.dart';
import 'package:travibe/core/theme/dark_colors.dart';
import 'package:travibe/core/widgets/app_loaders.dart';
import 'package:travibe/core/widgets/back_button_widget.dart';
import 'package:travibe/core/widgets/error_retry_view.dart';
import 'package:travibe/core/widgets/travibe_loading_indicator.dart';
import 'package:travibe/features/chats/screens/chat_navigation.dart';
import 'package:travibe/features/follow/cubit/follow_cubit.dart';
import 'package:travibe/features/follow/cubit/follow_users_cubit.dart';
import 'package:travibe/features/follow/widgets/people_skeleton.dart';
import 'package:travibe/features/follow_requests/cubit/incoming_requests_cubit.dart';
import 'package:travibe/features/follow_requests/widgets/follow_request_actions.dart';
import 'package:travibe/features/home/widgets/home_user_avatar.dart';
import 'package:travibe/features/profile/screens/profile_screen.dart';

/// Pending follow requests to my private account (Figma "Follow Requests").
class FollowRequestsScreen extends StatefulWidget {
  const FollowRequestsScreen({super.key, this.onOpenProfile});

  /// Test seam; defaults to [ProfileScreen.open].
  final void Function(BuildContext context, int userId)? onOpenProfile;

  /// Pushes the screen, keeping Root's shared cubits in scope.
  /// Shares Follow/Block/current-user/requests cubits with the route. Outside
  /// Root (no shared requests cubit) the route owns a short-lived one.
  static Future<void> open(BuildContext context) {
    final shared = context.read<IncomingRequestsCubit?>();
    final follow = context.read<FollowCubit?>();
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: 'follow-requests'),
        builder: (_) => chatRouteScope(
          context,
          shared != null
              ? const FollowRequestsScreen()
              : BlocProvider(
                  create: (_) => IncomingRequestsCubit(follow: follow),
                  child: const FollowRequestsScreen(),
                ),
        ),
      ),
    );
  }

  @override
  State<FollowRequestsScreen> createState() => _FollowRequestsScreenState();
}

class _FollowRequestsScreenState extends State<FollowRequestsScreen> {
  late final IncomingRequestsCubit _incoming = context
      .read<IncomingRequestsCubit>();
  late final FollowUsersCubit _list = FollowUsersCubit(
    loadPage: (page) async {
      final result = await _incoming.repo.list(page: page);
      _incoming.remember(
        result.users.map((user) => user.id),
        total: page == 1 ? result.total : null,
      );
      return result;
    },
  );

  @override
  void initState() {
    super.initState();
    unawaited(_list.load());
  }

  @override
  void dispose() {
    _list.close();
    super.dispose();
  }

  void _open(PublicUserModel user) {
    final id = int.tryParse(user.id);
    if (id == null || id < 1) return;
    final open = widget.onOpenProfile;
    if (open != null) {
      open(context, id);
    } else {
      ProfileScreen.open(context, userId: id);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: DarkColors.backgroundColor,
    body: SafeArea(
      bottom: false,
      child: Column(
        children: [
          SizedBox(height: AppSizes.h8),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: AppSizes.pw16),
            child: SizedBox(
              height: 44,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: BackButtonWidget(),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 52),
                    child: Text(
                      'Follow Requests',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: DarkColors.whiteColor,
                        fontSize: AppSizes.sp17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SizedBox(height: AppSizes.h16),
          Expanded(child: _body()),
        ],
      ),
    ),
  );

  Widget _body() => BlocBuilder<FollowUsersCubit, FollowUsersState>(
    bloc: _list,
    builder: (context, state) {
      if (state.status == FollowUsersStatus.initial ||
          state.status == FollowUsersStatus.loading) {
        return const PeopleSkeleton();
      }
      if (state.status == FollowUsersStatus.failure) {
        return ErrorRetryView(
          message: state.error!.message,
          onRetry: () => _list.load(force: true),
        );
      }
      return BlocBuilder<IncomingRequestsCubit, IncomingRequestsState>(
        builder: (context, incoming) {
          final users = state.users
              .where((user) => !incoming.isHandled(user.id))
              .toList();
          return AppRefreshIndicator(
            onRefresh: () async {
              await Future.wait([_list.load(force: true), _incoming.sync()]);
            },
            child: NotificationListener<ScrollNotification>(
              onNotification: (event) {
                if (event.metrics.extentAfter < 300) _list.more();
                return false;
              },
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  if (users.isEmpty)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: Center(
                        child: Text(
                          'No follow requests',
                          style: TextStyle(
                            color: DarkColors.greyColor,
                            fontSize: AppSizes.sp15,
                          ),
                        ),
                      ),
                    ),
                  SliverPadding(
                    padding: EdgeInsets.symmetric(horizontal: AppSizes.pw16),
                    sliver: SliverList.builder(
                      itemCount: users.length,
                      itemBuilder: (_, index) => FollowRequestTile(
                        key: ValueKey('follow-request-${users[index].id}'),
                        user: users[index],
                        onTap: () => _open(users[index]),
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.only(bottom: AppSizes.h24),
                      child: Column(
                        children: [
                          if (state.loadingMore)
                            const TravibeLoadingIndicator(size: 30),
                          if (state.paginationError != null)
                            ErrorRetryView(
                              message: state.paginationError!.message,
                              onRetry: () => _list.more(retry: true),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  );
}

class FollowRequestTile extends StatelessWidget {
  const FollowRequestTile({super.key, required this.user, this.onTap});
  final PublicUserModel user;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final own = isViewer(context, user.id);
    return Padding(
      padding: EdgeInsets.only(bottom: AppSizes.h12),
      child: Material(
        color: const Color(0xFF141414),
        borderRadius: BorderRadius.circular(AppSizes.r20),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: own ? const ValueKey('own-user-row') : null,
          onTap: own ? () => openUserProfile(context, user.id) : onTap,
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: AppSizes.pw12,
              vertical: AppSizes.ph12,
            ),
            child: Row(
              children: [
                HomeUserAvatar(url: user.avatarUrl, size: AppSizes.w44),
                SizedBox(width: AppSizes.w10),
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
                          fontSize: AppSizes.sp15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (user.handle.isNotEmpty)
                        Text(
                          user.handle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: DarkColors.greyColor,
                            fontSize: AppSizes.sp12,
                          ),
                        ),
                    ],
                  ),
                ),
                if (!own) ...[
                  SizedBox(width: AppSizes.w8),
                  FollowRequestActions(userId: user.id),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
