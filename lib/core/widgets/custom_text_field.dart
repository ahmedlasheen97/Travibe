import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:travibe/core/theme/app_styles.dart';

class CustomTextField extends StatefulWidget {
  const CustomTextField({
    super.key,
    required this.title,
    this.hintText,
    this.controller,
    this.validator,
    this.onChanged,
    this.onSaved,
    this.keyboardType,
    this.textInputAction,
    this.prefixIcon,
    this.suffixIcon,
    this.obscureText = false,
    this.enabled = true,
    this.readOnly = false,
    this.maxLines = 1,
    this.minLines,
    this.textCapitalization = TextCapitalization.none,
    this.autofocus = false,
    this.passwordVisibilityToggle = false,
    this.focusNode,
  });

  final bool passwordVisibilityToggle;
  final FocusNode? focusNode;
  final String title;
  final String? hintText;

  final TextEditingController? controller;

  final String? Function(String?)? validator;
  final void Function(String)? onChanged;
  final void Function(String?)? onSaved;

  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;

  final Widget? prefixIcon;
  final Widget? suffixIcon;

  final bool obscureText;
  final bool enabled;
  final bool readOnly;
  final bool autofocus;

  final int maxLines;
  final int? minLines;

  final TextCapitalization textCapitalization;

  @override
  State<CustomTextField> createState() => _CustomTextFieldState();
}

class _CustomTextFieldState extends State<CustomTextField> {
  bool _visible = false;
  late final FocusNode _ownFocus = FocusNode();
  FocusNode get _focus => widget.focusNode ?? _ownFocus;
  bool get _obscured =>
      widget.passwordVisibilityToggle ? !_visible : widget.obscureText;

  void _toggle() {
    final selection = widget.controller?.selection;
    setState(() => _visible = !_visible);
    _focus.requestFocus();
    if (selection != null && selection.isValid) {
      widget.controller!.selection = selection;
    }
  }

  @override
  void dispose() {
    _ownFocus.dispose();
    super.dispose();
  }

  Widget _eye() => SizedBox.square(
    dimension: 48,
    child: Tooltip(
      message: _visible ? 'Hide password' : 'Show password',
      excludeFromSemantics: true,
      child: Semantics(
        label: _visible ? 'Hide password' : 'Show password',
        child: IconButton(
          onPressed: widget.enabled ? _toggle : null,
          icon: ExcludeSemantics(
            child: SizedBox.square(
              dimension: 24,
              child: SvgPicture.asset(
                _visible
                    ? 'assets/images/interactions/eye.svg'
                    : 'assets/images/onboarding/eye-slash.svg',
                width: 24,
                height: 24,
              ),
            ),
          ),
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.title, style: AppStyles.smallSubtitlesStyles),

        const SizedBox(height: 8),

        TextFormField(
          controller: widget.controller,
          focusNode: _focus,
          validator: widget.validator,
          onChanged: widget.onChanged,
          onSaved: widget.onSaved,
          keyboardType: widget.keyboardType,
          textInputAction: widget.textInputAction,
          obscureText: _obscured,
          enabled: widget.enabled,
          readOnly: widget.readOnly,
          maxLines: _obscured ? 1 : widget.maxLines,
          minLines: widget.minLines,
          autofocus: widget.autofocus,
          textCapitalization: widget.textCapitalization,

          style: const TextStyle(color: Colors.white, fontSize: 16),

          cursorColor: Colors.white,

          decoration: InputDecoration(
            hintText: widget.hintText,

            hintStyle: TextStyle(
              color: Colors.white.withValues(alpha: 0.55),
              fontSize: 16,
            ),

            prefixIcon: Padding(
              padding: const EdgeInsets.all(16.0),
              child: widget.prefixIcon,
            ),

            suffixIcon: widget.passwordVisibilityToggle
                ? _eye()
                : widget.suffixIcon,

            filled: true,
            fillColor: const Color(0xFF171717),

            contentPadding: const EdgeInsets.all(16),
          ),
        ),
      ],
    );
  }
}
