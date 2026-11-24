import 'package:travibe/features/stories/widgets/story_ring.dart';
import 'package:travibe/features/home/widgets/home_loading_skeleton.dart';
import 'dart:math' as math;
import 'package:travibe/core/constants/app_sizes.dart';
import 'package:travibe/features/stories/widgets/your_story_button.dart';
import 'package:flutter/material.dart';
import 'package:travibe/core/theme/dark_colors.dart';
import 'package:travibe/features/home/widgets/home_user_avatar.dart';
import 'package:travibe/features/stories/data/story_model.dart';
import 'package:travibe/features/stories/data/story_style.dart';
import 'package:travibe/features/stories/widgets/open_story_viewer.dart';

class HomeStories extends StatelessWidget {
  const HomeStories({
    super.key,
    required this.stories,
    this.onAddStory,
    this.onViewStory,
    this.currentUserId,
    this.avatarUrl,
    this.loading = false,
    this.loadingMore = false,
    this.hasMore = false,
    this.onLoadMore,
    this.style = StoryStyle.circle,
  });
  final List<StoryGroup> stories;
  final void Function(List<StoryGroup> groups, int authorId)? onViewStory;
  final int? currentUserId;
  // Load failures never render here: the row keeps cached stories (or only
  // "You") and Home's shared error toast reports the failure.
  final String? avatarUrl;
  final bool loading, loadingMore, hasMore;
  final VoidCallback? onAddStory, onLoadMore;

  /// Circle (default) or the experimental portrait rounded-rectangle cards.
  final StoryStyle style;

  static const badgeDiameter = 20.0;
  // Badge center lies on the image circumference at the 45-degree diagonal.
  static double get badgeInset =>
      ringDiameter / 2 - avatarDiameter / (2 * math.sqrt2) - badgeDiameter / 2;
  static double get avatarDiameter =>
      math.min(AppSizes.w64, AppSizes.h64).clamp(56.0, 72.0);
  // Preserve the existing 72px reference layout frame and label geometry.
  // The visible 2px stroke now overlays the 64px image with zero padding.
  static double get ringDiameter =>
      avatarDiameter + 2 * AppSizes.adaptiveRadius(4);
  // Rectangle style: a 64x80 (at the reference size) portrait card, radius 16.
  static double get cardWidth => avatarDiameter;
  static double get cardHeight => avatarDiameter * 1.25;
  static double get cardRadius => avatarDiameter / 4;
  // Badge center lies on the card's bottom-right corner arc at 45 degrees.
  static double get cardBadgeInset =>
      AppSizes.adaptiveRadius(4) +
      cardRadius * (1 - 1 / math.sqrt2) -
      badgeDiameter / 2;

  /// Story frame (ring/card plus breathing room) for [style].
  static Size frameSize(StoryStyle style) => switch (style) {
    StoryStyle.circle => Size.square(ringDiameter),
    StoryStyle.rectangle => Size(
      cardWidth + 2 * AppSizes.adaptiveRadius(4),
      cardHeight + 2 * AppSizes.adaptiveRadius(4),
    ),
  };

  static TextStyle get labelStyle => TextStyle(
    fontFamily: 'Plus Jakarta Sans',
    fontSize: AppSizes.adaptiveFont(12),
    color: Colors.white70,
  );
  static double preferredHeight(
    BuildContext context, [
    StoryStyle style = StoryStyle.circle,
  ]) {
    final painter = TextPainter(
      text: TextSpan(
        text: 'You',
        style: DefaultTextStyle.of(context).style.merge(labelStyle),
      ),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    final height =
        frameSize(style).height +
        AppSizes.adaptiveHeight(6) +
        painter.height +
        AppSizes.adaptiveHeight(4);
    painter.dispose();
    return height;
  }

  @override
  Widget build(BuildContext context) {
    final ordered = storyPlayOrder(stories, currentUserId);
    final own =
        currentUserId != null && ordered.firstOrNull?.user.id == currentUserId
        ? ordered.first
        : null;
    final others = own == null ? ordered : ordered.sublist(1);
    final initialLoading = loading && stories.isEmpty;
    final rectangle = style == StoryStyle.rectangle;
    final frame = frameSize(style);
    return SizedBox(
      height: preferredHeight(context, style),
      child: NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          if (notification.metrics.extentAfter < 120 &&
              notification is ScrollUpdateNotification &&
              hasMore &&
              !loadingMore) {
            onLoadMore?.call();
          }
          return false;
        },
        child: ListView.separated(
          key: const PageStorageKey('home-stories-scroll'),
          scrollDirection: Axis.horizontal,
          padding: EdgeInsets.symmetric(horizontal: AppSizes.adaptiveWidth(20)),
          itemCount:
              1 +
              (initialLoading ? 5 : others.length) +
              (!loading && !loadingMore && hasMore ? 1 : 0),
          separatorBuilder: (_, _) =>
              SizedBox(width: AppSizes.adaptiveWidth(16)),
          itemBuilder: (context, index) {
            if (initialLoading && index > 0) {
              return HomeStorySkeleton(
                avatarDiameter: avatarDiameter,
                ringDiameter: ringDiameter,
                labelStyle: labelStyle,
                card: rectangle ? Size(cardWidth, cardHeight) : null,
                cardRadius: cardRadius,
                frame: frame,
              );
            }
            if (index > others.length) {
              return SizedBox(
                width: AppSizes.adaptiveWidth(120),
                child: Center(
                  child: TextButton(
                    key: const ValueKey('stories-more'),
                    onPressed: onLoadMore,
                    child: const Text('More Stories'),
                  ),
                ),
              );
            }
            final isYou = index == 0;
            final group = isYou ? own : others[index - 1];
            // "You" prefers my current picture over the (possibly stale) story feed.
            final url = isYou
                ? avatarUrl ?? group?.user.avatarUrl
                : group!.user.avatarUrl;
            final label = isYou ? 'You' : group!.user.name;
            final bubble = SizedBox(
              width: ringDiameter + AppSizes.adaptiveWidth(8),
              child: Column(
                children: [
                  Semantics(
                    label:
                        '$label${group?.hasUnseen == true ? ', unseen stories' : ''}${!isYou && onViewStory == null ? ', viewer unavailable' : ''}',
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        SizedBox.fromSize(
                          key: ValueKey(
                            'story-ring-${group?.user.id ?? 'you'}',
                          ),
                          size: frame,
                          child: Center(
                            child: StoryRing(
                              key: ValueKey(
                                'story-segments-${group?.user.id ?? 'you'}',
                              ),
                              stories: group?.stories ?? const [],
                              cornerRadius: rectangle ? cardRadius : null,
                              child: HomeUserAvatar(
                                key: ValueKey(
                                  'story-avatar-${group?.user.id ?? 'you'}',
                                ),
                                url: url,
                                size: rectangle ? cardWidth : avatarDiameter,
                                height: rectangle ? cardHeight : null,
                                borderRadius: rectangle ? cardRadius : null,
                              ),
                            ),
                          ),
                        ),
                        if (isYou)
                          Positioned(
                            bottom: rectangle ? cardBadgeInset : badgeInset,
                            right: rectangle ? cardBadgeInset : badgeInset,
                            // The whole own-story bubble owns one tap action.
                            // Badge taps must pass through the same menu gate.
                            child: ExcludeSemantics(
                              child: Container(
                                key: const ValueKey('add-story-photo'),
                                width: badgeDiameter,
                                height: badgeDiameter,
                                decoration: BoxDecoration(
                                  color: DarkColors.primaryColor,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: DarkColors.backgroundColor,
                                    width: AppSizes.adaptiveRadius(2),
                                  ),
                                ),
                                child: const Icon(
                                  Icons.add,
                                  size: 12,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  SizedBox(height: AppSizes.adaptiveHeight(6)),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: labelStyle,
                  ),
                ],
              ),
            );
            return isYou
                ? YourStoryButton(
                    currentUserId: currentUserId,
                    group: own,
                    onAddStory: onAddStory,
                    onViewStory: onViewStory == null || own == null
                        ? null
                        : () => onViewStory!([own, ...others], own.user.id),
                    child: bubble,
                  )
                : Semantics(
                    button: onViewStory != null,
                    child: GestureDetector(
                      key: ValueKey('story-author-${group!.user.id}'),
                      behavior: HitTestBehavior.opaque,
                      onTap: onViewStory == null
                          ? null
                          : () =>
                                onViewStory!([?own, ...others], group.user.id),
                      child: bubble,
                    ),
                  );
          },
        ),
      ),
    );
  }
}
