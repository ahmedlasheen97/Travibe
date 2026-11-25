import 'package:travibe/core/widgets/top_glow_background.dart';
import 'package:travibe/features/stories/widgets/open_story_viewer.dart';
import 'package:travibe/features/home/screens/post_screen.dart';
import 'package:travibe/features/likes/widgets/liked_by_sheet.dart';
import 'package:travibe/features/chats/widgets/chat_reverb_host.dart';
import 'package:travibe/features/chats/screens/chat_navigation.dart';
import 'package:travibe/features/chats/screens/chats_screen.dart';
import 'package:travibe/features/home/widgets/home_loading_skeleton.dart';
import 'package:travibe/core/notifications/push_notifications_host.dart';
import 'package:travibe/features/search/data/search_repo.dart';
import 'package:travibe/core/constants/app_sizes.dart';
import 'package:travibe/core/widgets/travibe_loading_indicator.dart';
import 'package:travibe/core/widgets/travibe_toast.dart';
import 'package:travibe/core/widgets/lazy_keyed_sliver_list.dart';
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
import 'package:travibe/features/home/widgets/post_report_flow.dart';
import 'package:travibe/features/home/widgets/own_post_actions.dart';
import 'package:travibe/core/utils/viewer_identity.dart';
import 'package:travibe/features/profile/cubit/current_user_cubit.dart';
import 'dart:async';
import 'package:travibe/features/follow/cubit/follow_cubit.dart';
import 'package:travibe/features/follow/widgets/follow_action_builder.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:travibe/core/navigation/bottom_nav_visibility.dart';
import 'package:travibe/features/stories/cubit/story_likes_cubit.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:travibe/features/home/cubit/home_account_cubit.dart';
import 'package:travibe/features/likes/cubit/likes_cubit.dart';
import 'package:travibe/features/likes/data/like_model.dart';
import 'package:travibe/features/shares/data/send_post_repo.dart';
import 'package:travibe/features/shares/widgets/send_post_sheet.dart';
import 'package:travibe/features/home/data/home_account_repo.dart';
import 'package:travibe/features/home/widgets/following_empty_state.dart';
import 'package:travibe/features/follow/cubit/follow_users_cubit.dart';
import 'package:travibe/features/follow/data/follow_repo.dart';
import 'package:travibe/features/follow/screens/follow_users_screen.dart';
import 'package:travibe/core/utils/formatters.dart';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/core/network/reconnect_monitor.dart';
import 'package:travibe/core/widgets/image_retry_signal.dart';
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
import 'package:travibe/features/search/screens/search_screen.dart';
import 'package:travibe/features/notifications/screens/notification_navigation.dart';
import 'package:travibe/features/stories/cubit/story_upload_cubit.dart';

/// Home's single shared error toast (sticky key and copy).
abstract final class HomeErrorToast {
  static const key = 'home-error';
  static const offlineMessage = 'No internet connection';
  static const failureMessage = "Couldn't load. Try again.";
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({
    super.key,
    this.postsRepo,
    this.publicationSignal,
    this.storyPublicationSignal,
    this.refreshSignal,
    this.accountRepo,
    this.storiesRepo,
    this.searchRepo,
    this.reconnectMonitor,
  });

  final PostsRepo? postsRepo;
  final Listenable? publicationSignal;

  /// Fires when a background Story upload is published (Root).
  final Listenable? storyPublicationSignal;
  final Listenable? refreshSignal;
  final HomeAccountRepo? accountRepo;
  final StoriesRepo? storiesRepo;
  final SearchRepo? searchRepo;

  /// Reconnect signal driving quiet retries while Home shows its error toast.
  final ReconnectMonitor? reconnectMonitor;

  @override
  Widget build(BuildContext context) {
    return _HomeView(
      postsRepo: postsRepo,
      publicationSignal: publicationSignal,
      storyPublicationSignal: storyPublicationSignal,
      refreshSignal: refreshSignal,
      accountRepo: accountRepo,
      storiesRepo: storiesRepo,
      searchRepo: searchRepo,
      reconnectMonitor: reconnectMonitor,
    );
  }
}

class _HomeView extends StatefulWidget {
  const _HomeView({
    this.postsRepo,
    this.publicationSignal,
    this.storyPublicationSignal,
    this.refreshSignal,
    this.accountRepo,
    this.storiesRepo,
    this.searchRepo,
    this.reconnectMonitor,
  });

  final PostsRepo? postsRepo;
  final Listenable? publicationSignal;

  /// Fires when a background Story upload is published (Root).
  final Listenable? storyPublicationSignal;
  final Listenable? refreshSignal;
  final HomeAccountRepo? accountRepo;
  final StoriesRepo? storiesRepo;
  final SearchRepo? searchRepo;

  /// Reconnect signal driving quiet retries while Home shows its error toast.
  final ReconnectMonitor? reconnectMonitor;

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

  // One sticky error toast for the whole of Home (feed, Stories, account,
  // suggestions): "No internet connection" or a generic failure, with Refresh.
  // No section renders inline error/retry text. While shown, quiet retries
  // run on reconnect, periodic probes and app resume.
  final List<StreamSubscription<Object?>> _errorSubscriptions = [];
  TravibeToastController? _toasts;
  late final ReconnectMonitor _reconnect;
  AppLifecycleListener? _lifecycle;
  bool _homeError = false;
  String? _errorMessage;

  List<ApiError> _homeFailures() {
    final feed = _activeFeed.state;
    final suggestions = _suggestions.state;
    final account = _account.state;
    return [
      if (feed is PostsFailure) feed.error,
      if (feed is PostsLoaded) ...[?feed.refreshError, ?feed.paginationError],
      ?_stories.state.error,
      if (account.status == HomeAccountStatus.failure) ?account.error,
      ?suggestions.error,
      ?suggestions.paginationError,
    ];
  }

  bool _retrying() {
    final feed = _activeFeed.state;
    final suggestions = _suggestions.state;
    return feed is PostsLoading ||
        feed is PostsInitial ||
        (feed is PostsLoaded && (feed.isRefreshing || feed.isLoadingMore)) ||
        _stories.state.loading ||
        _stories.state.loadingMore ||
        _account.state.status == HomeAccountStatus.loading ||
        suggestions.status == FollowUsersStatus.loading ||
        suggestions.refreshing ||
        suggestions.loadingMore;
  }

  void _syncHomeError() {
    if (!mounted) return;
    final failures = _homeFailures();
    // Keep the toast through a retry until it resolves.
    final show = failures.isNotEmpty || (_homeError && _retrying());
    final message = failures.isEmpty
        ? _errorMessage
        : failures.any((error) => error.isConnectionError)
        ? HomeErrorToast.offlineMessage
        : HomeErrorToast.failureMessage;
    if (show == _homeError && message == _errorMessage) return;
    final recovered = _homeError && !show;
    setState(() {
      _homeError = show;
      _errorMessage = show ? message : null;
    });
    if (show) {
      _toasts?.setSticky(
        HomeErrorToast.key,
        TravibeToastData.error(
          message ?? HomeErrorToast.failureMessage,
          actionLabel: 'Refresh',
          onAction: () => unawaited(_retryAll()),
        ),
      );
      _syncReconnect();
    } else {
      _clearHomeError();
      // Images that failed while offline reload once Home recovers.
      if (recovered) ImageRetrySignal.instance.bump();
    }
  }

  /// The reconnect monitor runs while Home shows its error toast or any post
  /// image is waiting to retry (image-only failures show no toast).
  void _syncReconnect() {
    if (mounted &&
        (_homeError || ImageRetrySignal.instance.failedCount.value > 0)) {
      _reconnect.start(_onReconnect);
    } else {
      _reconnect.stop();
    }
  }

  void _onReconnect() {
    if (!mounted) return;
    if (_homeError) {
      _retryQuietly(); // also retries images
    } else {
      ImageRetrySignal.instance.bump();
    }
  }

  void _clearHomeError() {
    _syncReconnect();
    _toasts?.setSticky(HomeErrorToast.key, null);
  }

  /// Refresh: retries everything on Home.
  Future<void> _retryAll() {
    ImageRetrySignal.instance.bump(manual: true);
    return _refreshFromUser(refreshAncillary: true);
  }

  /// Reconnect/probe/resume: retries only the sections that failed.
  void _retryQuietly() {
    if (!mounted || !_homeError) return;
    ImageRetrySignal.instance.bump();
    final feed = _activeFeed.state;
    if (feed is PostsFailure ||
        (feed is PostsLoaded && feed.refreshError != null)) {
      unawaited(_activeFeed.refresh());
    } else if (feed is PostsLoaded && feed.paginationError != null) {
      unawaited(_activeFeed.loadMore(retry: true));
    }
    if (_stories.state.error != null) unawaited(_stories.refresh());
    if (_account.state.status == HomeAccountStatus.failure) {
      unawaited(_account.load(force: true));
    }
    final suggestions = _suggestions.state;
    if (suggestions.paginationError != null &&
        suggestions.status == FollowUsersStatus.loaded) {
      unawaited(_suggestions.more(retry: true));
    } else if (suggestions.error != null) {
      unawaited(_suggestions.load(force: true));
    }
  }

  void _switchFeed(int index) {
    if (index == _selectedTab) return;
    if (_scrollController.hasClients) {
      _feedOffsets[_selectedTab] = _scrollController.offset;
    }
    setState(() => _selectedTab = index);
    _syncHomeError();
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
      unawaited(_suggestions.load(force: true));
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
  late final bool _ownsStories, _ownsStoryLikes;
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

  @override
  void initState() {
    super.initState();
    final postsRepo = widget.postsRepo ?? PostsRepo();
    _ownsLikes = context.read<LikesCubit?>() == null;
    _likes = context.read<LikesCubit?>() ?? LikesCubit();
    _ownsSaves = context.read<SavesCubit?>() == null;
    _saves = context.read<SavesCubit?>() ?? SavesCubit(repo: postsRepo);
    _account = HomeAccountCubit(repo: widget.accountRepo)..load();
    _activity = context.read<PostActivityCubit?>();
    _suggestions = FollowUsersCubit(
      type: FollowListType.suggested,
      repo: context.read<FollowCubit>().repo,
    )..load();
    _feeds = [
      PostsCubit(
        feed: FeedType.explore,
        postsRepo: postsRepo,
        likes: _likes,
        saves: _saves,
        activity: _activity,
      ),
      PostsCubit(
        feed: FeedType.following,
        postsRepo: postsRepo,
        likes: _likes,
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
    // Root shares one Stories source with Profile; standalone Home owns one.
    final sharedStories = context.read<StoriesCubit?>();
    _ownsStories = sharedStories == null;
    _stories =
        sharedStories ?? StoriesCubit(repo: widget.storiesRepo, blocks: blocks);
    unawaited(_stories.load());
    // The "You" picture comes from the shared current user; make sure it is
    // loading even if its first load failed (load() de-duplicates).
    final currentUser = context.read<CurrentUserCubit?>();
    if (currentUser != null &&
        currentUser.state.profile == null &&
        !currentUser.state.loading) {
      unawaited(currentUser.load());
    }
    final sharedLikes = context.read<StoryLikesCubit?>();
    _ownsStoryLikes = sharedLikes == null;
    _storyLikes = sharedLikes ?? StoryLikesCubit(repo: _stories.repo);
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
    widget.storyPublicationSignal?.addListener(_onStoryUploaded);
    widget.refreshSignal?.addListener(_onHomeRetap);
    _toasts = TravibeToastScope.maybeOf(context);
    _reconnect = widget.reconnectMonitor ?? ReconnectMonitor();
    ImageRetrySignal.instance.failedCount.addListener(_syncReconnect);
    for (final Stream<Object?> source in [
      ..._feeds.map((feed) => feed.stream),
      _stories.stream,
      _account.stream,
      _suggestions.stream,
    ]) {
      _errorSubscriptions.add(source.listen((_) => _syncHomeError()));
    }
    _lifecycle = AppLifecycleListener(onResume: _retryQuietly);
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncHomeError());
    _activeFeed.loadPosts();
    _scrollController.addListener(_onScroll);
  }

  /// Same opener as Profile; the row's [groups] already follow its order.
  Future<void> _openStoryViewer(List<StoryGroup> groups, int authorId) =>
      openStoriesOf(
        context,
        authorId: authorId,
        stories: _stories,
        likes: _storyLikes,
        fallbackOwnerId: _account.state.account?.id,
        fallbackSession: _storyOwnerSession,
      );

  /// Runs before the editor pops, so the toast is timed to the refresh end.
  Future<void> _onStoryPublished() async {
    try {
      await _stories.refresh();
    } finally {
      if (mounted) {
        TravibeToast.show(
          context,
          const TravibeToastData.success('Story published successfully'),
        );
      }
    }
  }

  /// Root already shows the success toast for background uploads.
  void _onStoryUploaded() => unawaited(_stories.refresh());

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
    if (oldWidget.storyPublicationSignal != widget.storyPublicationSignal) {
      oldWidget.storyPublicationSignal?.removeListener(_onStoryUploaded);
      widget.storyPublicationSignal?.addListener(_onStoryUploaded);
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
    if (_ownsStories) _stories.close();
    if (_ownsStoryLikes) _storyLikes.close();
    widget.publicationSignal?.removeListener(_onPostPublished);
    widget.storyPublicationSignal?.removeListener(_onStoryUploaded);
    widget.refreshSignal?.removeListener(_onHomeRetap);
    _explicitRefreshes.clear();
    _followSubscription?.cancel();
    _blockSubscription?.cancel();
    for (final subscription in _errorSubscriptions) {
      subscription.cancel();
    }
    _lifecycle?.dispose();
    ImageRetrySignal.instance.failedCount.removeListener(_syncReconnect);
    _reconnect.stop();
    _toasts?.setSticky(HomeErrorToast.key, null);
    if (widget.reconnectMonitor == null) _reconnect.dispose();
    _hiddenPosts.unregisterFeeds(_feeds);
    if (_ownsHidden) _hiddenPosts.close();
    _account.close();
    if (_ownsLikes) _likes.close();
    if (_ownsSaves) _saves.close();
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
    // Compare the author with the signed-in user; never assume ownership.
    final own = isViewer(
      context,
      post.userId.isNotEmpty ? post.userId : post.user.id,
      fallbackId: _account.state.account?.id,
      fallbackSession: _storyOwnerSession,
    );
    final feed = _activeFeed;
    final action = await PostOptionsSheet.show(
      context,
      actions: own ? ownPostActions : otherPostActions,
      commentsDisabled: post.commentsDisabled,
    );
    if (!mounted || action == null) return;
    if (own) {
      await runOwnPostAction(context, action: action, post: post, feed: feed);
      return;
    }
    if (action == PostOptionAction.hidePost) {
      await _setPostHidden(post.id, true);
    } else if (action == PostOptionAction.notInterested) {
      await notInterestedFlow(context, postId: post.id, hidden: _hiddenPosts);
    } else if (action == PostOptionAction.report) {
      await reportPostFlow(context, postId: post.id, repo: _hiddenPosts.repo);
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
    final toast = TravibeToast.of(context);
    final error = await _hiddenPosts.setHidden(postId, hidden);
    if (!mounted) return;
    if (error != null) {
      toast.present(
        TravibeToastData.error(
          error.message,
          actionLabel: 'Retry',
          onAction: () => _setPostHidden(postId, hidden),
        ),
      );
    } else if (_hiddenPosts.state.hidden.contains(postId) == hidden &&
        !_hiddenPosts.state.pending.contains(postId)) {
      if (!hidden) return;
      toast.present(
        TravibeToastData.info(
          'Post hidden',
          actionLabel: 'Undo',
          onAction: () => _setPostHidden(postId, false),
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
    return TopGlowBackground(
      fadeOnScroll: true,
      child: SafeArea(
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
                    // Pull-to-refresh also retries capped images.
                    onRefresh: _retryAll,
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
                                  name:
                                      state.account?.name ??
                                      context
                                          .read<CurrentUserCubit?>()
                                          ?.state
                                          .profile
                                          ?.name,
                                  signedIn: _storySession.hasSession,
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
                                  return _ownAvatar(
                                    context,
                                    ownerId: owner?.id,
                                    fallback: owner?.avatarUrl,
                                    builder: (avatarUrl) => StoryEntry(
                                      avatarUrl: avatarUrl,
                                      storiesRepo: _stories.repo,
                                      onPublished: _onStoryPublished,
                                      onSubmit: context
                                          .read<StoryUploadCubit?>()
                                          ?.enqueue,
                                      builder: (context, onAddStory) =>
                                          BlocBuilder<
                                            StoriesCubit,
                                            StoriesState
                                          >(
                                            bloc: _stories,
                                            builder: (context, state) =>
                                                ValueListenableBuilder(
                                                  valueListenable:
                                                      PreferencesManager()
                                                          .storyStyle,
                                                  builder:
                                                      (
                                                        context,
                                                        style,
                                                        _,
                                                      ) => HomeStories(
                                                        style: style,
                                                        stories: state.groups,
                                                        currentUserId:
                                                            int.tryParse(
                                                              owner?.id ?? '',
                                                            ),
                                                        avatarUrl: avatarUrl,
                                                        onAddStory: onAddStory,
                                                        onViewStory:
                                                            _openStoryViewer,
                                                        loading: state.loading,
                                                        loadingMore:
                                                            state.loadingMore,
                                                        hasMore: state.hasMore,
                                                        onLoadMore:
                                                            _stories.loadMore,
                                                      ),
                                                ),
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
                                    // Root's shared cubits (follow, block,
                                    // likes, saves, hidden, activity) so
                                    // post results stay in sync with feeds.
                                    builder: (_) => notificationRouteScope(
                                      context,
                                      SearchScreen(repo: widget.searchRepo),
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
                          // A change inside one post (like, comment count)
                          // rebuilds only that card (see _buildPostCard).
                          buildWhen: (a, b) => !a.sameShapeAs(b),
                          builder: (context, state) {
                            // Figma: an empty feed under the error toast
                            // (never inline error text), kept while quiet
                            // retries are in flight.
                            final failedEmpty =
                                state is PostsFailure ||
                                (state is PostsLoaded &&
                                    state.posts.isEmpty &&
                                    (state.refreshError != null ||
                                        state.paginationError != null));
                            if (failedEmpty ||
                                (_homeError && state is! PostsLoaded)) {
                              return const SliverFillRemaining(
                                key: ValueKey('home-offline-feed'),
                                hasScrollBody: false,
                                child: SizedBox.shrink(),
                              );
                            }

                            if (state is PostsLoaded) {
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
                                sliver: _buildFeed(state),
                              );
                            }

                            return const SliverToBoxAdapter(
                              child: HomeFeedSkeleton(),
                            );
                          },
                        ),
                        SliverToBoxAdapter(
                          child: SizedBox(
                            height: BottomNavScope.bottomInsetOf(context),
                          ),
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
        // Failures surface only through Home's shared error toast.
        if (state.account == null) return const SizedBox.shrink();
        return SuggestedUsersSection(
          showLoadingIndicators: false,
          compact: true,
          hideErrors: true,
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
          sliver: _buildFeed(
            posts,
            showFollowingIntro:
                account.followsNobody &&
                !posts.isRefreshing &&
                !posts.isLoadingMore &&
                posts.refreshError == null &&
                posts.paginationError == null,
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
        // Failure is reported by Home's shared error toast.
        return const SliverFillRemaining(
          key: ValueKey('home-following-unavailable'),
          hasScrollBody: false,
          child: SizedBox.shrink(),
        );
      }
      return SliverFillRemaining(
        hasScrollBody: false,
        child: account.followsNobody
            // Close under the tabs, not centered in the remaining space.
            ? Align(
                alignment: Alignment.topCenter,
                child: Padding(
                  padding: EdgeInsets.only(
                    top: FollowingEmptyState.topGap - FollowingEmptyState.inset,
                  ),
                  child: FollowingEmptyState(onExplorePeople: _explorePeople),
                ),
              )
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

  /// The feed, built lazily: cards are created as they scroll into view.
  Widget _buildFeed(PostsLoaded state, {bool showFollowingIntro = false}) {
    final feed = _activeFeed;
    final posts = state.posts;
    // Suggested users after the 2nd post (or after the last post if the
    // feed is shorter than that).
    final suggestedAt = posts.length > 1 ? 1 : posts.length - 1;
    final suggestedAfter = suggestedAt < 0 ? null : posts[suggestedAt].id;

    return LazyKeyedSliverList(
      keyPrefix: 'home-feed-item-',
      ids: [for (final post in posts) post.id],
      itemBuilder: (context, id) {
        // Keyed on the card alone: the in-feed suggestions aren't part of it.
        final card = KeyedSubtree(
          key: ValueKey('home-post-$id'),
          child: _buildPostCard(id, feed),
        );
        if (id != suggestedAfter) return card;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            card,
            _homeSuggestions(inFeed: true),
            SizedBox(height: AppSizes.adaptiveHeight(20)),
          ],
        );
      },
      leading: [
        SizedBox(height: AppSizes.adaptiveHeight(16)),
        if (showFollowingIntro)
          FollowingEmptyState(onExplorePeople: _explorePeople),
      ],
      // Refresh/pagination errors are shown by Home's shared error handling
      // (_syncHomeError), not as rows in the feed.
      trailing: [
        if (state.isLoadingMore && !_explicitRefreshes.containsKey(feed))
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(
              child: TravibeLoadingIndicator(
                size: 32,
                semanticsLabel: 'Loading more posts',
              ),
            ),
          ),
        SizedBox(height: AppSizes.adaptiveHeight(100)),
      ],
    );
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
      TravibeToast.show(context, TravibeToastData.error(error.message));
    },
  );

  Future<void> _openShare(PostModel post) async {
    if (_openingShare) return;
    _openingShare = true;
    try {
      await SendPostSheet.show(
        context,
        post: post,
        repo: SendPostRepo(discovery: context.read<FollowCubit>().repo),
      );
    } finally {
      _openingShare = false;
    }
  }

  /// Home's "You" bubble shows the same picture as the Profile tab: the
  /// session-scoped [CurrentUserCubit] profile (Profile caches into it), so it
  /// updates as soon as that profile loads or the picture changes. It doesn't
  /// depend on the Home account having loaded. The cubit clears synchronously
  /// on account changes, so its profile always belongs to this session. Until
  /// it has loaded, the Home account's picture ([fallback]) is used, but only
  /// when that account is this session's ([ownerId] is null otherwise).
  Widget _ownAvatar(
    BuildContext context, {
    required String? ownerId,
    required String? fallback,
    required Widget Function(String? avatarUrl) builder,
  }) {
    final current = context.read<CurrentUserCubit?>();
    final home = ownerId == null ? null : fallback;
    if (current == null) {
      return builder(_logOwnAvatar(home, 'home-account (no CurrentUserCubit)'));
    }
    return BlocBuilder<CurrentUserCubit, CurrentUserState>(
      bloc: current,
      buildWhen: (a, b) =>
          a.profile?.id != b.profile?.id ||
          a.profile?.avatarUrl != b.profile?.avatarUrl,
      builder: (context, state) {
        final profile = state.profile;
        if (profile == null) {
          return builder(
            _logOwnAvatar(
              home,
              'home-account (current user ${state.loading ? 'loading' : 'not loaded'}, owner $ownerId)',
            ),
          );
        }
        final mine = profile.avatarUrl;
        return builder(
          _logOwnAvatar(
            mine == null || mine.isEmpty ? null : mine,
            'current-user ${profile.id}',
          ),
        );
      },
    );
  }

  String? _lastOwnAvatar;
  bool _ownAvatarLogged = false;

  /// Debug only: logs the "You" picture whenever the resolved URL changes.
  /// A no-op in profile/release builds (`kDebugMode` is a compile-time
  /// constant, so this branch is removed there).
  String? _logOwnAvatar(String? url, String source) {
    if (!kDebugMode) return url;
    if (!_ownAvatarLogged || url != _lastOwnAvatar) {
      debugPrint('[home-you-avatar] ${url ?? '(none)'} from $source');
    }
    _ownAvatarLogged = true;
    _lastOwnAvatar = url;
    return url;
  }

  /// One feed card. It rebuilds only when its own post, like, save or
  /// hide-pending state changes, never when another post is liked or saved.
  Widget _buildPostCard(String id, PostsCubit feed) =>
      BlocSelector<PostsCubit, PostsState, PostModel?>(
        bloc: feed,
        selector: (state) => state.postById(id),
        builder: (context, post) =>
            post == null ? const SizedBox.shrink() : _postCard(post),
      );

  Widget _postCard(PostModel post) {
    final mediaUrls = post.media.map((m) => m.displayUrl).toList();
    final postId = int.tryParse(post.id);
    final target = postId == null ? null : LikeTarget.post(postId);

    return BlocBuilder<HomeAccountCubit, HomeAccountState>(
      bloc: _account,
      builder: (context, account) => Padding(
        padding: EdgeInsets.only(bottom: AppSizes.adaptiveHeight(16)),
        child: FollowActionBuilder(
          userId: post.user.id,
          initialFollowing: post.user.isFollowing,
          initialRequested: post.user.followRequested,
          builder: (context, relation, pending, onToggle) =>
              BlocSelector<HiddenPostsCubit, HiddenPostsState, bool>(
                bloc: _hiddenPosts,
                selector: (hidden) => hidden.pending.contains(post.id),
                builder: (context, hidePending) =>
                    BlocSelector<LikesCubit, LikesState, (bool, int, bool)?>(
                      bloc: _likes,
                      selector: (likes) => switch (target == null
                          ? null
                          : likes.values[target]) {
                        final value? => (
                          value.isLiked,
                          value.count,
                          value.pending,
                        ),
                        null => null,
                      },
                      builder: (context, like) {
                        final value = like == null
                            ? null
                            : LikeValue(
                                isLiked: like.$1,
                                count: like.$2,
                                pending: like.$3,
                              );
                        return BlocSelector<
                          SavesCubit,
                          SavesState,
                          (bool?, bool)
                        >(
                          bloc: _saves,
                          selector: (saves) => (
                            saves.values[post.id],
                            saves.pending.contains(post.id),
                          ),
                          builder: (context, save) => PostCard(
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
                            isSaved: save.$1 ?? post.isSaved,
                            isSavePending: save.$2,
                            onSaveTap: () async {
                              final error = await _saves.toggle(post);
                              if (error != null && context.mounted) {
                                TravibeToast.show(
                                  context,
                                  TravibeToastData.error(error.message),
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
                            likes: formatCount(value?.count ?? post.likesCount),
                            onOpen: () => PostScreen.open(context, post: post),
                            onLikesCountTap: postId == null
                                ? null
                                : () => LikedBySheet.show(
                                    context,
                                    postId: postId,
                                    count: value?.count ?? post.likesCount,
                                  ),
                            isLiked: value?.isLiked ?? post.isLiked,
                            isLikePending: value?.pending == true,
                            onLikeTap: target == null
                                ? null
                                : () async {
                                    final error = await _activeFeed.toggleLike(
                                      post,
                                    );
                                    if (error != null && context.mounted) {
                                      TravibeToast.show(
                                        context,
                                        TravibeToastData.error(error.message),
                                      );
                                    }
                                  },
                            comments: formatCount(post.commentsCount),
                            onCommentsTap: () => _openComments(post),
                            onShareTap: () => _openShare(post),
                            showFollowButton: true,
                            neutralFollowButton: true,
                            isFollowing: relation.isFollowing,
                            isFollowRequested: relation.isRequested,
                            isFollowPending: pending,
                            onFollowTap: post.user.isBlocked ? null : onToggle,
                            onMoreTap: hidePending
                                ? null
                                : () => _showPostOptions(post),
                          ),
                        );
                      },
                    ),
              ),
        ),
      ),
    );
  }
}
