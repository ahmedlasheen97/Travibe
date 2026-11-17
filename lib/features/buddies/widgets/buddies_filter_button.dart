import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:travibe/core/constants/app_sizes.dart';
import 'package:travibe/core/theme/dark_colors.dart';

/// Figma "Filters" pill for Buddies listings and search, with an orange badge
/// counting the applied filter values.
class BuddiesFilterButton extends StatelessWidget {
  const BuddiesFilterButton({
    super.key,
    required this.count,
    required this.onPressed,
  });
  final int count;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: count == 0 ? 'Filters' : 'Filters, $count active',
    excludeSemantics: true,
    child: FilledButton(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        foregroundColor: Colors.white,
        backgroundColor: const Color(0xFF2F2E2D),
        shape: const StadiumBorder(),
        padding: EdgeInsets.symmetric(
          horizontal: AppSizes.adaptiveWidth(16),
          vertical: AppSizes.adaptiveHeight(10),
        ),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        textStyle: Theme.of(context).textTheme.labelLarge!.copyWith(
          fontSize: 18,
          height: 24 / 18,
          letterSpacing: 0,
          fontWeight: FontWeight.w500,
          decoration: TextDecoration.none,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SvgPicture.asset('assets/images/interactions/buddies-filter.svg'),
          SizedBox(width: AppSizes.adaptiveWidth(8)),
          const Flexible(
            child: Text('Filters', overflow: TextOverflow.ellipsis),
          ),
          if (count > 0) ...[
            SizedBox(width: AppSizes.adaptiveWidth(8)),
            Container(
              key: const ValueKey('buddies-filter-count'),
              constraints: BoxConstraints(
                minWidth: AppSizes.adaptiveRadius(22),
              ),
              height: AppSizes.adaptiveRadius(22),
              padding: EdgeInsets.symmetric(
                horizontal: AppSizes.adaptiveWidth(6),
              ),
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                color: DarkColors.primaryColor,
                shape: BoxShape.rectangle,
                borderRadius: BorderRadius.all(Radius.circular(11)),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: AppSizes.adaptiveFont(12),
                  height: 1,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ],
      ),
    ),
  );
}
