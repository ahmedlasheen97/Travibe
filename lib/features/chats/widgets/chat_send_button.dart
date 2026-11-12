import 'package:travibe/core/widgets/app_loaders.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:travibe/core/theme/dark_colors.dart';

/// One action surface for text and media: dimensions, SVG, states and feedback.
class ChatSendButton extends StatelessWidget {
  const ChatSendButton({
    super.key,
    required this.onPressed,
    this.loading = false,
    this.tooltip = 'Send message',
  });
  final VoidCallback? onPressed;
  final bool loading;
  final String tooltip;
  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: 48,
    child: IconButton(
      tooltip: tooltip,
      onPressed: loading ? null : onPressed,
      style: IconButton.styleFrom(
        backgroundColor: DarkColors.primaryColor,
        disabledBackgroundColor: const Color(0xFF803D14),
      ),
      icon: loading
          ? SizedBox.square(
              dimension: 18,
              child: AppActivityIndicator(
                animating: !MediaQuery.disableAnimationsOf(context),
              ),
            )
          : SvgPicture.asset(
              'assets/images/interactions/send.svg',
              width: 20,
              height: 20,
            ),
    ),
  );
}
