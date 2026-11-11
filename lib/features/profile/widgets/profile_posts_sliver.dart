import 'package:travibe/features/profile/widgets/profile_empty_state.dart';
import 'package:travibe/features/create_post/screens/create_post_screen.dart';
import 'package:travibe/features/create_post/cubit/post_upload_cubit.dart';
import 'package:travibe/features/profile/widgets/profile_shimmer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:travibe/core/utils/formatters.dart';
import 'package:travibe/core/widgets/post_card.dart';
import 'package:travibe/features/block/cubit/block_cubit.dart';
import 'package:travibe/features/block/widgets/block_user_button.dart';
import 'package:travibe/features/comments/screens/comments_screen.dart';
import 'package:travibe/features/follow/cubit/follow_cubit.dart';
import 'package:travibe/features/follow/widgets/follow_action_builder.dart';
import 'package:travibe/features/home/cubit/hidden_posts_cubit.dart';
import 'package:travibe/features/home/cubit/posts_cubit.dart';
import 'package:travibe/features/home/data/post_model.dart';
import 'package:travibe/features/home/widgets/post_options_sheet.dart';
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
    this.onCreatePost,
  });
  final bool showLoadingIndicators;
  final VoidCallback? onCreatePost;
  final bool owner;
  @override
  State<ProfilePostsSliver> createState() => _ProfilePostsSliverState();
}

class _ProfilePostsSliverState extends State<ProfilePostsSliver> {
  bool _openingShare = false;
  bool _creating = false;
  Future<void> _create() async {
    if (_creating) return;
    if (widget.onCreatePost != null) {
      widget.onCreatePost!();
      return;
    }
    _creating = true;
    try {
      final draft = await CreatePostScreen.open(context);
      if (draft != null && mounted) {
        // Root's uploader publishes it and notifies PostActivityCubit.
        context.read<PostUploadCubit>().enqueue(draft);
      }
    } finally {
      _creating = false;
    }
  }

  @override
  void initState() {
    super.initState();
    final posts = context.read<PostsCubit>();
    if (posts.state is PostsInitial) posts.loadPosts();
  }

  Widget _message(String text, {VoidCallback? retry}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 24),
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
    builder: (context, state) {
      final posts = context.read<PostsCubit>();
      return SliverPadding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
        sliver: SliverList(
          delegate: SliverChildListDelegate([
            if (widget.showLoadingIndicators &&
                (state is PostsInitial || state is PostsLoading))
              const ProfilePostSkeleton(),
            if (state is PostsFailure)
              _message(state.errorMessage, retry: posts.loadPosts),
            if (state is PostsLoaded) ...[
              if (state.refreshError != null)
                _message(state.refreshError!.message, retry: posts.refresh),
              if (state.posts.isEmpty &&
                  !state.isRefreshing &&
                  state.refreshError == null)
                ProfileEmptyState(
                  asset: 'assets/images/profile/emptypost.svg',
                  title: 'No posts yet',
                  description: widget.owner
                      ? 'Share your first travel story and inspire other travelers.'
                      : 'This traveler hasn’t shared any posts yet.',
                  actionLabel: widget.owner ? 'Create Post' : null,
                  onAction: widget.owner ? _create : null,
                ),
              for (final post in state.posts)
                Padding(
                  key: ValueKey('profile-post-${post.id}'),
                  padding: const EdgeInsets.only(bottom: 16),
                  child: _card(post),
                ),
              if (state.isLoadingMore && widget.showLoadingIndicators)
                const Center(child: CircularProgressIndicator()),
              if (state.paginationError != null)
                _message(
                  state.paginationError!.message,
                  retry: () => posts.loadMore(retry: true),
                )
              else if (state.hasMore &&
                  !state.isRefreshing &&
                  !state.isLoadingMore)
                TextButton(
                  onPressed: posts.loadMore,
                  child: const Text('Load more'),
                ),
            ],
          ]),
        ),
      );
    },
  );
  Widget _card(PostModel post) {
    final posts = context.read<PostsCubit>();
    final media = post.media.map((m) => m.displayUrl).toList();
    Widget card(
      bool following,
      bool pending,
      VoidCallback? toggle,
    ) => BlocBuilder<SavesCubit, SavesState>(
      builder: (context, saves) => PostCard(
        postId: post.id,
        authorId: post.user.id,
        name: post.user.name,
        avatar: post.user.avatarUrl,
        time: timeAgo(post.createdAt),
        text: post.content ?? '',
        image: media.length == 1 ? media.first : null,
        images: media.length > 1 ? media : null,
        likes: formatCount(post.likesCount),
        isLiked: post.isLiked,
        isLikePending:
            context
                .watch<LikesCubit>()
                .value(LikeTarget.post(int.parse(post.id)))
                ?.pending ==
            true,
        onLikeTap: () async {
          final error = await context.read<PostsCubit>().toggleLike(post);
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
        isSaved: saves.values[post.id] ?? post.isSaved,
        isSavePending: saves.pending.contains(post.id),
        onSaveTap: () async {
          final error = await context.read<SavesCubit>().toggle(post);
          if (error != null && context.mounted) _error(context, error.message);
        },
        showFollowButton: !widget.owner && context.read<FollowCubit?>() != null,
        isFollowing: following,
        isFollowPending: pending,
        onFollowTap: toggle,
        onMoreTap: !widget.owner ? () => _options(post) : null,
      ),
    );
    return context.read<FollowCubit?>() == null || widget.owner
        ? card(post.user.isFollowing, false, null)
        : FollowActionBuilder(
            userId: post.user.id,
            initialFollowing: post.user.isFollowing,
            builder: (context, following, pending, toggle) =>
                card(following, pending, toggle),
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
              PostOptionAction.hidePost,
              if (block != null) PostOptionAction.blockUser,
            },
      commentsDisabled: post.commentsDisabled,
    );
    if (!mounted || action == null) return;
    if (own) {
      await runOwnPostAction(context, action: action, post: post, feed: feed);
      return;
    }
    if (action == PostOptionAction.blockUser) {
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
