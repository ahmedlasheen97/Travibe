import 'package:flutter/material.dart';
import 'package:travibe/core/constants/app_sizes.dart';
import 'package:travibe/core/theme/app_styles.dart';
import 'package:travibe/core/theme/dark_colors.dart';

class ProfileStats extends StatelessWidget {
  final int? posts;
  final int? followers;
  final int? following;
  final VoidCallback? onFollowersTap;
  final VoidCallback? onFollowingTap;

  const ProfileStats({
    super.key,
    required this.posts,
    required this.followers,
    required this.following,
    this.onFollowersTap,
    this.onFollowingTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        border: Border.all(color: DarkColors.darkgreyColor),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _statItem(posts?.toString() ?? '—', 'Posts'),
          _divider(),
          _statItem(
            followers?.toString() ?? '—',
            'Followers',
            onTap: onFollowersTap,
          ),
          _divider(),
          _statItem(
            following?.toString() ?? '—',
            'Following',
            onTap: onFollowingTap,
          ),
        ],
      ),
    );
  }

  Widget _divider() => const SizedBox(
    height: 28,
    child: VerticalDivider(
      width: 1,
      thickness: 1,
      color: DarkColors.darkgreyColor,
    ),
  );

  Widget _statItem(String value, String label, {VoidCallback? onTap}) {
    final content = Column(
      children: [
        Text(
          value,
          style: TextStyle(
            color: DarkColors.primaryColor,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        SizedBox(height: AppSizes.h2),
        Text(
          label,
          style: AppStyles.grey14MediumStyle.copyWith(
            fontWeight: FontWeight.w500,
            fontSize: AppSizes.sp12,
          ),
        ),
      ],
    );
    return Expanded(
      child: onTap == null
          ? content
          : Semantics(
              button: true,
              child: InkWell(
                onTap: onTap,
                borderRadius: BorderRadius.circular(12),
                child: content,
              ),
            ),
    );
  }
}
