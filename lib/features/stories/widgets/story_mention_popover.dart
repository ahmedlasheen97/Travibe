import 'package:flutter/material.dart';
import 'package:travibe/core/theme/dark_colors.dart';
import 'package:travibe/features/home/widgets/home_user_avatar.dart';
import 'package:travibe/features/profile/data/profile_repo.dart';

/// Name and avatar shown on the popover.
typedef StoryMentionProfile = ({String name, String? avatarUrl});

/// Loads a mentioned user's name and avatar; null when unavailable.
typedef StoryMentionProfileLoader =
    Future<StoryMentionProfile?> Function(int userId);

Future<StoryMentionProfile?> loadStoryMentionProfile(int userId) async {
  final profile = await ProfileRepo().getPublicProfile(userId);
  final name = profile?.name?.trim();
  if (profile == null || name == null || name.isEmpty) return null;
  return (name: name, avatarUrl: profile.avatarUrl);
}

/// Card under a tapped mention (Figma `mention_view_profile.png`): avatar,
/// name, "View profile" and a chevron, with a pointer towards the mention.
class StoryMentionPopover extends StatelessWidget {
  const StoryMentionPopover({
    super.key,
    required this.anchor,
    required this.target,
    required this.canvas,
    required this.username,
    required this.profile,
    required this.onViewProfile,
    required this.onDismiss,
  });

  /// The text bubble the card sits under (or above, near the bottom),
  /// canvas-local.
  final Rect anchor;

  /// The tapped `@username`; the pointer aims at its centre.
  final Rect target;
  final Size canvas;
  final String username;
  final StoryMentionProfile? profile;
  final VoidCallback onViewProfile, onDismiss;

  static const width = 240.0;
  static const _height = 64.0;
  static const _pointer = 8.0;
  static const _gap = 4.0;
  static const _margin = 16.0;

  @override
  Widget build(BuildContext context) {
    final below =
        anchor.bottom + _gap + _pointer + _height <= canvas.height - 96 ||
        anchor.top - _gap - _pointer - _height < 0;
    final maxLeft = canvas.width - width - _margin;
    final left = (target.center.dx - width / 2).clamp(
      _margin,
      maxLeft < _margin ? _margin : maxLeft,
    );
    final top = below
        ? anchor.bottom + _gap
        : anchor.top - _gap - _pointer - _height;
    final pointerX = (target.center.dx - left).clamp(20.0, width - 20.0);
    final card = Material(
      color: DarkColors.darkgreyColor.withValues(alpha: 0.92),
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: const ValueKey('story-mention-view-profile'),
        onTap: onViewProfile,
        child: SizedBox(
          height: _height,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                HomeUserAvatar(url: profile?.avatarUrl, size: 40),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        profile?.name ?? '@$username',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontFamily: 'Plus Jakarta Sans',
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 2),
                      const Text(
                        'View profile',
                        style: TextStyle(
                          color: Colors.white60,
                          fontFamily: 'Plus Jakarta Sans',
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: Colors.white),
              ],
            ),
          ),
        ),
      ),
    );
    final pointer = Padding(
      padding: EdgeInsets.only(left: pointerX - _pointer),
      child: CustomPaint(
        size: const Size(_pointer * 2, _pointer),
        painter: _PointerPainter(
          up: below,
          color: DarkColors.darkgreyColor.withValues(alpha: 0.92),
        ),
      ),
    );
    return Stack(
      children: [
        // Tapping anywhere else closes the card and resumes the story.
        Positioned.fill(
          child: GestureDetector(
            key: const ValueKey('story-mention-popover-barrier'),
            behavior: HitTestBehavior.opaque,
            onTap: onDismiss,
          ),
        ),
        Positioned(
          left: left,
          top: top,
          width: width,
          child: Semantics(
            button: true,
            label: 'View profile of ${profile?.name ?? '@$username'}',
            child: Column(
              key: const ValueKey('story-mention-popover'),
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: below ? [pointer, card] : [card, pointer],
            ),
          ),
        ),
      ],
    );
  }
}

class _PointerPainter extends CustomPainter {
  const _PointerPainter({required this.up, required this.color});
  final bool up;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final path = up
        ? (Path()
            ..moveTo(0, size.height)
            ..lineTo(size.width / 2, 0)
            ..lineTo(size.width, size.height))
        : (Path()
            ..moveTo(0, 0)
            ..lineTo(size.width / 2, size.height)
            ..lineTo(size.width, 0));
    canvas.drawPath(path..close(), Paint()..color = color);
  }

  @override
  bool shouldRepaint(_PointerPainter old) => old.up != up || old.color != color;
}
