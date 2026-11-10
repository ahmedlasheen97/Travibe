import 'package:flutter/material.dart';
import 'package:travibe/core/theme/dark_colors.dart';

class LanguageBottomSheet extends StatefulWidget {
  final String selectedLanguageCode; // 'en' or 'ar'

  const LanguageBottomSheet({super.key, required this.selectedLanguageCode});

  static Future<String?> show(BuildContext context, String currentCode) {
    return showModalBottomSheet<String>(
      context: context,
      backgroundColor: const Color(0xFF141414),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
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
        padding: const EdgeInsets.only(bottom: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  const Text(
                    'Language',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
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
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        color: isSelected
            ? DarkColors.primaryColor.withValues(alpha: 0.15)
            : Colors.transparent,
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: const TextStyle(color: Colors.white, fontSize: 15),
              ),
            ),
            if (isSelected)
              Icon(
                Icons.check_rounded,
                color: DarkColors.primaryColor,
                size: 20,
              ),
          ],
        ),
      ),
    );
  }
}
