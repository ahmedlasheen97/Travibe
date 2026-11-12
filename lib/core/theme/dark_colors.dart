import 'package:flutter/material.dart';

class DarkColors {
  static const Color primaryColor = Color(0xFFE45C10);
  static const Color backgroundColor = Color(0xFF080808);
  static const Color greyColor = Color(0xFFBDBCBB);
  static const Color darkgreyColor = Color(0xFF1C1C1C);
  static const Color whiteColor = Color(0xFFFFFFFF);

  /// Destructive actions (Discard, Delete post), sampled from Figma.
  static const Color dangerColor = Color(0xFFDD312A);

  /// Floating toasts, sampled from docs/figma/home_toasts/. Success and info
  /// are 90% opaque (about #1B9A48 / #2D2C2B over a #171717 card).
  static const Color toastSuccess = Color(0xE61CA84D);
  static const Color toastInfo = Color(0xE62D2C2B);
  static const Color toastError = Color(0xFFC82E27);

  /// Pills darken the toast: #262525 on info, #732622 on error.
  static const Color toastInfoPill = Color(0x29000000);
  static const Color toastErrorPill = Color(0x6B000000);
}
