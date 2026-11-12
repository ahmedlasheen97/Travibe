import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/features/stories/cubit/story_likes_cubit.dart';
import 'package:travibe/features/stories/data/story_model.dart';
import 'package:travibe/features/stories/widgets/story_glass.dart';

class StoryLikeButton extends StatelessWidget {
  const StoryLikeButton({
    super.key,
    required this.detail,
    required this.likes,
    this.onError,
  });
  final StoryDetail detail;
  final StoryLikesCubit likes;
  final ValueChanged<ApiError>? onError;

  @override
  Widget build(BuildContext context) =>
      BlocBuilder<StoryLikesCubit, StoryLikesState>(
        bloc: likes,
        builder: (context, state) {
          final value = state.values[detail.id];
          final liked = value?.isLiked ?? detail.isLiked;
          final pending = value?.pending == true;
          final refresh = state.refreshRequired.contains(detail.id);
          return StoryGlass(
            child: SizedBox.square(
              dimension: 48,
              child: IconButton(
                key: const ValueKey('story-like'),
                tooltip: refresh
                    ? 'Refresh like status'
                    : liked
                    ? 'Unlike Story'
                    : 'Like Story',
                isSelected: liked,
                onPressed: pending
                    ? null
                    : () async {
                        final error = await likes.toggle(detail);
                        if (context.mounted && error != null) {
                          onError?.call(error);
                        }
                      },
                icon: pending
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : SvgPicture.asset(
                        liked
                            ? 'assets/images/interactions/heart.svg'
                            : 'assets/images/interactions/heart2.svg',
                        width: 20,
                        height: 20,
                        excludeFromSemantics: true,
                      ),
              ),
            ),
          );
        },
      );
}
