import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/features/create_post/data/post_image.dart';

enum PostVisibility {
  public('Public'),
  followers('Followers'),
  private('Private');

  const PostVisibility(this.label);
  final String label;
}

/// A composed post. It is also the draft handed to the background uploader,
/// so it keeps the local photo bytes until they have been uploaded.
class CreatePostRequest {
  const CreatePostRequest({
    required this.content,
    this.visibility = PostVisibility.public,
    this.images = const [],
  });

  /// `StorePostRequest.content` maxLength in docs/openapi.json.
  static const maxContentLength = 2000;

  /// The API sets no count limit; this is the app's product limit.
  static const maxImages = 10;

  final String content;
  final PostVisibility visibility;
  final List<PostImage> images;

  // Laravel counts Unicode code points, rather than UTF-16 code units.
  int get characterCount => content.runes.length;
  bool get hasContent => content.trim().isNotEmpty || images.isNotEmpty;

  String? get validationError {
    if (!hasContent) return 'Write something or add a photo before publishing.';
    if (characterCount > maxContentLength) {
      return 'Posts must be $maxContentLength characters or fewer.';
    }
    if (images.length > maxImages) {
      return 'You can add up to $maxImages photos.';
    }
    return null;
  }

  CreatePostRequest copyWith({List<PostImage>? images}) => CreatePostRequest(
    content: content,
    visibility: visibility,
    images: images ?? this.images,
  );

  Map<String, dynamic> toJson() {
    final error = validationError;
    if (error != null) throw ApiError(message: error);
    if (images.any((image) => image.mediaId == null)) {
      throw ApiError(message: 'Your photos have not finished uploading.');
    }
    final text = content.trim();
    return {
      if (text.isNotEmpty) 'content': text,
      if (images.isNotEmpty)
        'media_ids': [for (final image in images) image.mediaId!],
      'visibility': visibility.name,
    };
  }
}
