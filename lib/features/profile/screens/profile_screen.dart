import 'package:travibe/features/chats/data/chat_repository.dart';
import 'package:travibe/features/profile/widgets/other_profile_actions.dart';
import 'package:travibe/core/widgets/back_button_widget.dart';
import 'package:travibe/features/home/cubit/hidden_posts_cubit.dart';
import 'package:travibe/features/home/cubit/post_activity_cubit.dart';
import 'package:travibe/features/home/cubit/posts_cubit.dart';
import 'package:travibe/features/home/data/posts_repo.dart';
import 'package:travibe/features/profile/widgets/profile_posts_scope.dart';
import 'package:travibe/features/profile/widgets/profile_posts_sliver.dart';
import 'package:travibe/features/saved/cubit/saves_cubit.dart';
import 'package:travibe/features/saved/cubit/saved_posts_cubit.dart';
import 'package:travibe/features/saved/widgets/saved_posts_sliver.dart';
import 'package:travibe/features/likes/cubit/likes_cubit.dart';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/core/widgets/travibe_loading_indicator.dart';
import 'package:flutter/material.dart';
import 'package:travibe/core/navigation/bottom_nav_visibility.dart';
import 'package:travibe/features/profile/screens/edit_profile_screen.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:travibe/core/constants/app_sizes.dart';
import 'package:travibe/core/theme/dark_colors.dart';
import 'package:travibe/core/widgets/error_retry_view.dart';
import 'package:travibe/features/block/cubit/block_cubit.dart';
import 'package:travibe/features/follow/cubit/follow_cubit.dart';
import 'package:travibe/features/follow/screens/follow_users_screen.dart';
import 'package:travibe/features/follow/data/follow_repo.dart';
import 'package:travibe/features/profile/cubit/profile_cubit.dart';
import 'package:travibe/features/profile/cubit/current_user_cubit.dart';
import 'package:travibe/features/profile/data/profile_model.dart';
import 'package:travibe/features/profile/data/profile_repo.dart';
import 'package:travibe/features/profile/widgets/about_section.dart';
import 'package:travibe/features/profile/widgets/profile_action_buttons.dart';
import 'package:travibe/features/profile/widgets/profile_avatar.dart';
import 'package:travibe/features/profile/widgets/profile_header_info.dart';
import 'package:travibe/features/profile/widgets/profile_saved_sub_tabs.dart';
import 'package:travibe/features/profile/widgets/profile_shimmer.dart';
import 'package:travibe/features/profile/widgets/profile_stats.dart';
import 'package:travibe/features/profile/widgets/profile_tabs.dart';
import 'package:travibe/features/profile/widgets/profile_top_bar.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({
    super.key,
    this.userId,
    this.profileRepo,
    this.postsRepo,
    this.chatRepository,
    this.refreshSignal,
    this.onCreatePost,
    this.onExplorePeople,
  });

  /// Null loads the authenticated full profile; otherwise loads a public profile.
  final int? userId;
  final ProfileRepo? profileRepo;
  final PostsRepo? postsRepo;
  final ChatRepository? chatRepository;
  final ValueListenable<int>? refreshSignal;
  final VoidCallback? onCreatePost, onExplorePeople;

  static final _openProfiles = Expando<Set<int>>();

  /// Preserve Root's session controllers across Navigator routes.
  static Future<void> open(
    BuildContext context, {
    int? userId,
    ProfileRepo? profileRepo,
    PostsRepo? postsRepo,
  }) {
    final navigator = Navigator.of(context);
    final active = _openProfiles[navigator] ??= <int>{};
    final target = userId ?? -1;
    if (!active.add(target)) return Future.value();
    final current = context.read<CurrentUserCubit?>();
    final follow = context.read<FollowCubit?>();
    final block = context.read<BlockCubit?>();
    final saves = context.read<SavesCubit?>();
    final savedPosts = context.read<SavedPostsCubit?>();
    final likes = context.read<LikesCubit?>();
    final activity = context.read<PostActivityCubit?>();
    final hidden = context.read<HiddenPostsCubit?>();
    return navigator
        .push<void>(
          MaterialPageRoute(
            settings: RouteSettings(
              name: userId == null ? 'my-profile' : 'user-profile/$userId',
            ),
            builder: (_) {
              final screen = ProfileScreen(
                userId: userId,
                profileRepo: profileRepo,
                postsRepo: postsRepo,
              );
              if (current == null &&
                  follow == null &&
                  block == null &&
                  saves == null &&
                  savedPosts == null &&
                  likes == null &&
                  activity == null &&
                  hidden == null) {
                return screen;
              }
              return MultiBlocProvider(
                providers: [
                  if (current != null) BlocProvider.value(value: current),
                  if (saves != null) BlocProvider.value(value: saves),
                  if (savedPosts != null) BlocProvider.value(value: savedPosts),
                  if (likes != null) BlocProvider.value(value: likes),
                  if (activity != null) BlocProvider.value(value: activity),
                  if (hidden != null) BlocProvider.value(value: hidden),
                  if (follow != null) BlocProvider.value(value: follow),
                  if (block != null) BlocProvider.value(value: block),
                ],
                child: screen,
              );
            },
          ),
        )
        .whenComplete(() => active.remove(target));
  }

  @override
  Widget build(BuildContext context) {
    Widget profileFor(int? session) => BlocProvider<ProfileCubit>(
      key: ValueKey((userId, session)),
      create: (context) => ProfileCubit(
        profileRepo: profileRepo,
        userId: userId,
        currentUser: context.read<CurrentUserCubit?>(),
      )..loadProfile(),
      child: _ProfileView(
        postsRepo: postsRepo,
        chatRepository: chatRepository,
        refreshSignal: refreshSignal,
        onCreatePost: onCreatePost,
        onExplorePeople: onExplorePeople,
      ),
    );

    Widget withSaved(BuildContext context) {
      final profile = BlocBuilder<SavesCubit, SavesState>(
        buildWhen: (before, after) => before.session != after.session,
        builder: (_, state) => profileFor(state.session),
      );
      return userId != null || context.read<SavedPostsCubit?>() != null
          ? profile
          : BlocProvider<SavedPostsCubit>(
              create: (context) => SavedPostsCubit(
                saves: context.read<SavesCubit>(),
                blocks: context.read<BlockCubit?>(),
                activity: context.read<PostActivityCubit>(),
                likes: context.read<LikesCubit>(),
              ),
              child: profile,
            );
    }

    if (context.read<SavesCubit?>() != null &&
        context.read<LikesCubit?>() != null &&
        context.read<PostActivityCubit?>() != null &&
        context.read<HiddenPostsCubit?>() != null) {
      return withSaved(context);
    }
    return MultiBlocProvider(
      providers: [
        if (context.read<SavesCubit?>() == null)
          BlocProvider(create: (_) => SavesCubit(repo: postsRepo)),
        if (context.read<LikesCubit?>() == null)
          BlocProvider(create: (_) => LikesCubit()),
        if (context.read<PostActivityCubit?>() == null)
          BlocProvider(create: (_) => PostActivityCubit()),
        if (context.read<HiddenPostsCubit?>() == null)
          BlocProvider(
            create: (_) =>
                HiddenPostsCubit(repo: postsRepo ?? PostsRepo(), feeds: []),
          ),
      ],
      child: Builder(builder: withSaved),
    );
  }
}

class _ProfileView extends StatefulWidget {
  const _ProfileView({
    this.postsRepo,
    this.chatRepository,
    this.refreshSignal,
    this.onCreatePost,
    this.onExplorePeople,
  });
  final VoidCallback? onCreatePost, onExplorePeople;
  final ValueListenable<int>? refreshSignal;
  final PostsRepo? postsRepo;
  final ChatRepository? chatRepository;
  @override
  State<_ProfileView> createState() => _ProfileViewState();
}

class _ProfileViewState extends State<_ProfileView> {
  int _selectedTab = 0;
  int _savedSubTab = 0;
  StreamSubscription<FollowState>? _followSubscription;
  StreamSubscription<BlockState>? _blockSubscription;
  BlockCubit? _block;
  BuildContext? _contentContext;
  Future<void>? _refreshRequest;
  bool _refreshing = false;

  void _retap() {
    final content = _contentContext;
    if (content != null && content.mounted) unawaited(_refresh(content));
  }

  @override
  void didUpdateWidget(covariant _ProfileView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshSignal == widget.refreshSignal) return;
    oldWidget.refreshSignal?.removeListener(_retap);
    widget.refreshSignal?.addListener(_retap);
  }

  Future<void> _refresh(BuildContext content) {
    if (_refreshRequest != null) return _refreshRequest!;
    final profile = content.read<ProfileCubit>();
    if (profile.state is! ProfileLoaded) return Future.value();
    final session = PreferencesManager().sessionRevision;
    setState(() => _refreshing = true);
    final requests = <Future<void>>[
      // Join an already-running profile request rather than superseding it.
      profile.loadProfile(),
      if (_selectedTab == 0) content.read<PostsCubit>().refresh(),
      if (_selectedTab == 2 && _savedSubTab == 0 && profile.userId == null)
        content.read<SavedPostsCubit>().load(),
    ];
    final request = Future.wait(requests).then<void>((_) {});
    _refreshRequest = request;
    return request.whenComplete(() {
      if (!mounted || session != PreferencesManager().sessionRevision) return;
      _refreshRequest = null;
      setState(() => _refreshing = false);
    });
  }

  @override
  void initState() {
    super.initState();
    widget.refreshSignal?.addListener(_retap);
    final cubit = context.read<ProfileCubit>();
    final follow = context.read<FollowCubit?>();
    _block = context.read<BlockCubit?>();
    var followRevision = follow?.state.revision;
    _followSubscription = follow?.stream.listen((state) {
      if (state.revision == followRevision) return;
      followRevision = state.revision;
      if (_block?.state.blocked[cubit.userId?.toString()] != true) {
        cubit.refresh();
      }
    });
    final id = cubit.userId?.toString();
    if (id != null) {
      var blocked = _block?.state.blocked[id];
      if (blocked == true) cubit.publicProfileUnavailable();
      _blockSubscription = _block?.stream.listen((state) {
        final next = state.blocked[id];
        if (next == blocked) return;
        blocked = next;
        if (next == true) {
          cubit.publicProfileUnavailable();
        } else {
          cubit.refresh();
        }
      });
    }
  }

  @override
  void dispose() {
    widget.refreshSignal?.removeListener(_retap);
    _followSubscription?.cancel();
    _blockSubscription?.cancel();
    super.dispose();
  }

  Widget _unavailable() => ErrorRetryView(
    message: 'This profile is unavailable.',
    onRetry: () => context.read<ProfileCubit>().refresh(),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: DarkColors.backgroundColor,
    appBar: context.read<ProfileCubit>().userId == null
        ? null
        : AppBar(
            leading: Navigator.of(context).canPop()
                ? const BackButtonWidget()
                : null,
            centerTitle: true,
            title: const Text(
              'Profile',
              style: TextStyle(color: Colors.white, fontSize: 18),
            ),
            actions: [
              BlocBuilder<ProfileCubit, ProfileState>(
                builder: (context, state) =>
                    state is ProfileLoaded && state.profile.isMe != true
                    ? OtherProfileActions(
                        key: ValueKey(('profile-options', state.profile.id)),
                        profile: state.profile,
                        repository: widget.chatRepository,
                        optionsOnly: true,
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          ),
    body: SafeArea(
      // Inside Root the content runs under the hideable bottom bar.
      bottom: BottomNavScope.bottomInsetOf(context) == 0,
      child: Stack(
        children: [
          Column(
            children: [
              if (context.read<ProfileCubit>().userId == null) ...[
                SizedBox(height: AppSizes.h8),
                const ProfileTopBar(),
              ],
              Expanded(
                child: BlocBuilder<ProfileCubit, ProfileState>(
                  builder: (context, state) {
                    _contentContext = null;
                    final id = context.read<ProfileCubit>().userId?.toString();
                    if (state is ProfileUnavailable ||
                        (id != null && _block?.state.blocked[id] == true)) {
                      return _unavailable();
                    }
                    if (state is ProfileLoaded) {
                      final authorId =
                          context.read<ProfileCubit>().userId ??
                          int.tryParse(state.profile.id);
                      if (authorId == null || authorId < 1) {
                        return _unavailable();
                      }
                      return ProfilePostsScope(
                        key: ValueKey(authorId),
                        userId: authorId,
                        repo: widget.postsRepo,
                        builder: (context) {
                          _contentContext = context;
                          return RefreshIndicator.noSpinner(
                            onRefresh: () => _refresh(context),
                            child: _buildContent(state),
                          );
                        },
                      );
                    }
                    if (state is ProfileFailure) {
                      return ErrorRetryView(
                        message: state.errorMessage,
                        onRetry: () =>
                            context.read<ProfileCubit>().loadProfile(),
                      );
                    }
                    return const ProfileShimmer();
                  },
                ),
              ),
            ],
          ),
          if (_refreshing)
            Positioned(
              // Header is 8px + 44px. This uses its existing lower clearance
              // and the avatar's 20px gap; it reserves no layout height.
              top: context.read<ProfileCubit>().userId == null
                  ? AppSizes.h8 + 44 + AppSizes.h20 - 30
                  : 0,
              left: 0,
              right: 0,
              child: const IgnorePointer(
                child: Center(
                  child: TravibeLoadingIndicator(
                    key: ValueKey('profile-refresh-indicator'),
                    size: 30,
                    semanticsLabel: 'Refreshing profile',
                  ),
                ),
              ),
            ),
        ],
      ),
    ),
  );

  Widget _buildContent(ProfileLoaded state) {
    final profile = state.profile;
    final canOpenConnections =
        _block != null && context.read<FollowCubit?>() != null;
    final canViewSaved = context.read<ProfileCubit>().userId == null;
    final selected = !canViewSaved && _selectedTab == 2 ? 0 : _selectedTab;
    return CustomScrollView(
      key: const PageStorageKey('profile-content'),
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverToBoxAdapter(
          child: Column(
            children: [
              if (state.error != null)
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: [
                      Text(
                        state.error!.message,
                        style: const TextStyle(color: Colors.white70),
                      ),
                      TextButton(
                        onPressed: () => context.read<ProfileCubit>().refresh(),
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
              SizedBox(height: AppSizes.h20),
              ProfileAvatar(imageUrl: profile.avatarUrl),
              SizedBox(height: AppSizes.h16),
              ProfileHeaderInfo(
                name: profile.displayName,
                username: profile.username?.isNotEmpty == true
                    ? '@${profile.username}'
                    : '',
                bio: profile.bio ?? '',
              ),
              if (context.read<ProfileCubit>().userId != null &&
                  profile.isMe != true)
                _followsYou(profile),
              SizedBox(height: AppSizes.h20),
              ProfileStats(
                posts: profile.postsCount,
                followers: profile.followersCount,
                following: profile.followingCount,
                onFollowersTap: canOpenConnections
                    ? () => FollowUsersScreen.open(
                        context,
                        type: FollowListType.followers,
                        userId: profile.id,
                        username: profile.username,
                        followersCount: profile.followersCount,
                        followingCount: profile.followingCount,
                        onExplorePeople: widget.onExplorePeople,
                      )
                    : null,
                onFollowingTap: canOpenConnections
                    ? () => FollowUsersScreen.open(
                        context,
                        type: FollowListType.following,
                        userId: profile.id,
                        username: profile.username,
                        followersCount: profile.followersCount,
                        followingCount: profile.followingCount,
                        onExplorePeople: widget.onExplorePeople,
                      )
                    : null,
              ),
              SizedBox(height: AppSizes.h20),
              if (context.read<ProfileCubit>().userId == null)
                ProfileActionButtons(
                  onEdit: state.refreshing
                      ? null
                      : () => Navigator.of(context).push(
                          MaterialPageRoute<bool>(
                            builder: (_) => EditProfileScreen(
                              profile: profile,
                              owner: context.read<ProfileCubit>(),
                            ),
                          ),
                        ),
                ),
              if (context.read<ProfileCubit>().userId != null &&
                  profile.isMe != true)
                OtherProfileActions(
                  key: ValueKey(('profile-actions', profile.id)),
                  profile: profile,
                  repository: widget.chatRepository,
                ),
              SizedBox(height: AppSizes.h24),
              ProfileTabs(
                selectedIndex: selected,
                showSaved: canViewSaved,
                onTabSelected: (index) => setState(() => _selectedTab = index),
              ),
              SizedBox(height: AppSizes.h8),
              if (selected == 2)
                ProfileSavedSubTabs(
                  selectedIndex: _savedSubTab,
                  onTabSelected: (index) =>
                      setState(() => _savedSubTab = index),
                ),
            ],
          ),
        ),
        if (selected == 1)
          _buildAboutTab(profile)
        else if (selected == 2 && _savedSubTab == 0)
          SavedPostsSliver(showLoadingIndicators: !_refreshing)
        else if (selected == 0)
          ProfilePostsSliver(
            onCreatePost: widget.onCreatePost,
            showLoadingIndicators: !_refreshing,
            owner:
                context.read<ProfileCubit>().userId == null ||
                profile.isMe == true,
          )
        else
          _notLoaded('Saved hotels are not loaded yet.'),
        SliverToBoxAdapter(
          child: SizedBox(height: BottomNavScope.bottomInsetOf(context)),
        ),
      ],
    );
  }

  Widget _followsYou(ProfileModel profile) {
    final follow = context.read<FollowCubit?>();
    Widget badge(bool value) => value
        ? Padding(
            padding: const EdgeInsets.only(top: 8),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: const Color(0xFF3A2216),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                child: Text(
                  'Follows You',
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ),
            ),
          )
        : const SizedBox.shrink();
    return follow == null
        ? badge(profile.followsYou == true)
        : BlocBuilder<FollowCubit, FollowState>(
            builder: (_, state) => badge(
              state.followsYou[profile.id] ?? profile.followsYou == true,
            ),
          );
  }

  Widget _notLoaded(String message) => SliverPadding(
    padding: const EdgeInsets.fromLTRB(20, 24, 20, 100),
    sliver: SliverToBoxAdapter(
      child: Center(
        child: Text(message, style: const TextStyle(color: Colors.white70)),
      ),
    ),
  );

  // ---------------- About tab (real data) ----------------
  Widget _buildAboutTab(ProfileModel profile) {
    final location = profile.currentLocation;
    final bio = profile.bio;

    final sections = <Widget>[
      if ((profile.nationality ?? profile.nationalityCode)?.isNotEmpty == true)
        AboutSection(
          title: 'Nationality',
          child: Text(
            profile.nationality ?? profile.nationalityCode!,
            style: const TextStyle(color: Colors.white70, fontSize: 14),
          ),
        ),
      if (location != null)
        AboutSection(
          title: 'Location',
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.location_on_outlined,
                color: Colors.white54,
                size: 16,
              ),
              SizedBox(width: AppSizes.w4),
              Flexible(
                child: Text(
                  location,
                  style: const TextStyle(color: Colors.white70, fontSize: 14),
                ),
              ),
            ],
          ),
        ),
      if (profile.gender?.trim().isNotEmpty == true)
        AboutSection(
          title: 'Gender',
          child: Text(
            profile.gender!,
            style: const TextStyle(color: Colors.white70, fontSize: 14),
          ),
        ),
      if (bio != null && bio.trim().isNotEmpty)
        AboutSection(
          title: 'Bio',
          child: Text(
            bio,
            maxLines: 2,
            softWrap: true,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 14,
              height: 1.5,
            ),
          ),
        ),
      if (profile.languages.isNotEmpty)
        AboutSection(
          title: 'Languages',
          child: ChipsRow(items: profile.languages),
        ),
      if (profile.interests.isNotEmpty)
        AboutSection(
          title: 'Interests',
          child: ChipsRow(items: profile.interests),
        ),
      if (profile.travelStyles.isNotEmpty)
        AboutSection(
          title: 'Travel Style',
          child: ChipsRow(items: profile.travelStyles),
        ),
    ];

    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      sliver: SliverList(
        delegate: SliverChildListDelegate([
          SizedBox(height: AppSizes.h8),
          if (sections.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 24),
              child: Center(
                child: Text(
                  'No profile details to display',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.5),
                    fontSize: 14,
                  ),
                ),
              ),
            )
          else
            ...sections,
          SizedBox(height: AppSizes.h100),
        ]),
      ),
    );
  }
}
