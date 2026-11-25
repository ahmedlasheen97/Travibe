import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:travibe/core/constants/app_sizes.dart';
import 'package:travibe/core/utils/formatters.dart';
import 'package:travibe/core/utils/viewer_identity.dart';
import 'package:travibe/core/widgets/error_retry_view.dart';
import 'package:travibe/core/widgets/post_card.dart';
import 'package:travibe/features/block/cubit/block_cubit.dart';
import 'package:travibe/features/block/widgets/block_user_button.dart';
import 'package:travibe/features/comments/screens/comments_screen.dart';
import 'package:travibe/features/home/cubit/hidden_posts_cubit.dart';
import 'package:travibe/features/home/cubit/post_activity_cubit.dart';
import 'package:travibe/features/home/cubit/posts_cubit.dart';
import 'package:travibe/features/home/data/post_model.dart';
import 'package:travibe/features/home/screens/post_screen.dart';
import 'package:travibe/features/home/widgets/own_post_actions.dart';
import 'package:travibe/features/home/widgets/post_options_sheet.dart';
import 'package:travibe/features/home/widgets/post_report_flow.dart';
import 'package:travibe/features/likes/cubit/likes_cubit.dart';
import 'package:travibe/features/likes/data/like_model.dart';
import 'package:travibe/features/likes/widgets/liked_by_sheet.dart';
import 'package:travibe/features/profile/widgets/profile_shimmer.dart';
import 'package:travibe/features/saved/cubit/saves_cubit.dart';
import 'package:travibe/features/search/cubit/search_cubit.dart';
import 'package:travibe/features/shares/widgets/send_post_sheet.dart';

/// Search's Posts tab: matching posts as shared [PostCard]s, paged on scroll.
/// Likes, saves, comment counts, hides, blocks and deletes come from Root's
/// shared cubits (when provided), so every feed stays consistent.
class SearchPostResults extends StatefulWidget {
  const SearchPostResults({super.key, required this.state, this.onOpen});
  final SearchState state;

  /// Opens a result; defaults to the Post screen.
  final ValueChanged<PostModel>? onOpen;

  @override
  State<SearchPostResults> createState() => _SearchPostResultsState();
}

class _SearchPostResultsState extends State<SearchPostResults> {
  late final bool _ownsLikes;
  late final LikesCubit _likes;
  final _comments = <String, int>{};
  bool _openingShare = false, _openingOptions = false;

  /// Own-post mutations (delete, commenting); other lists learn about them
  /// through the shared PostActivityCubit.
  PostsCubit? _mutations;

  @override
  void initState() {
    super.initState();
    final borrowed = context.read<LikesCubit?>();
    _ownsLikes = borrowed == null;
    _likes = borrowed ?? LikesCubit();
  }

  @override
  void dispose() {
    if (_ownsLikes) _likes.close();
    _mutations?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final cubit = context.read<SearchCubit>();
    switch (state.postsStatus) {
      case SearchStatus.idle:
      case SearchStatus.loading:
        return ListView(
          key: const ValueKey('search-posts-loading'),
          physics: const NeverScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(
            AppSizes.pw20,
            AppSizes.ph8,
            AppSizes.pw20,
            0,
          ),
          children: const [ProfilePostSkeleton(), ProfilePostSkeleton()],
        );
      case SearchStatus.failure:
        return ErrorRetryView(message: state.postsError, onRetry: cubit.retry);
      case SearchStatus.loaded:
        break;
    }

    final block = context.watch<BlockCubit?>()?.state;
    final hidden = context.watch<HiddenPostsCubit?>()?.state.hidden;
    final activity = context.watch<PostActivityCubit?>()?.state;
    final deleted = activity?.deleted;
    final saves = context.watch<SavesCubit?>()?.state;
    final posts = [
      for (final post in state.posts)
        if (block?.isBlocked(post.user.id) != true &&
            hidden?.contains(post.id) != true &&
            deleted?.contains(post.id) != true)
          post,
    ];
    if (posts.isEmpty && !state.hasMorePosts) {
      return _empty();
    }

    final footer =
        state.isLoadingMorePosts || state.postsPaginationError.isNotEmpty;
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification.metrics.pixels >=
            notification.metrics.maxScrollExtent - 600) {
          cubit.loadMorePosts();
        }
        return false;
      },
      child: ListView.builder(
        key: const ValueKey('search-posts-list'),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: EdgeInsets.fromLTRB(
          AppSizes.pw20,
          AppSizes.ph8,
          AppSizes.pw20,
          AppSizes.ph24,
        ),
        itemCount: posts.length + (footer ? 1 : 0),
        itemBuilder: (context, index) {
          if (index >= posts.length) {
            if (state.postsPaginationError.isNotEmpty) {
              return ErrorRetryView(
                message: state.postsPaginationError,
                onRetry: () => cubit.loadMorePosts(retry: true),
              );
            }
            return const ProfilePostSkeleton(
              key: ValueKey('search-posts-loading-more'),
            );
          }
          final post = posts[index];
          return Padding(
            key: ValueKey('search-post-${post.id}'),
            padding: const EdgeInsets.only(bottom: 16),
            child: _postCard(post, saves, activity),
          );
        },
      ),
    );
  }

  Widget _empty() => Center(
    key: const ValueKey('search-posts-empty'),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Text(
        'No posts found',
        textAlign: TextAlign.center,
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.5),
          fontSize: 14,
          height: 1.4,
        ),
      ),
    ),
  );

  Widget _postCard(
    PostModel post,
    SavesState? saves,
    PostActivityState? activity,
  ) {
    final target = LikeTarget.post(int.parse(post.id));
    final media = post.media.map((m) => m.displayUrl).toList();
    final comments =
        activity?.comments[post.id] ?? _comments[post.id] ?? post.commentsCount;
    return BlocBuilder<LikesCubit, LikesState>(
      bloc: _likes,
      buildWhen: (a, b) => a.values[target] != b.values[target],
      builder: (context, likes) {
        final like = likes.values[target];
        return PostCard(
          postId: post.id,
          authorId: post.user.id,
          name: post.user.name,
          avatar: post.user.avatarUrl,
          avatarSize: AppSizes.w40,
          time: timeAgo(post.createdAt),
          text: post.content ?? '',
          image: media.length == 1 ? media.first : null,
          images: media.length > 1 ? media : null,
          likes: formatCount(like?.count ?? post.likesCount),
          onOpen: () => widget.onOpen != null
              ? widget.onOpen!(post)
              : PostScreen.open(context, post: post),
          onLikesCountTap: () => LikedBySheet.show(
            context,
            postId: target.postId,
            count: like?.count ?? post.likesCount,
          ),
          isLiked: like?.isLiked ?? post.isLiked,
          isLikePending: like?.pending == true,
          onLikeTap: () async {
            final error = await _likes.toggle(
              target,
              initial: post.hasLikeState
                  ? LikeValue(isLiked: post.isLiked, count: post.likesCount)
                  : null,
            );
            if (error != null && context.mounted) _snack(error.message);
          },
          comments: formatCount(comments),
          onCommentsTap: () => CommentsScreen.open(
            context,
            postId: int.parse(post.id),
            likes: _likes,
            initialCount: comments,
            commentsDisabled: _commentsDisabled(post),
            onCountChanged: (count) {
              if (!mounted) return;
              context.read<PostActivityCubit?>()?.setCommentsCount(
                post.id,
                count,
              );
              setState(() => _comments[post.id] = count);
            },
          ),
          onMoreTap: () => _options(post),
          onShareTap: () async {
            if (_openingShare) return;
            _openingShare = true;
            try {
              await SendPostSheet.show(context, post: post);
            } finally {
              _openingShare = false;
            }
          },
          isSaved: saves?.values[post.id] ?? post.isSaved,
          isSavePending: saves?.pending.contains(post.id) ?? false,
          onSaveTap: saves == null
              ? null
              : () async {
                  final error = await context.read<SavesCubit>().toggle(post);
                  if (error != null && context.mounted) _snack(error.message);
                },
        );
      },
    );
  }

  bool _commentsDisabled(PostModel post) =>
      context.read<PostActivityCubit?>()?.state.commentsDisabled[post.id] ??
      post.commentsDisabled;

  void _snack(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<void> _options(PostModel result) async {
    if (_openingOptions) return;
    final post = result.copyWith(commentsDisabled: _commentsDisabled(result));
    final hidden = context.read<HiddenPostsCubit?>();
    final block = context.read<BlockCubit?>();
    if (hidden?.state.pending.contains(post.id) == true ||
        block?.state.pending.contains(post.user.id) == true) {
      return;
    }
    final own = isViewer(
      context,
      post.userId.isNotEmpty ? post.userId : post.user.id,
    );
    _openingOptions = true;
    final PostOptionAction? action;
    try {
      action = await PostOptionsSheet.show(
        context,
        actions: own
            ? ownPostActions
            : {
                if (hidden != null) ...[
                  PostOptionAction.notInterested,
                  PostOptionAction.hidePost,
                  PostOptionAction.report,
                ],
                if (block != null) PostOptionAction.blockUser,
              },
        commentsDisabled: post.commentsDisabled,
      );
    } finally {
      _openingOptions = false;
    }
    if (!mounted || action == null) return;
    if (own) {
      final feed = _mutations ??= PostsCubit(
        likes: _likes,
        saves: context.read<SavesCubit?>(),
        activity: context.read<PostActivityCubit?>(),
      );
      await runOwnPostAction(context, action: action, post: post, feed: feed);
    } else if (action == PostOptionAction.notInterested && hidden != null) {
      await notInterestedFlow(context, postId: post.id, hidden: hidden);
    } else if (action == PostOptionAction.report && hidden != null) {
      await reportPostFlow(context, postId: post.id, repo: hidden.repo);
    } else if (action == PostOptionAction.blockUser && block != null) {
      await confirmBlockChange(
        context,
        post.user.id,
        blocked: true,
        name: post.user.name,
      );
    } else if (action == PostOptionAction.hidePost && hidden != null) {
      final error = await hidden.setHidden(post.id, true);
      if (mounted) _snack(error?.message ?? 'Post hidden');
    }
  }
}
