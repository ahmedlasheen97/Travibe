import 'package:travibe/core/constants/app_sizes.dart';
import 'package:travibe/core/constants/feature_flags.dart';
import 'package:travibe/features/home/screens/post_screen.dart';
import 'package:travibe/features/likes/widgets/liked_by_sheet.dart';
import 'package:travibe/features/profile/widgets/profile_empty_state.dart';
import 'package:travibe/features/profile/widgets/profile_shimmer.dart';
import 'package:travibe/features/home/cubit/post_activity_cubit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:travibe/core/utils/formatters.dart';
import 'package:travibe/core/widgets/lazy_keyed_sliver_list.dart';
import 'package:travibe/core/widgets/post_card.dart';
import 'package:travibe/features/comments/screens/comments_screen.dart';
import 'package:travibe/features/likes/cubit/likes_cubit.dart';
import 'package:travibe/features/likes/data/like_model.dart';
import 'package:travibe/features/saved/cubit/saved_posts_cubit.dart';
import 'package:travibe/features/saved/cubit/saves_cubit.dart';
import 'package:travibe/features/home/data/post_model.dart';
import 'package:travibe/features/shares/widgets/send_post_sheet.dart';
import 'package:travibe/core/utils/viewer_identity.dart';
import 'package:travibe/features/block/cubit/block_cubit.dart';
import 'package:travibe/features/block/widgets/block_user_button.dart';
import 'package:travibe/features/home/cubit/hidden_posts_cubit.dart';
import 'package:travibe/features/home/cubit/posts_cubit.dart';
import 'package:travibe/features/home/widgets/own_post_actions.dart';
import 'package:travibe/features/home/widgets/post_options_sheet.dart';
import 'package:travibe/features/home/widgets/post_report_flow.dart';

/// Lives inside Profile's existing CustomScrollView, including its refresh gesture.
class SavedPostsSliver extends StatefulWidget {
  const SavedPostsSliver({
    super.key,
    this.showLoadingIndicators = true,
    this.bottomInset = 0,
  });
  final bool showLoadingIndicators;

  /// Root's bottom nav clearance; this tab owns it (see Profile).
  final double bottomInset;
  @override
  State<SavedPostsSliver> createState() => _SavedPostsSliverState();
}

class _SavedPostsSliverState extends State<SavedPostsSliver> {
  late final LikesCubit _likes;
  late final bool _ownsLikes;
  final _comments = <String, int>{};
  bool _openingShare = false, _openingOptions = false;

  /// Own-post mutations (delete, commenting); other lists learn about them
  /// through the shared PostActivityCubit.
  PostsCubit? _mutations;
  @override
  void initState() {
    super.initState();
    _ownsLikes = context.read<LikesCubit?>() == null;
    _likes = context.read<LikesCubit?>() ?? LikesCubit();
    final saved = context.read<SavedPostsCubit>();
    if (saved.state.status == SavedPostsStatus.initial) saved.load();
  }

  @override
  void dispose() {
    if (_ownsLikes) _likes.close();
    _mutations?.close();
    super.dispose();
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

  /// Same list shape: same post ids and flags. A change inside one post
  /// rebuilds only that card (its own [BlocSelector]).
  static bool _sameShape(SavedPostsState a, SavedPostsState b) {
    if (a.status != b.status ||
        a.hasMore != b.hasMore ||
        a.refreshing != b.refreshing ||
        a.loadingMore != b.loadingMore ||
        a.error != b.error ||
        a.paginationError != b.paginationError ||
        a.posts.length != b.posts.length) {
      return false;
    }
    for (var i = 0; i < a.posts.length; i++) {
      if (a.posts[i].id != b.posts[i].id) return false;
    }
    return true;
  }

  @override
  Widget build(
    BuildContext context,
  ) => BlocBuilder<SavedPostsCubit, SavedPostsState>(
    buildWhen: (a, b) => !_sameShape(a, b),
    builder: (context, state) {
      final cubit = context.read<SavedPostsCubit>();
      if (state.status == SavedPostsStatus.loaded &&
          state.posts.isEmpty &&
          !state.refreshing &&
          state.error == null &&
          state.paginationError == null &&
          !state.hasMore) {
        return ProfileEmptyStateSliver(
          asset: 'assets/images/profile/emptyitems.png',
          title: 'No saved items yet',
          description: kShowSavedHotels
              ? 'Save posts and hotels to find them here.'
              : 'Save posts to find them here.',
          bottomInset: widget.bottomInset,
        );
      }
      return SliverPadding(
        padding: EdgeInsets.fromLTRB(
          AppSizes.pw20,
          AppSizes.ph16,
          AppSizes.pw20,
          AppSizes.ph16 + widget.bottomInset,
        ),
        sliver: LazyKeyedSliverList(
          keyPrefix: 'saved-',
          ids: [
            if (state.status == SavedPostsStatus.loaded)
              for (final post in state.posts) post.id,
          ],
          itemBuilder: (context, id) => Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: _card(id),
          ),
          leading: [
            if (widget.showLoadingIndicators &&
                state.status == SavedPostsStatus.loading)
              const ProfilePostSkeleton(),
            if (state.status == SavedPostsStatus.initial)
              _message('Load your saved posts.', retry: cubit.load),
            if (state.status == SavedPostsStatus.failure)
              _message(state.error!.message, retry: cubit.load),
            if (state.status == SavedPostsStatus.loaded && state.error != null)
              _message(state.error!.message, retry: cubit.refresh),
          ],
          trailing: [
            if (state.status == SavedPostsStatus.loaded) ...[
              if (state.loadingMore && widget.showLoadingIndicators)
                const Center(child: CircularProgressIndicator()),
              if (state.paginationError != null)
                _message(
                  state.paginationError!.message,
                  retry: () => cubit.loadMore(retry: true),
                )
              else if (state.hasMore && !state.loadingMore && !state.refreshing)
                TextButton(
                  onPressed: cubit.loadMore,
                  child: const Text('Load more'),
                ),
            ],
          ],
        ),
      );
    },
  );

  static PostModel? _postById(SavedPostsState state, String id) {
    for (final post in state.posts) {
      if (post.id == id) return post;
    }
    return null;
  }

  /// One card. It rebuilds only when its own post, save state or like
  /// changes, not when another post is liked or saved.
  Widget _card(String id) =>
      BlocSelector<SavedPostsCubit, SavedPostsState, PostModel?>(
        selector: (state) => _postById(state, id),
        builder: (context, post) =>
            post == null ? const SizedBox.shrink() : _postCard(post),
      );

  Widget _postCard(PostModel post) {
    final target = LikeTarget.post(int.parse(post.id));
    final media = post.media.map((m) => m.displayUrl).toList();
    return BlocSelector<SavesCubit, SavesState, (bool?, bool)>(
      selector: (saves) =>
          (saves.values[post.id], saves.pending.contains(post.id)),
      builder: (context, save) =>
          BlocSelector<LikesCubit, LikesState, (bool, int, bool)?>(
            bloc: _likes,
            selector: (likes) => switch (likes.values[target]) {
              final value? => (value.isLiked, value.count, value.pending),
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
              return PostCard(
                postId: post.id,
                name: post.user.name,
                avatar: post.user.avatarUrl,
                avatarSize: AppSizes.w40,
                time: timeAgo(post.createdAt),
                text: post.content ?? '',
                image: media.length == 1 ? media.first : null,
                images: media.length > 1 ? media : null,
                likes: formatCount(value?.count ?? post.likesCount),
                onOpen: () => PostScreen.open(context, post: post),
                onLikesCountTap: () => LikedBySheet.show(
                  context,
                  postId: target.postId,
                  count: value?.count ?? post.likesCount,
                ),
                isLiked: value?.isLiked ?? post.isLiked,
                isLikePending: value?.pending == true,
                onLikeTap: () async {
                  final error = await _likes.toggle(
                    target,
                    initial: post.hasLikeState
                        ? LikeValue(
                            isLiked: post.isLiked,
                            count: post.likesCount,
                          )
                        : null,
                  );
                  if (error != null && context.mounted) {
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(SnackBar(content: Text(error.message)));
                  }
                },
                comments: formatCount(_comments[post.id] ?? post.commentsCount),
                onCommentsTap: () => CommentsScreen.open(
                  context,
                  postId: int.parse(post.id),
                  likes: _likes,
                  initialCount:
                      context
                          .read<PostActivityCubit?>()
                          ?.state
                          .comments[post.id] ??
                      _comments[post.id] ??
                      post.commentsCount,
                  commentsDisabled: post.commentsDisabled,
                  onCountChanged: (count) {
                    if (!mounted) return;
                    context.read<PostActivityCubit?>()?.setCommentsCount(
                      post.id,
                      count,
                    );
                    if (mounted) setState(() => _comments[post.id] = count);
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
                isSaved: save.$1 ?? post.isSaved,
                isSavePending: save.$2,
                onSaveTap: () async {
                  final error = await context.read<SavesCubit>().toggle(post);
                  if (error != null && context.mounted) {
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(SnackBar(content: Text(error.message)));
                  }
                },
              );
            },
          ),
    );
  }

  void _snack(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<void> _options(PostModel saved) async {
    if (_openingOptions) return;
    final disabled = context
        .read<PostActivityCubit?>()
        ?.state
        .commentsDisabled[saved.id];
    final post = disabled == null
        ? saved
        : saved.copyWith(commentsDisabled: disabled);
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
