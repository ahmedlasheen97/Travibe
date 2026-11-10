import 'package:flutter/material.dart';
import 'package:travibe/core/theme/dark_colors.dart';
import 'package:travibe/features/create_post/data/create_post_request.dart';
import 'package:travibe/features/create_post/widgets/create_post_styles.dart';

IconData audienceIcon(PostVisibility visibility) => switch (visibility) {
  PostVisibility.public => Icons.public,
  PostVisibility.followers => Icons.people_outline,
  PostVisibility.private => Icons.lock_outline,
};

Future<PostVisibility?> showAudienceSheet(
  BuildContext context,
  PostVisibility selected,
) => showModalBottomSheet<PostVisibility>(
  context: context,
  backgroundColor: createPostSurface,
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
  ),
  builder: (context) => SafeArea(
    top: false,
    child: Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 16, bottom: 24),
            width: 112,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          for (final visibility in PostVisibility.values)
            ListTile(
              key: ValueKey('audience-${visibility.name}'),
              contentPadding: const EdgeInsets.symmetric(horizontal: 24),
              leading: Icon(
                audienceIcon(visibility),
                size: 24,
                color: Colors.white70,
              ),
              title: Text(
                visibility.label,
                style: createPostTextStyle.copyWith(
                  fontWeight: FontWeight.w500,
                ),
              ),
              trailing: visibility == selected
                  ? const Icon(Icons.check, color: DarkColors.primaryColor)
                  : null,
              onTap: () => Navigator.pop(context, visibility),
            ),
        ],
      ),
    ),
  ),
);
