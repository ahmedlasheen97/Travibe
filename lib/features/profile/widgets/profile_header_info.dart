import 'package:flutter/material.dart';
import 'package:travibe/core/constants/app_sizes.dart';
import 'package:travibe/core/theme/dark_colors.dart';

class ProfileHeaderInfo extends StatelessWidget {
  final String name;
  final String username;
  final String bio;

  const ProfileHeaderInfo({
    super.key,
    required this.name,
    required this.username,
    required this.bio,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: AppSizes.pw32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            name,
            key: const ValueKey('profile-name'),
            textAlign: TextAlign.center,
            style: TextStyle(
              color: DarkColors.whiteColor,
              fontSize: AppSizes.sp20,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (username.isNotEmpty) ...[
            SizedBox(height: AppSizes.h2),
            Text(
              username,
              key: const ValueKey('profile-username'),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: DarkColors.greyColor,
                fontSize: AppSizes.sp14,
              ),
            ),
          ],
          if (bio.trim().isNotEmpty) ...[
            SizedBox(height: AppSizes.h8),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: AppSizes.pw8),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: AppSizes.w290),
                child: Text(
                  bio,
                  key: const ValueKey('profile-bio'),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  softWrap: true,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: DarkColors.whiteColor,
                    fontSize: AppSizes.sp16,
                    fontFamily: 'Plus Jakarta Sans',
                    fontWeight: FontWeight.w400,
                    height: 1.4,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
