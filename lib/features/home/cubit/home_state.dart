// part of 'posts_cubit.dart';

// import 'package:flutter/material.dart';
// import 'package:travibe/features/home/data/post_model.dart';

// @immutable
// sealed class PostsState {}

// final class PostsInitial extends PostsState {}

// final class PostsLoading extends PostsState {}

// final class PostsLoaded extends PostsState {
//   final List<PostModel> posts;
//   final bool hasMore;
//   final bool isLoadingMore;

//   PostsLoaded({
//     required this.posts,
//     required this.hasMore,
//     this.isLoadingMore = false,
//   });
// }

// final class PostsFailure extends PostsState {
//   final String errorMessage;
//   PostsFailure(this.errorMessage);
// }