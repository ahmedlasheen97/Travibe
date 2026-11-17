import 'package:flutter/material.dart';
import 'package:travibe/core/constants/app_sizes.dart';
import 'package:travibe/features/buddies/widgets/buddies_promo_card.dart';
import 'package:travibe/features/buddies/widgets/show_in_buddies_sheet.dart';

/// Figma "Meet People in Your City" card, shown while Show in Buddies is off.
class BuddiesVisibilityInvitation extends StatelessWidget {
  const BuddiesVisibilityInvitation({super.key, this.onTurnOn});

  /// Overrides opening the Show in Buddies sheet (tests, previews).
  final VoidCallback? onTurnOn;

  @override
  Widget build(BuildContext context) => BuddiesPromoCard(
    color: const Color(0xFF6644BD),
    image: 'assets/images/buddies/visibility.png',
    imageWidth: 138,
    imageHeight: 117,
    title: 'Meet People in Your City',
    message:
        'Turn on visibility to share your current city and let others discover you.',
    action: TextButton(
      onPressed: onTurnOn ?? () => showShowInBuddiesSheet(context),
      style: TextButton.styleFrom(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        padding: EdgeInsets.symmetric(
          horizontal: AppSizes.adaptiveWidth(16),
          vertical: AppSizes.adaptiveHeight(6),
        ),
        minimumSize: Size(0, AppSizes.adaptiveHeight(36)),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: const StadiumBorder(),
      ),
      child: Text(
        'Turn On Visibility',
        style: TextStyle(
          letterSpacing: 0,
          fontSize: AppSizes.adaptiveFont(16),
          height: 24 / 16,
          fontWeight: FontWeight.w500,
        ),
      ),
    ),
    footer: Row(
      children: [
        Icon(
          Icons.info_outline,
          size: AppSizes.adaptiveRadius(16),
          color: Colors.white,
        ),
        SizedBox(width: AppSizes.adaptiveWidth(4)),
        Flexible(
          child: Text(
            'You can turn this off from settings.',
            style: TextStyle(
              letterSpacing: 0,
              color: Colors.white,
              fontSize: AppSizes.adaptiveFont(12),
              height: 16 / 12,
            ),
          ),
        ),
      ],
    ),
  );
}
