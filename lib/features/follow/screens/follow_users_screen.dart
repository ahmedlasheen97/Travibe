import 'package:travibe/core/widgets/travibe_toast.dart';
import 'package:travibe/core/widgets/glass_confirm_dialog.dart';
import 'package:travibe/core/utils/viewer_identity.dart';
import 'package:travibe/core/models/public_user_model.dart';
import 'package:travibe/core/constants/app_sizes.dart';
import 'package:travibe/core/widgets/back_button_widget.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:travibe/core/theme/dark_colors.dart';
import 'package:travibe/core/widgets/error_retry_view.dart';
import 'package:travibe/core/widgets/travibe_loading_indicator.dart';
import 'package:travibe/features/block/cubit/block_cubit.dart';
import 'package:travibe/features/block/widgets/refresh_users_on_unblock.dart';
import 'package:travibe/features/buddies/screens/buddies_screen.dart';
import 'package:travibe/features/follow/cubit/follow_cubit.dart';
import 'package:travibe/features/follow/cubit/follow_users_cubit.dart';
import 'package:travibe/features/follow/data/follow_repo.dart';
import 'package:travibe/features/follow/widgets/follow_user_tile.dart';
import 'package:travibe/features/follow/widgets/people_skeleton.dart';
import 'package:travibe/features/profile/widgets/profile_empty_state.dart';

class FollowUsersScreen extends StatefulWidget {
  const FollowUsersScreen({
    super.key,
    required this.type,
    this.userId,
    this.username,
    this.followersCount,
    this.followingCount,
    this.onExplorePeople,
  });
  final FollowListType type;
  final String? userId, username;
  final int? followersCount, followingCount;
  final VoidCallback? onExplorePeople;

  static Future<void> open(
    BuildContext context, {
    required FollowListType type,
    String? userId,
    String? username,
    int? followersCount,
    int? followingCount,
    VoidCallback? onExplorePeople,
  }) {
    final follow = context.read<FollowCubit>();
    final block = context.read<BlockCubit>();
    return Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => MultiBlocProvider(
          providers: [
            BlocProvider.value(value: follow),
            BlocProvider.value(value: block),
          ],
          child: FollowUsersScreen(
            type: type,
            userId: userId,
            username: username,
            followersCount: followersCount,
            followingCount: followingCount,
            onExplorePeople: onExplorePeople,
          ),
        ),
      ),
    );
  }

  @override
  State<FollowUsersScreen> createState() => _FollowUsersScreenState();
}

class _FollowUsersScreenState extends State<FollowUsersScreen> {
  late FollowListType _selected = widget.type;
  final _lists = <FollowListType, FollowUsersCubit>{};
  final _subscriptions = <StreamSubscription<dynamic>>[];
  final _refreshes = <FollowListType, Future<void>>{};

  @override
  void initState() {
    super.initState();
    PreferencesManager().addListener(_sessionChanged);
    final follow = context.read<FollowCubit>();
    var revision = follow.state.revision;
    _subscriptions.add(
      follow.stream.listen((state) {
        if (state.revision == revision) return;
        revision = state.revision;
        for (final list in _lists.values) {
          unawaited(list.load(force: true));
        }
      }),
    );
  }

  void _sessionChanged() {
    if (mounted) {
      setState(() {
        _refreshes.clear();
      });
    }
  }

  FollowUsersCubit _list(FollowListType type) => _lists.putIfAbsent(type, () {
    final list = FollowUsersCubit(
      type: type,
      userId: widget.userId,
      repo: context.read<FollowCubit>().repo,
    );
    _subscriptions.add(
      list.stream.listen((_) {
        if (mounted) setState(() {});
      }),
    );
    unawaited(list.load());
    return list;
  });

  Future<void> _refresh(FollowListType type) {
    if (_refreshes[type] != null) return _refreshes[type]!;
    final request = _list(type).load();
    setState(() {
      _refreshes[type] = request;
    });
    return request.whenComplete(() {
      if (mounted && identical(_refreshes[type], request)) {
        setState(() {
          _refreshes.remove(type);
        });
      }
    });
  }

  /// Only my own Followers list can remove people.
  bool get _canRemove => isViewer(context, widget.userId);

  Future<void> _removeFollower(PublicUserModel user) async {
    final follow = context.read<FollowCubit>();
    final list = _lists[FollowListType.followers];
    if (list == null || follow.state.pending.contains(user.id)) return;
    final confirmed = await showGlassConfirmDialog(
      context,
      title: 'Remove follower?',
      message: 'Remove ${user.name} from your followers?',
      confirmLabel: 'Remove',
    );
    if (!mounted || !confirmed) return;
    final restore = list.removeLocally(user.id);
    final error = await follow.removeFollower(user.id);
    if (error == null) return;
    // On success the follow revision reloads both lists and profile counts.
    restore();
    if (mounted) {
      TravibeToast.show(context, TravibeToastData.error(error.message));
    }
  }

  void _explore() {
    if (widget.onExplorePeople != null) {
      widget.onExplorePeople!();
      return;
    }
    final follow = context.read<FollowCubit>();
    final block = context.read<BlockCubit>();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MultiBlocProvider(
          providers: [
            BlocProvider.value(value: follow),
            BlocProvider.value(value: block),
          ],
          child: Scaffold(
            appBar: AppBar(
              leading: Navigator.of(context).canPop()
                  ? const BackButtonWidget()
                  : null,
              title: const Text('Buddies'),
            ),
            body: const BuddiesScreen(),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    PreferencesManager().removeListener(_sessionChanged);
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    for (final cubit in _lists.values) {
      unawaited(cubit.close());
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _list(_selected);
    final types = _lists.keys.toList();
    final username = widget.username;
    final title = username?.isNotEmpty == true
        ? (username!.startsWith('@') ? username : '@$username')
        : _selected == FollowListType.suggested
        ? 'Suggested people'
        : widget.type == FollowListType.followers
        ? 'Followers'
        : 'Following';
    return Scaffold(
      backgroundColor: DarkColors.backgroundColor,
      appBar: AppBar(
        leading: Navigator.of(context).canPop()
            ? const BackButtonWidget()
            : null,

        centerTitle: true,
        title: Text(
          title,
          style: TextStyle(
            color: DarkColors.whiteColor,
            fontSize: AppSizes.sp18,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            if (widget.type != FollowListType.suggested)
              Padding(
                padding: EdgeInsets.fromLTRB(
                  AppSizes.pw20,
                  AppSizes.ph16,
                  AppSizes.pw20,
                  0,
                ),
                child: Row(
                  children: [
                    for (final type in [
                      FollowListType.followers,
                      FollowListType.following,
                    ])
                      Flexible(child: _tab(type)),
                  ],
                ),
              ),
            Expanded(
              child: IndexedStack(
                index: types.indexOf(_selected),
                children: [
                  for (final type in types)
                    BlocProvider.value(
                      key: ValueKey(type),
                      value: _lists[type]!,
                      child: RefreshUsersOnUnblock(child: _content(type)),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _content(FollowListType type) => Builder(
    builder: (context) => BlocBuilder<FollowUsersCubit, FollowUsersState>(
      builder: (context, state) {
        final cubit = context.read<FollowUsersCubit>();
        if (state.status == FollowUsersStatus.loading ||
            state.status == FollowUsersStatus.initial) {
          return const PeopleSkeleton();
        }
        if (state.status == FollowUsersStatus.failure) {
          return ErrorRetryView(
            message: state.error!.message,
            onRetry: cubit.load,
          );
        }
        return BlocBuilder<BlockCubit, BlockState>(
          builder: (context, block) => BlocBuilder<FollowCubit, FollowState>(
            builder: (context, follow) {
              final users = state.users
                  .where(
                    (user) =>
                        !block.isBlocked(user.id, fallback: user.isBlocked) &&
                        (type != FollowListType.suggested ||
                            !(follow.following[user.id] ?? user.isFollowing)),
                  )
                  .toList();
              final refreshing = _refreshes.containsKey(type);
              final canRemove = _canRemove;
              return Stack(
                children: [
                  RefreshIndicator.noSpinner(
                    onRefresh: () => _refresh(type),
                    child: NotificationListener<ScrollNotification>(
                      onNotification: (event) {
                        if (event.metrics.extentAfter < 300) cubit.more();
                        return false;
                      },
                      child: CustomScrollView(
                        key: PageStorageKey(('connections', type)),
                        physics: const AlwaysScrollableScrollPhysics(),
                        slivers: [
                          if (state.error != null)
                            SliverToBoxAdapter(
                              child: ErrorRetryView(
                                message: state.error!.message,
                                onRetry: cubit.load,
                              ),
                            ),
                          if (users.isEmpty &&
                              state.error == null &&
                              !state.refreshing)
                            SliverFillRemaining(
                              hasScrollBody: false,
                              child: _empty(type),
                            ),
                          SliverPadding(
                            padding: EdgeInsets.fromLTRB(
                              AppSizes.pw20,
                              AppSizes.ph14,
                              AppSizes.pw20,
                              0,
                            ),
                            sliver: SliverList.builder(
                              itemCount: users.length,
                              itemBuilder: (_, index) => FollowUserTile(
                                key: ValueKey(users[index].id),
                                user: users[index],
                                listType: type,
                                onRemove:
                                    type == FollowListType.followers &&
                                        canRemove
                                    ? () => _removeFollower(users[index])
                                    : null,
                              ),
                            ),
                          ),
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: EdgeInsets.only(bottom: AppSizes.ph24),
                              child: Column(
                                children: [
                                  if (state.loadingMore && !refreshing)
                                    TravibeLoadingIndicator(size: AppSizes.w30),
                                  if (state.paginationError != null)
                                    ErrorRetryView(
                                      message: state.paginationError!.message,
                                      onRetry: () => cubit.more(retry: true),
                                    ),
                                  if (state.hasMore &&
                                      !state.loadingMore &&
                                      !state.refreshing &&
                                      state.paginationError == null)
                                    TextButton(
                                      onPressed: cubit.more,
                                      child: const Text('Load more'),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (refreshing)
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      child: IgnorePointer(
                        child: Center(
                          child: TravibeLoadingIndicator(
                            size: AppSizes.w30,
                            semanticsLabel: 'Refreshing people',
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        );
      },
    ),
  );

  Widget _tab(FollowListType type) {
    final selected = _selected == type;
    final label = _tabLabel(type);
    return Padding(
      padding: EdgeInsetsDirectional.only(end: AppSizes.pw24),
      child: InkWell(
        key: ValueKey('follow-tab-${type.name}'),
        onTap: () => setState(() => _selected = type),
        child: IntrinsicWidth(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: EdgeInsets.symmetric(horizontal: AppSizes.pw12),
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: AppSizes.sp16,
                    color: selected
                        ? DarkColors.whiteColor
                        : DarkColors.greyColor,
                    fontWeight: selected ? FontWeight.w500 : FontWeight.w400,
                  ),
                ),
              ),
              SizedBox(height: AppSizes.h10),
              Container(
                height: AppSizes.h2,
                color: selected ? DarkColors.whiteColor : Colors.transparent,
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _tabLabel(FollowListType type) {
    final label = type == FollowListType.followers ? 'Followers' : 'Following';
    final count =
        _lists[type]?.state.total ??
        (type == FollowListType.followers
            ? widget.followersCount
            : widget.followingCount);
    return count == null ? label : '$label ($count)';
  }

  Widget _empty(FollowListType type) => ProfileEmptyState(
    asset: 'assets/images/profile/emptypic.svg',
    title: switch (type) {
      FollowListType.followers => 'No followers yet',
      FollowListType.following => 'You don’t follow anyone yet.',
      _ => 'No people yet',
    },
    description: switch (type) {
      FollowListType.followers =>
        'Your travel community is just getting started',
      FollowListType.following =>
        'Discover travelers and start building your travel community',
      _ => 'Discover travelers in Buddies.',
    },
    actionLabel: type == FollowListType.following ? 'Explore People' : null,
    onAction: type == FollowListType.following ? _explore : null,
  );
}
