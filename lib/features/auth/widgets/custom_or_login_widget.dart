import 'package:flutter/material.dart';
import 'package:travibe/core/theme/dark_colors.dart';

class CustomOrLoginWidget extends StatelessWidget {
  const CustomOrLoginWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SizedBox(width: 100, child: const Divider(color: DarkColors.greyColor)),
        SizedBox(width: 12),
        Text(
          "Or Login With",
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w400,
            color: DarkColors.greyColor,
          ),
        ),
        SizedBox(width: 12),
        SizedBox(width: 100, child: const Divider(color: DarkColors.greyColor)),
      ],
    );
  }
}
