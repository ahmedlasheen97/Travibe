import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:travibe/features/block/cubit/block_cubit.dart';
import 'package:travibe/features/follow/cubit/follow_cubit.dart';
import 'package:travibe/features/follow_requests/cubit/incoming_requests_cubit.dart';
import 'package:travibe/features/home/cubit/hidden_posts_cubit.dart';
import 'package:travibe/features/home/cubit/post_activity_cubit.dart';
import 'package:travibe/features/likes/cubit/likes_cubit.dart';
import 'package:travibe/features/profile/cubit/current_user_cubit.dart';
import 'package:travibe/features/saved/cubit/saved_posts_cubit.dart';
import 'package:travibe/features/saved/cubit/saves_cubit.dart';
import 'package:travibe/features/stories/cubit/stories_cubit.dart';
import 'package:travibe/features/stories/cubit/story_likes_cubit.dart';

/// Root's app-wide interaction cubits.
typedef AppCubitSet = ({
  CurrentUserCubit? current,
  SavesCubit saves,
  SavedPostsCubit savedPosts,
  LikesCubit likes,
  PostActivityCubit activity,
  HiddenPostsCubit hidden,
  FollowCubit follow,
  BlockCubit block,
  IncomingRequestsCubit incoming,
  StoriesCubit stories,
  StoryLikesCubit storyLikes,
});

/// Root's shared cubits, for screens pushed where Root's providers are not
/// ancestors: routes on the app navigator (push taps, deep links) and routes
/// pushed from other pushed routes (e.g. the Story viewer).
abstract final class AppCubits {
  static Object? _owner;
  static AppCubitSet? _cubits;

  static void attach(Object owner, AppCubitSet cubits) {
    _owner = owner;
    _cubits = cubits;
  }

  static void detach(Object owner) {
    if (!identical(_owner, owner)) return;
    _owner = null;
    _cubits = null;
  }

  /// The attached set, if Root is up.
  static AppCubitSet? get current => _cubits;
}

/// Reads every shared cubit now (the one in [context] when present,
/// otherwise Root's) and returns a wrapper that provides them to a pushed
/// route. Missing ones (no Root, e.g. some tests) are skipped.
Widget Function(Widget child) captureAppCubits(BuildContext context) {
  final root = AppCubits.current;
  T? pick<T extends StateStreamableSource<Object?>>(T? fromRoot) {
    final local = context.read<T?>();
    if (local != null) return local;
    return fromRoot == null || fromRoot.isClosed ? null : fromRoot;
  }

  final providers = <BlocProvider>[
    if (pick<CurrentUserCubit>(root?.current) case final c?)
      BlocProvider<CurrentUserCubit>.value(value: c),
    if (pick<SavesCubit>(root?.saves) case final c?)
      BlocProvider<SavesCubit>.value(value: c),
    if (pick<SavedPostsCubit>(root?.savedPosts) case final c?)
      BlocProvider<SavedPostsCubit>.value(value: c),
    if (pick<LikesCubit>(root?.likes) case final c?)
      BlocProvider<LikesCubit>.value(value: c),
    if (pick<PostActivityCubit>(root?.activity) case final c?)
      BlocProvider<PostActivityCubit>.value(value: c),
    if (pick<HiddenPostsCubit>(root?.hidden) case final c?)
      BlocProvider<HiddenPostsCubit>.value(value: c),
    if (pick<FollowCubit>(root?.follow) case final c?)
      BlocProvider<FollowCubit>.value(value: c),
    if (pick<BlockCubit>(root?.block) case final c?)
      BlocProvider<BlockCubit>.value(value: c),
    if (pick<IncomingRequestsCubit>(root?.incoming) case final c?)
      BlocProvider<IncomingRequestsCubit>.value(value: c),
    if (pick<StoriesCubit>(root?.stories) case final c?)
      BlocProvider<StoriesCubit>.value(value: c),
    if (pick<StoryLikesCubit>(root?.storyLikes) case final c?)
      BlocProvider<StoryLikesCubit>.value(value: c),
  ];
  return (child) => providers.isEmpty
      ? child
      : MultiBlocProvider(providers: providers, child: child);
}

/// [T] from [context], else Root's.
T? readAppCubit<T extends StateStreamableSource<Object?>>(
  BuildContext context,
) {
  final local = context.read<T?>();
  if (local != null) return local;
  final root = AppCubits.current;
  if (root == null) return null;
  final Object? shared = switch (T) {
    const (CurrentUserCubit) => root.current,
    const (FollowCubit) => root.follow,
    const (BlockCubit) => root.block,
    const (StoriesCubit) => root.stories,
    const (StoryLikesCubit) => root.storyLikes,
    _ => null,
  };
  return shared is T && !shared.isClosed ? shared : null;
}
