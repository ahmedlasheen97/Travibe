import 'package:flutter/material.dart';
import 'package:travibe/core/constants/app_sizes.dart';

/// Standard action buttons only; compact controls and destructive actions keep
/// their own styles. Geometry and label weight remain configurable by callers.
abstract final class ActionButtonStyle {
  static const fontSize = AppSizes.buttonLabelFont;
  static const shape = RoundedRectangleBorder(
    borderRadius: BorderRadius.all(Radius.circular(AppSizes.buttonRadius)),
  );
  static const label = TextStyle(
    fontFamily: 'Plus Jakarta Sans',
    fontSize: fontSize,
    fontWeight: FontWeight.w600,
  );
}
