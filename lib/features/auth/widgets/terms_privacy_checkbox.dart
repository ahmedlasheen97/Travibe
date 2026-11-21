import 'package:travibe/core/constants/app_sizes.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:travibe/core/theme/dark_colors.dart';
import 'package:travibe/features/profile/screens/privacy_policy_screen.dart';
import 'package:travibe/features/profile/screens/terms_of_service_screen.dart';

class TermsAndPrivacyCheckbox extends StatefulWidget {
  const TermsAndPrivacyCheckbox({super.key, this.onChanged});
  final ValueChanged<bool>? onChanged;
  @override
  State<TermsAndPrivacyCheckbox> createState() =>
      _TermsAndPrivacyCheckboxState();
}

class _TermsAndPrivacyCheckboxState extends State<TermsAndPrivacyCheckbox> {
  bool isChecked = false;
  bool _opening = false;
  late final TapGestureRecognizer _termsTap;
  late final TapGestureRecognizer _privacyTap;

  @override
  void initState() {
    super.initState();
    _termsTap = TapGestureRecognizer()
      ..onTap = () => _open(const TermsOfServiceScreen());
    _privacyTap = TapGestureRecognizer()
      ..onTap = () => _open(const PrivacyPolicyScreen());
  }

  @override
  void dispose() {
    _termsTap.dispose();
    _privacyTap.dispose();
    super.dispose();
  }

  Future<void> _open(Widget page) async {
    if (!mounted || _opening) return;
    setState(() => _opening = true);
    FocusManager.instance.primaryFocus?.unfocus();
    try {
      await Navigator.of(
        context,
      ).push(MaterialPageRoute<void>(builder: (_) => page));
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ar = Localizations.localeOf(context).languageCode == 'ar';
    final style = TextStyle(
      fontFamily: 'Plus Jakarta Sans',
      color: Colors.white,
      fontSize: AppSizes.authCaptionFont,
      fontWeight: FontWeight.w500,
      height: 1.4,
    );
    final lineHeight =
        MediaQuery.textScalerOf(context).scale(style.fontSize!) * style.height!;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: kMinInteractiveDimension,
          height: kMinInteractiveDimension,
          child: Semantics(
            label: ar
                ? 'أوافق على شروط الخدمة وسياسة الخصوصية'
                : 'I agree to the Terms of Service and Privacy Policy',
            child: Checkbox(
              value: isChecked,
              onChanged: (value) {
                setState(() => isChecked = value ?? false);
                widget.onChanged?.call(isChecked);
              },
              side: const BorderSide(
                color: Color(0xFFD3D1CF),
                width: AppSizes.authCheckboxBorderWidth,
              ),
              activeColor: const Color(0xFFE45C10),
              checkColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(
                  AppSizes.authCheckboxRadius,
                ),
              ),
            ),
          ),
        ),
        Expanded(
          // Align the first text line with the checkbox's visual center.
          // Subsequent lines have only the paragraph's normal line spacing.
          child: Padding(
            padding: EdgeInsets.only(
              top: ((kMinInteractiveDimension - lineHeight) / 2).clamp(
                0,
                double.infinity,
              ),
            ),
            child: Text.rich(
              key: const ValueKey('signup-legal-sentence'),
              TextSpan(
                children: [
                  TextSpan(text: ar ? 'أوافق على ' : 'I agree to the '),
                  TextSpan(
                    text: ar ? 'شروط الخدمة' : 'Terms of Service',
                    semanticsIdentifier: 'signup-terms-link',
                    recognizer: _termsTap,
                    style: const TextStyle(color: DarkColors.primaryColor),
                  ),
                  TextSpan(text: ar ? ' و' : ' and '),
                  TextSpan(
                    text: ar ? 'سياسة الخصوصية' : 'Privacy Policy',
                    semanticsIdentifier: 'signup-privacy-link',
                    recognizer: _privacyTap,
                    style: const TextStyle(color: DarkColors.primaryColor),
                  ),
                ],
              ),
              style: style,
            ),
          ),
        ),
      ],
    );
  }
}
