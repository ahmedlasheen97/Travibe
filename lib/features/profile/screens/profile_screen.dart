import 'package:travibe/core/utils/viewer_identity.dart';
import 'package:travibe/features/stories/widgets/open_story_viewer.dart';
import 'package:travibe/features/stories/data/story_model.dart';
import 'package:travibe/features/stories/cubit/story_likes_cubit.dart';
import 'package:travibe/features/stories/cubit/stories_cubit.dart';
import 'package:travibe/core/widgets/travibe_toast.dart';
import 'package:travibe/core/widgets/options_sheet.dart';
import 'package:travibe/core/widgets/profile_picture_viewer.dart';
import 'package:travibe/features/stories/widgets/start_add_story.dart';
import 'package:travibe/features/stories/data/stories_repo.dart';
import 'package:travibe/features/stories/cubit/story_upload_cubit.dart';
import 'package:travibe/features/chats/data/chat_repository.dart';
import 'package:travibe/features/follow_requests/cubit/incoming_requests_cubit.dart';
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
import 'package:travibe/features/follow/widgets/follows_you_badge.dart';
import 'package:travibe/features/profile/widgets/profile_avatar.dart';
import 'package:travibe/features/profile/widgets/profile_header_info.dart';
import 'package:travibe/features/profile/widgets/profile_saved_sub_tabs.dart';
import 'package:travibe/features/profile/widgets/profile_shimmer.dart';
import 'package:travibe/features/profile/widgets/profile_stats.dart';
import 'package:travibe/features/profile/widgets/profile_tabs.dart';
import 'package:travibe/features/profile/widgets/follow_request_card.dart';
import 'package:travibe/features/profile/widgets/private_profile_locked.dart';
import 'package:travibe/features/profile/widgets/profile_top_bar.dart';
import 'package:travibe/features/shares/data/post_share_actions.dart';

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
    this.storiesRepo,
  });

  /// Null loads the authenticated full profile; otherwise loads a public profile.
  final int? userId;
  final ProfileRepo? profileRepo;
  final PostsRepo? postsRepo;
  final ChatRepository? chatRepository;
  final ValueListenable<int>? refreshSignal;
  final VoidCallback? onCreatePost, onExplorePeople;

  /// Used by my profile's "+" (add story) flow; defaults to the real repo.
  final StoriesRepo? storiesRepo;

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
    final incoming = context.read<IncomingRequestsCubit?>();
    final stories = context.read<StoriesCubit?>();
    final storyLikes = context.read<StoryLikesCubit?>();
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
                  hidden == null &&
                  incoming == null &&
                  stories == null &&
                  storyLikes == null) {
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
                  if (incoming != null) BlocProvider.value(value: incoming),
                  if (stories != null) BlocProvider.value(value: stories),
                  if (storyLikes != null) BlocProvider.value(value: storyLikes),
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
        storiesRepo: storiesRepo,
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
    this.storiesRepo,
  });
  final VoidCallback? onCreatePost, onExplorePeople;
  final StoriesRepo? storiesRepo;
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
  StreamSubscription<ProfileState>? _profileSubscription;
  StreamSubscription<BlockState>? _blockSubscription;
  StreamSubscription<StoryUploadState>? _storyUploadSubscription;
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
    final loaded = profile.state;
    if (loaded is! ProfileLoaded) return Future.value();
    final locked = profile.userId != null && loaded.profile.isLocked;
    final session = PreferencesManager().sessionRevision;
    setState(() => _refreshing = true);
    final requests = <Future<void>>[
      // Join an already-running profile request rather than superseding it.
      profile.loadProfile(),
      if (_selectedTab == 0 && !locked) content.read<PostsCubit>().refresh(),
      if (_selectedTab == 2 && _savedSubTab == 0 && profile.userId == null)
        content.read<SavedPostsCubit>().load(),
      // The shared Stories source: this profile's ring and Home's row.
      if (content.read<StoriesCubit?>() case final stories?) stories.refresh(),
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
    if (cubit.userId == null) {
      // A background Story upload (from Home or this profile) finished.
      _storyUploadSubscription = context
          .read<StoryUploadCubit?>()
          ?.stream
          .listen((state) {
            if (state is StoryUploadDone && !cubit.isClosed) cubit.refresh();
          });
    }
    var followRevision = follow?.state.revision;
    _followSubscription = follow?.stream.listen((state) {
      if (state.revision == followRevision) return;
      followRevision = state.revision;
      if (_block?.state.blocked[cubit.userId?.toString()] != true) {
        cubit.refresh();
      }
    });
    final id = cubit.userId?.toString();
    if (id != null && follow != null) {
      // Share the profile's confirmed relationship with every post card.
      void seed(ProfileState state) {
        if (state is! ProfileLoaded || state.profile.isMe == true) return;
        follow.seed(
          state.profile.id,
          following: state.profile.isFollowing,
          followsYou: state.profile.followsYou,
          requested: state.profile.followRequested,
        );
      }

      seed(cubit.state);
      _profileSubscription = cubit.stream.listen(seed);
    }
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
    _profileSubscription?.cancel();
    _blockSubscription?.cancel();
    _storyUploadSubscription?.cancel();
    super.dispose();
  }

  /// The picture, ringed (same as Home) while this user has an active Story I
  /// can see in the shared Stories source. Tapping it: my own with a story →
  /// sheet (View story / View profile picture); another user's with a story
  /// → their Stories; no story → the full-screen picture.
  Widget _avatar(ProfileModel profile) {
    final mine = context.read<ProfileCubit>().userId == null;
    Widget avatar(StoryGroup? group) => ProfileAvatar(
      imageUrl: profile.avatarUrl,
      stories: group?.stories ?? const [],
      onTap: _avatarTap(profile, group, mine: mine),
      onAddStory: mine ? () => _addStory(profile) : null,
    );
    final stories = context.read<StoriesCubit?>();
    if (stories == null) return avatar(null);
    final id = int.tryParse(profile.id);
    return BlocBuilder<StoriesCubit, StoriesState>(
      bloc: stories,
      builder: (_, _) => avatar(stories.groupOf(id)),
    );
  }

  VoidCallback? _avatarTap(
    ProfileModel profile,
    StoryGroup? group, {
    required bool mine,
  }) {
    final url = profile.avatarUrl;
    final picture = url == null || url.isEmpty
        ? null
        : () => openProfilePictureViewer(context, url);
    final story = group != null && group.stories.isNotEmpty
        ? () => _openStories(profile, group)
        : null;
    if (story == null) return picture;
    if (!mine) return story;
    return () => showOptionsSheet<void>(
      context,
      builder: (sheet) => OptionsSheetBody(
        children: [
          OptionSheetTile(
            key: const ValueKey('profile-view-story'),
            icon: optionSvg('assets/images/interactions/story.svg'),
            label: 'View story',
            onTap: () {
              Navigator.of(sheet).pop();
              story();
            },
          ),
          if (picture != null)
            OptionSheetTile(
              key: const ValueKey('profile-view-picture'),
              icon: optionSvg('assets/images/icons/profile-circle.svg'),
              label: 'View profile picture',
              onTap: () {
                Navigator.of(sheet).pop();
                picture();
              },
            ),
        ],
      ),
    );
  }

  Future<void> _openStories(ProfileModel profile, StoryGroup group) =>
      openStoryViewer(
        context,
        groups: [group],
        authorId: group.user.id,
        stories: context.read<StoriesCubit>(),
        likes: context.read<StoryLikesCubit?>(),
        currentUserId: int.tryParse(
          viewerUserId(
                context,
                fallbackId: context.read<ProfileCubit>().userId == null
                    ? profile.id
                    : null,
                fallbackSession: PreferencesManager().sessionRevision,
              ) ??
              '',
        ),
      );

  /// The same picker → editor → upload flow as Home, opened over Profile.
  /// With the app's upload queue, Root shows the toast and the listener in
  /// [initState] refreshes; otherwise the editor publishes and calls back.
  Future<void> _addStory(ProfileModel profile) => startAddStory(
    context,
    avatarUrl: profile.avatarUrl,
    storiesRepo: widget.storiesRepo,
    onPublished: () async {
      final cubit = context.read<ProfileCubit>();
      try {
        await cubit.refresh();
      } finally {
        if (mounted) {
          TravibeToast.show(
            context,
            const TravibeToastData.success('Story published successfully'),
          );
        }
      }
    },
  );

  Future<void> _shareMyProfile(Uri url, Rect origin) async {
    try {
      await PostShareActions(verifiedPostUri: url).moreOptions(origin);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to share your profile. Please try again.'),
        ),
      );
    }
  }

  Widget _unavailable() => ErrorRetryView(
    message: 'This profile is unavailable.',
    onRetry: () => context.read<ProfileCubit>().refresh(),
  );

  Widget _profileOptions() => BlocBuilder<ProfileCubit, ProfileState>(
    builder: (context, state) =>
        state is ProfileLoaded && state.profile.isMe != true
        ? OtherProfileActions(
            key: ValueKey(('profile-options', state.profile.id)),
            profile: state.profile,
            repository: widget.chatRepository,
            optionsOnly: true,
          )
        : const SizedBox.shrink(),
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
            title: Text(
              'Profile',
              style: TextStyle(color: Colors.white, fontSize: AppSizes.sp18),
            ),
            actions: [
              if (_block case final block?)
                BlocBuilder<BlockCubit, BlockState>(
                  bloc: block,
                  builder: (context, blocks) {
                    final id = context.read<ProfileCubit>().userId.toString();
                    // A blocked profile body is unavailable; keep ⋮ so the
                    // viewer can unblock from here.
                    return blocks.blocked[id] == true
                        ? BlockedProfileOptionsButton(
                            key: ValueKey(('profile-unblock', id)),
                            userId: id,
                          )
                        : _profileOptions();
                  },
                )
              else
                _profileOptions(),
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
                  ? AppSizes.h8 + AppSizes.h44 + AppSizes.h20 - AppSizes.w30
                  : 0,
              left: 0,
              right: 0,
              child: IgnorePointer(
                child: Center(
                  child: TravibeLoadingIndicator(
                    key: const ValueKey('profile-refresh-indicator'),
                    size: AppSizes.w30,
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
    final isOther =
        context.read<ProfileCubit>().userId != null && profile.isMe != true;
    // Private account I can't see: header and counts only (lists are 403).
    final locked = isOther && profile.isLocked;
    final connections = canOpenConnections && !locked;
    return CustomScrollView(
      key: const PageStorageKey('profile-content'),
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverToBoxAdapter(
          child: Column(
            children: [
              if (state.error != null)
                Padding(
                  padding: EdgeInsets.all(AppSizes.pw12),
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
              _avatar(profile),
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
                onFollowersTap: connections
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
                onFollowingTap: connections
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
              if (isOther) FollowRequestCard(userId: profile.id),
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
                  onShare: profile.url == null
                      ? null
                      : (origin) => _shareMyProfile(profile.url!, origin),
                ),
              if (context.read<ProfileCubit>().userId != null &&
                  profile.isMe != true)
                OtherProfileActions(
                  key: ValueKey(('profile-actions', profile.id)),
                  profile: profile,
                  repository: widget.chatRepository,
                ),
              SizedBox(height: AppSizes.h24),
              if (!locked) ...[
                ProfileTabs(
                  selectedIndex: selected,
                  showSaved: canViewSaved,
                  onTabSelected: (index) =>
                      setState(() => _selectedTab = index),
                ),
                SizedBox(height: AppSizes.h8),
              ],
              if (!locked && selected == 2)
                ProfileSavedSubTabs(
                  selectedIndex: _savedSubTab,
                  onTabSelected: (index) =>
                      setState(() => _savedSubTab = index),
                ),
            ],
          ),
        ),
        if (locked)
          const SliverToBoxAdapter(child: PrivateProfileLocked())
        else if (selected == 1)
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
            padding: EdgeInsets.only(top: AppSizes.ph8),
            child: const FollowsYouBadge(),
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
    padding: EdgeInsets.fromLTRB(
      AppSizes.pw20,
      AppSizes.ph24,
      AppSizes.pw20,
      AppSizes.ph100,
    ),
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
            style: TextStyle(color: Colors.white70, fontSize: AppSizes.sp14),
          ),
        ),
      if (location != null)
        AboutSection(
          title: 'Location',
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.location_on_outlined,
                color: Colors.white54,
                size: AppSizes.w16,
              ),
              SizedBox(width: AppSizes.w4),
              Flexible(
                child: Text(
                  location,
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: AppSizes.sp14,
                  ),
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
            style: TextStyle(color: Colors.white70, fontSize: AppSizes.sp14),
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
            style: TextStyle(
              color: Colors.white70,
              fontSize: AppSizes.sp14,
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
      padding: EdgeInsets.symmetric(horizontal: AppSizes.pw20),
      sliver: SliverList(
        delegate: SliverChildListDelegate([
          SizedBox(height: AppSizes.h8),
          if (sections.isEmpty)
            Padding(
              padding: EdgeInsets.only(top: AppSizes.ph24),
              child: Center(
                child: Text(
                  'No profile details to display',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.5),
                    fontSize: AppSizes.sp14,
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
