import 'package:travibe/core/cubit/cursor_list_cubit.dart';
import 'package:travibe/core/models/public_user_model.dart';
import 'package:travibe/features/likes/data/like_model.dart';
import 'package:travibe/features/likes/data/likes_repo.dart';

/// Separate from offset-paginated Follow/Search lists and from like mutations.
class LikesUsersCubit extends CursorListCubit<PublicUserModel> {
  LikesUsersCubit({required LikeTarget target, LikesRepo? repo})
    : this._(repo ?? LikesRepo(), target: target);

  LikesUsersCubit.story({required int storyId, LikesRepo? repo})
    : this._(repo ?? LikesRepo(), storyId: storyId);

  LikesUsersCubit._(LikesRepo repo, {LikeTarget? target, int? storyId})
    : super(
        loadPage: (cursor) => target != null
            ? repo.list(target, cursor: cursor)
            : repo.listStory(storyId!, cursor: cursor),
        idOf: (user) => user.id,
      );
}
