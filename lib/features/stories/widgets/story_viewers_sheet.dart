import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:travibe/core/widgets/sheet_handle.dart';
import 'package:travibe/features/block/cubit/block_cubit.dart';
import 'package:travibe/features/block/widgets/block_user_button.dart';
import 'package:travibe/features/follow/cubit/follow_cubit.dart';
import 'package:travibe/features/follow/widgets/follow_action_builder.dart';
import 'package:travibe/features/follow/widgets/follow_pill.dart';
import 'package:travibe/features/home/widgets/home_user_avatar.dart';
import 'package:travibe/features/home/widgets/post_options_sheet.dart';
import 'package:travibe/features/stories/cubit/story_viewers_cubit.dart';
import 'package:travibe/features/stories/data/story_model.dart';

class StoryViewersSheet extends StatelessWidget {
  const StoryViewersSheet({
    super.key,
    required this.cubit,
    required this.count,
    this.follow,
    this.blocks,
  });
  final StoryViewersCubit cubit;
  final int count;
  final FollowCubit? follow;
  final BlockCubit? blocks;

  @override
  Widget build(BuildContext context) {
    final content = ColoredBox(color: Colors.black, child: _content());
    if (follow == null && blocks == null) return content;
    return MultiBlocProvider(
      providers: [
        if (follow != null) BlocProvider.value(value: follow!),
        if (blocks != null) BlocProvider.value(value: blocks!),
      ],
      child: content,
    );
  }

  Widget _content() => Builder(
    builder: (context) => SafeArea(
      top: false,
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * .65,
        child: Column(
          children: [
            const SizedBox(height: 12),
            const SheetHandle(),
            const SizedBox(height: 20),
            Expanded(
              child: BlocBuilder<StoryViewersCubit, StoryViewersState>(
                bloc: cubit,
                builder: (context, state) =>
                    NotificationListener<ScrollNotification>(
                      onNotification: (notification) {
                        if (notification.metrics.extentAfter < 180) {
                          cubit.loadMore();
                        }
                        return false;
                      },
                      child: RefreshIndicator(
                        onRefresh: cubit.refresh,
                        child: ListView(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          physics: const AlwaysScrollableScrollPhysics(),
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.start,
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
                                    '$count Views',
                                    textAlign: TextAlign.start,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 18,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const Padding(
                              padding: EdgeInsets.only(top: 10, bottom: 20),
                              child: Text(
                                'Only you can see who viewed your story.',
                                textAlign: TextAlign.start,
                                style: TextStyle(color: Colors.white70),
                              ),
                            ),
                            for (final user in state.users) _row(context, user),
                            if (state.loading)
                              const Padding(
                                padding: EdgeInsets.all(20),
                                child: Center(
                                  child: CircularProgressIndicator(),
                                ),
                              ),
                            if (state.error != null)
                              Column(
                                children: [
                                  Text(
                                    state.error!.message,
                                    textAlign: TextAlign.center,
                                  ),
                                  TextButton(
                                    onPressed: state.users.isEmpty
                                        ? cubit.refresh
                                        : cubit.loadMore,
                                    child: const Text('Retry'),
                                  ),
                                ],
                              ),
                            if (!state.loading &&
                                state.error == null &&
                                state.users.isEmpty)
                              const Padding(
                                padding: EdgeInsets.all(24),
                                child: Center(child: Text('No viewers yet.')),
                              ),
                            if (state.hasMore &&
                                !state.loading &&
                                state.error == null)
                              TextButton(
                                onPressed: cubit.loadMore,
                                child: const Text('Load more'),
                              ),
                          ],
                        ),
                      ),
                    ),
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _row(BuildContext context, StoryViewerUser user) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Row(
      children: [
        HomeUserAvatar(url: user.author.avatarUrl, size: 44),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            user.author.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white),
          ),
        ),
        if (user.hasLiked) ...[
          const SizedBox(width: 8),
          SvgPicture.asset(
            'assets/images/interactions/heart.svg',
            key: ValueKey('story-viewer-liked-${user.author.id}'),
            width: 20,
            height: 20,
            semanticsLabel: 'Liked this story',
          ),
        ],
        const SizedBox(width: 8),
        if (follow != null)
          FollowActionBuilder(
            userId: user.author.id.toString(),
            initialFollowing: user.isFollowing,
            builder: (context, following, pending, toggle) => ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 120),
              child: FollowPill(
                following: following,
                pending: pending,
                onPressed: toggle,
                // Keep the same neutral background while disabled/pending too.
                style: const ButtonStyle(
                  backgroundColor: WidgetStatePropertyAll(
                    FollowPill.backgroundColor,
                  ),
                  foregroundColor: WidgetStatePropertyAll(Colors.white),
                  overlayColor: WidgetStatePropertyAll(Colors.white10),
                ),
              ),
            ),
          ),
        if (blocks != null)
          IconButton(
            tooltip: 'Viewer options',
            icon: const Icon(Icons.more_vert, color: Colors.white),
            onPressed: () async {
              final action = await PostOptionsSheet.show(
                context,
                actions: const {PostOptionAction.blockUser},
              );
              if (action == PostOptionAction.blockUser &&
                  context.mounted &&
                  cubit.isOwner()) {
                await confirmBlockChange(
                  context,
                  user.author.id.toString(),
                  blocked: true,
                  name: user.author.name,
                );
              }
            },
          ),
      ],
    ),
  );
}
