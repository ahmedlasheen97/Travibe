import 'package:travibe/core/constants/app_sizes.dart';
import 'package:flutter/material.dart';
import 'package:travibe/core/theme/dark_colors.dart';

class CustomOrLoginWidget extends StatelessWidget {
  const CustomOrLoginWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Expanded(child: Divider(color: DarkColors.greyColor)),
        SizedBox(width: AppSizes.adaptiveWidth(12)),
        Flexible(
          flex: 3,
          child: Text(
            "Or Login With",
            style: TextStyle(
              fontSize: AppSizes.adaptiveFont(16),
              fontWeight: FontWeight.w400,
              color: DarkColors.greyColor,
            ),
          ),
        ),
        SizedBox(width: AppSizes.adaptiveWidth(12)),
        const Expanded(child: Divider(color: DarkColors.greyColor)),
      ],
    );
  }
}
