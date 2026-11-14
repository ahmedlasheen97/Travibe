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
      margin: EdgeInsets.symmetric(horizontal: AppSizes.pw20),
      padding: EdgeInsets.symmetric(vertical: AppSizes.ph14),
      decoration: BoxDecoration(
        border: Border.all(color: DarkColors.darkgreyColor),
        borderRadius: BorderRadius.circular(AppSizes.r20),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _statItem(posts?.toString() ?? '—', posts == 1 ? 'Post' : 'Posts'),
          _divider(),
          _statItem(
            followers?.toString() ?? '—',
            followers == 1 ? 'Follower' : 'Followers',
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

  Widget _divider() => SizedBox(
    height: AppSizes.h28,
    child: VerticalDivider(
      width: AppSizes.w1,
      thickness: AppSizes.h1,
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
            fontSize: AppSizes.sp18,
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
                borderRadius: BorderRadius.circular(AppSizes.r12),
                child: content,
              ),
            ),
    );
  }
}
