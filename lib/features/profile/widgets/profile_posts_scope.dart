import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:travibe/features/block/cubit/block_cubit.dart';
import 'package:travibe/features/follow/cubit/follow_cubit.dart';
import 'package:travibe/features/home/cubit/post_activity_cubit.dart';
import 'package:travibe/features/home/cubit/posts_cubit.dart';
import 'package:travibe/features/home/data/posts_repo.dart';
import 'package:travibe/features/likes/cubit/likes_cubit.dart';
import 'package:travibe/features/profile/cubit/profile_cubit.dart';
import 'package:travibe/features/saved/cubit/saves_cubit.dart';

/// Keeps the author cache alive across Profile's tab switches, never unavailable profiles.
class ProfilePostsScope extends StatefulWidget {
  const ProfilePostsScope({
    super.key,
    required this.userId,
    this.repo,
    required this.builder,
  });
  final int userId;
  final PostsRepo? repo;
  final WidgetBuilder builder;
  @override
  State<ProfilePostsScope> createState() => _ProfilePostsScopeState();
}

class _ProfilePostsScopeState extends State<ProfilePostsScope> {
  late final PostsCubit _posts;
  StreamSubscription<BlockState>? _blocks;
  StreamSubscription<FollowState>? _follows;
  StreamSubscription<PostActivityState>? _activity;
  @override
  void initState() {
    super.initState();
    _posts = PostsCubit(
      userId: widget.userId,
      postsRepo: widget.repo,
      likes: context.read<LikesCubit>(),
      saves: context.read<SavesCubit>(),
      activity: context.read<PostActivityCubit>(),
    );
    final blocks = context.read<BlockCubit?>();
    _posts.setBlockedUsers(blocks?.state.blockedIds ?? {});
    var unblock = blocks?.state.unblockRevision;
    _blocks = blocks?.stream.listen((state) {
      _posts.setBlockedUsers(state.blockedIds);
      if (state.unblockRevision != unblock) {
        unblock = state.unblockRevision;
        unawaited(_posts.refreshAfterBlockChange());
      }
    });
    final follow = context.read<FollowCubit?>();
    var following = follow?.state.following[widget.userId.toString()];
    var revision = follow?.state.revision;
    _follows = follow?.stream.listen((state) {
      final next = state.following[widget.userId.toString()];
      final mutated = state.revision != revision;
      revision = state.revision;
      if (next == following) return;
      final previous = following;
      following = next;
      // A first known value without a mutation (the profile's own seed) is
      // not a follow change.
      if (previous == null && !mutated) return;
      if (_posts.state is! PostsInitial) {
        unawaited(_posts.refreshAfterPublication());
      }
    });
    final profile = context.read<ProfileCubit>();
    final activity = context.read<PostActivityCubit>();
    var publication = activity.state.publicationRevision;
    _activity = activity.stream.listen((state) {
      if (state.publicationRevision == publication) return;
      publication = state.publicationRevision;
      if (state.authorId != widget.userId.toString()) return;
      unawaited(_posts.refreshAfterPublication());
      profile.refresh();
    });
  }

  @override
  void dispose() {
    _blocks?.cancel();
    _follows?.cancel();
    _activity?.cancel();
    _posts.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => BlocProvider.value(
    value: _posts,
    child: Builder(builder: widget.builder),
  );
}
