import 'package:flutter/material.dart';

class TermsAndPrivacyCheckbox extends StatefulWidget {
  const TermsAndPrivacyCheckbox({super.key, this.onChanged});

  final ValueChanged<bool>? onChanged;

  @override
  State<TermsAndPrivacyCheckbox> createState() =>
      _TermsAndPrivacyCheckboxState();
}

class _TermsAndPrivacyCheckboxState extends State<TermsAndPrivacyCheckbox> {
  bool isChecked = false;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 24,
          height: 24,
          child: Checkbox(
            value: isChecked,
            onChanged: (value) {
              setState(() {
                isChecked = value ?? false;
              });

              widget.onChanged?.call(isChecked);
            },
            side: const BorderSide(color: Color(0xFFD3D1CF), width: 2),
            activeColor: const Color(0xFFE45C10),
            checkColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),

        const SizedBox(width: 12),

        Expanded(
          child: RichText(
            text: const TextSpan(
              style: TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w500,
                height: 1.4,
              ),
              children: [
                TextSpan(text: 'I agree to the '),
                TextSpan(
                  text: 'Terms of Service',
                  style: TextStyle(color: Color(0xFFE45C10)),
                ),
                TextSpan(text: ' and\n'),
                TextSpan(
                  text: 'Privacy Policy.',
                  style: TextStyle(color: Color(0xFFE45C10)),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
