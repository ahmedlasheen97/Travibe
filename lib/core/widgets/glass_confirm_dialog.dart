import 'package:travibe/core/widgets/app_loaders.dart';
import 'package:flutter/material.dart';
import 'package:travibe/core/theme/dark_colors.dart';
import 'package:travibe/core/widgets/glass_surface.dart';

/// Shows the app-wide glass confirmation (Log Out look). Resolves to true only
/// when [confirmLabel] is tapped.
Future<bool> showGlassConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  String cancelLabel = 'Cancel',
  bool destructive = true,
  bool barrierDismissible = true,
}) async =>
    await showDialog<bool>(
      context: context,
      barrierDismissible: barrierDismissible,
      barrierColor: Colors.black54,
      builder: (_) => GlassConfirmDialog(
        title: title,
        message: message,
        confirmLabel: confirmLabel,
        cancelLabel: cancelLabel,
        destructive: destructive,
      ),
    ) ??
    false;

/// Compact glass confirmation: blurred [GlassSurface], destructive action on
/// the left and Cancel on the right. Stateful callers drive [loading],
/// [error] and [onConfirm]; by default the buttons pop true/false.
class GlassConfirmDialog extends StatelessWidget {
  const GlassConfirmDialog({
    super.key,
    required this.title,
    required this.message,
    required this.confirmLabel,
    this.cancelLabel = 'Cancel',
    this.destructive = true,
    this.loading = false,
    this.loadingLabel,
    this.error,
    this.notice,
    this.confirmEnabled = true,
    this.onConfirm,
    this.onCancel,
    this.surfaceKey,
  });

  final String title;
  final String message;
  final String confirmLabel;
  final String cancelLabel;
  final bool destructive;
  final bool loading;
  final String? loadingLabel;
  final String? error;
  final String? notice;
  final bool confirmEnabled;
  final VoidCallback? onConfirm;
  final VoidCallback? onCancel;
  final Key? surfaceKey;

  static const _buttonText = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w500,
  );

  @override
  Widget build(BuildContext context) {
    final confirm = onConfirm ?? () => Navigator.pop(context, true);
    final cancel = onCancel ?? () => Navigator.pop(context, false);
    return PopScope(
      canPop: !loading,
      child: Dialog(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 320),
          child: GlassSurface(
            surfaceKey: surfaceKey,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(22, 24, 22, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: DarkColors.whiteColor,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: DarkColors.greyColor,
                      fontSize: 14,
                      height: 1.5,
                    ),
                  ),
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        error!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: DarkColors.dangerColor,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  if (notice != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        notice!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: DarkColors.greyColor,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: TextButton(
                          onPressed: loading || !confirmEnabled
                              ? null
                              : confirm,
                          style: TextButton.styleFrom(
                            foregroundColor: destructive
                                ? DarkColors.dangerColor
                                : DarkColors.whiteColor,
                            textStyle: _buttonText,
                          ),
                          child: loading
                              ? Semantics(
                                  label: loadingLabel ?? confirmLabel,
                                  child: const AppActivityIndicator(radius: 11),
                                )
                              : Text(confirmLabel),
                        ),
                      ),
                      Expanded(
                        child: TextButton(
                          onPressed: loading ? null : cancel,
                          style: TextButton.styleFrom(
                            foregroundColor: DarkColors.whiteColor,
                            textStyle: _buttonText,
                          ),
                          child: Text(cancelLabel),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
