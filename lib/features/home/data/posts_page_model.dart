import 'package:travibe/core/models/cursor_pagination.dart';
import 'package:travibe/core/utils/json_parsers.dart';
import 'package:travibe/features/home/data/post_model.dart';

class PostsPageModel {
  final List<PostModel> posts;
  final int currentPage;
  final int lastPage;
  final int total;
  // Offset fields remain only for the unchanged Saved endpoint.
  final CursorPaginationMeta? pagination;

  const PostsPageModel({
    required this.posts,
    this.currentPage = 1,
    this.lastPage = 1,
    this.total = 0,
    this.pagination,
  });

  bool get hasMore => pagination?.hasMore ?? (currentPage < lastPage);

  factory PostsPageModel.fromCursorJson(dynamic json) {
    final page = CursorPage<PostModel>.fromJson(
      json,
      (item) => PostModel.fromJson(Map<String, dynamic>.from(item)),
    );
    return PostsPageModel(posts: page.items, pagination: page.pagination);
  }

  factory PostsPageModel.fromJson(Map<String, dynamic> json) {
    final data = json['data'];
    final meta = Map<String, dynamic>.from(json['meta'] ?? {});

    return PostsPageModel(
      posts: data is List
          ? data
                .map((e) => PostModel.fromJson(Map<String, dynamic>.from(e)))
                .toList()
          : const [],
      currentPage: parseInt(meta['current_page'], fallback: 1),
      lastPage: parseInt(meta['last_page'], fallback: 1),
      total: parseInt(meta['total']),
    );
  }
}
