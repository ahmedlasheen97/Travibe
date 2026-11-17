import 'package:flutter/material.dart';
import 'package:travibe/core/constants/app_sizes.dart';
import 'package:travibe/core/theme/dark_colors.dart';

/// Dark "Select …" dropdown pill used to open picker sheets (nationality).
class CountryPickerField extends StatelessWidget {
  const CountryPickerField({
    super.key,
    required this.hint,
    required this.onTap,
    this.value,
    this.loading = false,
  });
  final String hint;
  final String? value;
  final VoidCallback? onTap;
  final bool loading;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    enabled: onTap != null,
    label: value ?? hint,
    excludeSemantics: true,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppSizes.r28),
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: AppSizes.adaptiveWidth(16),
          vertical: AppSizes.adaptiveHeight(12),
        ),
        decoration: BoxDecoration(
          color: const Color(0xFF141414),
          border: Border.all(color: const Color(0xFF292929)),
          borderRadius: BorderRadius.circular(AppSizes.r28),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                value ?? hint,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: value != null
                      ? DarkColors.whiteColor
                      : DarkColors.greyColor,
                  fontSize: AppSizes.adaptiveFont(14),
                ),
              ),
            ),
            if (loading)
              SizedBox(
                width: AppSizes.adaptiveRadius(16),
                height: AppSizes.adaptiveRadius(16),
                child: const CircularProgressIndicator(strokeWidth: 2),
              )
            else
              Icon(
                Icons.keyboard_arrow_down_rounded,
                color: onTap == null
                    ? DarkColors.greyColor.withValues(alpha: .4)
                    : DarkColors.whiteColor,
              ),
          ],
        ),
      ),
    ),
  );
}
