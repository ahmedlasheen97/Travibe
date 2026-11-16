import 'package:flutter/material.dart';

/// Chats empty-state artwork (1x/2x/3x PNG).
class ChatEmptyIllustration extends StatelessWidget {
  const ChatEmptyIllustration({super.key});
  static const asset = 'assets/images/avatar/chat_empty.png';

  /// Decodes the artwork ahead of first paint (e.g. golden captures).
  static Future<void> precache(BuildContext context) =>
      precacheImage(const AssetImage(asset), context);

  @override
  Widget build(BuildContext context) => const ExcludeSemantics(
    child: Image(
      image: AssetImage(asset),
      width: 134,
      height: 121,
      fit: BoxFit.contain,
    ),
  );
}
