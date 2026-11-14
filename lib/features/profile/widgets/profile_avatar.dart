import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:travibe/core/constants/app_sizes.dart';
import 'package:travibe/core/theme/dark_colors.dart';
import 'package:travibe/features/stories/data/story_model.dart';
import 'package:travibe/features/stories/widgets/story_ring.dart';

/// The profile picture. Active [stories] draw Home's [StoryRing] (orange
/// unseen, grey seen); [onTap] opens the stories, the picture, or a sheet
/// offering both (decided by the caller). My own profile passes
/// [onAddStory], which adds the Home "You"-style "+" badge on the picture's
/// lower-right diagonal.
class ProfileAvatar extends StatelessWidget {
  final String? imageUrl;
  final List<StorySummary> stories;
  final VoidCallback? onTap;
  final VoidCallback? onAddStory;

  const ProfileAvatar({
    super.key,
    this.imageUrl,
    this.stories = const [],
    this.onTap,
    this.onAddStory,
  });

  @override
  Widget build(BuildContext context) {
    final url = imageUrl;
    final hasImage = url != null && url.isNotEmpty;
    final diameter = AppSizes.w128;
    final badge = AppSizes.w32;
    // Badge center lies on the picture's circumference at 45° (as on Home).
    final inset = diameter / 2 - diameter / (2 * math.sqrt2) - badge / 2;

    final picture = CircleAvatar(
      key: const ValueKey('profile-avatar'),
      radius: diameter / 2,
      backgroundColor: const Color(0xFF2A2A2A),
      backgroundImage: hasImage ? NetworkImage(url) : null,
      child: hasImage
          ? null
          : Icon(
              Icons.person_rounded,
              color: Colors.white54,
              size: AppSizes.w56,
            ),
    );
    Widget avatar = stories.isEmpty
        ? picture
        : StoryRing(
            key: const ValueKey('profile-story-ring'),
            stories: stories,
            child: picture,
          );
    if (onTap case final open?) {
      avatar = Semantics(
        button: true,
        label: 'Profile picture options',
        child: GestureDetector(
          key: const ValueKey('profile-open-stories'),
          behavior: HitTestBehavior.opaque,
          onTap: open,
          child: avatar,
        ),
      );
    }
    final onAdd = onAddStory;
    if (onAdd == null) return avatar;
    return SizedBox.square(
      dimension: diameter,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          avatar,
          Positioned(
            right: inset,
            bottom: inset,
            child: Semantics(
              button: true,
              label: 'Add story',
              child: GestureDetector(
                key: const ValueKey('profile-add-story'),
                behavior: HitTestBehavior.opaque,
                onTap: onAdd,
                child: Container(
                  width: badge,
                  height: badge,
                  decoration: BoxDecoration(
                    color: DarkColors.primaryColor,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: DarkColors.backgroundColor,
                      width: AppSizes.w2,
                    ),
                  ),
                  child: Icon(
                    Icons.add,
                    size: AppSizes.w20,
                    color: DarkColors.whiteColor,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
