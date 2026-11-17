import 'package:flutter/material.dart';
import 'package:travibe/core/constants/app_sizes.dart';
import 'package:travibe/core/theme/dark_colors.dart';

/// Figma "Complete your profile" card (docs/figma/buddiesflow/
/// complete_profile_card.png): artwork in a brown circle on the left; title,
/// text and a right-aligned orange button on the right.
class BuddiesCompleteProfileCard extends StatelessWidget {
  const BuddiesCompleteProfileCard({super.key, required this.onComplete});
  final VoidCallback? onComplete;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: EdgeInsets.all(AppSizes.adaptiveRadius(16)),
    decoration: BoxDecoration(
      color: const Color(0xFF1C1B1A),
      border: Border.all(color: const Color(0xFF2E2D2C)),
      borderRadius: BorderRadius.circular(AppSizes.adaptiveRadius(24)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ExcludeSemantics(
          child: Container(
            key: const ValueKey('complete-profile-art'),
            width: AppSizes.adaptiveRadius(80),
            height: AppSizes.adaptiveRadius(80),
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: Color(0x33E45C10),
              shape: BoxShape.circle,
            ),
            child: Image.asset(
              'assets/images/buddies/completeprofile.png',
              width: AppSizes.adaptiveRadius(53),
              height: AppSizes.adaptiveRadius(50),
              fit: BoxFit.contain,
            ),
          ),
        ),
        SizedBox(width: AppSizes.adaptiveWidth(12)),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Complete your profile',
                style: TextStyle(
                  letterSpacing: 0,
                  color: Colors.white,
                  fontSize: AppSizes.adaptiveFont(16),
                  height: 24 / 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              SizedBox(height: AppSizes.adaptiveHeight(2)),
              Text(
                'Add more details so people can get to know you more.',
                style: TextStyle(
                  letterSpacing: 0,
                  color: DarkColors.greyColor,
                  fontSize: AppSizes.adaptiveFont(13),
                  height: 18 / 13,
                ),
              ),
              SizedBox(height: AppSizes.adaptiveHeight(12)),
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: TextButton(
                  onPressed: onComplete,
                  style: TextButton.styleFrom(
                    backgroundColor: DarkColors.primaryColor,
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.symmetric(
                      horizontal: AppSizes.adaptiveWidth(16),
                      vertical: AppSizes.adaptiveHeight(6),
                    ),
                    minimumSize: Size(0, AppSizes.adaptiveHeight(36)),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    shape: const StadiumBorder(),
                  ),
                  child: Text(
                    'Complete Profile',
                    style: TextStyle(
                      letterSpacing: 0,
                      fontSize: AppSizes.adaptiveFont(16),
                      height: 24 / 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
