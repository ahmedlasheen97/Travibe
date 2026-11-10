import 'package:flutter/material.dart';

/// Standard action buttons only; compact controls and destructive actions keep
/// their own styles. Geometry and label weight remain configurable by callers.
abstract final class ActionButtonStyle {
  static const fontSize = 18.0;
  static const shape = RoundedRectangleBorder(
    borderRadius: BorderRadius.all(Radius.circular(32)),
  );
  static const label = TextStyle(
    fontFamily: 'Plus Jakarta Sans',
    fontSize: fontSize,
    fontWeight: FontWeight.w600,
  );
}
