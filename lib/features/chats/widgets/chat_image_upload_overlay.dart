import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';

class ChatImageUploadOverlay extends StatelessWidget {
  const ChatImageUploadOverlay({
    super.key,
    required this.child,
    required this.sending,
    this.progress,
  });
  final Widget child;
  final bool sending;
  final double? progress;
  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(16),
    child: Stack(
      children: [
        child,
        Positioned.fill(
          child: AnimatedSwitcher(
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 180),
            child: !sending
                ? const SizedBox.shrink()
                : Semantics(
                    key: const ValueKey('chat-image-upload-overlay'),
                    label: 'Sending attachment',
                    value:
                        progress != null &&
                            progress!.isFinite &&
                            progress! >= 0 &&
                            progress! <= 1
                        ? 'Upload ${(progress! * 100).floor()}%'
                        : null,
                    child: ColoredBox(
                      color: const Color(0x88000000),
                      child: Center(
                        child: CupertinoActivityIndicator(
                          color: Colors.white,
                          animating: !MediaQuery.disableAnimationsOf(context),
                        ),
                      ),
                    ),
                  ),
          ),
        ),
      ],
    ),
  );
}
