import 'package:flutter/material.dart';
import 'package:travibe/core/constants/app_sizes.dart';
import 'package:travibe/core/theme/action_button_style.dart';
import 'package:travibe/core/theme/dark_colors.dart';
import 'package:travibe/core/widgets/back_button_widget.dart';

/// Field fill and hairline border shared by the settings forms (Figma).
const settingsFieldFill = Color(0xFF171717);
const settingsFieldBorder = Color(0xFF2A2A2A);

/// Settings sub-screen frame: 44×44 back button + centered title, scrolling
/// [children], and [button] pinned under them. The body resizes for the
/// keyboard, so the button always stays above it.
class SettingsFormScaffold extends StatelessWidget {
  const SettingsFormScaffold({
    super.key,
    required this.title,
    required this.children,
    required this.button,
    this.busy = false,
  });

  final String title;
  final List<Widget> children;
  final Widget button;

  /// Blocks back navigation while a request is in flight.
  final bool busy;

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: Scaffold(
      backgroundColor: DarkColors.backgroundColor,
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(
                AppSizes.pw20,
                AppSizes.h8,
                AppSizes.pw20,
                0,
              ),
              child: SizedBox(
                height: 44,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 52),
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: AppSizes.adaptiveFont(20),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: BackButtonWidget(enabled: !busy),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: ListView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: EdgeInsets.fromLTRB(
                  AppSizes.pw20,
                  AppSizes.adaptiveHeight(24),
                  AppSizes.pw20,
                  AppSizes.adaptiveHeight(24),
                ),
                children: children,
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(
                AppSizes.pw20,
                AppSizes.ph12,
                AppSizes.pw20,
                AppSizes.ph20,
              ),
              child: button,
            ),
          ],
        ),
      ),
    ),
  );
}

/// Full-width pill action (orange by default) with a white loader.
class SettingsActionButton extends StatelessWidget {
  const SettingsActionButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.loading = false,
    this.loadingLabel,
    this.color = DarkColors.primaryColor,
  });

  final String label;

  /// Null disables the button.
  final VoidCallback? onPressed;
  final bool loading;
  final String? loadingLabel;
  final Color color;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    height: AppSizes.adaptiveHeight(56).clamp(48.0, 64.0),
    child: ElevatedButton(
      onPressed: loading ? null : onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        // Disabled keeps the brand color, dimmed (as the Figma states).
        disabledBackgroundColor: color.withValues(alpha: loading ? 1 : .45),
        disabledForegroundColor: Colors.white.withValues(alpha: .7),
        elevation: 0,
        shape: ActionButtonStyle.shape,
      ),
      child: loading
          ? Semantics(
              label: loadingLabel ?? label,
              child: const SizedBox.square(
                dimension: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: Colors.white,
                ),
              ),
            )
          : Text(label, style: ActionButtonStyle.label),
    ),
  );
}

/// Field title; [required] adds the red asterisk.
class SettingsFieldLabel extends StatelessWidget {
  const SettingsFieldLabel(this.text, {super.key, this.required = false});

  final String text;
  final bool required;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: AppSizes.h8),
    child: Text.rich(
      TextSpan(
        style: TextStyle(color: Colors.white, fontSize: AppSizes.sp16),
        children: [
          TextSpan(text: text),
          if (required)
            const TextSpan(
              text: ' *',
              style: TextStyle(color: DarkColors.dangerColor),
            ),
        ],
      ),
    ),
  );
}

/// Multi-line field with a right-aligned `n/max` counter under it.
class SettingsMultilineField extends StatelessWidget {
  const SettingsMultilineField({
    super.key,
    required this.controller,
    required this.hintText,
    required this.maxLength,
    this.enabled = true,
    this.fieldKey,
  });

  final TextEditingController controller;
  final String hintText;
  final int maxLength;
  final bool enabled;
  final Key? fieldKey;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(AppSizes.adaptiveRadius(24));
    OutlineInputBorder border(Color color) => OutlineInputBorder(
      borderRadius: radius,
      borderSide: BorderSide(color: color),
    );
    return TextField(
      key: fieldKey,
      controller: controller,
      enabled: enabled,
      minLines: 4,
      maxLines: 6,
      maxLength: maxLength,
      cursorColor: Colors.white,
      keyboardType: TextInputType.multiline,
      textCapitalization: TextCapitalization.sentences,
      style: TextStyle(color: Colors.white, fontSize: AppSizes.sp16),
      buildCounter:
          (_, {required currentLength, required isFocused, maxLength}) => Text(
            '$currentLength/$maxLength',
            style: TextStyle(
              color: Colors.white.withValues(alpha: .7),
              fontSize: AppSizes.sp14,
            ),
          ),
      decoration: InputDecoration(
        hintText: hintText,
        hintStyle: TextStyle(
          color: Colors.white.withValues(alpha: .55),
          fontSize: AppSizes.sp16,
        ),
        filled: true,
        fillColor: settingsFieldFill,
        contentPadding: EdgeInsets.all(AppSizes.adaptiveWidth(20)),
        border: border(settingsFieldBorder),
        enabledBorder: border(settingsFieldBorder),
        disabledBorder: border(settingsFieldBorder),
        focusedBorder: border(const Color(0xFF595966)),
      ),
    );
  }
}

/// Alert-circle icon + text row (info grey, or danger red for warnings).
class SettingsNotice extends StatelessWidget {
  const SettingsNotice(this.text, {super.key, this.danger = false});

  final String text;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final color = danger
        ? DarkColors.dangerColor
        : Colors.white.withValues(alpha: .7);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          Icons.error_outline_rounded,
          color: color,
          size: AppSizes.adaptiveRadius(22),
        ),
        SizedBox(width: AppSizes.adaptiveWidth(8)),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              color: color,
              fontSize: AppSizes.adaptiveFont(danger ? 16 : 15),
              height: 1.4,
            ),
          ),
        ),
      ],
    );
  }
}
