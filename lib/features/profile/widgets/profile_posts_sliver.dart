import 'package:travibe/core/constants/app_sizes.dart';
import 'package:travibe/features/home/screens/post_screen.dart';
import 'package:travibe/features/likes/widgets/liked_by_sheet.dart';
import 'package:travibe/features/profile/widgets/profile_empty_state.dart';
import 'package:travibe/features/profile/widgets/profile_shimmer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:travibe/core/utils/formatters.dart';
import 'package:travibe/core/widgets/lazy_keyed_sliver_list.dart';
import 'package:travibe/core/widgets/post_card.dart';
import 'package:travibe/features/block/cubit/block_cubit.dart';
import 'package:travibe/features/block/widgets/block_user_button.dart';
import 'package:travibe/features/comments/screens/comments_screen.dart';
import 'package:travibe/features/follow/cubit/follow_cubit.dart';
import 'package:travibe/features/home/cubit/hidden_posts_cubit.dart';
import 'package:travibe/features/home/cubit/posts_cubit.dart';
import 'package:travibe/features/home/data/post_model.dart';
import 'package:travibe/features/home/widgets/post_options_sheet.dart';
import 'package:travibe/features/home/widgets/post_report_flow.dart';
import 'package:travibe/features/home/widgets/own_post_actions.dart';
import 'package:travibe/core/utils/viewer_identity.dart';
import 'package:travibe/features/likes/cubit/likes_cubit.dart';
import 'package:travibe/features/likes/data/like_model.dart';
import 'package:travibe/features/saved/cubit/saves_cubit.dart';
import 'package:travibe/features/shares/widgets/send_post_sheet.dart';
import 'package:travibe/features/shares/data/send_post_repo.dart';

class ProfilePostsSliver extends StatefulWidget {
  const ProfilePostsSliver({
    super.key,
    required this.owner,
    this.showLoadingIndicators = true,
    this.bottomInset = 0,
  });
  final bool showLoadingIndicators;

  /// Root's bottom nav clearance; this tab owns it (see Profile).
  final double bottomInset;
  final bool owner;
  @override
  State<ProfilePostsSliver> createState() => _ProfilePostsSliverState();
}

class _ProfilePostsSliverState extends State<ProfilePostsSliver> {
  bool _openingShare = false;

  @override
  void initState() {
    super.initState();
    final posts = context.read<PostsCubit>();
    if (posts.state is PostsInitial) posts.loadPosts();
  }

  Widget _message(String text, {VoidCallback? retry}) => Padding(
    padding: EdgeInsets.symmetric(vertical: AppSizes.ph24),
    child: Column(
      children: [
        Text(text, style: const TextStyle(color: Colors.white70)),
        if (retry != null)
          TextButton(onPressed: retry, child: const Text('Retry')),
      ],
    ),
  );
  @override
  Widget build(BuildContext context) => BlocBuilder<PostsCubit, PostsState>(
    // Changes inside one post rebuild only that card (see _card).
    buildWhen: (a, b) => !a.sameShapeAs(b),
    builder: (context, state) {
      final posts = context.read<PostsCubit>();
      if (state is PostsLoaded &&
          state.posts.isEmpty &&
          !state.isRefreshing &&
          state.refreshError == null &&
          state.paginationError == null &&
          !state.hasMore) {
        return ProfileEmptyStateSliver(
          asset: 'assets/images/profile/emptypost.png',
          title: 'No posts yet',
          description: widget.owner
              ? null
              : 'This traveler hasn’t shared any posts yet.',
          // No button: the nav bar's + creates posts.
          bottomInset: widget.bottomInset,
        );
      }
      final loaded = state is PostsLoaded ? state : null;
      return SliverPadding(
        padding: EdgeInsets.fromLTRB(
          AppSizes.pw20,
          AppSizes.ph16,
          AppSizes.pw20,
          AppSizes.ph16 + widget.bottomInset,
        ),
        sliver: LazyKeyedSliverList(
          keyPrefix: 'profile-post-',
          ids: [for (final post in loaded?.posts ?? const []) post.id],
          itemBuilder: (context, id) => Padding(
            padding: EdgeInsets.only(bottom: AppSizes.ph16),
            child: _card(id),
          ),
          leading: [
            if (widget.showLoadingIndicators &&
                (state is PostsInitial || state is PostsLoading))
              const ProfilePostSkeleton(),
            if (state is PostsFailure)
              _message(state.errorMessage, retry: posts.loadPosts),
            if (loaded?.refreshError case final error?)
              _message(error.message, retry: posts.refresh),
          ],
          trailing: [
            if (loaded != null) ...[
              if (loaded.isLoadingMore && widget.showLoadingIndicators)
                const Center(child: CircularProgressIndicator()),
              if (loaded.paginationError != null)
                _message(
                  loaded.paginationError!.message,
                  retry: () => posts.loadMore(retry: true),
                )
              else if (loaded.hasMore &&
                  !loaded.isRefreshing &&
                  !loaded.isLoadingMore)
                TextButton(
                  onPressed: posts.loadMore,
                  child: const Text('Load more'),
                ),
            ],
          ],
        ),
      );
    },
  );

  /// One card. It rebuilds only when its own post, its save state or its
  /// like-pending flag changes, not when another post is liked or saved.
  Widget _card(String id) => BlocSelector<PostsCubit, PostsState, PostModel?>(
    selector: (state) => state.postById(id),
    builder: (context, post) {
      if (post == null) return const SizedBox.shrink();
      final target = int.tryParse(post.id) == null
          ? null
          : LikeTarget.post(int.parse(post.id));
      return BlocSelector<SavesCubit, SavesState, (bool?, bool)>(
        selector: (saves) =>
            (saves.values[post.id], saves.pending.contains(post.id)),
        builder: (context, save) => BlocSelector<LikesCubit, LikesState, bool>(
          selector: (likes) =>
              target != null && likes.values[target]?.pending == true,
          builder: (context, likePending) =>
              _postCard(context, post, save, likePending),
        ),
      );
    },
  );

  Widget _postCard(
    BuildContext context,
    PostModel post,
    (bool?, bool) save,
    bool likePending,
  ) {
    final posts = context.read<PostsCubit>();
    final media = post.media.map((m) => m.displayUrl).toList();
    // Every card here is by the profile's user; Follow lives in the header.
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
      likes: formatCount(post.likesCount),
      onOpen: () => PostScreen.open(context, post: post),
      onLikesCountTap: () => LikedBySheet.show(
        context,
        postId: int.parse(post.id),
        count: post.likesCount,
      ),
      isLiked: post.isLiked,
      isLikePending: likePending,
      onLikeTap: () async {
        final error = await posts.toggleLike(post);
        if (error != null && context.mounted) _error(context, error.message);
      },
      comments: formatCount(post.commentsCount),
      onCommentsTap: () => CommentsScreen.open(
        context,
        postId: int.parse(post.id),
        initialCount: post.commentsCount,
        likes: context.read<LikesCubit>(),
        commentsDisabled: post.commentsDisabled,
        onCountChanged: (count) {
          if (mounted) posts.setCommentsCount(post.id, count);
        },
      ),
      onShareTap: () => _share(post),
      isSaved: save.$1 ?? post.isSaved,
      isSavePending: save.$2,
      onSaveTap: () async {
        final error = await context.read<SavesCubit>().toggle(post);
        if (error != null && context.mounted) _error(context, error.message);
      },
      onMoreTap: () => _options(post),
    );
  }

  void _error(BuildContext context, String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  Future<void> _share(PostModel post) async {
    if (_openingShare) return;
    _openingShare = true;
    try {
      await SendPostSheet.show(
        context,
        post: post,
        repo: SendPostRepo(discovery: context.read<FollowCubit?>()?.repo),
      );
    } finally {
      _openingShare = false;
    }
  }

  Future<void> _options(PostModel post) async {
    final hidden = context.read<HiddenPostsCubit>();
    final block = context.read<BlockCubit?>();
    if (hidden.state.pending.contains(post.id) ||
        block?.state.pending.contains(post.user.id) == true) {
      return;
    }
    final own =
        widget.owner ||
        isViewer(context, post.userId.isNotEmpty ? post.userId : post.user.id);
    final feed = context.read<PostsCubit>();
    final action = await PostOptionsSheet.show(
      context,
      actions: own
          ? ownPostActions
          : {
              PostOptionAction.notInterested,
              PostOptionAction.hidePost,
              PostOptionAction.report,
              if (block != null) PostOptionAction.blockUser,
            },
      commentsDisabled: post.commentsDisabled,
    );
    if (!mounted || action == null) return;
    if (own) {
      await runOwnPostAction(context, action: action, post: post, feed: feed);
      return;
    }
    if (action == PostOptionAction.notInterested) {
      await notInterestedFlow(context, postId: post.id, hidden: hidden);
    } else if (action == PostOptionAction.report) {
      await reportPostFlow(context, postId: post.id, repo: hidden.repo);
    } else if (action == PostOptionAction.blockUser) {
      await confirmBlockChange(
        context,
        post.user.id,
        blocked: true,
        name: post.user.name,
      );
    } else if (action == PostOptionAction.hidePost) {
      final error = await hidden.setHidden(post.id, true);
      if (!mounted) return;
      if (error != null) {
        _error(context, error.message);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'Post hidden from feeds. It remains visible on this profile.',
            ),
            action: SnackBarAction(
              label: 'Undo',
              onPressed: () async {
                if (!mounted) return;
                final error = await hidden.setHidden(post.id, false);
                if (mounted && error != null) _error(context, error.message);
              },
            ),
          ),
        );
      }
    }
  }
}
