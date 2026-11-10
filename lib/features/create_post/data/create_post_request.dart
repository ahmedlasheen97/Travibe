import 'package:travibe/core/datasource/remotedata/api_error.dart';

enum PostVisibility {
  public('Public'),
  followers('Followers'),
  private('Private');

  const PostVisibility(this.label);
  final String label;
}

class CreatePostRequest {
  const CreatePostRequest({
    required this.content,
    this.visibility = PostVisibility.public,
  });
  static const maxContentLength = 2000;
  final String content;
  final PostVisibility visibility;

  // Laravel counts Unicode code points, rather than UTF-16 code units.
  int get characterCount => content.runes.length;
  String? get validationError {
    if (content.trim().isEmpty) return 'Write something before publishing.';
    if (characterCount > maxContentLength) {
      return 'Posts must be 2000 characters or fewer.';
    }
    return null;
  }

  Map<String, dynamic> toJson() {
    final error = validationError;
    if (error != null) throw ApiError(message: error);
    return {'content': content.trim(), 'visibility': visibility.name};
  }
}
