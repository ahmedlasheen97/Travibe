import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:travibe/features/chats/widgets/chat_reverb_host.dart';
import 'package:travibe/features/chats/cubit/chat_unread_cubit.dart';
import 'package:flutter_svg/svg.dart';
import 'package:travibe/core/constants/app_sizes.dart';
import 'package:travibe/core/notifications/push_notifications_host.dart';
import 'package:travibe/core/theme/dark_colors.dart';

class HomeTopBar extends StatelessWidget {
  final String? name;
  final int? unreadCount;
  final VoidCallback onMessagesTap;
  final VoidCallback onNotificationsTap;

  const HomeTopBar({
    super.key,
    this.name,
    this.unreadCount,
    required this.onMessagesTap,
    required this.onNotificationsTap,
  });

  static TextStyle get greetingStyle => TextStyle(
    fontFamily: 'Plus Jakarta Sans',
    fontSize: AppSizes.adaptiveFont(18),
    color: Colors.white,
    fontWeight: FontWeight.w400,
  );
  static TextStyle get subtitleStyle => TextStyle(
    fontFamily: 'Plus Jakarta Sans',
    fontSize: AppSizes.adaptiveFont(14),
    color: const Color(0xFFBDBCBB),
    fontWeight: FontWeight.w400,
  );
  static double preferredHeight(BuildContext context) {
    double line(TextStyle style) {
      final painter = TextPainter(
        text: TextSpan(text: 'Hello', style: style),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
      )..layout();
      final height = painter.height;
      painter.dispose();
      return height;
    }

    final textHeight =
        line(greetingStyle.copyWith(fontWeight: FontWeight.w700)) +
        AppSizes.adaptiveHeight(4) +
        line(DefaultTextStyle.of(context).style.merge(subtitleStyle));
    return textHeight > AppSizes.adaptiveRadius(48)
        ? textHeight
        : AppSizes.adaptiveRadius(48);
  }

  @override
  Widget build(BuildContext context) {
    final activity = PushNotificationsScope.maybeOf(context)?.notifications;
    if (unreadCount != null || activity == null) {
      return _content(context, unreadCount ?? 0);
    }
    return ListenableBuilder(
      listenable: activity,
      builder: (context, _) => _content(context, activity.count),
    );
  }

  Widget _content(BuildContext context, int count) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: AppSizes.adaptiveWidth(20)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                RichText(
                  textScaler: MediaQuery.textScalerOf(context),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  text: TextSpan(
                    style: greetingStyle,
                    children: [
                      const TextSpan(text: 'Hello, '),
                      TextSpan(
                        text: name?.trim().isNotEmpty == true
                            ? name!.trim().split(RegExp(r'\s+')).first
                            : 'there',
                        style: greetingStyle.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: AppSizes.adaptiveHeight(4)),
                Text(
                  'Discover. Connect. Explore.',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: subtitleStyle,
                ),
              ],
            ),
          ),
          _messagesButton(context),
          SizedBox(width: AppSizes.adaptiveWidth(10)),
          _circleIconButton(
            SvgPicture.asset(
              'assets/images/home/notification.svg',
              width: AppSizes.adaptiveRadius(18),
              height: AppSizes.adaptiveRadius(18),
            ),
            onTap: onNotificationsTap,
            badgeCount: count,
            buttonKey: const ValueKey('home-notification-bell'),
          ),
        ],
      ),
    );
  }

  Widget _messagesButton(BuildContext context) {
    final unread = ChatReverbScope.unreadOf(context);
    Widget button(int count) => Stack(
      clipBehavior: Clip.none,
      children: [
        _circleIconButton(
          SvgPicture.asset(
            'assets/images/home/messages-2.svg',
            width: AppSizes.adaptiveRadius(24),
            height: AppSizes.adaptiveRadius(24),
          ),
          onTap: onMessagesTap,
          buttonKey: const ValueKey('home-messages-button'),
        ),
        if (count > 0)
          PositionedDirectional(
            top: -3,
            end: -4,
            child: IgnorePointer(
              child: Semantics(
                label: '$count unread messages',
                child: Container(
                  key: const ValueKey('chat-unread-badge'),
                  constraints: const BoxConstraints(
                    minWidth: 18,
                    minHeight: 18,
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: DarkColors.primaryColor,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: DarkColors.backgroundColor,
                      width: 1.5,
                    ),
                  ),
                  child: Text(
                    count > 99 ? '99+' : '$count',
                    textScaler: TextScaler.noScaling,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
    if (unread == null) return button(0);
    return BlocBuilder<ChatUnreadCubit, ChatUnreadState>(
      bloc: unread,
      builder: (_, state) => button(state.count),
    );
  }

  Widget _circleIconButton(
    Widget icon, {
    required VoidCallback onTap,
    int badgeCount = 0,
    Key? buttonKey,
  }) {
    return InkWell(
      key: buttonKey,
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppSizes.adaptiveRadius(24)),
      child: Container(
        width: AppSizes.adaptiveRadius(48),
        height: AppSizes.adaptiveRadius(48),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: const Color(0xFF3B3B3B)),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            icon,
            if (badgeCount > 0)
              Positioned(
                top: 0,
                right: 0,
                child: Semantics(
                  label: '$badgeCount unread notifications',
                  child: Container(
                    key: const ValueKey('notification-unread-badge'),
                    constraints: const BoxConstraints(
                      minWidth: 18,
                      minHeight: 18,
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: DarkColors.primaryColor,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      badgeCount > 99 ? '99+' : '$badgeCount',
                      textScaler: TextScaler.noScaling,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
