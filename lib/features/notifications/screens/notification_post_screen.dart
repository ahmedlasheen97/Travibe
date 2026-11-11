import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/core/utils/formatters.dart';
import 'package:travibe/core/widgets/back_button_widget.dart';
import 'package:travibe/core/widgets/post_card.dart';
import 'package:travibe/features/comments/screens/comments_screen.dart';
import 'package:travibe/features/comments/data/comments_repo.dart';
import 'package:travibe/features/home/cubit/post_activity_cubit.dart';
import 'package:travibe/features/likes/cubit/likes_cubit.dart';
import 'package:travibe/features/likes/data/like_model.dart';
import 'package:travibe/features/saved/cubit/saves_cubit.dart';
import 'package:travibe/features/shares/widgets/send_post_sheet.dart';
import '../data/notification_targets.dart';

/// A single authorized post using the existing PostCard and interaction owners.
/// The project had no standalone Post Detail route to reuse.
class NotificationPostScreen extends StatefulWidget {
  const NotificationPostScreen({
    super.key,
    required this.content,
    this.openComments = false,
    this.comments,
    this.highlightCommentId,
  });
  final NotificationContent content;
  final int? highlightCommentId;
  final bool openComments;
  final CommentsRepo? comments;
  @override
  State<NotificationPostScreen> createState() => _NotificationPostScreenState();
}

class _NotificationPostScreenState extends State<NotificationPostScreen> {
  final _preferences = PreferencesManager();
  late final _session = _preferences.sessionRevision;
  late final _borrowedLikes = context.read<LikesCubit?>();
  late final _borrowedSaves = context.read<SavesCubit?>();
  late final _likes = _borrowedLikes ?? LikesCubit();
  late final _saves = _borrowedSaves ?? SavesCubit();
  StreamSubscription<dynamic>? _likeChanges, _saveChanges;
  int? _commentCount;
  bool _commentsOpen = false, _shareOpen = false;
  bool get _active =>
      mounted &&
      _preferences.hasSession &&
      _session == _preferences.sessionRevision;
  @override
  void initState() {
    super.initState();
    _preferences.addListener(_changed);
    _likeChanges = _likes.stream.listen((_) => _changed());
    _saveChanges = _saves.stream.listen((_) => _changed());
    if (widget.openComments) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _comments());
    }
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _preferences.removeListener(_changed);
    unawaited(_likeChanges?.cancel() ?? Future.value());
    unawaited(_saveChanges?.cancel() ?? Future.value());
    if (_borrowedLikes == null) unawaited(_likes.close());
    if (_borrowedSaves == null) unawaited(_saves.close());
    super.dispose();
  }

  Future<void> _comments() async {
    if (!_active || _commentsOpen) return;
    final post = widget.content.post!;
    if (post.commentsDisabled) return;
    _commentsOpen = true;
    final comment = widget.content.comment;
    try {
      await CommentsScreen.open(
        context,
        repo: widget.comments,
        postId: int.parse(post.id),
        initialCount: _commentCount ?? post.commentsCount,
        commentsDisabled: post.commentsDisabled,
        likes: _likes,
        highlightCommentId: widget.highlightCommentId,
        // Top-level comments are highlighted in the main thread; replies
        // open their parent's thread.
        parentId: comment?.parentId,
        onCountChanged: (count) {
          if (!_active) return;
          setState(() => _commentCount = count);
          context.read<PostActivityCubit?>()?.setCommentsCount(post.id, count);
        },
      );
    } finally {
      _commentsOpen = false;
    }
  }

  Future<void> _share() async {
    if (!_active || _shareOpen) return;
    _shareOpen = true;
    try {
      await SendPostSheet.show(context, post: widget.content.post!);
    } finally {
      _shareOpen = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final post = widget.content.post!;
    final target = LikeTarget.post(int.parse(post.id));
    final like =
        _likes.value(target) ??
        LikeValue(isLiked: post.isLiked, count: post.likesCount);
    final media = post.media
        .map((m) => m.displayUrl)
        .where((url) => url.isNotEmpty)
        .toList();
    return Scaffold(
      backgroundColor: const Color(0xFF0B0B0B),
      appBar: AppBar(
        leading: const BackButtonWidget(),
        title: const Text('Post'),
        centerTitle: true,
      ),
      body: SafeArea(
        top: false,
        child: !_active
            ? const Center(child: Text('Sign in again to view this post.'))
            : SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: PostCard(
                  postId: post.id,
                  authorId: post.user.id,
                  name: post.user.name,
                  avatar: post.user.avatarUrl,
                  time: timeAgo(post.createdAt),
                  text: post.content ?? '',
                  responsive: true,
                  homePresentation: true,
                  image: media.length == 1 ? media.single : null,
                  images: media.length > 1 ? media : null,
                  likes: formatCount(like.count),
                  isLiked: like.isLiked,
                  isLikePending: like.pending,
                  onLikeTap: !post.hasLikeState
                      ? null
                      : () async {
                          if (!_active) return;
                          final error = await _likes.toggle(
                            target,
                            initial: like,
                          );
                          if (!context.mounted) return;
                          if (_active && error != null) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(error.message)),
                            );
                          }
                        },
                  comments: formatCount(_commentCount ?? post.commentsCount),
                  onCommentsTap: _comments,
                  onShareTap: _share,
                  isSaved: _saves.state.values[post.id] ?? post.isSaved,
                  isSavePending: _saves.state.pending.contains(post.id),
                  onSaveTap: !post.hasSaveState
                      ? null
                      : () async {
                          if (!_active) return;
                          final error = await _saves.toggle(post);
                          if (!context.mounted) return;
                          if (_active && error != null) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(error.message)),
                            );
                          }
                        },
                ),
              ),
      ),
    );
  }
}
