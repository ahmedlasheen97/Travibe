import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/core/utils/formatters.dart';
import 'package:travibe/core/utils/viewer_identity.dart';
import 'package:travibe/core/widgets/back_button_widget.dart';
import 'package:travibe/core/widgets/post_card.dart';
import 'package:travibe/features/block/cubit/block_cubit.dart';
import 'package:travibe/features/block/widgets/block_user_button.dart';
import 'package:travibe/features/comments/cubit/comments_cubit.dart';
import 'package:travibe/features/comments/data/comments_repo.dart';
import 'package:travibe/features/comments/screens/comments_screen.dart';
import 'package:travibe/features/follow/cubit/follow_cubit.dart';
import 'package:travibe/features/follow/widgets/follow_action_builder.dart';
import 'package:travibe/features/home/cubit/hidden_posts_cubit.dart';
import 'package:travibe/features/home/cubit/post_activity_cubit.dart';
import 'package:travibe/features/home/cubit/posts_cubit.dart';
import 'package:travibe/features/home/data/post_model.dart';
import 'package:travibe/features/home/widgets/own_post_actions.dart';
import 'package:travibe/features/home/widgets/post_options_sheet.dart';
import 'package:travibe/features/likes/cubit/likes_cubit.dart';
import 'package:travibe/features/likes/data/like_model.dart';
import 'package:travibe/features/likes/data/likes_repo.dart';
import 'package:travibe/features/likes/widgets/liked_by_sheet.dart';
import 'package:travibe/features/notifications/screens/notification_navigation.dart';
import 'package:travibe/features/saved/cubit/saves_cubit.dart';
import 'package:travibe/features/shares/widgets/send_post_sheet.dart';

/// Figma "Post": one post with its comments inline and a pinned composer.
/// Used by post cards, notifications and shared-post links.
class PostScreen extends StatefulWidget {
  const PostScreen({
    super.key,
    required this.post,
    this.highlightCommentId,
    this.highlightParentId,
    this.comments,
    this.likers,
  });
  final PostModel post;

  /// Scrolled into view and tinted (notification deep link).
  final int? highlightCommentId;

  /// When the highlighted comment is a reply, its thread opens as a sheet.
  final int? highlightParentId;
  final CommentsRepo? comments;
  final LikesRepo? likers;

  /// Pushes the screen with the app-wide interaction cubits of [context].
  static Future<void> open(
    BuildContext context, {
    required PostModel post,
    CommentsRepo? comments,
  }) {
    if (int.tryParse(post.id) == null) return Future.value();
    return Navigator.of(context).push<void>(
      MaterialPageRoute(
        settings: RouteSettings(name: 'post/${post.id}'),
        builder: (_) => notificationRouteScope(
          context,
          PostScreen(post: post, comments: comments),
        ),
      ),
    );
  }

  @override
  State<PostScreen> createState() => _PostScreenState();
}

class _PostScreenState extends State<PostScreen> {
  final _preferences = PreferencesManager();
  late final _session = _preferences.sessionRevision;
  late final _borrowedLikes = context.read<LikesCubit?>();
  late final _borrowedSaves = context.read<SavesCubit?>();
  late final _likes = _borrowedLikes ?? LikesCubit();
  late final _saves = _borrowedSaves ?? SavesCubit();
  late final _activity = context.read<PostActivityCubit?>();

  /// Own-post mutations; results reach every feed through PostActivityCubit.
  late final _mutations = PostsCubit(
    likes: _likes,
    saves: _saves,
    activity: _activity,
  );
  final _composerFocus = FocusNode();
  StreamSubscription<dynamic>? _likeChanges, _saveChanges, _activityChanges;
  int? _commentCount;
  bool _shareOpen = false, _likersOpen = false, _closing = false;

  PostModel get _post => widget.post;
  bool get _active =>
      mounted &&
      _preferences.hasSession &&
      _session == _preferences.sessionRevision;
  bool get _commentsDisabled =>
      _activity?.state.commentsDisabled[_post.id] ?? _post.commentsDisabled;

  @override
  void initState() {
    super.initState();
    _preferences.addListener(_changed);
    _likeChanges = _likes.stream.listen((_) => _changed());
    _saveChanges = _saves.stream.listen((_) => _changed());
    _activityChanges = _activity?.stream.listen((state) {
      // Deleted from this screen or elsewhere: nothing left to show.
      if (state.deleted.contains(_post.id)) {
        _close();
      } else {
        _changed();
      }
    });
    final parent = widget.highlightParentId;
    if (parent != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _openReplies(parent));
    }
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  void _close() {
    if (!mounted || _closing) return;
    _closing = true;
    Navigator.of(context).maybePop();
  }

  @override
  void dispose() {
    _preferences.removeListener(_changed);
    unawaited(_likeChanges?.cancel() ?? Future.value());
    unawaited(_saveChanges?.cancel() ?? Future.value());
    unawaited(_activityChanges?.cancel() ?? Future.value());
    unawaited(_mutations.close());
    if (_borrowedLikes == null) unawaited(_likes.close());
    if (_borrowedSaves == null) unawaited(_saves.close());
    _composerFocus.dispose();
    super.dispose();
  }

  void _countChanged(int count) {
    if (!_active) return;
    setState(() => _commentCount = count);
    _activity?.setCommentsCount(_post.id, count);
  }

  /// A reply's thread is not part of the inline list; show it as before.
  Future<void> _openReplies(int parentId) async {
    if (!_active) return;
    await CommentsScreen.open(
      context,
      repo: widget.comments,
      postId: int.parse(_post.id),
      initialCount: _commentCount ?? _post.commentsCount,
      commentsDisabled: _commentsDisabled,
      likes: _likes,
      highlightCommentId: widget.highlightCommentId,
      parentId: parentId,
      onCountChanged: _countChanged,
    );
  }

  Future<void> _share() async {
    if (!_active || _shareOpen) return;
    _shareOpen = true;
    try {
      await SendPostSheet.show(context, post: _post);
    } finally {
      _shareOpen = false;
    }
  }

  Future<void> _likers(int count) async {
    if (!_active || _likersOpen) return;
    _likersOpen = true;
    try {
      await LikedBySheet.show(
        context,
        postId: int.parse(_post.id),
        count: count,
        repo: widget.likers,
      );
    } finally {
      _likersOpen = false;
    }
  }

  void _snack(String message) => ScaffoldMessenger.maybeOf(
    context,
  )?.showSnackBar(SnackBar(content: Text(message)));

  Future<void> _options() async {
    if (!_active) return;
    final hidden = context.read<HiddenPostsCubit?>();
    final blocks = context.read<BlockCubit?>();
    if (hidden?.state.pending.contains(_post.id) == true ||
        blocks?.state.pending.contains(_post.user.id) == true) {
      return;
    }
    final own = isViewer(
      context,
      _post.userId.isNotEmpty ? _post.userId : _post.user.id,
    );
    final action = await PostOptionsSheet.show(
      context,
      actions: own
          ? ownPostActions
          : {
              if (hidden != null) PostOptionAction.hidePost,
              if (blocks != null) PostOptionAction.blockUser,
            },
      commentsDisabled: _commentsDisabled,
    );
    if (!mounted || !_active || action == null) return;
    if (own) {
      await runOwnPostAction(
        context,
        action: action,
        post: _post,
        feed: _mutations,
      );
      return;
    }
    if (action == PostOptionAction.hidePost && hidden != null) {
      final error = await hidden.setHidden(_post.id, true);
      if (!mounted) return;
      if (error != null) return _snack(error.message);
      _snack('Post hidden');
      _close();
    } else if (action == PostOptionAction.blockUser && blocks != null) {
      if (!mounted) return;
      await confirmBlockChange(
        context,
        _post.user.id,
        blocked: true,
        name: _post.user.name,
      );
      if (blocks.state.isBlocked(_post.user.id)) _close();
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFF0B0B0B),
    appBar: AppBar(
      backgroundColor: const Color(0xFF0B0B0B),
      leading: const BackButtonWidget(),
      title: const Text('Post'),
      centerTitle: true,
    ),
    body: !_active
        ? const Center(child: Text('Sign in again to view this post.'))
        : BlocProvider(
            create: (_) => CommentsCubit(
              postId: int.parse(_post.id),
              initialCount: _post.commentsCount,
              repo: widget.comments,
              likes: _likes,
              onCountChanged: _countChanged,
            )..load(),
            child: CommentsThreadView(
              header: _header(),
              commentsDisabled: _commentsDisabled,
              highlightCommentId: widget.highlightParentId == null
                  ? widget.highlightCommentId
                  : null,
              composerFocus: _composerFocus,
            ),
          ),
  );

  Widget _header() {
    if (context.read<FollowCubit?>() == null) {
      return _card(following: _post.user.isFollowing);
    }
    return FollowActionBuilder(
      userId: _post.user.id,
      initialFollowing: _post.user.isFollowing,
      builder: (context, following, pending, toggle) => _card(
        following: following,
        pending: pending,
        onFollow: _post.user.isBlocked ? null : toggle,
        showFollow: true,
      ),
    );
  }

  Widget _card({
    required bool following,
    bool pending = false,
    VoidCallback? onFollow,
    bool showFollow = false,
  }) {
    final target = LikeTarget.post(int.parse(_post.id));
    final like =
        _likes.value(target) ??
        LikeValue(isLiked: _post.isLiked, count: _post.likesCount);
    final media = _post.media
        .map((m) => m.displayUrl)
        .where((url) => url.isNotEmpty)
        .toList();
    return PostCard(
      postId: _post.id,
      authorId: _post.user.id,
      name: _post.user.name,
      avatar: _post.user.avatarUrl,
      time: timeAgo(_post.createdAt),
      text: _post.content ?? '',
      responsive: true,
      detailPresentation: true,
      image: media.length == 1 ? media.single : null,
      images: media.length > 1 ? media : null,
      likes: formatCount(like.count),
      isLiked: like.isLiked,
      isLikePending: like.pending,
      onLikeTap: !_post.hasLikeState
          ? null
          : () async {
              if (!_active) return;
              final error = await _likes.toggle(target, initial: like);
              if (_active && error != null) _snack(error.message);
            },
      onLikesCountTap: () => _likers(like.count),
      comments: formatCount(_commentCount ?? _post.commentsCount),
      onCommentsTap: _commentsDisabled ? null : _composerFocus.requestFocus,
      onShareTap: _share,
      isSaved: _saves.state.values[_post.id] ?? _post.isSaved,
      isSavePending: _saves.state.pending.contains(_post.id),
      onSaveTap: !_post.hasSaveState
          ? null
          : () async {
              if (!_active) return;
              final error = await _saves.toggle(_post);
              if (_active && error != null) _snack(error.message);
            },
      showFollowButton: showFollow,
      neutralFollowButton: true,
      isFollowing: following,
      isFollowPending: pending,
      onFollowTap: onFollow,
      onMoreTap: _options,
    );
  }
}
