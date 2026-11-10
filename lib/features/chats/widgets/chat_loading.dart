import 'package:flutter/material.dart';
import 'package:skeletonizer/skeletonizer.dart';

/// Home's dark loading palette/timing, using the requested Flutter-only loader.
/// Bones are presentation-only and never enter repositories or session caches.
class ChatSkeleton extends StatelessWidget {
  const ChatSkeleton({
    super.key,
    required this.child,
    this.label = 'Loading messages',
  });
  final Widget child;
  final String label;
  @override
  Widget build(BuildContext context) => Semantics(
    label: label,
    child: ExcludeSemantics(
      child: IgnorePointer(
        child: Skeletonizer.zone(
          effect: MediaQuery.disableAnimationsOf(context)
              ? const SolidColorEffect(color: Color(0xFF232323))
              : const ShimmerEffect(
                  baseColor: Color(0xFF232323),
                  highlightColor: Color(0xFF303030),
                  duration: Duration(milliseconds: 1800),
                ),
          child: child,
        ),
      ),
    ),
  );
}

class ChatHistorySkeleton extends StatelessWidget {
  const ChatHistorySkeleton({super.key});
  @override
  Widget build(BuildContext context) => ChatSkeleton(
    child: Column(
      children: [
        for (var i = 0; i < 6; i++)
          Align(
            alignment: i.isEven
                ? AlignmentDirectional.centerStart
                : AlignmentDirectional.centerEnd,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: FractionallySizedBox(
                widthFactor: i % 3 == 0 ? .7 : .48,
                child: Bone(
                  height: i % 3 == 0 ? 72 : 42,
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          ),
      ],
    ),
  );
}

class ChatMediaSkeleton extends StatelessWidget {
  const ChatMediaSkeleton({super.key});
  @override
  Widget build(BuildContext context) => ChatSkeleton(
    label: 'Loading shared media',
    child: GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 8,
      mainAxisSpacing: 8,
      children: List.generate(
        9,
        (_) => Bone(borderRadius: BorderRadius.circular(12)),
      ),
    ),
  );
}
