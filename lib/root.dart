import 'package:travibe/features/chats/widgets/chat_reverb_host.dart';
import 'package:travibe/features/chats/data/chat_reverb_service.dart';
import 'package:travibe/features/chats/cubit/chat_unread_cubit.dart';
import 'dart:async';
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
import 'package:flutter/rendering.dart';
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
import 'package:travibe/features/create_post/widgets/post_upload_toast.dart';
import 'package:travibe/features/create_post/widgets/create_post_styles.dart';
import 'package:travibe/features/home/data/posts_repo.dart';
import 'package:travibe/features/home/data/home_account_repo.dart';

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
  });
  final CreatePostRepo? createPostRepo;
  final PostsRepo? postsRepo;
  final HomeAccountRepo? homeAccountRepo;
  final FollowRepo? followRepo;
  final BuddiesRepo? buddiesRepo;
  final ProfileRepo? profileRepo;
  final MediaUploadFactory? mediaUploads;
  final PostImagePicker? postImagePicker;

  @override
  State<Root> createState() => _RootState();
}

class _RootState extends State<Root> {
  PushNotificationsCoordinator? _push;
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
    _reverb?.detach(this);
    _chatUnread?.detach(this);
    unawaited(_reverbBlocks?.cancel() ?? Future.value());
    _postUploads.close();
    _publications.dispose();
    _homeRefreshes.dispose();
    _buddiesRefreshes.dispose();
    _profileRefreshes.dispose();
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
  bool _isNavVisible = true;

  late final List<Widget> screens = [
    HomeScreen(
      postsRepo: widget.postsRepo,
      publicationSignal: _publications,
      refreshSignal: _homeRefreshes,
      accountRepo: widget.homeAccountRepo,
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
        child: Scaffold(
          body: Stack(
            children: [
              NotificationListener<UserScrollNotification>(
                onNotification: (notification) {
                  if (notification.metrics.axis != Axis.vertical) return false;
                  if (notification.direction == ScrollDirection.reverse) {
                    // scrolling down → hide
                    if (_isNavVisible) setState(() => _isNavVisible = false);
                  } else if (notification.direction ==
                      ScrollDirection.forward) {
                    // scrolling up → show
                    if (!_isNavVisible) setState(() => _isNavVisible = true);
                  }
                  return false; // let the notification keep bubbling
                },
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
              const Positioned(
                left: 0,
                right: 0,
                bottom: 16,
                child: PostUploadToast(),
              ),
            ],
          ),
          bottomNavigationBar: AnimatedSlide(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeInOut,
            offset: _isNavVisible ? Offset.zero : const Offset(0, 1.5),
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 200),
              opacity: _isNavVisible ? 1 : 0,
              child: LiquidGlassBottomNav(
                navigation: BottomNavigationBar(
                  currentIndex: _currentIndex,
                  onTap: (value) {
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
      _isNavVisible = true;
    });
  }

  void _onPostUpload(BuildContext context, PostUploadState state) {
    if (state is! PostUploadDone) return;
    // Home stays mounted, so its existing Cubits and scroll/tab state survive.
    _publications.value++;
    _activity.published(state.post);
    // Figma: floating green toast, 20px side margins, radius 4.
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: createPostSuccess,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        elevation: 0,
        content: const Row(
          children: [
            Icon(Icons.check_circle, color: Colors.white, size: 20),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Post published successfully',
                style: createPostTextStyle,
              ),
            ),
          ],
        ),
      ),
    );
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
      setState(() {
        _currentIndex = 0;
        _isNavVisible = true;
      });
      // The composer is already closed; the toast reports upload progress.
      _postUploads.enqueue(draft);
    } finally {
      _openingComposer = false;
    }
  }
}
