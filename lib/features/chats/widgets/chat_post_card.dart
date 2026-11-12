import 'package:flutter/material.dart';
import 'package:travibe/core/constants/app_sizes.dart';
import 'package:travibe/core/theme/dark_colors.dart';
import 'package:travibe/core/utils/formatters.dart';
import 'package:travibe/features/home/widgets/home_user_avatar.dart';
import '../data/chat_models.dart';
import 'chat_history_image.dart';

/// Card for a `post` message (Figma: chat / shared post). A null [post] means
/// the post was removed or the viewer may no longer open it: shown as
/// unavailable and not tappable.
class ChatPostCard extends StatelessWidget {
  const ChatPostCard({super.key, required this.post, this.onOpen});
  final ChatSharedPost? post;
  final VoidCallback? onOpen;

  static double get width => AppSizes.adaptiveWidth(292);
  static double get padding => AppSizes.adaptiveWidth(16);
  static double get imageWidth => width - padding * 2;
  static double get imageMaxHeight => AppSizes.adaptiveHeight(320);

  @override
  Widget build(BuildContext context) {
    final post = this.post;
    if (post == null) {
      return Semantics(
        label: 'Post unavailable',
        child: _card(
          const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.hide_image_outlined, color: Colors.white60, size: 18),
              SizedBox(width: 8),
              Text('Post unavailable', style: TextStyle(color: Colors.white60)),
            ],
          ),
        ),
      );
    }
    final content = post.content?.trim() ?? '';
    final image = post.imageUrl;
    final time = timeAgo(post.createdAt);
    return Semantics(
      container: true,
      button: onOpen != null,
      onTap: onOpen,
      label: 'Shared post by ${post.author.name}. Open post',
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onOpen,
        child: _card(
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  HomeUserAvatar(
                    url: post.author.avatarUrl,
                    size: AppSizes.adaptiveRadius(40),
                  ),
                  SizedBox(width: AppSizes.adaptiveWidth(12)),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          post.author.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: DarkColors.whiteColor,
                            fontSize: AppSizes.sp16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (time.isNotEmpty)
                          Text(
                            time,
                            style: TextStyle(
                              color: Colors.white60,
                              fontSize: AppSizes.sp12,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              if (content.isNotEmpty) ...[
                SizedBox(height: AppSizes.h16),
                Text(
                  content,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: DarkColors.whiteColor,
                    fontSize: AppSizes.sp15,
                  ),
                ),
              ],
              if (image != null) ...[
                SizedBox(height: AppSizes.h12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(
                    AppSizes.adaptiveRadius(20),
                  ),
                  child: ChatHistoryImage(
                    key: ValueKey(image),
                    url: image,
                    width: imageWidth,
                    maxHeight: imageMaxHeight,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _card(Widget child) => Container(
    width: width,
    padding: EdgeInsets.all(padding),
    decoration: BoxDecoration(
      color: DarkColors.darkgreyColor,
      borderRadius: BorderRadius.circular(AppSizes.adaptiveRadius(24)),
    ),
    child: child,
  );
}
