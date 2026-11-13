import 'package:flutter/material.dart';
import 'package:travibe/features/follow/widgets/follow_action_builder.dart';

/// Presentation shared with Home suggestions; follow mutations stay in
/// FollowActionBuilder/FollowCubit, supplied through [onPressed].
class FollowPill extends StatelessWidget {
  const FollowPill({
    super.key,
    required this.relation,
    required this.pending,
    required this.onPressed,
    this.style,
  });
  final FollowRelation relation;
  final bool pending;
  final VoidCallback? onPressed;
  final ButtonStyle? style;
  static const backgroundColor = Color(0xFF2F2E2D);

  @override
  Widget build(BuildContext context) => TextButton(
    onPressed: pending ? null : onPressed,
    style: (style ?? const ButtonStyle()).merge(
      TextButton.styleFrom(
        backgroundColor: backgroundColor,
        minimumSize: const Size(0, 36),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        shape: const StadiumBorder(),
      ),
    ),
    child: pending
        ? const SizedBox.square(
            dimension: 16,
            child: CircularProgressIndicator(
              semanticsLabel: 'Updating follow status',
              strokeWidth: 2,
            ),
          )
        : Text(
            relation.label,
            maxLines: 1,
            style: TextStyle(
              fontSize: 14,
              height: 24 / 14,
              color: relation.isRequested ? requestedFollowColor : Colors.white,
              fontWeight: FontWeight.w500,
              decoration: TextDecoration.none,
            ),
          ),
  );
}
