import 'package:travibe/features/home/screens/post_screen.dart';
import 'package:travibe/features/likes/widgets/liked_by_sheet.dart';
import 'package:travibe/features/profile/widgets/profile_empty_state.dart';
import 'package:travibe/features/profile/widgets/profile_shimmer.dart';
import 'package:travibe/features/home/cubit/post_activity_cubit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:travibe/core/utils/formatters.dart';
import 'package:travibe/core/widgets/post_card.dart';
import 'package:travibe/features/comments/screens/comments_screen.dart';
import 'package:travibe/features/likes/cubit/likes_cubit.dart';
import 'package:travibe/features/likes/data/like_model.dart';
import 'package:travibe/features/saved/cubit/saved_posts_cubit.dart';
import 'package:travibe/features/saved/cubit/saves_cubit.dart';
import 'package:travibe/features/home/data/post_model.dart';
import 'package:travibe/features/shares/widgets/send_post_sheet.dart';

/// Lives inside Profile's existing CustomScrollView, including its refresh gesture.
class SavedPostsSliver extends StatefulWidget {
  const SavedPostsSliver({super.key, this.showLoadingIndicators = true});
  final bool showLoadingIndicators;
  @override
  State<SavedPostsSliver> createState() => _SavedPostsSliverState();
}

class _SavedPostsSliverState extends State<SavedPostsSliver> {
  late final LikesCubit _likes;
  late final bool _ownsLikes;
  final _comments = <String, int>{};
  bool _openingShare = false;
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
  @override
  Widget build(BuildContext context) =>
      BlocBuilder<SavedPostsCubit, SavedPostsState>(
        builder: (context, state) {
          final cubit = context.read<SavedPostsCubit>();
          return SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                if (widget.showLoadingIndicators &&
                    state.status == SavedPostsStatus.loading)
                  const ProfilePostSkeleton(),
                if (state.status == SavedPostsStatus.initial)
                  _message('Load your saved posts.', retry: cubit.load),
                if (state.status == SavedPostsStatus.failure)
                  _message(state.error!.message, retry: cubit.load),
                if (state.status == SavedPostsStatus.loaded) ...[
                  if (state.error != null)
                    _message(state.error!.message, retry: cubit.refresh),
                  if (state.posts.isEmpty &&
                      !state.refreshing &&
                      state.error == null)
                    const ProfileEmptyState(
                      asset: 'assets/images/profile/emptyitems.svg',
                      title: 'No saved items yet',
                      description: 'Save posts and hotels to find them here.',
                    ),
                  for (final post in state.posts)
                    Padding(
                      key: ValueKey('saved-${post.id}'),
                      padding: const EdgeInsets.only(bottom: 16),
                      child: _card(post),
                    ),
                  if (state.loadingMore && widget.showLoadingIndicators)
                    const Center(child: CircularProgressIndicator()),
                  if (state.paginationError != null)
                    _message(
                      state.paginationError!.message,
                      retry: () => cubit.loadMore(retry: true),
                    )
                  else if (state.hasMore &&
                      !state.loadingMore &&
                      !state.refreshing)
                    TextButton(
                      onPressed: cubit.loadMore,
                      child: const Text('Load more'),
                    ),
                ],
              ]),
            ),
          );
        },
      );

  Widget _card(PostModel post) {
    final target = LikeTarget.post(int.parse(post.id));
    final media = post.media.map((m) => m.displayUrl).toList();
    return BlocBuilder<SavesCubit, SavesState>(
      builder: (context, saves) => BlocBuilder<LikesCubit, LikesState>(
        bloc: _likes,
        builder: (context, likes) {
          final value = likes.values[target];
          return PostCard(
            postId: post.id,
            name: post.user.name,
            avatar: post.user.avatarUrl,
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
                    ? LikeValue(isLiked: post.isLiked, count: post.likesCount)
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
                  context.read<PostActivityCubit?>()?.state.comments[post.id] ??
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
            onShareTap: () async {
              if (_openingShare) return;
              _openingShare = true;
              try {
                await SendPostSheet.show(context, post: post);
              } finally {
                _openingShare = false;
              }
            },
            isSaved: saves.values[post.id] ?? post.isSaved,
            isSavePending: saves.pending.contains(post.id),
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
}
