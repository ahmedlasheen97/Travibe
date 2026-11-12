import 'package:travibe/core/widgets/glass_confirm_dialog.dart';
import 'package:flutter/material.dart';
import 'package:travibe/features/stories/widgets/story_reply_composer.dart';
import 'package:travibe/features/stories/widgets/story_other_options_sheet.dart';
import 'package:travibe/features/stories/cubit/story_likes_cubit.dart';
import 'package:travibe/features/stories/widgets/story_like_button.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:travibe/features/stories/widgets/story_glass.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:travibe/core/utils/formatters.dart';
import 'package:travibe/core/widgets/sheet_handle.dart';
import 'package:travibe/features/follow/cubit/follow_cubit.dart';
import 'package:travibe/features/stories/cubit/story_viewers_cubit.dart';
import 'package:travibe/features/stories/widgets/story_viewers_sheet.dart';
import 'package:travibe/features/block/cubit/block_cubit.dart';
import 'package:travibe/features/home/widgets/home_user_avatar.dart';
import 'package:travibe/features/stories/cubit/story_viewer_cubit.dart';
import 'package:travibe/features/stories/data/story_model.dart';
import 'package:travibe/features/stories/data/stories_repo.dart';
import 'package:travibe/features/stories/widgets/story_viewer_canvas.dart';

class StoryViewerScreen extends StatefulWidget {
  const StoryViewerScreen({
    super.key,
    required this.groups,
    required this.initialAuthorId,
    this.repo,
    this.likes,
    this.blocks,
    this.follow,
    this.currentUserId,
    this.onViewed,
    this.onDeleted,
    this.imageProvider,
    this.duration = const Duration(seconds: 5),
  });
  final List<StoryGroup> groups;
  final int initialAuthorId;
  final StoriesRepo? repo;
  final StoryLikesCubit? likes;
  final BlockCubit? blocks;
  final FollowCubit? follow;
  final int? currentUserId;
  final void Function(int id, int count)? onViewed;
  final void Function(int id)? onDeleted;
  final ImageProvider Function(String url)? imageProvider;
  final Duration duration;
  @override
  State<StoryViewerScreen> createState() => _StoryViewerScreenState();
}

class _StoryViewerScreenState extends State<StoryViewerScreen>
    with WidgetsBindingObserver {
  late final _repo = widget.repo ?? widget.likes?.repo ?? StoriesRepo();
  late final _likes = widget.likes ?? StoryLikesCubit(repo: _repo);
  late final _viewer = StoryViewerCubit(
    groups: widget.groups,
    initialAuthorId: widget.initialAuthorId,
    repo: _repo,
    likes: _likes,
    blocks: widget.blocks,
    currentUserId: widget.currentUserId,
    onViewed: widget.onViewed,
    onDeleted: widget.onDeleted,
    duration: widget.duration,
  );
  bool _closing = false;
  void _close() {
    if (!mounted || _closing) return;
    _closing = true;
    if (_viewer.state.status != StoryViewerStatus.finished) _viewer.finish();
    final route = ModalRoute.of(context);
    final navigator = Navigator.of(context);
    // Remove sheets/dialogs belonging to this viewer before removing its route.
    navigator.popUntil((candidate) => candidate == route);
    navigator.pop();
  }

  bool _ownerSheetOpen = false;
  Future<void> _ownerAction({required bool viewers}) async {
    if (_ownerSheetOpen || !_viewer.ownsCurrent || _viewer.deleting) return;
    _ownerSheetOpen = true;
    _viewer.pause(true, reason: 'owner-sheet');
    final detail = _viewer.state.detail!;
    final request = _viewer.state.request;
    bool currentOwner() =>
        mounted &&
        !_closing &&
        _viewer.ownsCurrent &&
        _viewer.state.request == request &&
        _viewer.state.detail?.id == detail.id;
    try {
      if (viewers) {
        final cubit = StoryViewersCubit(
          storyId: detail.id,
          repo: _viewer.repo,
          isOwner: currentOwner,
          blocks: widget.blocks,
        );
        try {
          cubit.refresh();
          await showModalBottomSheet<void>(
            context: context,
            isScrollControlled: true,
            backgroundColor: Colors.black,
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            builder: (_) => StoryViewersSheet(
              cubit: cubit,
              count: _viewer.state.viewsCount ?? detail.viewsCount,
              follow: widget.follow,
              blocks: widget.blocks,
            ),
          );
        } finally {
          await cubit.close();
        }
      } else {
        final delete = await showModalBottomSheet<bool>(
          context: context,
          backgroundColor: Colors.black,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          builder: (sheetContext) => SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 12),
                const SheetHandle(),
                const SizedBox(height: 16),
                ListTile(
                  leading: const Icon(Icons.delete_outline, color: Colors.red),
                  title: const Text(
                    'Delete story',
                    style: TextStyle(
                      color: Colors.red,
                      fontFamily: 'Plus Jakarta Sans',
                    ),
                  ),
                  onTap: () => Navigator.pop(sheetContext, true),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        );
        if (delete != true || !mounted || !currentOwner()) return;
        final confirmed = await showGlassConfirmDialog(
          context,
          title: 'Delete story?',
          message: 'This story will be removed.',
          confirmLabel: 'Delete',
        );
        if (!confirmed || !currentOwner()) return;
        final operation = _viewer.deleteCurrent();
        if (mounted) setState(() {});
        final error = await operation;
        if (mounted && !_closing && error != null) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(error.message)));
        }
      }
    } finally {
      _ownerSheetOpen = false;
      _viewer.pause(false, reason: 'owner-sheet');
      if (mounted && !_closing) setState(() {});
    }
  }

  bool _otherSheetOpen = false;
  bool _replyActive = false;
  int? _replyStory;
  void _replyFocus(bool active) {
    _replyActive = active;
    _viewer.pause(active, reason: 'reply');
  }

  Future<void> _otherOptions() async {
    final state = _viewer.state;
    final detail = state.detail;
    if (_otherSheetOpen ||
        detail == null ||
        detail.isMine ||
        detail.userId == widget.currentUserId ||
        state.status != StoryViewerStatus.ready) {
      return;
    }
    FocusScope.of(context).unfocus();
    _otherSheetOpen = true;
    _viewer.pause(true, reason: 'other-sheet');
    final request = state.request;
    bool current() =>
        mounted &&
        !_closing &&
        _viewer.state.request == request &&
        _viewer.state.detail?.id == detail.id;
    try {
      await showModalBottomSheet<void>(
        context: context,
        backgroundColor: Colors.black,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        builder: (_) => StoryOtherOptionsSheet(
          userId: detail.userId.toString(),
          name: detail.user.name,
          blocks: widget.blocks,
          canAct: current,
        ),
      );
    } finally {
      _otherSheetOpen = false;
      _viewer.pause(false, reason: 'other-sheet');
    }
  }

  int _imageRequest = -1;
  ImageProvider? _image;
  ImageProvider _imageFor(StoryViewerState state) {
    if (_imageRequest != state.request) {
      _imageRequest = state.request;
      _image =
          widget.imageProvider?.call(state.detail!.media.url!) ??
          NetworkImage(state.detail!.media.url!);
    }
    return _image!;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _viewer.pause(
        WidgetsBinding.instance.lifecycleState != null &&
            WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed,
        reason: 'lifecycle',
      );
      _viewer.start();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) =>
      _viewer.pause(state != AppLifecycleState.resumed, reason: 'lifecycle');
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _viewer.close();
    if (widget.likes == null) _likes.close();
    super.dispose();
  }

  @override
  Widget build(
    BuildContext context,
  ) => BlocConsumer<StoryViewerCubit, StoryViewerState>(
    bloc: _viewer,
    listener: (context, state) {
      if (_replyStory != state.detail?.id) {
        _replyStory = state.detail?.id;
        if (_replyActive) _replyFocus(false);
      }
      if (state.status == StoryViewerStatus.finished) {
        _close();
      }
    },
    builder: (context, state) => PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) {
          _closing = true;
          if (_viewer.state.status != StoryViewerStatus.finished) {
            _viewer.finish();
          }
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        resizeToAvoidBottomInset: false,
        body: SafeArea(
          bottom: false,
          child: LayoutBuilder(
            builder: (context, constraints) => Stack(
              fit: StackFit.expand,
              children: [
                if (state.status == StoryViewerStatus.ready) ...[
                  StoryViewerCanvas(
                    key: ValueKey(state.request),
                    image: _imageFor(state),
                    layers: state.layers,
                    onReady: () => _viewer.imageDisplayed(state.request),
                    onError: () => _viewer.imageFailed(state.request),
                  ),
                  if (!state.imageReady)
                    const Center(child: CircularProgressIndicator()),
                ],
                Positioned.fill(
                  child: Listener(
                    onPointerCancel: (_) => _viewer.pause(false),
                    child: GestureDetector(
                      key: const ValueKey('story-viewer-taps'),
                      behavior: HitTestBehavior.opaque,
                      onTapUp: (details) =>
                          details.localPosition.dx < constraints.maxWidth / 2
                          ? _viewer.previous()
                          : _viewer.next(),
                      onLongPressStart: (_) => _viewer.pause(true),
                      onLongPressEnd: (_) => _viewer.pause(false),
                      onLongPressCancel: () => _viewer.pause(false),
                    ),
                  ),
                ),
                if (state.status == StoryViewerStatus.loading)
                  const Center(child: CircularProgressIndicator()),
                if (state.status == StoryViewerStatus.failure)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            state.error!.message,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontFamily: 'Plus Jakarta Sans',
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextButton(
                            key: const ValueKey('story-viewer-retry'),
                            onPressed: _viewer.retry,
                            child: const Text('Retry'),
                          ),
                          TextButton(
                            key: const ValueKey('story-viewer-skip'),
                            onPressed: _viewer.next,
                            child: const Text('Next Story'),
                          ),
                        ],
                      ),
                    ),
                  ),
                if (state.status == StoryViewerStatus.ready &&
                    !state.detail!.isMine &&
                    state.detail!.userId != widget.currentUserId)
                  Positioned(
                    left: 16,
                    right: 16,
                    bottom: MediaQuery.viewInsetsOf(context).bottom + 16,
                    child: SafeArea(
                      top: false,
                      child: Row(
                        key: const ValueKey('story-other-controls'),
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: StoryReplyComposer(
                              key: ValueKey(state.detail!.id),
                              storyId: state.detail!.id,
                              onActiveChanged: _replyFocus,
                            ),
                          ),
                          const SizedBox(width: 8),
                          StoryLikeButton(
                            detail: state.detail!,
                            likes: _likes,
                            onError: (error) {
                              if (mounted &&
                                  !_closing &&
                                  _viewer.state.request == state.request) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text(error.message)),
                                );
                              }
                            },
                          ),
                          const SizedBox(width: 8),
                          StoryGlass(
                            child: SizedBox.square(
                              dimension: 48,
                              child: IconButton(
                                key: const ValueKey('story-other-options'),
                                tooltip: 'Story options',
                                icon: const Icon(
                                  Icons.more_vert,
                                  color: Colors.white,
                                ),
                                onPressed: _otherOptions,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                if (state.status == StoryViewerStatus.ready &&
                    _viewer.ownsCurrent)
                  Positioned(
                    left: 16,
                    right: 16,
                    bottom: 16,
                    child: SafeArea(
                      top: false,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Flexible(
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: StoryGlass(
                                key: const ValueKey('story-views-glass'),
                                child: Material(
                                  type: MaterialType.transparency,
                                  child: InkWell(
                                    key: const ValueKey('story-views'),
                                    borderRadius: BorderRadius.circular(999),
                                    onTap: _viewer.deleting
                                        ? null
                                        : () => _ownerAction(viewers: true),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                        vertical: 12,
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          SvgPicture.asset(
                                            'assets/images/interactions/eye.svg',
                                            width: 24,
                                            height: 24,
                                            excludeFromSemantics: true,
                                          ),
                                          const SizedBox(width: 8),
                                          Flexible(
                                            child: Text(
                                              '${state.viewsCount ?? state.detail!.viewsCount}',
                                              semanticsLabel:
                                                  '${state.viewsCount ?? state.detail!.viewsCount} views',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontFamily: 'Plus Jakarta Sans',
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                          const Icon(
                                            Icons.keyboard_arrow_down,
                                            color: Colors.white,
                                            size: 24,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          StoryGlass(
                            key: const ValueKey('story-options-glass'),
                            child: Material(
                              type: MaterialType.transparency,
                              child: IconButton(
                                key: const ValueKey('story-owner-options'),
                                tooltip: 'Story options',
                                constraints: const BoxConstraints.tightFor(
                                  width: 48,
                                  height: 48,
                                ),
                                onPressed: _viewer.deleting
                                    ? null
                                    : () => _ownerAction(viewers: false),
                                icon: _viewer.deleting
                                    ? const SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(
                                        Icons.more_vert,
                                        color: Colors.white,
                                        size: 24,
                                      ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          for (var i = 0; i < state.count; i++)
                            Expanded(
                              child: Padding(
                                padding: EdgeInsets.only(
                                  right: i == state.count - 1 ? 0 : 4,
                                ),
                                child: LinearProgressIndicator(
                                  key: ValueKey('story-progress-$i'),
                                  minHeight: 3,
                                  borderRadius: BorderRadius.circular(2),
                                  backgroundColor: Colors.white30,
                                  value: i < state.index
                                      ? 1
                                      : i > state.index
                                      ? 0
                                      : state.progress,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          if (state.detail != null)
                            Expanded(
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: StoryGlass(
                                  key: const ValueKey('story-author-glass'),
                                  child: Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                      12,
                                      8,
                                      16,
                                      8,
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        HomeUserAvatar(
                                          url: state.detail!.user.avatarUrl,
                                          size: 36,
                                        ),
                                        const SizedBox(width: 10),
                                        Flexible(
                                          child: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                state.detail!.user.name,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  fontFamily:
                                                      'Plus Jakarta Sans',
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                              if (state.detail!.createdAt !=
                                                  null)
                                                Text(
                                                  timeAgo(
                                                    state.detail!.createdAt,
                                                  ),
                                                  key: const ValueKey(
                                                    'story-posting-time',
                                                  ),
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: const TextStyle(
                                                    fontFamily:
                                                        'Plus Jakarta Sans',
                                                    color: Colors.white70,
                                                    fontSize: 12,
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            )
                          else
                            const Spacer(),
                          const SizedBox(width: 8),
                          IconButton(
                            key: const ValueKey('story-viewer-close'),
                            tooltip: 'Close Story',
                            onPressed: _close,
                            icon: const Icon(Icons.close, color: Colors.white),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
