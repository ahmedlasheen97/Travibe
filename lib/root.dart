import 'package:travibe/features/chats/widgets/chat_reverb_host.dart';
import 'package:travibe/features/chats/data/chat_reverb_service.dart';
import 'package:travibe/features/chats/cubit/chat_unread_cubit.dart';
import 'dart:async';
import 'package:travibe/core/deeplinks/post_deep_links.dart';
import 'package:travibe/features/buddies/data/buddies_repo.dart';
import 'package:travibe/features/home/cubit/post_activity_cubit.dart';
import 'package:travibe/features/home/cubit/hidden_posts_cubit.dart';
import 'package:travibe/features/saved/cubit/saves_cubit.dart';
import 'package:travibe/features/saved/cubit/saved_posts_cubit.dart';
import 'package:travibe/features/likes/cubit/likes_cubit.dart';
import 'package:travibe/features/block/cubit/block_cubit.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:travibe/features/follow/cubit/follow_cubit.dart';
import 'package:travibe/features/follow/data/follow_repo.dart';
import 'package:flutter/material.dart';
import 'package:travibe/core/notifications/push_notifications_host.dart';
import 'package:travibe/core/navigation/bottom_nav_visibility.dart';
import 'package:flutter_svg/svg.dart';
import 'package:travibe/core/constants/app_sizes.dart';
import 'package:travibe/core/widgets/liquid_glass_bottom_nav.dart';
import 'package:travibe/features/buddies/screens/buddies_screen.dart';
import 'package:travibe/features/explore/screens/explore_screen.dart';
import 'package:travibe/features/home/screens/home_screen.dart';
import 'package:travibe/features/profile/screens/profile_screen.dart';
import 'package:travibe/features/profile/data/profile_repo.dart';
import 'package:travibe/features/create_post/screens/create_post_screen.dart';
import 'package:travibe/features/create_post/data/create_post_repo.dart';
import 'package:travibe/features/create_post/data/post_image_picker.dart';
import 'package:travibe/features/create_post/cubit/post_upload_cubit.dart';
import 'package:travibe/features/create_post/widgets/discard_post_dialog.dart';
import 'package:flutter/cupertino.dart' show CupertinoActivityIndicator;
import 'package:travibe/core/theme/dark_colors.dart';
import 'package:travibe/core/widgets/travibe_toast.dart';
import 'package:travibe/features/home/data/posts_repo.dart';
import 'package:travibe/features/home/data/home_account_repo.dart';
import 'package:travibe/features/stories/data/stories_repo.dart';

class Root extends StatefulWidget {
  const Root({
    super.key,
    this.createPostRepo,
    this.postsRepo,
    this.homeAccountRepo,
    this.followRepo,
    this.buddiesRepo,
    this.profileRepo,
    this.mediaUploads,
    this.postImagePicker,
    this.storiesRepo,
  });
  final CreatePostRepo? createPostRepo;
  final PostsRepo? postsRepo;
  final HomeAccountRepo? homeAccountRepo;
  final FollowRepo? followRepo;
  final BuddiesRepo? buddiesRepo;
  final ProfileRepo? profileRepo;
  final MediaUploadFactory? mediaUploads;
  final PostImagePicker? postImagePicker;
  final StoriesRepo? storiesRepo;

  @override
  State<Root> createState() => _RootState();
}

class _RootState extends State<Root> {
  PushNotificationsCoordinator? _push;
  PostDeepLinkCoordinator? _postLinks;
  ChatReverbService? _reverb;
  ChatUnreadCubit? _chatUnread;
  StreamSubscription<BlockState>? _reverbBlocks;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final unread = ChatReverbScope.unreadOf(context);
    if (!identical(unread, _chatUnread)) {
      _chatUnread?.detach(this);
      _chatUnread = unread;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && identical(unread, _chatUnread)) unread?.attach(this);
      });
    }
    final reverb = ChatReverbScope.maybeOf(context);
    if (!identical(_reverb, reverb)) {
      _reverb?.detach(this);
      unawaited(_reverbBlocks?.cancel() ?? Future.value());
      _reverb = reverb;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !identical(_reverb, reverb)) return;
        reverb?.blockedUsers({
          ..._blockCubit.state.blockedIds,
          ..._blockCubit.state.pending,
        });
        reverb?.attach(this);
      });
      _reverbBlocks = _blockCubit.stream.listen(
        (state) =>
            reverb?.blockedUsers({...state.blockedIds, ...state.pending}),
      );
    }
    final links = PostDeepLinksScope.maybeOf(context);
    if (!identical(links, _postLinks)) {
      _postLinks?.detach(this);
      _postLinks = links;
      // After the first frame, so the post opens above the Root shell.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && identical(links, _postLinks)) {
          links?.attach(this, context);
        }
      });
    }
    final next = PushNotificationsScope.maybeOf(context);
    if (identical(next, _push)) return;
    _push?.detach(this);
    _push = next;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && identical(next, _push)) {
        next?.attach(this, context, follow: _followCubit);
      }
    });
  }

  late final _followCubit = FollowCubit(repo: widget.followRepo);
  late final _saves = SavesCubit(repo: widget.postsRepo);
  late final _savedPosts = SavedPostsCubit(
    saves: _saves,
    blocks: _blockCubit,
    activity: _activity,
    likes: _likes,
  );
  final _likes = LikesCubit();
  final _activity = PostActivityCubit();
  late final _hidden = HiddenPostsCubit(
    repo: widget.postsRepo ?? PostsRepo(),
    feeds: [],
  );
  late final _postUploads = PostUploadCubit(
    repo: widget.createPostRepo,
    uploads: widget.mediaUploads,
  );
  final _publications = ValueNotifier<int>(0);
  final _homeRefreshes = ValueNotifier<int>(0);
  final _buddiesRefreshes = ValueNotifier<int>(0);
  final _profileRefreshes = ValueNotifier<int>(0);
  final Set<int> _visitedTabs = {0};
  bool _openingComposer = false;
  late final _blockCubit = BlockCubit(follow: _followCubit);

  @override
  void dispose() {
    _push?.detach(this);
    _postLinks?.detach(this);
    _reverb?.detach(this);
    _chatUnread?.detach(this);
    unawaited(_reverbBlocks?.cancel() ?? Future.value());
    _postUploads.close();
    _publications.dispose();
    _homeRefreshes.dispose();
    _buddiesRefreshes.dispose();
    _profileRefreshes.dispose();
    _navVisibility.dispose();
    _toasts.dispose();
    _savedPosts.close();
    _saves.close();
    _likes.close();
    _activity.close();
    _hidden.close();
    _blockCubit.close();
    _followCubit.close();
    super.dispose();
  }

  int _currentIndex = 0;
  final _navVisibility = BottomNavVisibility();
  final _toasts = TravibeToastController();

  late final List<Widget> screens = [
    HomeScreen(
      postsRepo: widget.postsRepo,
      publicationSignal: _publications,
      refreshSignal: _homeRefreshes,
      accountRepo: widget.homeAccountRepo,
      storiesRepo: widget.storiesRepo,
    ),
    ExploreScreen(),
    SizedBox(),
    BuddiesScreen(refreshSignal: _buddiesRefreshes, repo: widget.buddiesRepo),
    ProfileScreen(
      profileRepo: widget.profileRepo,
      postsRepo: widget.postsRepo,
      refreshSignal: _profileRefreshes,
      onCreatePost: _showCreateOptions,
      onExplorePeople: _explorePeople,
    ),
  ];

  final List<String> _outlineIcons = [
    'assets/images/home/home.svg',
    'assets/images/home/Compas.svg',
    '',
    'assets/images/home/profile-2user.svg',
    'assets/images/home/user.svg',
  ];

  final List<String> _filledIcons = [
    'assets/images/home/home2.svg',
    'assets/images/home/Compas2.svg',
    '',
    'assets/images/home/profile-2user2.svg',
    'assets/images/home/user2.svg',
  ];

  @override
  Widget build(BuildContext context) {
    final navHeight = LiquidGlassBottomNav.heightOf(context);
    final safeBottom = MediaQuery.viewPaddingOf(context).bottom;
    return MultiBlocProvider(
      providers: [
        BlocProvider.value(value: _saves),
        BlocProvider.value(value: _savedPosts),
        BlocProvider.value(value: _likes),
        BlocProvider.value(value: _activity),
        BlocProvider.value(value: _hidden),
        BlocProvider.value(value: _followCubit),
        BlocProvider.value(value: _blockCubit),
        BlocProvider.value(value: _postUploads),
      ],
      child: BlocListener<PostUploadCubit, PostUploadState>(
        listener: _onPostUpload,
        child: BottomNavScope(
          visibility: _navVisibility,
          barHeight: navHeight,
          child: TravibeToastScope(
            controller: _toasts,
            child: Scaffold(
              extendBody: true,
              body: Stack(
                children: [
                  NotificationListener<ScrollNotification>(
                    onNotification: _navVisibility.handleScroll,
                    // Fixed clearance: extendBody's animated inset would relayout
                    // the tabs on every frame of the slide.
                    child: Builder(
                      builder: (context) => MediaQuery(
                        data: MediaQuery.of(context).copyWith(
                          padding: MediaQuery.paddingOf(
                            context,
                          ).copyWith(bottom: navHeight),
                          viewPadding: MediaQuery.viewPaddingOf(
                            context,
                          ).copyWith(bottom: safeBottom),
                        ),
                        child: IndexedStack(
                          index: _currentIndex,
                          children: [
                            for (var i = 0; i < screens.length; i++)
                              _visitedTabs.contains(i)
                                  ? TickerMode(
                                      enabled: i == _currentIndex,
                                      child: screens[i],
                                    )
                                  : const SizedBox.shrink(),
                          ],
                        ),
                      ),
                    ),
                  ),
                  TravibeToastHost(
                    controller: _toasts,
                    visibility: _navVisibility,
                    navHeight: navHeight,
                    safeBottom: safeBottom,
                  ),
                ],
              ),
              bottomNavigationBar: HideableBottomBar(
                visibility: _navVisibility,
                child: LiquidGlassBottomNav(
                  navigation: BottomNavigationBar(
                    currentIndex: _currentIndex,
                    onTap: (value) {
                      _navVisibility.show();
                      if (value == 0) {
                        _push?.refreshCount();
                        unawaited(_chatUnread?.refresh() ?? Future.value());
                      }
                      if (value == 2) {
                        _showCreateOptions();
                        return;
                      }
                      if (value == 0 && _currentIndex == 0) {
                        _homeRefreshes.value++;
                        return;
                      }
                      if (value == 3 && _currentIndex == 3) {
                        _buddiesRefreshes.value++;
                        return;
                      }
                      if (value == 4 && _currentIndex == 4) {
                        _profileRefreshes.value++;
                        return;
                      }
                      setState(() {
                        _currentIndex = value;
                        _visitedTabs.add(value);
                      });
                    },
                    backgroundColor: Colors.transparent,
                    elevation: 0,
                    items: [
                      for (int i = 0; i < 5; i++)
                        if (i == 2)
                          BottomNavigationBarItem(
                            icon: Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(24),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(
                                      0xFFE45C10,
                                    ).withValues(alpha: 0.6),
                                    blurRadius: 10,
                                    spreadRadius: 0,
                                    offset: Offset.zero,
                                  ),
                                ],
                              ),
                              child: SvgPicture.asset(
                                'assets/images/home/Component 53 (1).svg',
                                width: AppSizes.w42,
                                height: AppSizes.h42,
                              ),
                            ),
                            label: ' ',
                          )
                        else
                          BottomNavigationBarItem(
                            icon: SvgPicture.asset(
                              i == _currentIndex
                                  ? _filledIcons[i]
                                  : _outlineIcons[i],
                              width: 22,
                              height: 22,
                            ),
                            label: [
                              'Home',
                              'Explore',
                              '',
                              'Buddies',
                              'Profile',
                            ][i],
                          ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _explorePeople() {
    final rootRoute = ModalRoute.of(context);
    Navigator.of(context).popUntil(
      (route) => rootRoute == null ? route.isFirst : route == rootRoute,
    );
    if (!mounted) return;
    setState(() {
      _currentIndex = 3;
      _visitedTabs.add(3);
    });
    _navVisibility.show();
  }

  static const _uploadToast = 'upload';

  void _onPostUpload(BuildContext context, PostUploadState state) {
    switch (state) {
      case PostUploading():
        _toasts.setSticky(
          _uploadToast,
          const TravibeToastData.info(
            'Uploading your post',
            leading: CupertinoActivityIndicator(
              radius: 10,
              color: DarkColors.whiteColor,
            ),
          ),
        );
      case PostUploadFailed():
        _toasts.setSticky(
          _uploadToast,
          TravibeToastData.error(
            'Couldn’t publish your post',
            actionLabel: 'Retry',
            onAction: _postUploads.retry,
            onClose: () async {
              if (await showDiscardPostDialog(this.context)) {
                _postUploads.discard();
              }
            },
          ),
        );
      case PostUploadDone(:final post):
        _toasts.setSticky(_uploadToast, null);
        // Home stays mounted, so its existing Cubits and scroll/tab state survive.
        _publications.value++;
        _activity.published(post);
        _toasts.show(
          const TravibeToastData.success('Post published successfully'),
        );
      case PostUploadIdle():
        _toasts.setSticky(_uploadToast, null);
    }
  }

  Future<void> _showCreateOptions() async {
    if (_openingComposer) return;
    _openingComposer = true;
    try {
      final draft = await CreatePostScreen.open(
        context,
        repo: widget.createPostRepo,
        picker: widget.postImagePicker,
      );
      if (!mounted || draft == null) return;
      setState(() => _currentIndex = 0);
      _navVisibility.show();
      // The composer is already closed; the toast reports upload progress.
      _postUploads.enqueue(draft);
    } finally {
      _openingComposer = false;
    }
  }
}
