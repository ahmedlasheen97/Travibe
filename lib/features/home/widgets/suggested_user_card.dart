import 'package:travibe/core/utils/viewer_identity.dart';
import 'package:travibe/core/widgets/user_profile_link.dart';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:travibe/features/follow/widgets/follow_pill.dart';
import 'package:travibe/core/models/public_user_model.dart';
import 'package:travibe/features/follow/widgets/follow_action_builder.dart';
import 'package:travibe/features/home/widgets/home_user_avatar.dart';

class SuggestedUserCard extends StatelessWidget {
  const SuggestedUserCard({super.key, required this.user});
  final PublicUserModel user;

  static double heightFor(TextScaler scaler) =>
      12 +
      56 +
      8 +
      scaler.scale(14) * (24 / 14) +
      scaler.scale(12) * (16 / 12) +
      12 +
      math.max(36, scaler.scale(14) * (24 / 14) + 12) +
      16; // Allow fractional font metrics to round up without clipping.

  @override
  Widget build(BuildContext context) => FollowActionBuilder(
    userId: user.id,
    initialFollowing: user.isFollowing,
    initialRequested: user.followRequested,
    builder: (context, relation, pending, onToggle) => Container(
      width: 144,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF141414),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          UserProfileLink(
            userId: user.id,
            child: HomeUserAvatar(url: user.avatarUrl),
          ),
          const SizedBox(height: 8),
          UserProfileLink(
            userId: user.id,
            child: Text(
              user.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: 'Plus Jakarta Sans',
                fontSize: 14,
                height: 24 / 14,
                color: Colors.white,
                fontWeight: FontWeight.w600,
                decoration: TextDecoration.none,
              ),
            ),
          ),
          Text(
            user.handle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 12,
              height: 16 / 12,
              color: Colors.white54,
              decoration: TextDecoration.none,
            ),
          ),
          const SizedBox(height: 12),
          // Never offer Follow on the signed-in user's own card; keep the
          // card height so the row stays aligned.
          Visibility(
            visible: !isViewer(context, user.id),
            maintainSize: true,
            maintainAnimation: true,
            maintainState: true,
            child: SizedBox(
              width: double.infinity,
              child: FollowPill(
                relation: relation,
                pending: pending,
                onPressed: onToggle,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
