import 'package:flutter/material.dart';
import 'package:travibe/core/constants/app_sizes.dart';
import 'package:travibe/core/theme/dark_colors.dart';
import 'package:travibe/core/widgets/sheet_handle.dart';

class LanguageBottomSheet extends StatefulWidget {
  final String selectedLanguageCode; // 'en' or 'ar'

  const LanguageBottomSheet({super.key, required this.selectedLanguageCode});

  static Future<String?> show(BuildContext context, String currentCode) {
    return showModalBottomSheet<String>(
      context: context,
      // Same frame as the post ⋮ sheet (PostOptionsSheet).
      backgroundColor: const Color(0xFF0A0A0A),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppSizes.r24)),
      ),
      builder: (_) => LanguageBottomSheet(selectedLanguageCode: currentCode),
    );
  }

  @override
  State<LanguageBottomSheet> createState() => _LanguageBottomSheetState();
}

class _LanguageBottomSheetState extends State<LanguageBottomSheet> {
  late String _selected = widget.selectedLanguageCode;

  static const _languages = [
    {'code': 'en', 'label': 'English'},
    {'code': 'ar', 'label': 'العربية'},
  ];

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(bottom: AppSizes.ph16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(height: AppSizes.h16),
            const SheetHandle(),
            SizedBox(height: AppSizes.h16),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: AppSizes.pw20),
              child: Row(
                children: [
                  Text(
                    'Language',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: AppSizes.sp17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: AppSizes.h12),
            for (final lang in _languages)
              _languageTile(lang['code']!, lang['label']!),
          ],
        ),
      ),
    );
  }

  Widget _languageTile(String code, String label) {
    final isSelected = _selected == code;
    return InkWell(
      onTap: () {
        setState(() => _selected = code);
        Navigator.pop(context, code);
      },
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.symmetric(
          horizontal: AppSizes.pw20,
          vertical: AppSizes.ph16,
        ),
        color: isSelected
            ? DarkColors.primaryColor.withValues(alpha: 0.15)
            : Colors.transparent,
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(color: Colors.white, fontSize: AppSizes.sp15),
              ),
            ),
            if (isSelected)
              Icon(
                Icons.check_rounded,
                color: DarkColors.primaryColor,
                size: AppSizes.w20,
              ),
          ],
        ),
      ),
    );
  }
}
