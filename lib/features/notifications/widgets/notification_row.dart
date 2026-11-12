import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:travibe/core/constants/app_sizes.dart';
import 'package:travibe/core/theme/dark_colors.dart';
import 'package:travibe/core/utils/formatters.dart';
import 'package:travibe/features/home/widgets/home_user_avatar.dart';
import '../data/notification_model.dart';
import '../data/notification_presentation.dart';

/// Flat, adaptive inbox row. All content comes from Laravel or a verified
/// presentation adapter. No API calls or destination guessing in this widget.
class NotificationRow extends StatelessWidget {
  const NotificationRow({
    super.key,
    required this.item,
    required this.onRead,
    this.resolver = const NotificationPresentationResolver(),
    this.followAction,
    this.thumbnail,
    this.onAvatarTap,
    this.showUnreadDot,
  });
  final InboxNotification item;

  /// Defaults to `!item.isRead`; the inbox keeps it for rows new this visit.
  final bool? showUnreadDot;
  final VoidCallback? onRead;

  /// Opens the actor's profile; null when there is no actor (e.g. nearby).
  final VoidCallback? onAvatarTap;
  final NotificationPresentationResolver resolver;
  final Widget? followAction;
  final NotificationThumbnail? thumbnail;
  @override
  Widget build(BuildContext context) {
    final unread = showUnreadDot ?? !item.isRead;
    final icon = NotificationPresentationResolver.icon(resolver.kind(item));
    final preview = thumbnail ?? resolver.thumbnail(item);
    final actor = item.actor?.name ?? item.actor?.username;
    final emphasis = actor;
    final remainder = resolver.description(item);
    final secondary = resolver.secondary(item);
    final avatarSize = AppSizes.adaptiveRadius(52),
        overlaySize = AppSizes.adaptiveRadius(20);
    final textStyle = TextStyle(
      fontFamily: 'Plus Jakarta Sans',
      color: Colors.white,
      fontSize: AppSizes.adaptiveFont(16),
      fontWeight:
          resolver.kind(item) == NotificationKind.nearby && item.actor == null
          ? FontWeight.w600
          : FontWeight.w400,
      height: 1.5,
    );
    return Semantics(
      label: unread ? 'Unread notification' : 'Read notification',
      child: InkWell(
        key: ValueKey('notification-${item.id}'),
        onTap: onRead,
        child: Padding(
          padding: EdgeInsetsDirectional.fromSTEB(
            2,
            AppSizes.adaptiveHeight(12),
            AppSizes.adaptiveWidth(20),
            AppSizes.adaptiveHeight(12),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 12,
                child: Padding(
                  padding: EdgeInsets.only(top: avatarSize / 2 - 4),
                  child: !unread
                      ? const SizedBox(height: 8)
                      : Container(
                          key: ValueKey('notification-unread-${item.id}'),
                          width: 8,
                          height: 8,
                          margin: const EdgeInsets.symmetric(horizontal: 2),
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: DarkColors.primaryColor,
                          ),
                        ),
                ),
              ),
              _AvatarTap(
                onTap: item.actor == null ? null : onAvatarTap,
                id: item.id,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    if (item.actor == null &&
                        resolver.kind(item) == NotificationKind.nearby)
                      Container(
                        width: avatarSize,
                        height: avatarSize,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Color(0xFF171717),
                        ),
                        alignment: Alignment.center,
                        child: SvgPicture.asset(icon!, width: 32, height: 32),
                      )
                    else
                      HomeUserAvatar(
                        url: item.actor?.avatarUrl,
                        size: avatarSize,
                      ),
                    if (icon != null &&
                        !(item.actor == null &&
                            resolver.kind(item) == NotificationKind.nearby))
                      PositionedDirectional(
                        bottom: 0,
                        end: 0,
                        child: SvgPicture.asset(
                          icon,
                          key: ValueKey('notification-icon-${item.id}'),
                          width: overlaySize,
                          height: overlaySize,
                          excludeFromSemantics: true,
                        ),
                      ),
                    if (icon == null)
                      const PositionedDirectional(
                        bottom: 0,
                        end: 0,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: Color(0xFF292929),
                            shape: BoxShape.circle,
                          ),
                          child: SizedBox.square(
                            dimension: 20,
                            child: Icon(
                              Icons.notifications_none,
                              size: 14,
                              color: Colors.white70,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              SizedBox(width: AppSizes.adaptiveWidth(8)),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _Summary(
                      name: emphasis,
                      message: remainder,
                      time: item.createdAt == null
                          ? null
                          : timeAgo(item.createdAt),
                      style: textStyle,
                    ),
                    if (secondary != null && secondary.isNotEmpty)
                      Text(
                        secondary,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: textStyle.copyWith(
                          color: const Color(0xFF8C8C8C),
                        ),
                      ),
                  ],
                ),
              ),
              if (followAction != null) ...[
                const SizedBox(width: 8),
                Padding(padding: EdgeInsets.only(top: 8), child: followAction!),
              ],
              if (followAction == null &&
                  preview != null &&
                  preview.supported) ...[
                SizedBox(width: AppSizes.adaptiveWidth(12)),
                _Preview(preview: preview),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _AvatarTap extends StatelessWidget {
  const _AvatarTap({
    required this.onTap,
    required this.id,
    required this.child,
  });
  final VoidCallback? onTap;
  final String id;
  final Widget child;
  @override
  Widget build(BuildContext context) => onTap == null
      ? child
      : Semantics(
          button: true,
          label: 'Open profile',
          child: GestureDetector(
            key: ValueKey('notification-avatar-$id'),
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: child,
          ),
        );
}

class _Preview extends StatelessWidget {
  const _Preview({required this.preview});
  final NotificationThumbnail preview;
  @override
  Widget build(BuildContext context) {
    // Figma: posts are square, Stories are a portrait rectangle.
    final story = preview.kind == NotificationMediaKind.story;
    return ClipRRect(
      borderRadius: BorderRadius.circular(
        AppSizes.adaptiveRadius(story ? 8 : 10),
      ),
      child: SizedBox(
        key: ValueKey(
          story ? 'notification-story-preview' : 'notification-post-preview',
        ),
        width: story ? 48 : 52,
        height: story ? 72 : 52,
        child: Image.network(
          preview.url,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => const SizedBox.shrink(),
        ),
      ),
    );
  }
}

/// Reserve the timestamp while truncating whole grapheme clusters, including
/// emoji/Arabic. No raw enum text or extra ellipsis is appended by Text overflow.
class _Summary extends StatelessWidget {
  const _Summary({
    required this.name,
    required this.message,
    required this.time,
    required this.style,
  });
  final String? name, time;
  final String message;
  final TextStyle style;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final content = name == null ? message : '$name $message';
      final clusters = content.characters.toList(growable: false);
      final nameLength = name?.characters.length ?? 0;
      TextSpan span(int n, bool shortened) {
        final bold = n < nameLength ? n : nameLength;
        return TextSpan(
          style: style,
          children: [
            if (bold > 0)
              TextSpan(
                text: clusters.take(bold).join(),
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            TextSpan(text: clusters.skip(bold).take(n - bold).join()),
            if (shortened) const TextSpan(text: '…'),
            if (time != null)
              TextSpan(
                text: '  $time',
                style: const TextStyle(
                  color: Color(0xFF8C8C8C),
                  fontWeight: FontWeight.w400,
                ),
              ),
          ],
        );
      }

      bool fits(int n, bool shortened) {
        final painter = TextPainter(
          text: span(n, shortened),
          maxLines: 3,
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
        )..layout(maxWidth: constraints.maxWidth);
        final result = !painter.didExceedMaxLines;
        painter.dispose();
        return result;
      }

      var length = clusters.length;
      final shortened = !fits(length, false);
      if (shortened) {
        var low = 0, high = length;
        while (low < high) {
          final mid = (low + high + 1) ~/ 2;
          if (fits(mid, true)) {
            low = mid;
          } else {
            high = mid - 1;
          }
        }
        length = low;
      }
      return Text.rich(
        span(length, shortened),
        maxLines: 3,
        overflow: TextOverflow.clip,
        semanticsLabel: '$content ${time ?? ''}',
      );
    },
  );
}
