import 'package:flutter/material.dart';
import 'package:travibe/core/theme/dark_colors.dart';

/// Profile Setup progress (Figma): equal rounded bars, orange for completed
/// and current steps, grey for upcoming ones.
class SetupStepIndicator extends StatelessWidget {
  const SetupStepIndicator({
    super.key,
    required this.count,
    required this.current,
  });
  final int count;

  /// Zero-based index of the step on screen.
  final int current;

  static const upcomingColor = Color(0xFF303030);

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Step ${current + 1} of $count',
    excludeSemantics: true,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < count; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          AnimatedContainer(
            key: ValueKey('setup-step-bar-$i'),
            duration: const Duration(milliseconds: 200),
            width: 44,
            height: 6,
            decoration: BoxDecoration(
              color: i <= current ? DarkColors.primaryColor : upcomingColor,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
        ],
      ],
    ),
  );
}
