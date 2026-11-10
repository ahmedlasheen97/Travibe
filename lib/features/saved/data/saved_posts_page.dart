import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/features/home/data/post_model.dart';
import 'package:travibe/features/home/data/posts_page_model.dart';

/// Validates the documented paginator before reusing the existing post model.
PostsPageModel parseSavedPostsPage(
  dynamic response, {
  required int requestedPage,
}) {
  Never invalid() =>
      throw ApiError(message: 'Unable to read saved posts. Please try again.');
  if (response is! Map ||
      response['data'] is! List ||
      response['meta'] is! Map ||
      response['links'] is! Map) {
    invalid();
  }
  final meta = response['meta'] as Map;
  final current = meta['current_page'];
  final last = meta['last_page'];
  final total = meta['total'];
  if (current is! int ||
      current != requestedPage ||
      current < 1 ||
      last is! int ||
      last < 1 ||
      total is! int ||
      total < 0) {
    invalid();
  }
  final links = response['links'] as Map;
  for (final key in ['first', 'last', 'prev', 'next']) {
    if (!links.containsKey(key) ||
        (links[key] != null && links[key] is! String)) {
      invalid();
    }
  }
  final posts = <PostModel>[];
  for (final raw in response['data'] as List) {
    if (raw is! Map ||
        raw['id'] is! int ||
        (raw['id'] as int) < 1 ||
        raw['user'] is! Map) {
      invalid();
    }
    if (raw.containsKey('is_saved') && raw['is_saved'] is! bool) invalid();
    // Membership in the authenticated Saved endpoint also confirms this flag
    // when optional viewer fields are not serialized by PostResource.
    if (raw['is_saved'] == false) invalid();
    posts.add(
      PostModel.fromJson(
        Map<String, dynamic>.from(raw),
      ).copyWith(isSaved: true, hasSaveState: true),
    );
  }
  return PostsPageModel(
    posts: posts,
    currentPage: current,
    lastPage: last,
    total: total,
  );
}
