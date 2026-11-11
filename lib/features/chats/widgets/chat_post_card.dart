import 'package:flutter/material.dart';
import 'package:travibe/core/constants/app_sizes.dart';
import 'package:travibe/features/home/widgets/home_user_avatar.dart';
import '../data/chat_models.dart';
import 'chat_history_image.dart';

/// Compact card for a `post` message. A null [post] means the post was
/// removed or the viewer may no longer open it: shown as unavailable and not
/// tappable.
class ChatPostCard extends StatelessWidget {
  const ChatPostCard({super.key, required this.post, this.onOpen});
  final ChatSharedPost? post;
  final VoidCallback? onOpen;

  static const width = 240.0;

  @override
  Widget build(BuildContext context) {
    final post = this.post;
    if (post == null) {
      return Semantics(
        label: 'Post unavailable',
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.hide_image_outlined, color: Colors.white60, size: 18),
            SizedBox(width: 8),
            Text('Post unavailable', style: TextStyle(color: Colors.white60)),
          ],
        ),
      );
    }
    final content = post.content?.trim() ?? '';
    final image = post.imageUrl;
    return Semantics(
      container: true,
      button: onOpen != null,
      onTap: onOpen,
      label: 'Shared post by ${post.author.name}. Open post',
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onOpen,
        child: SizedBox(
          width: width,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  HomeUserAvatar(
                    url: post.author.avatarUrl,
                    size: AppSizes.adaptiveRadius(28),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      post.author.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              if (image != null) ...[
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 240),
                    child: ChatHistoryImage(
                      key: ValueKey(image),
                      url: image,
                      aspectRatio: 1,
                    ),
                  ),
                ),
              ],
              if (content.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  content,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
