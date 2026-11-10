import 'package:travibe/features/chats/widgets/chat_reverb_host.dart';
import 'package:travibe/features/chats/screens/chat_navigation.dart';
import 'package:travibe/features/chats/screens/chats_screen.dart';
import 'package:travibe/features/home/widgets/home_loading_skeleton.dart';
import 'package:travibe/core/notifications/push_notifications_host.dart';
import 'package:travibe/features/search/data/search_repo.dart';
import 'package:travibe/core/constants/app_sizes.dart';
import 'package:travibe/core/widgets/travibe_loading_indicator.dart';
import 'package:travibe/features/stories/screens/story_viewer_screen.dart';
import 'package:travibe/features/stories/data/story_model.dart';
import 'package:travibe/features/stories/cubit/stories_cubit.dart';
import 'package:travibe/features/stories/data/stories_repo.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/features/home/cubit/post_activity_cubit.dart';
import 'package:travibe/features/saved/cubit/saves_cubit.dart';
import 'package:travibe/features/comments/screens/comments_screen.dart';
import 'package:travibe/features/block/cubit/block_cubit.dart';
import 'package:travibe/features/block/widgets/block_user_button.dart';
import 'package:travibe/features/home/cubit/hidden_posts_cubit.dart';
import 'package:travibe/features/home/widgets/post_options_sheet.dart';
import 'dart:async';
import 'package:travibe/features/follow/cubit/follow_cubit.dart';
import 'package:travibe/features/follow/widgets/follow_action_builder.dart';
import 'package:flutter/material.dart';
import 'package:travibe/features/stories/cubit/story_likes_cubit.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:travibe/features/home/cubit/home_account_cubit.dart';
import 'package:travibe/features/likes/cubit/likes_cubit.dart';
import 'package:travibe/features/likes/data/like_model.dart';
import 'package:travibe/features/shares/cubit/shares_cubit.dart';
import 'package:travibe/features/shares/data/shares_repo.dart';
import 'package:travibe/features/shares/data/send_post_repo.dart';
import 'package:travibe/features/shares/widgets/send_post_sheet.dart';
import 'package:travibe/features/home/data/home_account_repo.dart';
import 'package:travibe/features/home/widgets/following_empty_state.dart';
import 'package:travibe/features/follow/cubit/follow_users_cubit.dart';
import 'package:travibe/features/follow/data/follow_repo.dart';
import 'package:travibe/features/follow/screens/follow_users_screen.dart';
import 'package:travibe/core/utils/formatters.dart';
import 'package:travibe/core/widgets/error_retry_view.dart';
import 'package:travibe/core/widgets/post_card.dart';
import 'package:travibe/features/home/cubit/posts_cubit.dart';
import 'package:travibe/features/home/data/post_model.dart';
import 'package:travibe/features/home/data/posts_repo.dart';
import 'package:travibe/features/home/widgets/home_stories.dart';
import 'package:travibe/features/stories/widgets/story_entry.dart';
import 'package:travibe/features/home/widgets/home_tabs.dart';
import 'package:travibe/features/home/widgets/home_top_bar.dart';
import 'package:travibe/features/home/widgets/pinned_tabs_delegate.dart';
import 'package:travibe/features/home/widgets/suggested_users_section.dart';
import 'package:travibe/features/home/widgets/trending_destinations_section.dart';
import 'package:travibe/features/search/screens/search_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({
    super.key,
    this.postsRepo,
    this.publicationSignal,
    this.refreshSignal,
    this.accountRepo,
    this.sharesRepo,
    this.storiesRepo,
    this.searchRepo,
  });

  final PostsRepo? postsRepo;
  final Listenable? publicationSignal;
  final Listenable? refreshSignal;
  final HomeAccountRepo? accountRepo;
  final SharesRepo? sharesRepo;
  final StoriesRepo? storiesRepo;
  final SearchRepo? searchRepo;

  @override
  Widget build(BuildContext context) {
    return _HomeView(
      postsRepo: postsRepo,
      publicationSignal: publicationSignal,
      refreshSignal: refreshSignal,
      accountRepo: accountRepo,
      sharesRepo: sharesRepo,
      storiesRepo: storiesRepo,
      searchRepo: searchRepo,
    );
  }
}

class _HomeView extends StatefulWidget {
  const _HomeView({
    this.postsRepo,
    this.publicationSignal,
    this.refreshSignal,
    this.accountRepo,
    this.sharesRepo,
    this.storiesRepo,
    this.searchRepo,
  });

  final PostsRepo? postsRepo;
  final Listenable? publicationSignal;
  final Listenable? refreshSignal;
  final HomeAccountRepo? accountRepo;
  final SharesRepo? sharesRepo;
  final StoriesRepo? storiesRepo;
  final SearchRepo? searchRepo;

  @override
  State<_HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends State<_HomeView> {
  final ScrollController _scrollController = ScrollController();
  int _selectedTab = 0; // 0 = Explore, 1 = Following
  late final List<PostsCubit> _feeds;
  late final LikesCubit _likes;
  late final bool _ownsLikes;
  late final SavesCubit _saves;
  late final bool _ownsSaves;
  late final SharesCubit _shares;
  late final bool _ownsShares;
  late final bool _ownsHidden;
  PostActivityCubit? _activity;
  bool _openingShare = false;
  bool _openingChats = false;

  Future<void> _openChats() async {
    if (_openingChats || !PreferencesManager().hasSession) return;
    _openingChats = true;
    try {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => chatRouteScope(context, const ChatsScreen()),
        ),
      );
    } finally {
      _openingChats = false;
      if (mounted) {
        unawaited(
          ChatReverbScope.unreadOf(context)?.refresh() ?? Future.value(),
        );
      }
    }
  }

  bool _openingStoryViewer = false;
  late final HiddenPostsCubit _hiddenPosts;
  late final HomeAccountCubit _account;
  late final FollowUsersCubit _suggestions;
  StreamSubscription<FollowState>? _followSubscription;
  StreamSubscription<BlockState>? _blockSubscription;
  int _unblockRevision = 0;
  bool _refreshingFollowing = false;
  bool _followingDirty = false;
  late int _followRevision;
  PostsCubit get _activeFeed => _feeds[_selectedTab];

  final _feedOffsets = [0.0, 0.0];

  void _switchFeed(int index) {
    if (index == _selectedTab) return;
    if (_scrollController.hasClients) {
      _feedOffsets[_selectedTab] = _scrollController.offset;
    }
    setState(() => _selectedTab = index);
    if (index == 1 && _followingDirty) {
      _refreshFollowing();
    } else if (_activeFeed.state is PostsInitial) {
      _activeFeed.loadPosts();
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _selectedTab != index || !_scrollController.hasClients) {
        return;
      }
      _scrollController.jumpTo(
        _feedOffsets[index].clamp(
          0.0,
          _scrollController.position.maxScrollExtent,
        ),
      );
    });
  }

  final _explicitRefreshes = <PostsCubit, Future<void>>{};

  void _onHomeRetap() => unawaited(_refreshFromUser());

  Future<void> _refreshFromUser({bool refreshAncillary = false}) {
    if (!mounted) return Future.value();
    final feed = _activeFeed;
    final pending = _explicitRefreshes[feed];
    if (pending != null) return pending;
    final session = _storySession.sessionRevision;
    final request = feed.refresh();
    setState(() {
      _explicitRefreshes[feed] = request;
    });
    // Pull-to-refresh retains existing auxiliary refreshes, but their completion
    // must not delay removal of the feed's indicator.
    if (refreshAncillary) {
      unawaited(_stories.refresh());
      unawaited(_account.load(force: true));
      unawaited(_suggestions.load());
    }
    return request.whenComplete(() {
      if (mounted &&
          session == _storySession.sessionRevision &&
          identical(_explicitRefreshes[feed], request)) {
        setState(() {
          _explicitRefreshes.remove(feed);
        });
      }
    });
  }

  late final StoriesCubit _stories;
  late final StoryLikesCubit _storyLikes;
  final _storySession = PreferencesManager();
  late int _storyOwnerSession;

  void _onStorySession() {
    final revision = _storySession.sessionRevision;
    // Hide previous-account owner metadata immediately; the StoriesCubit
    // independently clears its collection and invalidates all pending pages.
    if (mounted) {
      setState(() {
        _storyOwnerSession = -1;
        _explicitRefreshes.clear();
        _feedOffsets.fillRange(0, _feedOffsets.length, 0);
      });
    }
    _account.load(force: true).then((_) {
      if (mounted &&
          revision == _storySession.sessionRevision &&
          _storySession.hasSession &&
          _account.state.status == HomeAccountStatus.loaded) {
        setState(() => _storyOwnerSession = revision);
      }
    });
  }

  final List<TrendingDestination> _trendingDestinations = const [
    TrendingDestination(
      name: 'Bali, Indonesia',
      postsCount: '1.3K Posts',
      image: 'assets/images/posts/Rectangle 37.png',
    ),
    TrendingDestination(
      name: 'Bali, Indonesia',
      postsCount: '1.3K Posts',
      image: 'assets/images/posts/Rectangle 37.png',
    ),
    TrendingDestination(
      name: 'Bali, Indonesia',
      postsCount: '1.3K Posts',
      image: 'assets/images/posts/Rectangle 37.png',
    ),
  ];

  @override
  void initState() {
    super.initState();
    final postsRepo = widget.postsRepo ?? PostsRepo();
    _ownsLikes = context.read<LikesCubit?>() == null;
    _likes = context.read<LikesCubit?>() ?? LikesCubit();
    _ownsSaves = context.read<SavesCubit?>() == null;
    _saves = context.read<SavesCubit?>() ?? SavesCubit(repo: postsRepo);
    _account = HomeAccountCubit(repo: widget.accountRepo)..load();
    final sharesRepo = widget.sharesRepo ?? SharesRepo();
    _ownsShares =
        widget.sharesRepo != null || context.read<SharesCubit?>() == null;
    _activity = context.read<PostActivityCubit?>();
    _shares = _ownsShares
        ? SharesCubit(
            repo: sharesRepo,
            currentUserId: () async {
              final id = int.tryParse(_account.state.account?.id ?? '');
              return id ?? await sharesRepo.currentUserId();
            },
          )
        : context.read<SharesCubit>();
    _suggestions = FollowUsersCubit(
      type: FollowListType.suggested,
      repo: context.read<FollowCubit>().repo,
    )..load();
    _feeds = [
      PostsCubit(
        feed: FeedType.explore,
        postsRepo: postsRepo,
        likes: _likes,
        shares: _shares,
        saves: _saves,
        activity: _activity,
      ),
      PostsCubit(
        feed: FeedType.following,
        postsRepo: postsRepo,
        likes: _likes,
        shares: _shares,
        saves: _saves,
        activity: _activity,
      ),
    ];
    _ownsHidden = context.read<HiddenPostsCubit?>() == null;
    _hiddenPosts =
        context.read<HiddenPostsCubit?>() ??
        HiddenPostsCubit(repo: postsRepo, feeds: _feeds);
    if (!_ownsHidden) _hiddenPosts.registerFeeds(_feeds);
    final blocks = context.read<BlockCubit>();
    _storyOwnerSession = _storySession.hasSession
        ? _storySession.sessionRevision
        : -1;
    _storySession.addListener(_onStorySession);
    _stories = StoriesCubit(repo: widget.storiesRepo, blocks: blocks)..load();
    _storyLikes = StoryLikesCubit(repo: _stories.repo);
    _unblockRevision = blocks.state.unblockRevision;
    for (final feed in _feeds) {
      feed.setBlockedUsers(blocks.state.blockedIds);
    }
    _blockSubscription = blocks.stream.listen((state) {
      for (final feed in _feeds) {
        feed.setBlockedUsers(state.blockedIds);
      }
      if (state.unblockRevision != _unblockRevision) {
        _unblockRevision = state.unblockRevision;
        for (final feed in _feeds) {
          unawaited(feed.refreshAfterBlockChange());
        }
      }
    });
    final follow = context.read<FollowCubit>();
    _followRevision = follow.state.revision;
    _followSubscription = follow.stream.listen((state) {
      if (state.revision == _followRevision) return;
      _followRevision = state.revision;
      _account.load(force: true);
      _followingDirty = true;
      if (_feeds[1].state is! PostsInitial) _refreshFollowing();
    });
    widget.publicationSignal?.addListener(_onPostPublished);
    widget.refreshSignal?.addListener(_onHomeRetap);
    _activeFeed.loadPosts();
    _scrollController.addListener(_onScroll);
  }

  Future<void> _openStoryViewer(List<StoryGroup> groups, int authorId) async {
    if (_openingStoryViewer || !_storySession.hasSession) return;
    _openingStoryViewer = true;
    final blocks = context.read<BlockCubit>();
    final follow = context.read<FollowCubit>();
    final revision = _storySession.sessionRevision;
    var viewed = false;
    var viewerClosed = false;
    final currentUserId = _storyOwnerSession == revision
        ? int.tryParse(_account.state.account?.id ?? '')
        : null;
    try {
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => StoryViewerScreen(
            groups: List.unmodifiable(groups),
            initialAuthorId: authorId,
            repo: _stories.repo,
            likes: _storyLikes,
            blocks: blocks,
            follow: follow,
            currentUserId: currentUserId,
            onViewed: (id, count) {
              if (mounted && _storySession.sessionRevision == revision) {
                if (viewerClosed) {
                  unawaited(_stories.refresh());
                  return;
                }
                viewed = true;
                _stories.confirmedView(id, count);
              }
            },
            onDeleted: (id) {
              if (mounted && _storySession.sessionRevision == revision) {
                _stories.confirmedDelete(id);
              }
            },
          ),
        ),
      );
    } finally {
      viewerClosed = true;
      _openingStoryViewer = false;
      if (viewed && mounted && _storySession.sessionRevision == revision) {
        unawaited(_stories.refresh());
      }
    }
  }

  void _onPostPublished() {
    for (final feed in _feeds) {
      unawaited(feed.refreshAfterPublication());
    }
  }

  @override
  void didUpdateWidget(covariant _HomeView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshSignal != widget.refreshSignal) {
      oldWidget.refreshSignal?.removeListener(_onHomeRetap);
      widget.refreshSignal?.addListener(_onHomeRetap);
    }
    if (oldWidget.publicationSignal != widget.publicationSignal) {
      oldWidget.publicationSignal?.removeListener(_onPostPublished);
      widget.publicationSignal?.addListener(_onPostPublished);
    }
  }

  Future<void> _refreshFollowing() async {
    if (_refreshingFollowing) return;
    _refreshingFollowing = true;
    try {
      while (_followingDirty && mounted) {
        // Wait for a pre-mutation page-one request before fetching fresh data.
        await _feeds[1].pendingLoad;
        if (!mounted) return;
        _followingDirty = false;
        await _feeds[1].refresh();
      }
    } finally {
      _refreshingFollowing = false;
    }
  }

  @override
  void dispose() {
    _storySession.removeListener(_onStorySession);
    _stories.close();
    _storyLikes.close();
    widget.publicationSignal?.removeListener(_onPostPublished);
    widget.refreshSignal?.removeListener(_onHomeRetap);
    _explicitRefreshes.clear();
    _followSubscription?.cancel();
    _blockSubscription?.cancel();
    _hiddenPosts.unregisterFeeds(_feeds);
    if (_ownsHidden) _hiddenPosts.close();
    _account.close();
    if (_ownsLikes) _likes.close();
    if (_ownsSaves) _saves.close();
    if (_ownsShares) _shares.close();
    _suggestions.close();
    for (final feed in _feeds) {
      feed.close();
    }
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _showPostOptions(PostModel post) async {
    if (_hiddenPosts.state.pending.contains(post.id)) return;
    final blocks = context.read<BlockCubit>();
    if (blocks.state.pending.contains(post.user.id)) return;
    final action = await PostOptionsSheet.show(
      context,
      actions: const {PostOptionAction.hidePost, PostOptionAction.blockUser},
    );
    if (!mounted) return;
    if (action == PostOptionAction.hidePost) {
      await _setPostHidden(post.id, true);
    } else if (action == PostOptionAction.blockUser) {
      await confirmBlockChange(
        context,
        post.user.id,
        blocked: true,
        name: post.user.name,
      );
    }
  }

  Future<void> _setPostHidden(String postId, bool hidden) async {
    final error = await _hiddenPosts.setHidden(postId, hidden);
    if (!mounted) return;
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.message),
          action: SnackBarAction(
            label: 'Retry',
            onPressed: () => _setPostHidden(postId, hidden),
          ),
        ),
      );
    } else if (_hiddenPosts.state.hidden.contains(postId) == hidden &&
        !_hiddenPosts.state.pending.contains(postId)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(hidden ? 'Post hidden' : 'Post unhidden'),
          action: hidden
              ? SnackBarAction(
                  label: 'Undo',
                  onPressed: () => _setPostHidden(postId, false),
                )
              : null,
        ),
      );
    }
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.positions.last;
    if (position.outOfRange || position.pixels <= 0) return;
    if (position.pixels >= position.maxScrollExtent - 400) {
      _activeFeed.loadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: LayoutBuilder(
            builder: (context, _) => Stack(
              fit: StackFit.expand,
              children: [
                RefreshIndicator.noSpinner(
                  onRefresh: () => _refreshFromUser(refreshAncillary: true),
                  notificationPredicate: (notification) =>
                      notification.depth == 0 &&
                      notification.metrics.axis == Axis.vertical,
                  child: CustomScrollView(
                    physics: const BouncingScrollPhysics(
                      parent: AlwaysScrollableScrollPhysics(),
                    ),
                    controller: _scrollController,
                    slivers: [
                      SliverToBoxAdapter(
                        child: Column(
                          children: [
                            SizedBox(height: AppSizes.adaptiveHeight(20)),
                            BlocBuilder<HomeAccountCubit, HomeAccountState>(
                              bloc: _account,
                              builder: (context, state) => HomeTopBar(
                                name: state.account?.name,
                                onMessagesTap: _openChats,
                                onNotificationsTap: () =>
                                    PushNotificationsScope.openInbox(context),
                              ),
                            ),
                            SizedBox(height: AppSizes.adaptiveHeight(20)),
                            BlocBuilder<HomeAccountCubit, HomeAccountState>(
                              bloc: _account,
                              builder: (context, accountState) {
                                final owner =
                                    _storyOwnerSession ==
                                        _storySession.sessionRevision
                                    ? accountState.account
                                    : null;
                                return StoryEntry(
                                  avatarUrl: owner?.avatarUrl,
                                  storiesRepo: _stories.repo,
                                  onPublished: _stories.refresh,
                                  builder: (context, onAddStory) =>
                                      BlocBuilder<StoriesCubit, StoriesState>(
                                        bloc: _stories,
                                        builder: (context, state) =>
                                            HomeStories(
                                              stories: state.groups,
                                              currentUserId: int.tryParse(
                                                owner?.id ?? '',
                                              ),
                                              avatarUrl: owner?.avatarUrl,
                                              onAddStory: onAddStory,
                                              onViewStory: _openStoryViewer,
                                              loading: state.loading,
                                              loadingMore: state.loadingMore,
                                              hasMore: state.hasMore,
                                              error: state.error?.message,
                                              onRetry: _stories.refresh,
                                              onLoadMore: _stories.loadMore,
                                            ),
                                      ),
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                      SliverPersistentHeader(
                        pinned: true,
                        delegate: PinnedTabsDelegate(
                          height: HomeTabs.preferredHeight(context),
                          child: HomeTabs(
                            selectedIndex: _selectedTab,
                            onTabSelected: _switchFeed,
                            onSearchTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => MultiBlocProvider(
                                    providers: [
                                      BlocProvider.value(
                                        value: context.read<FollowCubit>(),
                                      ),
                                      BlocProvider.value(
                                        value: context.read<BlockCubit>(),
                                      ),
                                    ],
                                    child: SearchScreen(
                                      repo: widget.searchRepo,
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                      BlocBuilder<PostsCubit, PostsState>(
                        key: const ValueKey('home-feed-content'),
                        bloc: _activeFeed,
                        builder: (context, state) {
                          if (state is PostsFailure) {
                            return SliverFillRemaining(
                              hasScrollBody: false,
                              child: ErrorRetryView(
                                message: state.errorMessage,
                                onRetry: () => _activeFeed.loadPosts(),
                              ),
                            );
                          }

                          if (state is PostsLoaded) {
                            if (state.posts.isEmpty &&
                                state.refreshError != null) {
                              return SliverFillRemaining(
                                hasScrollBody: false,
                                child: ErrorRetryView(
                                  message: state.refreshError!.message,
                                  onRetry: _refreshFromUser,
                                ),
                              );
                            }
                            if (state.posts.isEmpty &&
                                state.paginationError != null) {
                              return SliverFillRemaining(
                                hasScrollBody: false,
                                child: ErrorRetryView(
                                  message: state.paginationError!.message,
                                  onRetry: () =>
                                      _activeFeed.loadMore(retry: true),
                                ),
                              );
                            }
                            if (_selectedTab == 1) {
                              return _followingSliver(state);
                            }
                            if (state.posts.isEmpty) {
                              return SliverToBoxAdapter(
                                child: Column(
                                  children: [
                                    _noPosts(state),
                                    _homeSuggestions(),
                                    SizedBox(
                                      height: AppSizes.adaptiveHeight(100),
                                    ),
                                  ],
                                ),
                              );
                            }
                            return SliverPadding(
                              padding: EdgeInsets.symmetric(
                                horizontal: AppSizes.adaptiveWidth(10),
                              ),
                              sliver: SliverList(
                                delegate: SliverChildListDelegate(
                                  _buildFeed(state),
                                ),
                              ),
                            );
                          }

                          return const SliverToBoxAdapter(
                            child: HomeFeedSkeleton(),
                          );
                        },
                      ),
                    ],
                  ),
                ),
                _loadingOverlay(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _loadingOverlay() => BlocBuilder<PostsCubit, PostsState>(
    bloc: _activeFeed,
    builder: (context, state) {
      if (!_explicitRefreshes.containsKey(_activeFeed)) {
        return const SizedBox.shrink();
      }
      // The enclosing SafeArea puts this floating overlay below system UI.
      // Positioned contributes no height to the header, tabs or post list.
      return const Positioned(
        top: 0,
        left: 0,
        right: 0,
        child: IgnorePointer(
          child: Center(
            child: TravibeLoadingIndicator(
              key: ValueKey('home-top-loading'),
              size: 30,
              semanticsLabel: 'Loading posts',
            ),
          ),
        ),
      );
    },
  );

  void _explorePeople() =>
      FollowUsersScreen.open(context, type: FollowListType.suggested);

  Widget _homeSuggestions({bool inFeed = false}) => Padding(
    key: const ValueKey('home-suggestions'),
    padding: EdgeInsets.symmetric(
      horizontal: AppSizes.adaptiveWidth(inFeed ? 10 : 20),
    ),
    child: BlocBuilder<HomeAccountCubit, HomeAccountState>(
      bloc: _account,
      builder: (context, state) {
        if (state.account == null) {
          if (state.status == HomeAccountStatus.failure) {
            return ErrorRetryView(
              message: state.error!.message,
              onRetry: _account.load,
            );
          }
          return const SizedBox.shrink();
        }
        return SuggestedUsersSection(
          showLoadingIndicators: false,
          compact: true,
          currentUserId: state.account!.id,
          cubit: _suggestions,
        );
      },
    ),
  );

  Widget _followingSliver(
    PostsLoaded posts,
  ) => BlocBuilder<HomeAccountCubit, HomeAccountState>(
    bloc: _account,
    builder: (context, account) {
      if (posts.posts.isNotEmpty) {
        // The following endpoint also includes own posts: keep those visible below
        // the zero-relationships introduction instead of discarding their data.
        return SliverPadding(
          padding: EdgeInsets.symmetric(horizontal: AppSizes.adaptiveWidth(10)),
          sliver: SliverList(
            delegate: SliverChildListDelegate(
              _buildFeed(
                posts,
                showFollowingIntro:
                    account.followsNobody &&
                    !posts.isRefreshing &&
                    !posts.isLoadingMore &&
                    posts.refreshError == null &&
                    posts.paginationError == null,
              ),
            ),
          ),
        );
      }
      if (account.status == HomeAccountStatus.loading) {
        return const SliverFillRemaining(
          hasScrollBody: false,
          child: SizedBox.shrink(),
        );
      }
      if (!account.hasVerifiedCount) {
        return SliverFillRemaining(
          hasScrollBody: false,
          child: ErrorRetryView(
            message:
                account.error?.message ??
                'Unable to load your following count. Please try again.',
            onRetry: () => _account.load(force: true),
          ),
        );
      }
      return SliverFillRemaining(
        hasScrollBody: false,
        child: account.followsNobody
            ? FollowingEmptyState(onExplorePeople: _explorePeople)
            : Center(child: _noPosts(posts, following: true)),
      );
    },
  );

  Widget _noPosts(PostsLoaded state, {bool following = false}) => Padding(
    padding: EdgeInsets.symmetric(
      horizontal: AppSizes.adaptiveWidth(24),
      vertical: AppSizes.adaptiveHeight(40),
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'No posts yet',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white70,
            fontSize: AppSizes.adaptiveFont(16),
          ),
        ),
        if (following) ...[
          SizedBox(height: AppSizes.adaptiveHeight(8)),
          Text(
            'New posts from people you follow will appear here.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white54,
              fontSize: AppSizes.adaptiveFont(14),
              height: 1.5,
            ),
          ),
        ],
        if (state.hasMore)
          TextButton(onPressed: _activeFeed.loadMore, child: Text('Load more')),
      ],
    ),
  );

  List<Widget> _buildFeed(
    PostsLoaded state, {
    bool showFollowingIntro = false,
  }) {
    final posts = state.posts;
    // Suggested users after the 2nd post, trending after the 4th
    // (or after the last post if the feed is shorter than that).
    final suggestedAt = posts.length > 1 ? 1 : posts.length - 1;
    final trendingAt = posts.length > 3 ? 3 : posts.length - 1;

    final items = <Widget>[
      SizedBox(height: AppSizes.adaptiveHeight(16)),
      if (showFollowingIntro)
        FollowingEmptyState(onExplorePeople: _explorePeople),
    ];
    if (state.refreshError != null) {
      items.add(
        ErrorRetryView(
          message: state.refreshError!.message,
          onRetry: _refreshFromUser,
        ),
      );
    }

    for (var i = 0; i < posts.length; i++) {
      items.add(_buildPostCard(posts[i]));

      if (i == suggestedAt) {
        items.add(_homeSuggestions(inFeed: true));
        items.add(SizedBox(height: AppSizes.adaptiveHeight(20)));
      }
      if (i == trendingAt) {
        items.add(
          TrendingDestinationsSection(
            destinations: _trendingDestinations,
            onSeeAllTap: () {},
          ),
        );
        items.add(SizedBox(height: AppSizes.adaptiveHeight(20)));
      }
    }

    if (state.isLoadingMore && !_explicitRefreshes.containsKey(_activeFeed)) {
      items.add(
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 16),
          child: Center(
            child: TravibeLoadingIndicator(
              size: 32,
              semanticsLabel: 'Loading more posts',
            ),
          ),
        ),
      );
    }

    if (state.paginationError != null) {
      items.add(
        ErrorRetryView(
          message: state.paginationError!.message,
          onRetry: () => _activeFeed.loadMore(retry: true),
        ),
      );
    }

    items.add(SizedBox(height: AppSizes.adaptiveHeight(100)));
    return items;
  }

  Future<void> _openComments(PostModel post) => CommentsScreen.open(
    context,
    postId: int.parse(post.id),
    initialCount: post.commentsCount,
    likes: _likes,
    commentsDisabled: post.commentsDisabled,
    onCountChanged: (count) {
      if (!mounted) return;
      for (final feed in _feeds) {
        feed.setCommentsCount(post.id, count);
      }
    },
    onSyncError: (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    },
  );

  Future<void> _openShare(PostModel post) async {
    if (_openingShare) return;
    final id = int.tryParse(post.id);
    if (id == null || id < 1 || post.visibility != 'public') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Only public posts can be shared.')),
      );
      return;
    }
    _openingShare = true;
    try {
      await SendPostSheet.show(
        context,
        postText: post.content?.trim().isNotEmpty == true
            ? post.content!
            : 'A post on Travibe.',
        repo: SendPostRepo(discovery: context.read<FollowCubit>().repo),
      );
    } finally {
      _openingShare = false;
    }
  }

  Widget _buildPostCard(PostModel post) {
    final mediaUrls = post.media.map((m) => m.displayUrl).toList();
    final postId = int.tryParse(post.id);
    final target = postId == null ? null : LikeTarget.post(postId);

    return BlocBuilder<HomeAccountCubit, HomeAccountState>(
      key: ValueKey('home-post-${post.id}'),
      bloc: _account,
      builder: (context, account) => Padding(
        padding: EdgeInsets.only(bottom: AppSizes.adaptiveHeight(16)),
        child: FollowActionBuilder(
          userId: post.user.id,
          initialFollowing: post.user.isFollowing,
          builder: (context, following, pending, onToggle) =>
              BlocBuilder<HiddenPostsCubit, HiddenPostsState>(
                bloc: _hiddenPosts,
                builder: (context, hiddenState) =>
                    BlocBuilder<LikesCubit, LikesState>(
                      bloc: _likes,
                      builder: (context, likeState) {
                        final value = target == null
                            ? null
                            : likeState.values[target];
                        return BlocBuilder<SharesCubit, SharesState>(
                          bloc: _shares,
                          builder: (context, sharesState) {
                            final share = postId == null
                                ? null
                                : sharesState.posts[postId];
                            return BlocBuilder<SavesCubit, SavesState>(
                              bloc: _saves,
                              builder: (context, savesState) => PostCard(
                                responsive: true,
                                homePresentation: true,
                                postId: post.id,
                                authorId: post.user.id,
                                currentUserId:
                                    _storyOwnerSession ==
                                        _storySession.sessionRevision
                                    ? account.account?.id
                                    : null,
                                currentUserSessionRevision: _storyOwnerSession,
                                isSaved:
                                    savesState.values[post.id] ?? post.isSaved,
                                isSavePending: savesState.pending.contains(
                                  post.id,
                                ),
                                onSaveTap: () async {
                                  final error = await _saves.toggle(post);
                                  if (error != null && context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text(error.message)),
                                    );
                                  }
                                },
                                name: post.user.name,
                                avatar: post.user.avatarUrl,
                                time: timeAgo(post.createdAt),
                                text: post.content ?? '',
                                image: mediaUrls.length == 1
                                    ? mediaUrls.first
                                    : null,
                                images: mediaUrls.length > 1 ? mediaUrls : null,
                                likes: formatCount(
                                  value?.count ?? post.likesCount,
                                ),
                                isLiked: value?.isLiked ?? post.isLiked,
                                isLikePending: value?.pending == true,
                                onLikeTap: target == null
                                    ? null
                                    : () async {
                                        final error = await _activeFeed
                                            .toggleLike(post);
                                        if (error != null && context.mounted) {
                                          ScaffoldMessenger.of(
                                            context,
                                          ).showSnackBar(
                                            SnackBar(
                                              content: Text(error.message),
                                            ),
                                          );
                                        }
                                      },
                                comments: formatCount(post.commentsCount),
                                onCommentsTap: () => _openComments(post),
                                shares: formatCount(
                                  share?.count ?? post.sharesCount,
                                ),
                                isSharePending: share?.pending == true,
                                onShareTap: () => _openShare(post),
                                showFollowButton: true,
                                neutralFollowButton: true,
                                isFollowing: following,
                                isFollowPending: pending,
                                onFollowTap: post.user.isBlocked
                                    ? null
                                    : onToggle,
                                onMoreTap: hiddenState.pending.contains(post.id)
                                    ? null
                                    : () => _showPostOptions(post),
                              ),
                            );
                          },
                        );
                      },
                    ),
              ),
        ),
      ),
    );
  }
}
